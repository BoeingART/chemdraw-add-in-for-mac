#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Local, single-session Mac prototype. Failure keeps the ChemDraw document open."""
import argparse
import hashlib
import json
import signal
import subprocess
import sys
import time
import uuid
import shutil
import queue
import threading
from pathlib import Path

from automation import ROOT, chem_application, chem_open, chem_is_open, chem_snapshot, chem_render_vector, chem_close, office, office_preview
from metadata import encode, decode, validate_source, object_id
from verification import verify_saved_figure, read_saved_figure
from carrier import create_carrier, read_carrier, render_svg, has_vectors, svg_aspect

WORK = ROOT / "work"
STATE = WORK / "monitor-state.json"
LOG = WORK / "events.jsonl"


def record(event, **details):
    WORK.mkdir(exist_ok=True)
    entry = {"time": time.time(), "event": event, **details}
    with LOG.open("a") as stream: stream.write(json.dumps(entry) + "\n")
    print(json.dumps(entry), flush=True)


def write_state(value):
    temporary = STATE.with_suffix(".tmp")
    temporary.write_text(json.dumps(value))
    temporary.replace(STATE)


class Bridge:
    def __init__(self):
        self.session = None

    def payload(self, host, document, drawing_id):
        if host == "word":
            tag = office("payload", host, document, drawing_id)
            if tag.startswith(("CFM1:", "CFM2:")): return tag
        office("persist", host, document)
        return read_saved_figure(document, host, drawing_id)["tag"]

    def paste(self, host, snapshot):
        if self.session:
            raise RuntimeError("Close the current managed ChemDraw edit before pasting another drawing")
        document = office("context", host)
        if host == "powerpoint" and (not document or not Path(document).is_absolute()):
            # The native clipboard capture is already on disk. Let the user name
            # the deck, then paste those same bytes even if the clipboard changes.
            write_state({"saveDialogBundle": "com.microsoft.Powerpoint"})
            try:
                record("paste_needs_save", host=host)
                document = office("save-for-paste", host)
                if not document:
                    record("paste_cancelled", host=host, reason="save-dialog-cancelled")
                    return
            finally:
                write_state({})
        if not document or not Path(document).is_file():
            raise RuntimeError("Save the target Office document once before using editable paste")
        snapshot = Path(snapshot)
        write_state({"pasteBusyBundle": "com.microsoft.Word" if host == "word" else "com.microsoft.Powerpoint"})
        try:
            if (snapshot / "source.cdx").exists():
                source = (snapshot / "source.cdx").read_bytes()
                validate_source(source)
            else:
                original_tag, png = read_carrier((snapshot / "carrier.svg").read_bytes())
                _, source = decode(original_tag)
                (snapshot / "preview.png").write_bytes(png)
            drawing_id = str(uuid.uuid4())  # Every paste is an independent editable instance.
            image = snapshot / "preview.png"
            carrier = snapshot / "figure.svg"
            vector = snapshot / "native.svg"
            captured_svg = snapshot / "carrier.svg"
            if captured_svg.exists() and has_vectors(captured_svg.read_bytes()):
                vector.write_bytes(captured_svg.read_bytes())
            else:
                source_file = snapshot / ("render.cdx" if source.startswith(b"VjCD0100") else "render.cdxml")
                source_file.write_bytes(source)
                chem_render_vector(source_file, vector)
            image.write_bytes(render_svg(vector.read_bytes()))
            tag = create_carrier(source, image, drawing_id, carrier, vector=vector)
            aspect = svg_aspect(carrier.read_bytes())
            office("insert", host, office_preview(host, carrier), tag, drawing_id, document, str(aspect))
            evidence = verify_saved_figure(document, host, drawing_id, source, image)
            (snapshot / "verification.json").write_text(json.dumps(evidence, indent=2))
            record("pasted", host=host, document=document, drawing_id=drawing_id,
                   source_sha256=hashlib.sha256(source).hexdigest(), portable_carrier=True)
        finally:
            write_state({})

    def begin(self, host, tag):
        document = office("context", host)
        requested_id = object_id(tag)
        if self.session:
            previous = self.session
            if (host, document, requested_id) == (previous["host"], previous["document"], previous["id"]):
                # The window may have been hidden or closed outside our intercepted path.
                # Resume its retained draft; never overwrite it with the embedded old source.
                chem_open(Path(previous["path"]))
                record("edit_resumed", host=host, drawing_id=requested_id, document=document)
                return
            if chem_is_open(Path(previous["path"])):
                chem_open(Path(previous["path"]))
                raise RuntimeError("Finish the visible ChemDraw edit before opening another drawing")
            recovery = WORK / "recovery" / f'{previous["id"]}-{time.time_ns()}'
            recovery.mkdir(parents=True)
            shutil.copy2(previous["path"], recovery / Path(previous["path"]).name)
            (recovery / "session.json").write_text(json.dumps(previous, indent=2))
            record("closed_session_retained", drawing_id=previous["id"], recovery=str(recovery))
            self.session = None
            write_state({})
        if not tag.startswith(("CFM1:", "CFM2:")):
            tag = self.payload(host, document, requested_id)
        drawing_id, source = decode(tag)
        session_dir = WORK / "sessions" / drawing_id
        session_dir.mkdir(parents=True, exist_ok=True)
        extension = "cdx" if source.startswith(b"VjCD0100") else "cdxml"
        path = session_dir / f"CFM-{drawing_id}.{extension}"
        path.write_bytes(source)
        (session_dir / f"original.{extension}").write_bytes(source)
        self.session = {"host": host, "document": document, "id": drawing_id,
                        "path": str(path), "originalTag": tag,
                        "windowTitle": path.name, "chemBundle": chem_application()["bundle"], "busy": False}
        (session_dir / "session.json").write_text(json.dumps(self.session, indent=2))
        write_state(self.session)
        try:
            chem_open(path)
        except Exception:
            # A failed activation must remain resumable, with its draft intact.
            write_state(self.session)
            raise
        record("opened", host=host, drawing_id=drawing_id, document=document)

    def finish(self, gesture):
        if not self.session:
            return
        session = self.session
        session["busy"] = True
        write_state(session)
        path = Path(session["path"])
        image = path.parent / f"preview-{time.time_ns()}.png"
        try:
            # The native close gesture is held. Save the live document before allowing closure.
            chem_snapshot(path, image)
            source = path.read_bytes()
            validate_source(source)
            if not image.read_bytes().startswith(b"\x89PNG\r\n\x1a\n"):
                raise RuntimeError("ChemDraw did not produce a valid PNG preview")
            new_tag = encode(source, session["id"])
            old_tag = self.payload(session["host"], session["document"], session["id"])
            if old_tag not in (session["originalTag"], new_tag):
                raise RuntimeError("The Office figure changed during editing; kept both versions")
            carrier = path.parent / f"figure-{time.time_ns()}.svg"
            create_carrier(source, image, session["id"], carrier)
            safe_preview = office_preview(session["host"], carrier)
            aspect = svg_aspect(carrier.read_bytes())
            office("update", session["host"], session["document"], session["id"], safe_preview, new_tag, str(aspect))
            recovered_tag = self.payload(session["host"], session["document"], session["id"])
            _, recovered = decode(recovered_tag)
            if recovered != source:
                raise RuntimeError("Write-back verification failed; ChemDraw remains open")
            session["originalTag"] = new_tag
            write_state(session)
            evidence = verify_saved_figure(session["document"], session["host"], session["id"], source, image)
            # A second dirty check inside chem_close refuses to discard a newer edit.
            chem_close(path)
            bundle = "com.microsoft.Word" if session["host"] == "word" else "com.microsoft.Powerpoint"
            subprocess.check_output([str(ROOT / "build/event-monitor"), "--activate-office",
                                     bundle, Path(session["document"]).name], text=True)
            office("activate", session["host"], session["document"], session["id"])
            front = subprocess.check_output([str(ROOT / "build/event-monitor"), "--frontmost"], text=True).strip()
            record("committed", host=session["host"], drawing_id=session["id"], gesture=gesture,
                   source_sha256=hashlib.sha256(source).hexdigest(), bytes=len(source), frontmost_app=front)
            (path.parent / "verification.json").write_text(json.dumps(evidence, indent=2))
            session["originalTag"] = new_tag
            (path.parent / ("committed.cdx" if source.startswith(b"VjCD0100") else "committed.cdxml")).write_bytes(source)
            self.session = None
            write_state({})
        except Exception:
            session["busy"] = False
            write_state(session)
            raise


def run_monitor():
    WORK.mkdir(exist_ok=True)
    lock_path = WORK / "monitor.lock"
    import fcntl
    lock = lock_path.open("w")
    try: fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError: raise SystemExit("A ChemOffice monitor is already running")
    bridge = Bridge()
    if STATE.exists():
        previous = json.loads(STATE.read_text())
        if previous.get("path") and Path(previous["path"]).is_file():
            bridge.session = previous
            previous["busy"] = False
            record("session_resumed", drawing_id=previous["id"])
    write_state(bridge.session or {})
    process = subprocess.Popen([str(ROOT / "build/event-monitor"), str(STATE)],
                               stdout=subprocess.PIPE, text=True, bufsize=1)
    events = queue.Queue()
    def read_events():
        try:
            for line in process.stdout:
                events.put((json.loads(line), None))
        finally:
            events.put((None, None))
    threading.Thread(target=read_events, daemon=True).start()
    from office_ui import start_office_ui
    try:
        panel = start_office_ui(ROOT, bridge, events)
        if panel: record("office_panel_ready", url="https://localhost:17524/taskpane.html")
    except Exception as error:
        panel = None
        record("office_panel_unavailable", message=str(error))
    def stop(*_):
        process.terminate()
        raise KeyboardInterrupt
    signal.signal(signal.SIGTERM, stop)
    try:
        while True:
            event, future = events.get()
            if event is None: break
            if future is not None and not future.set_running_or_notify_cancel(): continue
            kind = event["event"]
            try:
                if kind == "open": bridge.begin(event["host"], event["tag"])
                elif kind == "edit-selection":
                    tag = office("selected", event["host"])
                    if not tag: raise RuntimeError("Select one ChemOffice drawing in your document, then choose Edit selected drawing")
                    object_id(tag)
                    bridge.begin(event["host"], tag)
                elif kind == "paste": bridge.paste(event["host"], event["snapshot"])
                elif kind == "close": bridge.finish(event["gesture"])
                else: record(kind, **{k: v for k, v in event.items() if k != "event"})
                if future is not None: future.set_result(True)
            except Exception as error:
                if future is not None: future.set_exception(error)
                record("error", operation=kind, message=str(error))
    except KeyboardInterrupt:
        pass
    finally:
        if panel: panel.shutdown(); panel.server_close()
        process.terminate()
        process.wait(timeout=5)
        if bridge.session:
            bridge.session["busy"] = False
        write_state(bridge.session or {})
        record("stopped")


def create_demo(host):
    WORK.mkdir(exist_ok=True)
    source = (ROOT / "assets/demo.cdxml").read_bytes()
    tag = encode(source)
    drawing_id, _ = decode(tag)
    render_path = WORK / f"CFM-demo-{drawing_id}.cdxml"
    render_path.write_bytes(source)
    png = WORK / f"CFM-demo-{drawing_id}.png"
    chem_open(render_path)
    chem_snapshot(render_path, png)
    chem_close(render_path)
    output = WORK / f"ChemOffice-{host}-{drawing_id[:8]}.{'docx' if host == 'word' else 'pptx'}"
    carrier = png.with_suffix(".svg")
    create_carrier(source, png, drawing_id, carrier)
    office("demo", host, office_preview(host, carrier), tag, output, drawing_id,
           str(svg_aspect(carrier.read_bytes())))
    verify_saved_figure(str(output), host, drawing_id, source, png)
    record("demo_created", host=host, path=str(output), drawing_id=drawing_id)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="ChemOffice for Mac local prototype")
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("run", help="Enable managed-figure double-click and safe close handling")
    demo = commands.add_parser("demo", help="Create an isolated editable test document")
    demo.add_argument("host", choices=["word", "powerpoint"])
    args = parser.parse_args()
    if args.command == "run": run_monitor()
    else: create_demo(args.host)

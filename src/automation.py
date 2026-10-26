# SPDX-License-Identifier: Apache-2.0
"""Application object-model calls; no keystroke or clipboard automation."""
import subprocess
import shutil
import json
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
_chem_application = None


def chem_application():
    """Resolve once per process so every step of an edit uses the same installation."""
    global _chem_application
    if _chem_application is None:
        applications = json.loads(subprocess.check_output(
            [str(ROOT / "build/event-monitor"), "--discover-chemdraw"], text=True))
        if not applications:
            raise RuntimeError("No installed ChemDraw application was found; install and activate ChemDraw first")
        _chem_application = applications[0]
    return _chem_application


def chem_target():
    return json.dumps(chem_application()["path"], ensure_ascii=False)


def office_preview(host: str, image: Path) -> Path:
    # A stable, explicitly granted file avoids asking Office for a new file on each edit.
    # Do not reach into another application's protected container.
    directory = ROOT / "work"
    directory.mkdir(exist_ok=True)
    destination = directory / f"office-preview-{host}{image.suffix}"
    shutil.copy2(image, destination)
    return destination


def script(body: str, *args: str, timeout: int = 30) -> str:
    code = "on run argv\n" + body + "\nend run"
    result = subprocess.run(["/usr/bin/osascript", "-e", code, "--", *map(str, args)],
                            capture_output=True, text=True, timeout=timeout)
    if result.returncode:
        raise RuntimeError(result.stderr.strip())
    return result.stdout.strip()


def office(action: str, host: str, *args: str) -> str:
    path = ROOT / "office" / host / "adapter.applescript"
    result = subprocess.run(["/usr/bin/osascript", str(path), action, *map(str, args)],
                            capture_output=True, text=True, timeout=610 if action == "save-for-paste" else 45)
    if result.returncode:
        raise RuntimeError(result.stderr.strip())
    return result.stdout.strip()


def chem_open(path: Path) -> None:
    monitor = str(ROOT / "build/event-monitor")
    # Launch Services delivers the document-open event after a cold application
    # launch, rather than racing AppleScript against ChemDraw's startup screen.
    application = chem_application()
    launched = subprocess.run([monitor, "--open-document", application["path"], str(path)],
                              capture_output=True, text=True, timeout=45)
    if launched.returncode:
        raise RuntimeError(launched.stderr.strip() or "ChemDraw could not open this drawing")
    script(f'''with timeout of 40 seconds
    tell application {chem_target()}
        set targetPath to item 1 of argv
        set targetFound to false
        repeat 300 times
            repeat with d in documents
                try
                    if POSIX path of ((file of d) as alias) is targetPath then
                        set index of window of d to 1
                        set targetFound to true
                    end if
                end try
            end repeat
            if targetFound then exit repeat
            delay 0.1
        end repeat
        if not targetFound then error "ChemDraw did not open the managed source"
        activate
    end tell
    end timeout''', path, timeout=45)
    for _ in range(30):
        result = subprocess.run([monitor, "--activate-window", application["path"], path.name], capture_output=True)
        if result.returncode == 0:
            focused = json.loads(subprocess.check_output([monitor, "--focused"], text=True))
            if focused.get("bundle") == application["bundle"] and focused.get("title") == path.name:
                return
        time.sleep(0.1)
    raise RuntimeError("The drawing opened, but macOS did not bring its ChemDraw window forward; double-click again to resume")


def chem_is_open(path: Path) -> bool:
    if subprocess.check_output([str(ROOT / "build/event-monitor"), "--is-running", chem_application()["path"]], text=True).strip() != "yes":
        return False
    return script(f'''tell application {chem_target()}
        repeat with d in documents
            try
                if POSIX path of ((file of d) as alias) is (item 1 of argv) then return "open"
            end try
        end repeat
        return "closed"
    end tell''', path) == "open"


def chem_snapshot(path: Path, png: Path) -> None:
    # Matching a unique session path prevents touching any unrelated ChemDraw document.
    script(f'''set outputFile to POSIX file (item 2 of argv)
    tell application {chem_target()}
        set targetPath to item 1 of argv
        set matches to {{}}
        repeat with candidate in documents
            try
                if POSIX path of ((file of candidate) as alias) is targetPath then set end of matches to candidate
            end try
        end repeat
        if (count matches) is not 1 then error "Expected exactly one managed ChemDraw document"
        set d to item 1 of matches
        if POSIX path of ((file of document 1) as alias) is not targetPath then error "Managed drawing is not active"
        -- The native tap sees Close before ChemDraw has consumed all earlier
        -- keystrokes. Let those queued edits run before switching tools.
        delay 0.25
        -- Finish the live label/caption editor before serializing the document.
        -- The generic AppleScript save event alone can miss an in-progress text edit.
        do command "chooseSelectionTool_Marquee"
        -- ChemDraw may finish the caption/layout on its next UI turn. A save
        -- acknowledgement is insufficient: require two clean observations.
        set sourceSaved to false
        repeat 5 times
            delay 0.1
            save d
            delay 0.1
            if not (modified of d) then
                delay 0.1
                if not (modified of d) then
                    set sourceSaved to true
                    exit repeat
                end if
            end if
        end repeat
        if not sourceSaved then error "ChemDraw still reports unsaved changes"
        save d in outputFile as "Scalable Vector Graphics (SVG)"
        if modified of d then error "Drawing changed during snapshot; close again to retry"
    end tell''', path, png.with_suffix(".svg"))
    from carrier import render_svg
    png.write_bytes(render_svg(png.with_suffix(".svg").read_bytes()))


def chem_render_vector(source: Path, vector: Path) -> None:
    """Export a captured selection without activating an unrelated editor window."""
    script(f'''set drawingFile to (POSIX file (item 1 of argv)) as alias
    set outputFile to POSIX file (item 2 of argv)
    tell application {chem_target()}
        open drawingFile
        set matches to {{}}
        repeat with d in documents
            try
                if POSIX path of ((file of d) as alias) is (item 1 of argv) then set end of matches to d
            end try
        end repeat
        if (count matches) is not 1 then error "Cannot identify captured chemistry for vector export"
        set d to item 1 of matches
        if modified of d then error "Captured source unexpectedly has pending edits"
        save d in outputFile as "Scalable Vector Graphics (SVG)"
        if modified of d then error "Captured drawing changed during vector export; kept open"
        close d saving no
    end tell''', source, vector)


def chem_close(path: Path) -> None:
    script(f'''tell application {chem_target()}
        repeat with d in documents
            try
                if POSIX path of ((file of d) as alias) is (item 1 of argv) then
                    if modified of d then error "Drawing changed before close; kept open"
                    close d saving no
                    return "closed"
                end if
            on error messageText number errorNumber
                if errorNumber is not -1728 then error messageText number errorNumber
            end try
        end repeat
        error "Managed drawing is no longer open"
    end tell''', path)

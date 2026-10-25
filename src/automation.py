# SPDX-License-Identifier: Apache-2.0
"""Application object-model calls; no keystroke or clipboard automation."""
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CHEM_ID = "com.perkinelmer.ChemDraw.22"


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
                            capture_output=True, text=True, timeout=45)
    if result.returncode:
        raise RuntimeError(result.stderr.strip())
    return result.stdout.strip()


def chem_open(path: Path) -> None:
    script(f'''set drawingFile to (POSIX file (item 1 of argv)) as alias
    tell application id "{CHEM_ID}"
        open drawingFile
        activate
    end tell''', path)


def chem_snapshot(path: Path, png: Path) -> None:
    # Matching a unique session path prevents touching any unrelated ChemDraw document.
    script(f'''set outputFile to POSIX file (item 2 of argv)
    tell application id "{CHEM_ID}"
        set targetPath to item 1 of argv
        set matches to {{}}
        repeat with candidate in documents
            try
                if POSIX path of ((file of candidate) as alias) is targetPath then set end of matches to candidate
            end try
        end repeat
        if (count matches) is not 1 then error "Expected exactly one managed ChemDraw document"
        set d to item 1 of matches
        save d
        if modified of d then error "ChemDraw still reports unsaved changes"
        save d in outputFile as "PNG"
        if modified of d then error "Drawing changed during snapshot; close again to retry"
    end tell''', path, png)


def chem_close(path: Path) -> None:
    script(f'''tell application id "{CHEM_ID}"
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

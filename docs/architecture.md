# Prototype architecture

This project implements custom managed pictures, not native OLE objects or an Office add-in. The installed ChemDraw remains the editor.

1. A Swift annotated-session event tap recognizes a double-click on a selected managed Office picture. It reads only that selection's identity through the Office object model.
2. Python resolves the original document and extracts checksum-protected, compressed CDXML. Word carries it in picture alternative text. PowerPoint carries it in a hidden same-slide text box paired with a named picture.
3. The source is materialized under `work/sessions/<drawing-id>/` and opened in ChemDraw. Only one managed editing session is supported.
4. The event tap holds the managed window's ⌘W or recognized red-button event. While committing, it suppresses further key-down and mouse-down events directed to that managed ChemDraw window.
5. ChemDraw receives a short settling interval, exits its live text editor, saves with bounded clean-state checks, and exports a PNG. A different active document, remaining dirty state, invalid source, or failed render aborts the transaction.
6. The original Office figure's source must still match its opening version (or the same new version from a partial retry). The adapter replaces the picture, updates the embedded source, and saves the Office document.
7. Python reads the saved OOXML package, follows the actual picture relationship, compares exact source bytes, and compares the normalized preview. Only then may the clean ChemDraw document close. The adapter activates the original document and selects its figure.

Failures retain the session and editable draft. They do not provide cross-application rollback or a guarantee against process crashes. A monitor restart reloads a retained session; the native helper watches its parent process so an abandoned event tap does not continue intercepting input.

`src/automation.py` owns application object-model calls, `office/*/adapter.applescript` owns host-specific behavior, and `src/verification.py` verifies the saved document. Stable `work/office-preview-*.png` files are used so Office can receive a one-time grant to a known preview file without accessing another application's protected container.

No keystroke text or clipboard contents are logged. Normal logs contain session identity, document path, gestures, errors, source hashes, and focus evidence. Optional `CFM_DIAGNOSTICS=1` additionally records pointer target and close-button hit-test coordinates; it is off by default.

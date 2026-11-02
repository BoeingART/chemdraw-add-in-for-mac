# Word and Excel native OLE — Build 31

Validated on 2 November 2026 with Word 16.114.1 and ChemDraw 26.0.0.6599. Version 2.0.0 Build 31 is installed at `/Applications/ChemDraw Add-in for Mac.app` on branch `codex/windows-ole-interop`.

## Word application checks

- Copied native CDX from ChemDraw and pasted with Command-V into a new, unsaved Word document through the installed helper. Word inserted an embedded OLE object without requesting a document save.
- Opened a managed OLE by double-click, edited it in ChemDraw and synchronized Command-S while retaining the editor. The saved DOCX contained the exact committed source, `ChemDraw.Document.6.0` class, matching PNG preview and expected dimensions.
- Pasted an independent copy while the original editor remained open. Switched Word documents, edited the original and saved again. The update returned to the original document and left the new copy's source intact.
- Opened an unmarked OLE fixture by double-click. Its compound-file source came from the supplied Windows PowerPoint example. ChemDraw's File → Save synchronized the edit, and the resulting DOCX retained the native OLE class, exact source and matching preview.
- Saved-file checks found a 1,024 × 839 preview and zero mean pixel difference in both installed save tests. The committed edited source was 23,549 bytes; the installed clipboard-paste copy retained its separate 21,881-byte source.
- Word imports a bookmarked object-only range directly from its cache. The installed tests showed no transport document or file-access dialog during paste and write-back, and ChemDraw stayed in front during synchronization. One warm Word save completed 5.13 seconds after the source file write.
- Development acceptance also checked surrounding `Before`/`After` text, native insertion while an OLE field was selected, and independent copies in the same document. `tests/native/WordOLELiveTests.swift` provides begin, insert, watch, verify and verify-installed modes. These modes operate on their own acceptance documents.

The saved acceptance files are under `build/Word-native-OLE-build31.docx`, `build/Word-native-OLE-installed31-paste.docx` and `build/Word-native-OLE-unmarked31.docx`. User documents were not saved by the helper.

## Excel checks

Excel is not installed on this Mac. At the user's request, installation and application testing are deferred. The Excel implementation creates an XLSX transport with native OLE storage, a worksheet OLE relationship and a matching drawing shape. Transfer reads the copied source before pasting, stages a pending object, checks the pasted object's type and embedded source, and replaces the original only after verification.

Word and Excel transport round trips, native source/class retention, preview dimensions and external-relationship rejection passed in 43 OLE format checks. Native paste, save, failure retention and draft independence for all three Office hosts passed in 131 transaction checks. Excel's application object model and clipboard behavior still require testing with Excel installed.

## Installation checks

The final local DMG and ZIP passed package validation: application signatures, both processor architectures, size budgets, packaged resources, disk-image mounting, interface checks and helper discovery. The user reconfirmed system permissions after installation. Setup verified actual read/write access for Word and PowerPoint, skipped absent Excel, confirmed Accessibility and automatically started the ready keyboard/mouse helper.

CDX uses native OLE storage. CDXML and legacy graphics retain the vector-carrier compatibility path. These are local test packages; no GitHub Release was published.

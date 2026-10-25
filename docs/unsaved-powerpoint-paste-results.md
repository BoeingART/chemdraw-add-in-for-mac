# First paste into an unsaved PowerPoint deck

## Reported failure and cause

The user reported that the chemistry in the current ChemDraw document would not paste into the current PowerPoint deck. The helper was running and recognized the chemical clipboard. Its recent log showed repeated `paste` errors at the saved-target guard: “Save the target Office document once before using editable paste”. The guard consumed the original ⌘V event, and its exception was written only to the log. There was no visible instruction explaining the unchanged slide.

Once the current presentation had a saved path, the same multi-fragment, colored ChemDraw selection pasted successfully. Native CDX source, SVG vectors, and saved picture proportions passed verification. The reported selection did not require a raster fallback or a change to its chemistry.

## Fix

When PowerPoint returns an unsaved presentation name rather than an absolute path, the helper now presents a native save-location dialog. It retains the clipboard snapshot captured by the original paste. After saving the original presentation as PPTX, it continues that paste and verifies the actual saved file. The existing target-identity check still rejects insertion if the active deck changes before insertion.

While the save dialog is open, the native monitor passes normal input to PowerPoint. Canceling leaves the presentation unchanged and keeps the captured source locally; errors and cancellation clear the temporary dialog state. A missing previously saved file does not trigger an unsolicited Save As operation. Word's save-first requirement is unchanged.

## Actual application checks

| Scenario | Observed result |
| --- | --- |
| Paste the reported selection into the user's now-saved presentation | Managed SVG drawing inserted; source and geometry checks passed |
| Create a new unsaved PowerPoint deck and press ⌘V | Save-location dialog appeared with a proposed PPTX name |
| Type a filename, navigate to a local test folder, and save | Input worked normally; the original paste continued without another copy or paste |
| Compare the source in both saved decks | Both contained the exact original captured CDX bytes at insertion |
| Repeat in another blank deck and cancel the save dialog | No drawing inserted, `paste_cancelled` recorded, temporary state cleared |
| Double-click the drawing in the user's original deck and close with ⌘W | Matching ChemDraw source opened; write-back verified; returned to the original PowerPoint document |

After the final close, the saved source matched the independent committed ChemDraw file exactly. Native SVG artwork and the displayed figure proportions were verified. Preview comparison had mean pixel error approximately **0.001913** and ink coverage **1.0**, within the existing acceptance limits. ChemDraw updated document metadata on save; insertion and post-close hashes are not assumed to remain identical. No semantic chemical edits were introduced during this recheck.

The original ChemDraw document was left open. Test decks were closed after use, and the user's presentation was left showing the inserted drawing. The final helper state had no active edit.

## Checks and scope

All **28 automated tests passed**. Four new cases cover unsaved PowerPoint save-and-resume with exact captured source, cancellation without insertion, cleanup after save failure, and refusal to Save As a missing saved target. The native helper and the PowerPoint AppleScript adapter compiled successfully.

The user's actual clipboard captures, source files, and presentation copies remain in the ignored local work folder. Public regression tests use the existing synthetic ethanol fixture. This report adds no new acceptance claim for the red close button, application quitting, crashes, or other Office versions.

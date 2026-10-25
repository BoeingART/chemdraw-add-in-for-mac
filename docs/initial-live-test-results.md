# Live test results

> Historical report for the initial close-only prototype. See [current copy/paste results](live-test-results.md) for the later portable-graphic implementation.

Tested locally on **25 October 2026**, using the installed applications and separate, newly created documents. This is a working prototype of the managed-figure workflow, not a claim of complete Windows OLE compatibility.

## Test Mac

| Component | Version |
| --- | --- |
| macOS | 27.0, build 26A428 |
| ChemDraw | 22.0.0.22 |
| Microsoft Word | 16.114 |
| Microsoft PowerPoint | 16.114 |
| Python | 3.13.1 |

## Final acceptance runs

The four runs below used the final save-wait implementation. Each began with a real Office figure double-click. No manual save was inserted between the final edit and **⌘W**.

| Scenario | Word | PowerPoint |
| --- | --- | --- |
| Double-click opens the editable drawing in installed ChemDraw | Passed | Passed |
| Type a final text marker, then immediately press ⌘W | Passed: `WORD-IMMEDIATE-FINAL-Z` | Passed: `PPT-IMMEDIATE-FINAL-Z` |
| Last `Z` recovered from the saved Office source | Passed | Passed |
| Double-click again to reopen the saved drawing | Passed | Passed |
| Add a single bond, then immediately press ⌘W | Passed: 3 atoms / 2 bonds → 5 atoms / 3 bonds | Passed: 3 atoms / 2 bonds → 5 atoms / 3 bonds |
| Earlier final text survives the subsequent bond edit | Passed | Passed |
| Saved Office preview agrees with final ChemDraw PNG | Passed | Passed |
| Return to original application, document, and selected figure | Passed | Passed |
| Duplicate picture introduced | No | No |

The saved examples and their evidence are in [examples](../examples/README.md). They include the actual `.docx` / `.pptx`, the exact CDXML recovered during each commit, verification measurements, and the recorded close event.

### Persistent evidence

| Run | Source bytes | SHA-256 of the embedded final source |
| --- | ---: | --- |
| Word final text | 3,045 | `de961a918aef05b9ee8d1d252b48714f6dd9e9b37786639c10375294e30555de` |
| PowerPoint final text | 3,275 | `6cea3347cfd2de3bba078f4d75e569ca27c0cd5e004f25fe2b0fc88083f49e48` |
| Word final bond | 3,344 | `76ebc463ce2fe8fbdb96345fc5d2b8a6ad37b6740f1b4f4ef4d365b817c8e4fe` |
| PowerPoint final bond | 3,577 | `7e6f4bf900c94ad3aedccc0bc4219392bc54ecbb5710d647a8b039d994081bbe` |

For all four runs, the embedded preview had mean normalized pixel error **0.0** and symmetric ink coverage **1.0 / 1.0**. The source comparison is byte-for-byte. Preview comparison permits Office resizing/re-encoding; it is a visual comparison, not a PNG byte comparison. Application focus was recorded immediately after activation; the final bond runs also independently checked the active document and selected figure through Office's object model.

## Problems found and corrected

- An active ChemDraw caption editor can outlive a generic save event. Closing now allows earlier input to reach ChemDraw, finishes the caption, and waits for two clean saved-state observations before exporting. The brief settling interval is a practical workaround, not a formal guarantee that every future ChemDraw event queue is drained.
- A Word trial reported unsaved changes after save. The helper held the window open instead of discarding it. Bounded save/recheck handling was added, followed by the clean acceptance runs above.
- Word can resize or re-encode an imported PNG. Source and preview verification were separated so a harmless encoding change does not masquerade as lost chemistry.
- Word insertion and PowerPoint deletion can invalidate indexed picture references. The adapters now identify the replacement explicitly, preserving the managed figure count in the tested documents.
- PowerPoint initially did not persist a fixture when given a plain path string. The adapter now uses a file URL and the Open XML presentation format.

Earlier exploratory failures remain in the ignored local `work/events.jsonl`; they are not counted as successful acceptance runs.

## Red close button and other limits

**The red window button has not passed an end-to-end foreground test.** Handling is implemented, including the separate AppKit traffic-light process in this macOS version. The automation system delivered its red-button clicks to that separate process while Codex was foreground; those attempts did not establish a real ChemDraw close. A later successful close was logged as `command-w`, so it is counted only as ⌘W. Use ⌘W for the verified path.

This preview recognizes figures it created. Arbitrary pasted pictures, existing Windows OLE objects, File-menu Close, Quit, crashes, Force Quit, grouped objects, complex wrapping, effects, animations, layering, cloud collaboration, and arbitrary ChemDraw content have not received these acceptance tests. Copying just the PowerPoint picture omits its separate source box. Copy the entire example document instead.

The helper operates on one managed drawing at a time. It saves the original Office document as part of write-back, including any other pending document edits. Use the separate examples or copies of your work. Local drafts remain in `work/sessions`; a failed transaction can leave Office partially updated, so this is not an atomic cross-application transaction.

## Automated checks

**8 tests passed**: metadata round-trip and corruption rejection; valid and visibly different preview comparison; save failure, independent Office-source conflict, and saved-preview failure. The failure tests check that the managed drawing is not closed and its final draft is retained. These are unit tests with mocked application failures, not simulations of an actual application crash.

Both demo launchers were run on this Mac. The native monitor compiled successfully, and the launch scripts passed shell syntax checks. Accessibility and application-control access were already available to the test process. Fresh Terminal permission prompts and a clean-machine installation are not covered by this run.

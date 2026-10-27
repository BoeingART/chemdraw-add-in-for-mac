# Installed save synchronization verification — v1.3.1

Date: 2026-10-27. ChemDraw 26.0.0.6599, Word and PowerPoint on the user's Mac.

## Reproduction and cause

The installed v1.3.0 helper logged an opened or resumed drawing and immediately logged `stopped`. Both its helper process and keyboard/mouse monitor were gone before Command-S. Restarting the helper synchronized the pending saved source, but double-clicking the same figure reproduced the immediate exit.

The event monitor hosted an AppKit progress panel while using one bare `CFRunLoopRun()` invocation as its process lifetime. An AppKit interruption during activation returned from that invocation, allowing the monitor to exit successfully and taking the save observer down with it. The previous component-level save tests did not exercise this installed monitor lifetime.

## Fix and automated checks

- `NativeMonitorLoop` runs AppKit's application event loop. A parent-process watchdog stops it and posts a wake event so timer-triggered shutdown completes and progress feedback clears.
- The helper reports an unexpected monitor exit as a failure with the exit status and recovery action.
- The installer and add-in metadata identify the corrected build as v1.3.1, application build 12.
- All 147 native checks passed, including two new monitor-lifetime checks. The new regression interrupts the underlying Core Foundation run loop, verifies that application event handling continues, and then checks parent-exit cleanup.
- Universal installer checks passed: both architectures, signatures, payload, metadata, native interface self-test, packaged discovery, offline scripts and internal integrity validation.

Apple documents the lifetime of [`NSApplication.run()`](https://developer.apple.com/documentation/appkit/nsapplication/run()) and the need for an event when [`stop(_:)`](https://developer.apple.com/documentation/appkit/nsapplication/stop(_:)) is called from a timer.

## Installed end-to-end checks

The user completed the v1.3.1 installation and system permission prompts. Verification used the application in `/Applications/ChemDraw Add-in for Mac.app`, its real helper, its real event monitor, the normal chemical clipboard and the ordinary Office insert/update adapters. Office cache files were written by the installed helper.

- Original PowerPoint drawing: resumed the retained edit, completed close/write-back, and later reopened the original figure. Its source bytes matched the backup retained before these checks.
- Word: created an independent unsaved document, pasted chemistry with Command-V and double-clicked it. Deleted all objects and pressed Command-S; the existing Office figure visibly became white. Undo followed by File → Save restored its chemistry and text. Both completed saves left the ChemDraw edit open; Command-W subsequently committed and closed it.
- PowerPoint: created an independent unsaved presentation and pasted through Command-V. Double-click, clear/Command-S, undo/Command-S and close/write-back all succeeded. The existing picture visibly changed to white and then back to the chemical structure and text.
- The same helper and monitor processes, 94521 and 94522, remained alive throughout these opens, saves, focus changes and closes. No monitor stop occurred during the final installed run.

A system permission prompt initially blocked the first Word paste and that attempt timed out. After the user completed that prompt, retry and all subsequent save checks succeeded. A separate command-line demo invocation lacked Office container access; the installed GUI flow above performed the final verification.

The test PowerPoint presentation was closed without saving. The unsaved Word test document remains available for inspection. The original PowerPoint document and its ChemDraw editing window were restored for the user; plugin operations did not save the user's Office document.

# Office file-access recovery — v1.3.2

Date: 2026-10-28.

## Cause and correction

In v1.3.1, `preinstall` exited without renewing Office-container consent. The setup loop retried filesystem access, but provided only a Files & Folders settings link when a previous denial or stale application decision prevented a new prompt. Earlier installed validation of this failure mode is recorded in `installation-readiness-results.md`.

The installer again resets only `SystemPolicyAppDataDetailed` for the bundle identifier read from the payload, in the signed-in desktop user's session. Offline targets and sessions without a desktop user are skipped. An unregistered first installation continues to setup; other renewal failures stop with the specific cause. Accessibility and Automation decisions are retained.

The native setup checks Cocoa and POSIX permission failures separately for Word and PowerPoint. A denied host offers **重新授权文件访问**, and **修复加载项** also requests renewed Office-container consent for the running application. Renewal is an explicit operation on the serial setup queue; the polling loop verifies access and automatically resumes setup after the user grants it. Repeated clicks during renewal do not schedule duplicate renewals. Other filesystem failures display their cause.

Both the add-in and preview directories now require an actual disposable write/read-back probe. A readable, already-current manifest alone cannot mark its host ready. Probes are removed after verification. The existing startup policy continues to require keyboard/mouse-monitor readiness before completion.

## Completed checks

- Installer script fixtures: 14 passed. These execute rewritten copies of the real scripts against command shims, covering scoped renewal, user-session execution, payload identity, unknown first-install identities, reset failures, offline/no-user installations, legacy cleanup, relaunch, and retained data.
- Native installer checks: 13 passed with `build/test-panel --installer-only`, including explicit renewal scope and failure handling, wrapped permission errors, per-host failure/recovery, directory writing/read-back, existing manifests, unrelated add-ins, certificate retention, and Word-only configuration.
- Startup/readiness checks: 12 passed with `build/test-setup`, including automatic continuation after authorization, failure retry, process-specific readiness, and duplicate-helper prevention.
- Task-pane checks: 8 passed with `node tests/taskpane.test.cjs`.
- Core drawing checks: 17 passed before the complete native runner stopped at its clipboard test.
- Version metadata, concise installer/release text, shell syntax, and `git diff --check` passed.
- Universal native build completed successfully for `arm64` and `x86_64`; both final executables contain both architectures. Compiler caches were placed under `build/module-cache` for the restricted execution environment.

## Build and installed verification still required

The complete native runner stopped in `test-monitor`: the restricted environment could not expose the test chemical pasteboard, producing “Chemical clipboard was not recognized”. The packaged UI self-test also exited before producing a result in this environment.

Packaging stopped at the system icon conversion tool with “Invalid Iconset”. A separate attempt to sign the staged event monitor with the existing project identity returned “no identity found”. The existing signing policy was retained. No v1.3.2 installer was produced, and expanded-package checks were not run.

The installed application still reports v1.3.1. This run did not change live system privacy decisions or replace the installed application. Build the installer in the maintainer's normal desktop terminal using `zsh scripts/package.sh`, then run `zsh scripts/test-package.sh`. Installed acceptance requires the user to confirm the Word/PowerPoint prompts and observe successful setup and paste-helper readiness.

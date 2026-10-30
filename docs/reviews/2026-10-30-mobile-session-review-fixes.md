# Reviewed mobile session fixes — 2026-10-30

## Scope and evidence

Read AGENTS.md, docs/governance/COMMON_PRINCIPLES.md, PROJECT_CONTEXT.md and CHECKLIST.md (the latter two are under docs/governance), and the neorang-narang-dev and surgical-patch skills. Branch: feature/mobile-broker-poc.

Existing working-tree changes were present in Android manifests/MainActivity, lib/main.dart, lib/pages/home_page.dart, macOS generated registration, Android debug resources, lib/mobile, test/mobile_sync_test.dart and three review documents. Preserved them. This task edits only lib/mobile/mobile_sync.dart, mobile_page.dart, mobile_transport_io.dart, test/mobile_sync_test.dart and this new review.

Code evidence: withdrawal/logout buttons were enabled during upload, but their _run calls lacked concurrent:true, so _run returned without invoking MobileSync. Transport mapped both 401 and 403 to login_required; MobileSync never invalidated rejected credentials. Page disposal removed the handoff handler but retained the pending PKCE transaction in the shared session.

## Changes

- Route withdrawal/logout through the existing concurrent action mechanism. Its result epoch prevents the earlier upload result from overwriting the newer action message. Preserve the existing transaction that persists withdrawal intent and cancels queued rows before network deletion, the guarded upload update, and immediate local logout credential removal.
- Bind authenticated requests to the sending session epoch and token. A current-session 401 clears credentials and active consent without deleting queues, owner/generation or deletion intent. Older-session failures cannot invalidate a replacement session, including a replacement with the same token value. HTTP 403 remains request_rejected, distinct from invalid authentication.
- Cancel pending login on page disposal, including transaction creation, exchange and status initialization. Reject late results with the existing epoch mechanism. Clear provisional credentials if exchange has completed but login initialization is pending. Install the handoff handler before ready and ignore callbacks on disposed pages. Keep PKCE verifier construction, transaction matching and single-use consumption.

Regression additions: actual withdrawal/logout button taps against real MobileSync with a controlled in-flight upload and temporary SQLite fixture; logout request is separately held to assert immediate local logout. Tests observe real operation futures inside runAsync, avoiding SQLite waits in widget fake async. Also cover current/stale 401, queue/deletion preservation and relogin, HTTP status classification, leaving/reopening the page and late handoff, single-use rejection, cancellation during transaction creation/exchange/status initialization. Existing test assertions were retained; no existing tests were removed or weakened.

No schema, real records, server API, Auth0, device data or SDK permission changes. No actual databases or network services were opened by this task. No .mobile-stage application, stage_mobile_client.py, staging, commit or push.

## Actual checks in this task

- PASS: git diff --check (tracked changes; only pre-existing CRLF conversion warnings). The mobile sources/test are untracked in this working tree, so separately scanned those four files for trailing whitespace: no matches.
- PASS, static inspection only: no print/debugPrint calls in mobile sources/test; no stage_mobile/.mobile-stage references there. No runtime privacy claim.
- SDK probe: D:\flutter\bin\dart.bat --version produced no output and remained running across polls; interrupted it. No SDK bootstrap/access retries after this failure to start. This run did not produce a lockfile denial diagnostic, so the exact cause remains UNKNOWN.
- NOT_RUN: dart format, scoped Flutter tests, flutter analyze, full suite, Android build/device verification. Test startup was not reached; added tests are unexecuted.
- Environment probes also found python unavailable and py -3 reporting no installed Python; those edit attempts made no changes. A process inventory query was denied. Subsequent edits used apply_patch/PowerShell only.

Prior repository review documents describe earlier formatting and SDK lockfile-denial results. Those are prior recorded reports, not checks executed or confirmed in this task. No prior user-reported test success is counted as current validation.

Run directly in PowerShell with normal writable SDK access:

```powershell
Set-Location D:\CHGO-VibeCodeing\neorang_narang_app
& D:\flutter\bin\dart.bat format lib/mobile/mobile_sync.dart lib/mobile/mobile_page.dart lib/mobile/mobile_transport_io.dart test/mobile_sync_test.dart
& D:\flutter\bin\flutter.bat test test/mobile_sync_test.dart --reporter expanded
& D:\flutter\bin\flutter.bat analyze
```

Runtime acceptance remains unverified until these commands complete successfully.

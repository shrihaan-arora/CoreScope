# Security and privacy model

## Runtime behaviour

CoreScope is designed to read local hardware state only. The current source code contains no `URLSession`, web requests, analytics SDK, login system, cloud storage, remote configuration, shell/subprocess execution, auto-updater, launch-at-login entry, daemon, or privileged helper.

The hardware sensor library is created lazily after the window opens and retained only for the lifetime of the running process. It is not installed as a system service. There is no timer or continuous sensor poll: the app takes a reading on launch and then only after a user-initiated refresh.

Closing the last window asks macOS to terminate the app. The operating system releases the process's memory and process-owned resources at exit. RAM cannot be zero while the dashboard is open, and no software can guarantee immunity from all exploitation.

## Dependency

CoreScope has zero external package dependencies. It interfaces directly with native Apple frameworks (`IOKit`, `Foundation`, `SwiftUI`) and includes an internal C target (`CIOHIDSensors`) for private IOKit HID sensor headers. No packages are fetched at build time or runtime.

## Permissions

The prototype does not request administrator/root privileges. If the sensor library cannot access a reading, the UI reports the value as unavailable. Do not add a privileged helper merely to make a sensor value appear without a separate security review and explicit consent design.

## Release checklist

Before publishing a built app:

- Review source changes and the resolved dependency version.
- Confirm the app bundle contains no unexpected helper executables or login items.
- Inspect entitlements and ensure no network client or unnecessary capability was added.
- Test the app with outgoing network access blocked and verify core monitoring still works.
- Confirm Activity Monitor shows no CoreScope process after quitting.
- Publish source, dependency notices, checksums, and reproducible build instructions.
- Do not describe the app as “unhackable” or claim that GitHub hosting alone guarantees safety.

## Reporting an issue

Report suspected privacy or security problems through the repository's GitHub Security Advisories once a public repository has been created. Do not include personal data or machine identifiers in public reports.

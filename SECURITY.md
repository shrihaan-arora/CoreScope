# Security and privacy model

## Runtime behaviour

CoreScope is designed to read local hardware state only. The source code contains no intentional app-level network calls, `URLSession` invocations, web requests, analytics SDKs, login systems, cloud storage, remote configuration, shell/subprocess execution, auto-updaters, launch-at-login entries, daemons, or privileged helpers. The absence of intentional network capabilities significantly reduces the external attack surface, but does not constitute an absolute guarantee against every possible exploit, memory defect, or local security boundary issue in underlying macOS system libraries.

Hardware sensor resources are managed strictly on demand: the HID event-system client (`IOHIDEventSystemClient`) and power-source handles are created specifically for each scan and released immediately after data collection. They are never retained across scans or held open for the lifetime of the process, nor are they installed as a system service. There is no background timer, file watcher, or continuous sensor polling loop: the application takes one scan upon opening and refreshes only when the user explicitly clicks **Refresh**.

Closing the last window asks macOS to terminate the application. The operating system cleans up process memory and descriptors at exit. RAM usage is non-zero while the dashboard window is open, and no software can offer absolute immunity from all exploitation.

## Dependency

CoreScope has zero external package dependencies. It interfaces directly with native Apple frameworks (`IOKit`, `Foundation`, `SwiftUI`) and includes an internal C target (`CIOHIDSensors`) for private IOKit HID sensor headers. No packages are fetched at build time or runtime.

## Permissions

CoreScope does not request administrator or root privileges (`sudo`). If any sensor reading is restricted or inaccessible, the UI reports the value as unavailable rather than attempting privilege escalation. Do not add a privileged helper or helper executable merely to make a sensor value appear without a separate security review and explicit consent design.

## Release checklist

Before publishing a built app:

- Review source changes and confirm `Package.swift` has zero external dependencies.
- Confirm the app bundle contains no unexpected helper executables, daemons, or login items.
- Inspect entitlements and ensure no network client or unnecessary capability was added.
- Test the app with outgoing network access blocked and verify core monitoring still works.
- Confirm Activity Monitor shows no CoreScope process after quitting.
- Publish source, dependency notices, checksums, and reproducible build instructions.
- Do not describe the app as “unhackable” or claim that GitHub hosting alone guarantees safety.

## Reporting an issue

Report suspected privacy or security vulnerabilities via [GitHub Security Advisories](https://github.com/shrihaan-arora/CoreScope/security/advisories) on the public repository. Do not include personal data or machine identifiers in public reports.

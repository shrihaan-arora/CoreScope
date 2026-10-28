# Third-party notices

CoreScope has **zero external package dependencies**.

All hardware telemetry is implemented natively using macOS system frameworks and private Apple Silicon IOKit HID services:
- **PMU Temperature Sensors:** Queried directly via Apple's local IOKit HID Event System (`IOHIDEventSystemClient`, usage page `0xFF00`, usage `0x05`) without root privileges or third-party binaries.
- **Power and Battery Telemetry:** Queried directly via macOS `IOKit.ps` (`IOPowerSources`).
- **Thermal Pressure:** Queried directly via Apple Foundation `ProcessInfo.thermalState`.

No third-party packages, remote code, or tracking libraries are included in this project.

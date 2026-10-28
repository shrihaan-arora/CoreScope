# CoreScope

A native, on-demand macOS hardware dashboard for Apple Silicon. CoreScope provides genuine PMU die temperatures, AC/DC power-source detection, battery telemetry, and macOS thermal pressure without external dependencies, daemons, or root privileges.

## Core design rules

- **Independent native implementation**: Zero external dependencies. Uses Apple's native IOKit HID event system and system frameworks directly.
- **On-demand only**: No menu-bar extra, login item, daemon, launch agent, privileged helper, or continuous polling.
- **Zero background overhead**: One scan when opened; one new scan only when the user presses **Refresh**.
- **Responsive UI**: Scanning runs off the UI thread so the dashboard opens instantly.
- **100% Private**: Zero network calls, analytics, accounts, or telemetry reporting.
- **Truthful data**: Hardware values are never fabricated or estimated. If a sensor is inaccessible, the UI explains why.
- **Clean exit**: Closing the window terminates the process.

## Requirements

- macOS 13 or later on Apple Silicon (M-series).
- Xcode 15+ or matching Swift 6 toolchain.
- No internet access required — builds completely offline with zero package dependencies.

## Run CoreScope

1. Open Terminal and navigate to the project directory:

   ```sh
   cd CoreScope
   ```

2. Build and run the GUI application:

   ```sh
   swift run CoreScope
   ```

3. Or run the headless CLI probe to inspect sensor output directly in Terminal:

   ```sh
   swift run CoreScope --cli
   ```

## Hardware Telemetry Architecture

### PMU Temperature Sensors
Apple Silicon exposes hardware thermal nodes via the local IOKit HID Event System. CoreScope queries `IOHIDEventSystemClient` with matching criteria for the Apple vendor usage page (`0xFF00`, usage `0x05`). Each matching service provides:
- Live die temperature (`IOHIDServiceClientCopyEvent` with `kIOHIDEventTypeTemperature`).
- Hardware node descriptor (`IOHIDServiceClientCopyProperty` with `Product`).
- Subsystem categorization (Silicon Die, Device Nodes, Battery, Storage).

### Power & Battery
Power status is gathered via Apple's public `IOPowerSources` (`IOKit.ps`) API, accurately distinguishing between:
- Active power source (AC power vs. battery discharge).
- Physical external power adapter attachment.
- Active battery charging state (e.g. charging vs. charge hold).

### Thermal State
System thermal pressure level is read directly from `ProcessInfo.processInfo.thermalState` (Nominal, Fair, Serious, Critical).

### Hardware-Specific Limitations
- **Sensor Identifiers**: Thermal nodes are reported under their genuine Apple PMU channel names (e.g. `PMU tdie1`, `PMU tdev4`, `gas gauge battery`). Apple does not publicly document a 1:1 mapping between PMU channel names and specific CPU/GPU core numbers; CoreScope intentionally presents the authentic raw descriptors rather than fabricating core assignments.
- **Platform Scope**: Validated on Apple Silicon M-series (tested on Apple M4). Intel Macs use legacy SMC keys and are not supported by this HID-based probe.

## Security and Privacy

See [SECURITY.md](SECURITY.md) and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## License

CoreScope is licensed under the MIT License. See `LICENSE`.

# CoreScope

A native, on-demand macOS hardware dashboard for Apple Silicon. CoreScope provides genuine PMU die temperatures, AC/DC power-source detection, battery telemetry, and macOS thermal pressure without external dependencies, daemons, or root privileges.

## Core design rules

- **Independent native implementation**: Zero external dependencies. Uses Apple's native IOKit HID event system and system frameworks directly.
- **On-demand only**: No menu-bar extra, login item, daemon, launch agent, privileged helper, or continuous polling.
- **Zero background overhead**: One scan when opened; one new scan only when the user presses **Refresh**.
- **Responsive UI**: Scanning runs off the UI thread so the dashboard opens instantly.
- **Local-only by design**: CoreScope is designed to make no intentional app-level network requests, has no telemetry or cloud backend, and reads hardware information locally. While this offline design significantly minimizes exposure, no software can guarantee absolute immunity from data leaks or every possible exploit.
- **Truthful data**: Hardware values are never fabricated or estimated. If a sensor is inaccessible, the UI explains why.
- **Clean exit**: Closing the window terminates the process.

## Requirements

- macOS 13 or later on Apple Silicon (M-series).
- Xcode 15+ or matching Swift 6 toolchain.
- No internet access required — builds completely offline with zero package dependencies.

## Build and Run

### 1. Run in Development Mode

Run the native SwiftUI application directly:
```sh
swift run CoreScope
```

Or run the headless CLI probe to inspect sensor channels in Terminal:
```sh
swift run CoreScope --cli
```

### 2. Package into a Native macOS Application (.app)

CoreScope includes a reproducible packaging script that builds the release binary with Swift Package Manager, structures a standard `CoreScope.app` bundle, generates `Info.plist`, applies an ad-hoc signature, and creates an optional ZIP archive:

```sh
./scripts/package-app.sh
```

Launch the packaged application:
```sh
open build/CoreScope.app
```

#### Customizing the Bundle Identifier
You can customize bundle metadata via environment variables:
```sh
BUNDLE_ID="io.custom.corescope" APP_VERSION="1.1.0" ./scripts/package-app.sh
```

*Note on code signing and distribution*: The packaging script applies an ad-hoc code signature (`codesign --sign -`) to establish bundle code integrity for execution on the local build machine. Ad-hoc signing does **not** provide Apple Developer ID signing or Gatekeeper notarization. Normal external distribution to other macOS systems requires an Apple Developer account, an official Developer ID Application certificate, and completion of Apple's automated notarization ticket stapling workflow (`xcrun notarytool`). Do not disable macOS security protections or strip quarantine attributes to run untrusted binaries.

### 3. Run Automated Tests

Execute the complete test suite (both synthetic invariant tests and live Apple Silicon hardware probe checks):
```sh
swift test
```

## Hardware Telemetry Architecture

### PMU Temperature Sensors
Apple Silicon exposes hardware thermal nodes via the local IOKit HID Event System. CoreScope queries `IOHIDEventSystemClient` with matching criteria for the Apple vendor usage page (`0xFF00`, usage `0x05`). Each matching service provides:
- Live die temperature (`IOHIDServiceClientCopyEvent` with `kIOHIDEventTypeTemperature`).
- Hardware node descriptor (`IOHIDServiceClientCopyProperty` with `Product`).
- Subsystem categorization:
  - **Silicon Die (`tdie`)**: Compute complex thermal sensors embedded across CPU/GPU cores and SoC fabric.
  - **Device Nodes (`tdev`)**: Peripheral power-management thermal nodes across the logic board.
  - **Battery (`battery` / `gas gauge`)**: Battery pack thermal sensors.
  - **Storage (`nand` / `storage`)**: NVMe and NAND flash storage controller sensors.
  - **Calibration / Reference (`tcal`)**: Reference channels reported by Apple PMU firmware. These are strictly isolated from operating die averages. CoreScope does not speculate on internal PMU calibration register designs without official technical documentation.

Sensor resources follow an on-demand lifecycle: `IOHIDEventSystemClient` and matching service handles are instantiated strictly for the duration of a scan and released immediately after reading. No sensor clients or timers remain active while the dashboard is idle.

### Power & Battery
Power status is gathered via Apple's public `IOPowerSources` (`IOKit.ps`) API, accurately distinguishing between:
- Active power source (AC power vs. battery discharge).
- Physical external power adapter attachment.
- Active battery charging state (e.g. charging vs. charge hold).

### Thermal State
System thermal pressure level is read directly from `ProcessInfo.processInfo.thermalState` (Nominal, Fair, Serious, Critical).

### Hardware-Specific Limitations
- **Sensor Identifiers**: Thermal nodes are reported under their genuine Apple PMU channel names (e.g. `PMU tdie1`, `PMU tdev4`, `gas gauge battery`). Apple does not publicly document a 1:1 mapping between PMU channel names and specific CPU/GPU core numbers; CoreScope intentionally presents the authentic raw descriptors rather than fabricating core assignments.
- **Calibration Channels (`tcal`)**: PMU channels labeled `tcal` are classified separately under Calibration / Reference and excluded from operating summaries. They are not assumed or claimed to represent factory calibration setpoints or target temperatures.
- **Platform Scope**: Validated on Apple Silicon M-series (tested on Apple M4). Intel Macs use legacy SMC keys and are not supported by this HID-based probe.

## Security and Privacy

See [SECURITY.md](SECURITY.md) and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## License

CoreScope is licensed under the MIT License. See `LICENSE`.

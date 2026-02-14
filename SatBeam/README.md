# SatBeam — Satellite Signal Measurement

Measure and map satellite connectivity using your iPhone 14+.

## What It Does

SatBeam detects your iPhone's connection type (satellite, cellular, Wi-Fi),
measures network latency as a signal quality proxy, and logs each measurement
with your GPS location. Results are plotted on a color-coded map.

### 4 Tabs

- **Record** — Big red REC button. Shows live connection type, carrier, RAT, latency.
- **Log** — List of all measurements with averages. Export to CSV.
- **Map** — Color-coded dots on a map showing where you measured and how good the signal was.
- **Sky** — Compass that shows where Globalstar satellites are likely visible in your sky.

## What It Measures

Each tap of REC captures:

- **Connection type** — Satellite / Cellular / Wi-Fi (via CoreTelephony + NWPathMonitor)
- **Latency** — Round-trip time in ms to Apple's connectivity endpoint
- **Carrier name** — Your cellular provider or "Globalstar" for satellite
- **Radio access technology** — LTE, NR, NTN, etc.
- **GPS location** — Latitude, longitude, altitude
- **Signal quality** — Derived from latency (Excellent/Good/Fair/Weak/No Signal)

## Requirements

- iPhone 14 or later (has Globalstar satellite modem)
- iOS 17.0+
- Xcode 15+ on a Mac
- Free Apple Developer account (for running on your phone)
- Location permission

## How to Build & Run (Step by Step)

### 1. Create the Xcode Project

1. Open **Xcode** on your Mac
2. **File → New → Project**
3. Choose **iOS → App** and click Next
4. Fill in:
   - Product Name: `SatBeam`
   - Team: (your Apple ID)
   - Organization Identifier: `com.satbeam`
   - Interface: **SwiftUI**
   - Language: **Swift**
5. Click **Create** and save it somewhere

### 2. Replace the Generated Files

Xcode created some starter files. Replace them with the SatBeam source:

1. In Xcode's file navigator (left panel), **delete** these generated files:
   - `ContentView.swift`
   - `SatBeamApp.swift` (we have our own)
2. **Drag the following folders/files** from this repo's `SatBeam/` directory
   into the Xcode project navigator:
   - `SatBeamApp.swift`
   - `Info.plist`
   - `Models/` folder
   - `Services/` folder
   - `Store/` folder
   - `Views/` folder
3. When prompted, check **"Copy items if needed"** and make sure the target is checked

### 3. Configure the Project

1. Click the **project name** (blue icon) in the navigator
2. Under **General**:
   - Minimum Deployments: **iOS 17.0**
3. Under **Info**:
   - Xcode should pick up the `Info.plist` — verify the location permissions are there
4. Under **Signing & Capabilities**:
   - Team: Select your Apple ID
   - Bundle Identifier: `com.satbeam.app`

### 4. Run on Your iPhone

1. **Plug in your iPhone** via USB (or use wireless debugging if set up)
2. Select your iPhone from the device dropdown at the top of Xcode
3. Click the **Play button** (or Cmd+R)
4. First time: your phone may say "Untrusted Developer"
   - Go to **Settings → General → VPN & Device Management** → tap your developer profile → Trust
5. Run again — the app should launch!

**Note:** The satellite radio is not available in the iOS Simulator. You must run on a physical iPhone 14+.

## How to Test

- **On Wi-Fi:** Tap REC — you'll see "Wi-Fi" connection type and low latency (~5-30ms)
- **On Cellular:** Turn off Wi-Fi, tap REC — you'll see "Cellular" and medium latency (~30-100ms)
- **On Satellite:** Go outside with no cell service, trigger satellite messaging, tap REC — you'll see high latency (~600-2500ms) and potentially "Globalstar" as carrier
- **Sky tab:** Rotate your phone — the compass tracks heading and shows where satellites orbit

## Export

Tap **Export** in the Log tab to share a CSV file. Import into Python, Excel, or any GIS tool.

## Technical Notes

- Uses **only public iOS APIs** — no jailbreak, no private entitlements needed
- CoreTelephony detects carrier name and radio access technology
- NWPathMonitor detects connection type changes
- Latency is measured via HTTP HEAD to `captive.apple.com`
- Signal quality thresholds are tuned per connection type (satellite has higher acceptable latency)
- Sky view uses Globalstar orbital parameters (52 deg inclination, 1414 km altitude) to approximate satellite visibility

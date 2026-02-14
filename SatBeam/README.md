# SatBeam — Satellite Beam Power Measurement

Measure and map satellite spot beam signal strength using your iPhone 14+.

## How It Works

The app reads satellite signal metrics from the iPhone's Qualcomm baseband
(which handles the Globalstar NTN connection used for Emergency SOS / satellite
messaging). Each tap of the REC button captures:

- **Beam power** (RSRP in dBm)
- **Signal quality** (RSRQ, SINR)
- **Satellite name** (constellation or individual sat)
- **GPS location** (latitude, longitude, altitude)

All measurements are logged and plotted on a color-coded map.

## Signal Reading Strategy

The app uses a layered approach to read signal metrics:

1. **CoreTelephony** (public API) — detects NTN radio access technology
   and carrier info (Globalstar)
2. **Baseband log cache** — parses RSRP/RSRQ/SINR/RSSI values from
   the Qualcomm baseband logs on disk
3. **Private frameworks** — extension point for CommCenter XPC or
   Field Test internals on development devices

### Enhancing Signal Reads

For the richest data, pull a **sysdiagnose** after a satellite session:

```
Volume Up → Volume Down → Hold Side Button (~1.5s, feel vibration)
```

Then connect to a Mac and extract baseband logs:

```bash
idevicecrashreport -e /tmp/sysdiag
tar xzf /tmp/sysdiag/sysdiagnose_*.tar.gz
grep -ri "RSRP\|RSRQ\|SINR\|NTN" logs/Baseband/
```

The key names found there can be added to `SignalService.parseBasebandLog()`
to extract exact dBm values.

## Requirements

- iPhone 14 or later (has Globalstar satellite modem)
- iOS 17.0+
- Clear sky view (satellite needs line-of-sight)
- Location permission

## Building

1. Open Xcode
2. File → New → Project → iOS App (SwiftUI)
3. Replace the generated files with the contents of `SatBeam/`
4. Set deployment target to iOS 17.0
5. Add `CoreTelephony.framework` and `Network.framework`
6. Build and run on a physical device (satellite radio not available in simulator)

## Export

Tap **Export** in the Log tab to share a CSV file containing all measurements.
Import into Python, Excel, or any GIS tool for analysis.

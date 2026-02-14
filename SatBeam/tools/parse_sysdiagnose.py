#!/usr/bin/env python3
"""
parse_sysdiagnose.py — Find satellite / NTN signal data in an iPhone sysdiagnose.

Usage:
    1. Pull a sysdiagnose off your iPhone (see README)
    2. Run:
        python3 parse_sysdiagnose.py /path/to/sysdiagnose_2024.xxx.tar.gz

    Or if already extracted:
        python3 parse_sysdiagnose.py /path/to/sysdiagnose_folder/

    The script will:
    - Extract the archive (if needed)
    - Search ALL files for satellite/NTN/Globalstar keywords
    - Find signal metrics (RSRP, RSRQ, SINR, RSSI)
    - Print a summary of what it found and where
"""

import sys
import os
import re
import tarfile
import gzip
import json
from pathlib import Path
from collections import defaultdict

# Keywords that indicate satellite / NTN radio data
SATELLITE_KEYWORDS = [
    # NTN (Non-Terrestrial Network) — 3GPP term for satellite
    r'NTN',
    r'ntn',
    r'non.?terrestrial',
    # Globalstar (iPhone 14+ satellite provider)
    r'[Gg]lobalstar',
    r'GLOBALSTAR',
    # Satellite generic
    r'satellite',
    r'SATELLITE',
    r'sat.?link',
    r'sat.?conn',
    r'sat.?beam',
    # Band 53 / n53 (Globalstar NTN band)
    r'[Bb]and.?53',
    r'\bn53\b',
    r'n253',
    # Signal metrics with NTN/SAT prefix
    r'NTN.?RSRP',
    r'NTN.?RSRQ',
    r'NTN.?SINR',
    r'NTN.?RSSI',
    r'SAT.?RSRP',
    r'SAT.?RSRQ',
    r'SAT.?SINR',
    r'SAT.?RSSI',
    # Emergency SOS (satellite feature)
    r'emergencySOS',
    r'EmergencySOS',
    r'SOS.*satellite',
    # Qualcomm baseband NTN terms
    r'QMI.*NTN',
    r'nrNtn',
    r'NR_NTN',
    r'lte.?ntn',
    # Apple internal satellite framework names (speculative)
    r'SatelliteConnection',
    r'SatelliteManager',
    r'CommCenter.*satellite',
    r'CommCenter.*NTN',
    r'BasebandNTN',
]

# Signal metric patterns — these capture the actual dBm/dB values
SIGNAL_PATTERNS = [
    (r'(?:NTN[_.]?)?RSRP[\s:=]+(-?\d+\.?\d*)', 'RSRP'),
    (r'(?:NTN[_.]?)?RSRQ[\s:=]+(-?\d+\.?\d*)', 'RSRQ'),
    (r'(?:NTN[_.]?)?SINR[\s:=]+(-?\d+\.?\d*)', 'SINR'),
    (r'(?:NTN[_.]?)?RSSI[\s:=]+(-?\d+\.?\d*)', 'RSSI'),
    (r'(?:NTN[_.]?)?SNR[\s:=]+(-?\d+\.?\d*)',  'SNR'),
    (r'signal[_\s]?strength[\s:=]+(-?\d+\.?\d*)', 'signal_strength'),
    (r'rx[_\s]?power[\s:=]+(-?\d+\.?\d*)',      'rx_power'),
    (r'tx[_\s]?power[\s:=]+(-?\d+\.?\d*)',      'tx_power'),
    (r'beam[_\s]?id[\s:=]+(\d+)',               'beam_id'),
    (r'cell[_\s]?id[\s:=]+(\d+)',               'cell_id'),
    (r'earfcn[\s:=]+(\d+)',                     'earfcn'),
    (r'arfcn[\s:=]+(\d+)',                      'arfcn'),
]

# Interesting directories in a sysdiagnose
PRIORITY_DIRS = [
    'logs/Baseband',
    'logs/baseband',
    'Baseband',
    'logs/powerd',
    'logs/CommCenter',
    'logs/MobileWireless',
    'logs/networking',
    'logs/WiFi',
    'WiFi',
    'logs/CrashReporter/Baseband',
    'system_logs',
]


class SysdiagnoseParser:
    def __init__(self, path):
        self.path = Path(path)
        self.extracted_dir = None
        self.hits = defaultdict(list)       # file -> list of (line_num, line)
        self.signal_values = []             # list of (file, metric_name, value)
        self.interesting_files = set()

    def run(self):
        print(f"\n{'='*60}")
        print(f"  SatBeam Sysdiagnose Parser")
        print(f"{'='*60}\n")

        # Extract if tarball
        work_dir = self._prepare()
        if not work_dir:
            return

        print(f"Searching: {work_dir}\n")

        # Walk every file
        file_count = 0
        for root, dirs, files in os.walk(work_dir):
            for fname in files:
                fpath = Path(root) / fname
                file_count += 1
                self._scan_file(fpath)

        print(f"Scanned {file_count} files.\n")

        # Print results
        self._print_keyword_hits()
        self._print_signal_values()
        self._print_interesting_files()
        self._print_recommendations()

    def _prepare(self):
        if self.path.is_dir():
            return self.path

        if self.path.suffix == '.gz' or '.tar' in self.path.name:
            print(f"Extracting {self.path.name}...")
            extract_to = self.path.parent / 'sysdiag_extracted'
            extract_to.mkdir(exist_ok=True)
            try:
                with tarfile.open(self.path, 'r:*') as tar:
                    tar.extractall(path=extract_to)
                print(f"Extracted to {extract_to}\n")
                return extract_to
            except Exception as e:
                print(f"Error extracting: {e}")
                return None

        print(f"Error: {self.path} is not a directory or tarball")
        return None

    def _scan_file(self, fpath):
        # Skip binaries, images, etc.
        skip_ext = {'.png', '.jpg', '.jpeg', '.gif', '.bmp', '.ico',
                    '.mp4', '.mov', '.m4a', '.wav', '.pdf',
                    '.dylib', '.so', '.o', '.a', '.framework',
                    '.ips', '.ca', '.sqlite', '.db', '.shm', '.wal'}
        if fpath.suffix.lower() in skip_ext:
            return
        if fpath.stat().st_size > 50_000_000:  # skip files > 50MB
            return

        try:
            content = fpath.read_text(errors='ignore')
        except Exception:
            return

        rel_path = str(fpath)
        found_keyword = False

        for line_num, line in enumerate(content.splitlines(), 1):
            # Check satellite keywords
            for kw in SATELLITE_KEYWORDS:
                if re.search(kw, line):
                    self.hits[rel_path].append((line_num, line.strip()[:200]))
                    found_keyword = True
                    break

            # Check signal metrics (always, not just in satellite context)
            for pattern, name in SIGNAL_PATTERNS:
                match = re.search(pattern, line, re.IGNORECASE)
                if match:
                    self.signal_values.append((rel_path, name, match.group(1), line_num, line.strip()[:200]))

        if found_keyword:
            self.interesting_files.add(rel_path)

        # Also flag files in known baseband log directories
        for d in PRIORITY_DIRS:
            if d in str(fpath):
                self.interesting_files.add(rel_path)
                break

    def _print_keyword_hits(self):
        print(f"\n{'='*60}")
        print(f"  SATELLITE / NTN KEYWORD HITS")
        print(f"{'='*60}\n")

        if not self.hits:
            print("  No satellite/NTN keywords found in any file.")
            print("  This might mean:")
            print("    - No satellite session was active before the sysdiagnose")
            print("    - The baseband logs use different terminology")
            print("    - The logs were rotated/cleared")
            print()
            return

        total = sum(len(v) for v in self.hits.values())
        print(f"  Found {total} hits across {len(self.hits)} files:\n")

        for fpath, matches in sorted(self.hits.items()):
            # Shorten path for readability
            short = fpath.split('sysdiag_extracted/')[-1] if 'sysdiag_extracted' in fpath else fpath
            print(f"  --- {short} ({len(matches)} hits) ---")
            for line_num, line in matches[:10]:  # show first 10 per file
                print(f"    L{line_num}: {line}")
            if len(matches) > 10:
                print(f"    ... and {len(matches) - 10} more")
            print()

    def _print_signal_values(self):
        print(f"\n{'='*60}")
        print(f"  SIGNAL METRIC VALUES FOUND")
        print(f"{'='*60}\n")

        if not self.signal_values:
            print("  No signal metric values found.")
            print()
            return

        # Group by metric name
        by_metric = defaultdict(list)
        for fpath, name, value, line_num, line in self.signal_values:
            by_metric[name].append((fpath, value, line_num, line))

        for metric, entries in sorted(by_metric.items()):
            print(f"  {metric}: {len(entries)} occurrences")
            for fpath, value, line_num, line in entries[:5]:
                short = fpath.split('sysdiag_extracted/')[-1] if 'sysdiag_extracted' in fpath else fpath
                print(f"    = {value}  ({short}:L{line_num})")
            if len(entries) > 5:
                print(f"    ... and {len(entries) - 5} more")
            print()

    def _print_interesting_files(self):
        print(f"\n{'='*60}")
        print(f"  FILES WORTH EXAMINING MANUALLY")
        print(f"{'='*60}\n")

        if not self.interesting_files:
            print("  None found.")
            return

        for f in sorted(self.interesting_files):
            short = f.split('sysdiag_extracted/')[-1] if 'sysdiag_extracted' in f else f
            size = Path(f).stat().st_size if Path(f).exists() else 0
            print(f"  {short}  ({size:,} bytes)")
        print()

    def _print_recommendations(self):
        print(f"\n{'='*60}")
        print(f"  NEXT STEPS")
        print(f"{'='*60}\n")

        if self.hits:
            print("  Data found! Here's what to do:\n")
            print("  1. Look at the files listed above — the signal metric")
            print("     values and their key names are what the app needs")
            print("  2. Update SignalService.swift parseBasebandLog() with")
            print("     the exact key names you see (e.g. NTN_RSRP, nrRsrp)")
            print("  3. If values are in a plist or JSON, update the parser")
            print("     to handle that format")
        else:
            print("  No satellite data found. Try:\n")
            print("  1. Trigger a satellite session first:")
            print("     - Go outside with clear sky view")
            print("     - Open Messages → try sending via satellite")
            print("     - Or: Settings → Emergency SOS → satellite demo")
            print("  2. Wait a few minutes for the modem to log")
            print("  3. Then take a NEW sysdiagnose")
            print("  4. Run this script again on the new dump")
            print()
            print("  Alternative: try Field Test Mode on the iPhone:")
            print("    Phone app → dial *3001#12345#* → call")
            print("    Look for NTN or satellite panels")

        print()


if __name__ == '__main__':
    if len(sys.argv) != 2:
        print("Usage: python3 parse_sysdiagnose.py <sysdiagnose.tar.gz or folder>")
        sys.exit(1)

    parser = SysdiagnoseParser(sys.argv[1])
    parser.run()

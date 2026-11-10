# Hollyland Wireless Tally for OBS Studio

Light up a **Hollyland wireless tally system** (tested on a base with firmware S4.0.0.10, HW H000) from **OBS Studio** with no vMix needed. The OBS Python script pretends to be vMix's TCP API (port 8099), so the Hollyland base thinks it is talking to vMix.

ใช้ไฟ Tally ไร้สายของ Hollyland กับ OBS Studio ได้โดยไม่ต้องมี vMix: สคริปต์ Python ของ OBS จำลอง vMix TCP API (พอร์ต 8099) ให้ตัวฐานคุยด้วย

## Features
- Red = Program, Green = Preview (Studio Mode), real-time.
- Map each tally light (1–16) to an OBS scene or source.
- Status window opens automatically when the script loads (no terminal): big colored rows per light, this PC's IP, connection state.
- Auto-scans the network for the tally base and tells you what to set if it is found but not connected.
- One-click Windows installer.

## Install (Windows)
1. Install **Python 3.11 64-bit** from python.org (keep "tcl/tk" ticked).
2. Download this repo (Code → Download ZIP) and extract it.
3. **Close OBS**, then double-click `Install Hollyland Tally.bat`.
4. Open OBS. The script loads by itself and the status window appears.
5. In **Tools → Scripts → obs_hollyland_tally.py**, pick which scene/source each light number follows.

## Set up the tally base
On the Hollyland base, set **Switcher = vMix**, **Switcher IP = the IP of the computer running OBS** (shown in the status window), **port 8099**. Do not enter the base's own IP. Both must be on the same network.

## macOS
Copy `obs_hollyland_tally.py` and `tally_window.pyw` into the same folder, set OBS → Tools → Scripts → Python Settings to a Python 3.11 install, then add the script.

## How it works (protocol notes)
The Hollyland base does **not** send `SUBSCRIBE TALLY`. It polls about once per second with:
```
TALLY
ACTS Overlay1 … ACTS Overlay4
ACTS InputPreview
```
It needs:
- `TALLY OK <digits>` (0 = off, 1 = program, 2 = preview per input)
- `ACTS OK <name> <n>`; for `InputPreview`, `n` = the preview input number. **Green only lights when both TALLY digit 2 and InputPreview agree**, so only one light can be green at a time.

On a scene change the script also pushes `TALLY OK …` and `ACTS OK InputPreview n` immediately, so the lights do not wait for the next poll.

## Files
| File | Purpose |
|---|---|
| `obs_hollyland_tally.py` | OBS script (vMix TCP emulator + tally logic) |
| `tally_window.pyw` | Status window (tkinter), started by the script |
| `Install Hollyland Tally.bat`, `install.ps1`, `add_to_obs.py` | Windows installer |

## License
MIT

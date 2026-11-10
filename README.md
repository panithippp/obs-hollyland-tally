# Hollyland Wireless Tally for OBS Studio

Light up a **Hollyland wireless tally system** (tested on a base with firmware S4.0.0.10, HW H000) from **OBS Studio** with no vMix needed. The OBS Python script pretends to be vMix's TCP API (port 8099), so the Hollyland base thinks it is talking to vMix.

ใช้ไฟ Tally ไร้สายของ Hollyland กับ OBS Studio ได้โดยไม่ต้องมี vMix: สคริปต์ Python ของ OBS จำลอง vMix TCP API (พอร์ต 8099) ให้ตัวฐานคุยด้วย

## Features
- Red = Program, Green = Preview (Studio Mode), real-time.
- Map each tally light (1–16) to an OBS scene or source (auto-mapped to the first scenes until you choose).
- Status window opens automatically when the script loads (no terminal): big colored rows per light, this PC's IP, connection state.
- Status window can be resized freely (drag the frame): the colour bars and all text scale with it. Text size: **A- / A+** in the window, keys **+ / -** (**0** = 100 %), or OBS → Tools → Scripts → *Status window text size*. Size, position and text size are remembered (`~/.hollyland_tally_window.json`).
- Closing the status window (X) keeps it closed. To show it again: OBS → Tools → Scripts → **Open status window** (it also comes back when OBS restarts or the script is reloaded). If the window crashes, the script reopens it.
- Auto-scans the network for the tally base and tells you what to set if it is found but not connected.
- One-click Windows installer.

## Install (Windows)
1. On GitHub: **Code → Download ZIP**. Right click the ZIP → **Extract All**.
2. Double-click **`Install Hollyland Tally.bat`** in the extracted folder. That's all.

The installer does everything by itself, no admin needed:
- Finds OBS Studio (registry or the usual folders). If OBS is not installed it tells you.
- Finds a 64-bit Python that OBS can use (3.11 preferred, 3.12/3.10 OK; 3.13+ is not supported by OBS) via the registry, `py -0p` and the usual folders. If there is none, it downloads **Python 3.11.9 from python.org**, checks its signature and installs it for your user only (with tkinter for the status window). Falls back to `winget`.
- Closes OBS if it is open (and opens it again at the end). If OBS was never started on this PC, it starts it once so OBS creates its settings, then closes it.
- Copies the script, sets **Tools → Scripts → Python Settings** for you (`[Python] Path64bit` in `user.ini`, and `global.ini` for older OBS), and adds the script to **every scene collection**. Light settings you already made are kept.
- Checks Windows Firewall for incoming TCP **8099** to OBS. Only if a rule is missing or blocking, Windows asks once (UAC) to add the rule *Hollyland Tally (OBS TCP 8099)*. If you say No, it shows what to do.
- Prints a summary: Python, OBS, script added/loaded, firewall, and **this PC's IP to enter as Switcher IP on the base**.
- Log: `%TEMP%\hollyland_tally_install.log`.

Out of the box, **lights 1, 2, 3, 4 follow your first 4 OBS scenes** (scene list order). To choose yourself: **Tools → Scripts → obs_hollyland_tally.py** and pick a scene/source per light; your choice always wins.

**New OBS with fewer scenes than lights?** (a fresh OBS has only "Scene") The script then creates the missing scenes once, named **Camera 2, Camera 3, Camera 4** (so a fresh OBS ends up with Scene, Camera 2, Camera 3, Camera 4 = lights 1–4), and saves them. It never deletes or renames scenes, skips names that already exist, and does nothing if you have chosen any light yourself or turned auto-map off. Put each camera into its scene and you're ready.

### ติดตั้ง (ภาษาไทย)
1. กด **Code → Download ZIP** แล้วคลิกขวาที่ไฟล์ ZIP → **Extract All**
2. ดับเบิลคลิก **`Install Hollyland Tally.bat`** จบแค่นี้ ตัวติดตั้งหา OBS/Python เอง ถ้าไม่มี Python จะโหลด Python 3.11 จาก python.org มาติดตั้งให้ ตั้งค่า Python ใน OBS เพิ่มสคริปต์ เช็กไฟร์วอลล์ แล้วเปิด OBS ให้ ตอนจบจะบอก IP ของเครื่องนี้ไว้ใส่เป็น Switcher IP ที่ตัวฐาน
3. ตอนแรกไฟ 1–4 จะตาม Scene 4 อันแรกใน OBS อัตโนมัติ เปลี่ยนเองได้ที่ Tools → Scripts
4. ถ้าเพิ่งลง OBS ใหม่และยังมี Scene ไม่ถึง 4 อัน (OBS ใหม่มีแค่ "Scene") สคริปต์จะสร้าง Scene ที่ขาดให้เองครั้งเดียว ชื่อ **Camera 2, Camera 3, Camera 4** แล้วบันทึกไว้ ไม่ลบหรือเปลี่ยนชื่อ Scene เดิม และจะไม่สร้างถ้าคุณเลือกไฟเองแล้วหรือปิด auto-map ไว้ จากนั้นใส่กล้องลงในแต่ละ Scene ได้เลย

### Uninstall
Double-click **`Uninstall Hollyland Tally.bat`**: removes the script from all scene collections and deletes its files (Python and the OBS Python setting are left alone).

### Troubleshooting
- *"install.ps1 was not found"*: you ran the .bat from inside the ZIP. Extract the ZIP first.
- The window says the tally device is found but not connected: on the base set **Switcher IP = this PC's IP** (shown in the window), not the base's own IP.
- Anything else: send `%TEMP%\hollyland_tally_install.log`.

## หน้าต่างสถานะ (Status window) — ภาษาไทย
- ลากขอบหน้าต่างเพื่อย่อ/ขยาย แถบสีและตัวอักษรจะปรับขนาดตามอัตโนมัติ
- ปรับขนาดตัวอักษร: ปุ่ม **A- / A+** ในหน้าต่าง, คีย์ **+ / -** (**0** = 100%) หรือ OBS → Tools → Scripts → *ขนาดตัวอักษร % (Status window text size)* — จำขนาด/ตำแหน่งหน้าต่างไว้ให้ครั้งต่อไป
- กด X ปิดแล้วจะไม่เด้งขึ้นมาอีก ถ้าต้องการเปิดใหม่: OBS → Tools → Scripts → **🪟 เปิดหน้าต่างสถานะ (Open status window)** (เปิด OBS ใหม่ หรือ reload สคริปต์ ก็จะกลับมาเอง)

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
| `Uninstall Hollyland Tally.bat`, `uninstall.ps1` | Windows uninstaller |

## License
MIT

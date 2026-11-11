# Hollyland Wireless Tally for OBS Studio

Light up a **Hollyland wireless tally system** (tested on a base with firmware S4.0.0.10, HW H000) from **OBS Studio** with no vMix needed. The OBS Python script pretends to be vMix's TCP API (port 8099), so the Hollyland base thinks it is talking to vMix.

ใช้ไฟ Tally ไร้สายของ Hollyland กับ OBS Studio ได้โดยไม่ต้องมี vMix: สคริปต์ Python ของ OBS จำลอง vMix TCP API (พอร์ต 8099) ให้ตัวฐานคุยด้วย

## What this script can do
- Light up a Hollyland wireless tally system from OBS Studio, with no vMix.
- Red = Program, green = Preview (Studio Mode), in real time. Lights update as soon as you switch a scene or source, not only on the next poll.
- Map each tally light (1–16) to an OBS scene or a source. Until you choose, lights 1–4 follow your first scenes automatically.
- A status window opens when the script loads (no terminal): one color bar per light, this PC's IP, and whether the base is connected.
- The bars use color only — no color names or Program/Preview wording on the rows. A top legend on a black background says **RED = PROGRAM** in red and **GREEN = PREVIEW** in green. The next line, in white, shows a rectangle = scene and an arrow = source.
- A drawn rectangle appears before a scene name, and a left-to-right arrow before a source name.
- After OBS starts or you reload the script, it checks the tally connection every 5 seconds, four times, then every 60 seconds.
- Auto-scans the LAN for the tally base and tells you what to set if it is found but not connected.
- Double-click installers in the `windows` folder (`1. Click to Install.bat`) or the `mac` folder (`1. Click to Install.command`).
- MIT license.

### Status window details
- Resize the window freely (drag the frame): the colour bars and all text scale with it. Text size: **A- / A+** in the window, keys **+ / -** (**0** = 100 %), or OBS → Tools → Scripts → *Status window text size*. Size, position and text size are remembered (`~/.hollyland_tally_window.json`).
- Closing the status window (X) keeps it closed. To show it again: OBS → Tools → Scripts → **Open status window** (it also comes back when OBS restarts or the script is reloaded). If the window crashes, the script reopens it.

### สคริปต์ทำอะไรได้บ้าง
- ใช้ไฟ Tally ไร้สายของ Hollyland กับ OBS ได้ โดยไม่ต้องมี vMix
- แดง = Program, เขียว = Preview (Studio Mode) แบบเรียลไทม์ ไฟเปลี่ยนทันทีเมื่อสลับซีนหรือซอร์ส ไม่ต้องรอรอบโพลล์ถัดไป
- จับคู่ไฟ 1–16 กับซีนหรือซอร์สใน OBS ได้ ถ้ายังไม่เลือกเอง ไฟ 1–4 จะตามซีนแรกโดยอัตโนมัติ
- มีหน้าต่างสถานะเปิดเองเมื่อโหลดสคริปต์: แถบสีแต่ละไฟ, IP ของเครื่องนี้, และสถานะการเชื่อมต่อ
- แถบสีไม่ใส่ชื่อสีหรือคำว่า Program/Preview ด้านบนมีคำอธิบายพื้นดำ: **RED = PROGRAM** สีแดง และ **GREEN = PREVIEW** สีเขียว บรรทัดถัดไปตัวหนังสือสีขาว บอกว่าไอคอนสี่เหลี่ยม = ซีน, ลูกศร = ซอร์ส
- หน้าชื่อซีนมีไอคอนสี่เหลี่ยม หน้าชื่อซอร์สมีลูกศรซ้ายไปขวา
- หลังเปิด OBS หรือรีโหลดสคริปต์ จะเช็กการเชื่อมต่อทุก 5 วินาที 4 ครั้ง แล้วค่อยกลับไปเช็กทุก 60 วินาที
- สแกนหาตัวฐานในเครือข่าย และบอกว่าต้องตั้งอะไร หากเจอเครื่องแต่ยังไม่เชื่อมต่อ
- มีตัวติดตั้งแบบดับเบิลคลิกในโฟลเดอร์ `windows` (`1. Click to Install.bat`) หรือโฟลเดอร์ `mac` (`1. Click to Install.command`)

## Install
After you extract the GitHub ZIP:
- **Windows:** open the **`windows`** folder and double-click **`1. Click to Install.bat`**
- **macOS:** open the **`mac`** folder and double-click **`1. Click to Install.command`**

## Install (Windows)
1. On GitHub: **Code → Download ZIP**. Right click the ZIP → **Extract All**.
2. Open the **`windows`** folder and double-click **`1. Click to Install.bat`**. That's all.

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
2. เปิดโฟลเดอร์ **`windows`** แล้วดับเบิลคลิก **`1. Click to Install.bat`** จบแค่นี้ ตัวติดตั้งหา OBS/Python เอง ถ้าไม่มี Python จะโหลด Python 3.11 จาก python.org มาติดตั้งให้ ตั้งค่า Python ใน OBS เพิ่มสคริปต์ เช็กไฟร์วอลล์ แล้วเปิด OBS ให้ ตอนจบจะบอก IP ของเครื่องนี้ไว้ใส่เป็น Switcher IP ที่ตัวฐาน
3. ตอนแรกไฟ 1–4 จะตาม Scene 4 อันแรกใน OBS อัตโนมัติ เปลี่ยนเองได้ที่ Tools → Scripts
4. ถ้าเพิ่งลง OBS ใหม่และยังมี Scene ไม่ถึง 4 อัน (OBS ใหม่มีแค่ "Scene") สคริปต์จะสร้าง Scene ที่ขาดให้เองครั้งเดียว ชื่อ **Camera 2, Camera 3, Camera 4** แล้วบันทึกไว้ ไม่ลบหรือเปลี่ยนชื่อ Scene เดิม และจะไม่สร้างถ้าคุณเลือกไฟเองแล้วหรือปิด auto-map ไว้ จากนั้นใส่กล้องลงในแต่ละ Scene ได้เลย

### Uninstall
Double-click **`windows/2. Uninstall.bat`**: removes the script from all scene collections and deletes its files (Python and the OBS Python setting are left alone).

### Troubleshooting
- *"install.ps1 was not found"*: you ran the .bat from inside the ZIP, or not from the `windows` folder. Extract the ZIP first, then open **`windows`** and run the .bat from there.
- The window says the tally device is found but not connected: on the base set **Switcher IP = this PC's IP** (shown in the window), not the base's own IP.
- Anything else: send `%TEMP%\hollyland_tally_install.log` (Windows) or `~/Library/Logs/hollyland_tally_install.log` (macOS).

## หน้าต่างสถานะ (Status window) — ภาษาไทย
- ลากขอบหน้าต่างเพื่อย่อ/ขยาย แถบสีและตัวอักษรจะปรับขนาดตามอัตโนมัติ
- ปรับขนาดตัวอักษร: ปุ่ม **A- / A+** ในหน้าต่าง, คีย์ **+ / -** (**0** = 100%) หรือ OBS → Tools → Scripts → *ขนาดตัวอักษร % (Status window text size)* — จำขนาด/ตำแหน่งหน้าต่างไว้ให้ครั้งต่อไป
- กด X ปิดแล้วจะไม่เด้งขึ้นมาอีก ถ้าต้องการเปิดใหม่: OBS → Tools → Scripts → **เปิดหน้าต่างสถานะ (Open status window)** (เปิด OBS ใหม่ หรือ reload สคริปต์ ก็จะกลับมาเอง)

## Set up the tally base
On the Hollyland base, set **Switcher = vMix**, **Switcher IP = the IP of the computer running OBS** (shown in the status window), **port 8099**. Do not enter the base's own IP. Both must be on the same network.

## Install (macOS)
1. On GitHub: **Code → Download ZIP**. Double-click the ZIP in Finder to extract it.
2. Open the **`mac`** folder and double-click **`1. Click to Install.command`**. A Terminal window opens and does the rest.

The installer, no admin password needed:
- Checks that it is running from the extracted `mac` folder (the two script files are in the parent folder).
- Finds OBS (`/Applications/OBS.app`, `~/Applications/OBS.app`, Steam, or Spotlight). Quits OBS if it is open and opens it again at the end. If OBS was never started on this Mac, it starts it once so OBS creates its settings, then quits it.
- Finds the OBS scripts folder `~/Library/Application Support/obs-studio/scripts/` and copies `obs_hollyland_tally.py` and `tally_window.pyw` there (only these two files are replaced; your other scripts are not touched). If it cannot find the OBS settings folder, it asks you to choose a folder.
- **Opens that folder in Finder** so you can see the copied files.
- Finds a Python that OBS can load (3.11 preferred, 3.12/3.10 OK; **3.13+ is not supported by OBS**) from python.org (`/Library/Frameworks`) or Homebrew (`python@3.11` / `python@3.12`), and sets **Tools → Scripts → Python Settings** for you (`[Python] Path64bit` in `user.ini`, and `global.ini` for older OBS).
- The status window needs a Python with **Tk 8.6 or newer**. If Homebrew is installed, the installer offers to run `brew install python@3.11 python-tk@3.11` (or `brew install python-tk@3.14` for the window only) and asks before it installs anything. It does **not** install Homebrew itself.
- Adds the script to **every scene collection**. Light settings you already made are kept.
- Prints a summary of what it did and **this Mac's IP to enter as Switcher IP on the base** (port 8099). The Terminal window stays open so you can read it, then you close it yourself (press Return, or close the window).
- Log: `~/Library/Logs/hollyland_tally_install.log`.

**No Homebrew and no Python?** The installer still copies the files and opens the folder, then tells you what to do: install Python 3.11 from [python.org](https://www.python.org/downloads/release/python-3119/) (macOS 64-bit universal2 installer, includes Tk 8.6), or install [Homebrew](https://brew.sh) and run `brew install python@3.11 python-tk@3.11`. Then run the installer again.

**macOS firewall:** the installer does not change it. If OBS asks to accept incoming network connections, click **Allow** (the base connects to this Mac on TCP 8099). If macOS asks whether OBS may find devices on your local network, click **Allow**.

**If macOS will not open the file:**
- *"cannot be opened because it is from an unidentified developer"* / *"Apple could not verify…"*: right-click the file → **Open** → **Open**. On newer macOS: **System Settings → Privacy & Security → Open Anyway**.
- *"you do not have appropriate access privileges"* (the ZIP lost the execute bit): open Terminal and run `chmod +x ` then drag the file into the Terminal window and press Return. Or type `bash ` (with a space), drag the file in, and press Return.

**Uninstall:** double-click **`mac/2. Uninstall.command`**: removes the script from all scene collections and deletes its two files (Python and the OBS Python setting are left alone).

### Manual install (macOS fallback)
Copy `obs_hollyland_tally.py` and `tally_window.pyw` into the same folder (`~/Library/Application Support/obs-studio/scripts/` works), set OBS → Tools → Scripts → Python Settings to the folder that holds `Python.framework` for Python 3.11 (python.org: `/Library/Frameworks`, Homebrew: `/opt/homebrew/opt/python@3.11/Frameworks`), then add the script with **+**.

The status window needs a Python with **Tk 8.6 or newer**. Apple's Command Line Tools Python (Tk 8.5) can import tkinter, but on current macOS it opens a **blank white window**. Install Homebrew Tk and the script will find it automatically:

```
brew install python-tk@3.14
```

(Python 3.14 is fine for the status window only. OBS itself needs 3.12 or older.)

### ติดตั้งบน macOS (ภาษาไทย)
1. กด **Code → Download ZIP** แล้วดับเบิลคลิกไฟล์ ZIP ใน Finder เพื่อแตกไฟล์
2. เปิดโฟลเดอร์ **`mac`** แล้วดับเบิลคลิก **`1. Click to Install.command`** จะมีหน้าต่าง Terminal เปิดขึ้นมาทำงานให้เอง
3. ตัวติดตั้งจะหาโฟลเดอร์สคริปต์ของ OBS (`~/Library/Application Support/obs-studio/scripts/`) คัดลอกไฟล์ 2 ไฟล์ไปวาง แล้ว **เปิดโฟลเดอร์นั้นใน Finder** ให้เห็นไฟล์ ถ้าหาโฟลเดอร์ไม่เจอ จะให้เลือกโฟลเดอร์เอง
4. ตัวติดตั้งหา Python ที่ OBS ใช้ได้ (3.11 ดีที่สุด, 3.12/3.10 ได้, **3.13 ขึ้นไป OBS ใช้ไม่ได้**) ตั้งค่า Python ใน OBS เพิ่มสคริปต์ในทุก scene collection (ค่าไฟเดิมยังอยู่) ถ้ามี OBS เปิดอยู่จะปิดให้ก่อนแล้วเปิดใหม่ตอนจบ ตอนจบจะแสดงสรุปสิ่งที่ทำไปแล้ว และ IP ของเครื่อง Mac นี้ไว้ใส่เป็น Switcher IP ที่ตัวฐาน (พอร์ต 8099) หน้าต่าง Terminal จะค้างไว้ให้อ่าน จนคุณปิดเอง
5. หน้าต่างสถานะต้องใช้ Python ที่มี **Tk 8.6 ขึ้นไป** ถ้ามี Homebrew ตัวติดตั้งจะถามก่อนแล้วค่อยรัน `brew install` ให้ ถ้าไม่มี Homebrew จะไม่ติดตั้ง Homebrew ให้เอง แต่จะบอกขั้นตอน (ติดตั้ง Python 3.11 จาก python.org หรือติดตั้ง Homebrew แล้วรัน `brew install python@3.11 python-tk@3.11`) แล้วรันตัวติดตั้งอีกครั้ง
6. ถ้า macOS ไม่ยอมเปิดไฟล์ ("unidentified developer"): คลิกขวาที่ไฟล์ → **Open** → **Open** หรือ System Settings → Privacy & Security → **Open Anyway**
7. ถ้าขึ้นว่า "do not have appropriate access privileges": เปิด Terminal พิมพ์ `chmod +x ` แล้วลากไฟล์มาวางใน Terminal กด Return (หรือพิมพ์ `bash ` แล้วลากไฟล์มาวาง กด Return)
8. ถ้า OBS ถามเรื่องรับการเชื่อมต่อจากเครือข่าย หรือหาอุปกรณ์ในเครือข่าย ให้กด **Allow**
9. ถอนการติดตั้ง: ดับเบิลคลิก **`mac/2. Uninstall.command`**
10. ติดตั้งเองแบบเดิม: คัดลอก 2 ไฟล์ไปที่โฟลเดอร์ scripts ของ OBS ตั้ง Python Settings แล้วกด + เพิ่มสคริปต์ (ติดตั้ง `python-tk@3.14` ด้วย Homebrew — Python ของระบบเป็น Tk 8.5 จะเปิดหน้าต่างสถานะเป็นจอขาวว่าง)

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

### Example: Camera 1 is Program, Camera 2 is Preview
Assume Studio Mode is on, and light 1 is mapped to Camera 1 and light 2 to Camera 2.

**First check (when OBS starts or the script loads):** the script reads whatever is already Program and Preview. You do not have to click anything first. When the base connects and asks `TALLY` / `ACTS InputPreview`, or as soon as a change is pushed, the lights match that current state. In this example the script sends:
```
TALLY OK 1200000000000000
ACTS OK InputPreview 2
```
Light 1 is red (Program), light 2 is green (Preview), and the other lights stay off. The 5-second connection checks (four times after start or reload, then every 60 seconds) only ask whether the base is still connected. They do not drive the lights.

**When you click Cut or Transition:** OBS swaps the scenes — Camera 2 becomes Program and Camera 1 becomes Preview. The script sees that change immediately and pushes:
```
TALLY OK 2100000000000000
ACTS OK InputPreview 1
```
Light 2 turns red and light 1 turns green. A slower Transition follows when OBS updates Program and Preview, usually as the transition starts.

Green Preview needs Studio Mode. Light numbers follow the mapping in the script (or auto-map, which is scene-list order).

### หลักการทำงาน (บันทึกโปรโตคอล)
ตัวฐาน Hollyland **ไม่ได้** ส่ง `SUBSCRIBE TALLY` แต่โพลล์ประมาณวินาทีละครั้งด้วย:
```
TALLY
ACTS Overlay1 … ACTS Overlay4
ACTS InputPreview
```
สิ่งที่ต้องตอบกลับ:
- `TALLY OK <digits>` (0 = ดับ, 1 = program, 2 = preview ตามแต่ละช่อง)
- `ACTS OK <name> <n>`; สำหรับ `InputPreview`, `n` = หมายเลขอินพุตที่เป็น Preview **ไฟเขียวติดเมื่อทั้งหลัก TALLY เป็น 2 และ InputPreview ชี้ช่องเดียวกัน** ดังนั้นไฟเขียวได้ครั้งละดวงเดียว

เมื่อซีนเปลี่ยน สคริปต์จะส่ง `TALLY OK …` และ `ACTS OK InputPreview n` ทันที ไฟจึงไม่ต้องรอรอบโพลล์ถัดไป

### ตัวอย่าง: กล้อง 1 เป็น Program, กล้อง 2 เป็น Preview
สมมติว่าเปิด Studio Mode อยู่ และไฟ 1 จับคู่กับ Camera 1, ไฟ 2 จับคู่กับ Camera 2

**ครั้งแรก (ตอนเปิด OBS หรือโหลดสคริปต์):** สคริปต์อ่านค่า Program และ Preview ที่มีอยู่แล้ว ไม่ต้องกดอะไรก่อน เมื่อตัวฐานเชื่อมต่อแล้วถาม `TALLY` / `ACTS InputPreview` หรือเมื่อสคริปต์ส่งค่าไปเอง ไฟจะตรงกับสถานะตอนนั้น ในตัวอย่างนี้สคริปต์ส่ง:
```
TALLY OK 1200000000000000
ACTS OK InputPreview 2
```
ไฟ 1 แดง (Program), ไฟ 2 เขียว (Preview) ไฟดวงอื่นดับ การเช็กทุก 5 วินาที (4 ครั้งหลังเปิดหรือรีโหลด แล้วค่อยทุก 60 วินาที) เป็นการเช็กแค่ว่าตัวฐานยังเชื่อมต่ออยู่ ไม่ได้สั่งสีไฟ

**เมื่อกด Cut หรือ Transition:** OBS สลับซีน Camera 2 ขึ้นเป็น Program และ Camera 1 เป็น Preview สคริปต์เห็นการเปลี่ยนแปลงทันทีแล้วส่ง:
```
TALLY OK 2100000000000000
ACTS OK InputPreview 1
```
ไฟ 2 เปลี่ยนเป็นแดง ไฟ 1 เปลี่ยนเป็นเขียว ถ้าใช้ Transition แบบมีเวลา ไฟจะตามตอนที่ OBS อัปเดต Program และ Preview ซึ่งมักเป็นตอนเริ่มทรานซิชัน

ไฟเขียวของ Preview ต้องเปิด Studio Mode หมายเลขไฟตามการจับคู่ในสคริปต์ (หรือ auto-map ตามลำดับซีนในลิสต์)

## Files
| File | Purpose |
|---|---|
| `obs_hollyland_tally.py` | OBS script (vMix TCP emulator + tally logic) |
| `tally_window.pyw` | Status window (tkinter), started by the script |
| `add_to_obs.py` | Shared helper used by both installers |
| `windows/1. Click to Install.bat`, `windows/helpers/install.ps1` | Windows installer (double-click the .bat) |
| `windows/2. Uninstall.bat`, `windows/helpers/uninstall.ps1` | Windows uninstaller |
| `mac/1. Click to Install.command`, `mac/helpers/install_mac.sh` | macOS installer (double-click the .command) |
| `mac/2. Uninstall.command`, `mac/helpers/uninstall_mac.sh` | macOS uninstaller |

## License
MIT

# MasinaV3 LTE-Only Build — Setup Status

## Build Context

This is an LTE-only drone build based on the MasinaV3 project (FPV drone over 4G). No ELRS radio — all control goes through 4G. This document captures what's been done on the Raspberry Pi and what remains before flight.

---

## Pi Details

- **Host**: `zodiac118@rssod.local`
- **Password**: `vancouver1`
- **OS**: Raspberry Pi OS Bookworm (32-bit) — **not** Legacy as README suggests
- **Camera**: IMX290-83 IR-CUT (not the OV5647/Pi Camera V1 the README assumes)
- **Modem (current)**: Huawei E3372-325 — **incompatible** with US LTE bands, acts as USB ethernet in HiLink mode
- **Modem (ordered)**: SIM7600G-H — global band support, AT command mode, works with NetworkManager
- **DDNS**: `rssod.ddns.net` (No-IP) → points to ground station's public IP
- **Ground station**: Windows PC (runs UDP Server, GStreamer video, No-IP DUC client, Xbox/PS controller)

---

## What's Done on the Pi

### System
- OS updated (`apt update && apt upgrade`)
- All dependencies from README step 5 installed (GStreamer, build tools, etc.)
- `bcm2835` library built and installed
- System clock corrected (was wrong, caused apt failures)

### Camera (IMX290 via libcamera)
Since this is Bookworm with an IMX290 (not the legacy OV5647), the entire camera stack differs from the README:

- `/boot/firmware/config.txt` configured:
  - `camera_auto_detect=0`
  - `dtoverlay=vc4-kms-v3d` (not fkms)
  - `dtoverlay=imx290,clock-frequency=37125000`
  - `dtparam=i2c_arm=on`
  - No `start_x=1` or `gpu_mem=256` (those are legacy-only)
- `libcamera-apps-lite` installed (provides `rpicam-vid`, `rpicam-hello`, `rpicam-still`)
- `gst-rpicamsrc` was built but is **not used** — it's for the legacy MMAL stack
- DMA heap permissions: udev rule at `/etc/udev/rules.d/99-dma-heap.rules` sets `/dev/dma_heap/*` to 0666
- IMX290 kernel module auto-loads via `/etc/modules-load.d/imx290.conf`
- Camera tested and confirmed working at 640x360, 1280x720, 1920x1080

### Video Stream Service (`cam_stream.service`)
```
[Unit]
Description=Camera Stream
After=NetworkManager.service

[Service]
ExecStartPre=/bin/chmod 666 /dev/dma_heap/linux,cma /dev/dma_heap/system
ExecStart=/bin/bash -c 'rpicam-vid -t 0 --inline --width 640 --height 360 --framerate 30 --bitrate 800000 --codec h264 -n -o - | gst-launch-1.0 fdsrc ! h264parse ! rtph264pay config-interval=1 pt=96 ! udpsink host=rssod.ddns.net port=2222'
Restart=always
RestartSec=5

[Install]
WantedBy=default.target
```
- **Status**: enabled, tested over LAN with GStreamer RTP receive — confirmed working
- `rpicam-vid` pipes raw H.264 into GStreamer for RTP wrapping, making output compatible with the standard README receive commands
- DDNS hostname `rssod.ddns.net` is configured

### Controls/Telemetry Client
- MasinaV3 repo cloned to `/home/zodiac118/MasinaV3/`
- Client binary compiled and copied to `/home/zodiac118/client/`
- Config at `/root/config.txt`:
  ```
  host=rssod.ddns.net
  LOCAL_TIMEOUT=300000
  FAILSAFE_TIMEOUT=5000
  STABILIZE_TIMEOUT=250
  USE_ELRS_SWITCH=0
  HOVER_VALUE=1200
  ```
- `client.service` enabled (starts `/home/zodiac118/client/client`)
- `your_ddns` is a placeholder — replace with actual DDNS hostname

### DNS Workaround
The E3372 modem hijacks DNS to 192.168.8.1 which doesn't resolve anything. Temporary fix applied:
```
echo -e "nameserver 8.8.8.8\nnameserver 8.8.4.4" | sudo tee /etc/resolv.conf
```
This will need to be re-done after reboots until the SIM7600G-H + NetworkManager are configured properly.

---

## What's Left Before Flight

### When SIM7600G-H Arrives

**1. Configure NetworkManager (README "Method 2: NetworkManager")**
```bash
# Edit NetworkManager config
sudo nano /etc/NetworkManager/NetworkManager.conf
```
Replace contents with:
```
[main]
plugins=ifupdown,keyfile
dhcp=internal

[ifupdown]
managed=true
```
Then:
```bash
sudo systemctl disable dhcpcd
sudo systemctl disable wpa_supplicant
sudo systemctl enable NetworkManager
sudo reboot
```
After reboot, create the GSM connection:
```bash
sudo nmcli c add type gsm ifname '*' con-name MOBILE apn <YOUR_APN> connection.autoconnect-priority 20
```
Verify: `nmcli` should show `ttyUSBx: connected to MOBILE`

**2. Install PiTunnel**
- Create account at https://www.pitunnel.com
- Run the install command they provide:
  ```bash
  curl -s https://pitunnel.com/get/<YOUR_TOKEN> | sudo bash
  ```
- This gives you remote SSH/terminal access to the Pi over 4G

**3. ~~Set Up Dynamic DNS~~ DONE**
- `rssod.ddns.net` configured on No-IP, pointing to `71.198.189.240`
- Pi's `cam_stream.service` and `/root/config.txt` updated with hostname
- **Still needed**: Install No-IP DUC client on the Windows ground station PC to keep IP current ([download](https://www.noip.com/download?page=win))

**4. Open Ports on Ground Station Router**
- UDP **2222** — video stream
- UDP **2223** — telemetry (Pi → PC)
- UDP **2224** — controls (PC → Pi)
- Forward all three to your ground station PC's local IP

**5. Firewall on Ground Station PC**
- Allow inbound + outbound UDP 2222-2224
- On Windows: Windows Defender Firewall > Inbound Rules > New Rule > Port > UDP 2222-2224

### On the Pi (No Hardware Dependency)

**6. Enable Serial Port**
```bash
sudo raspi-config
```
Navigate to Interface Options > Serial Port:
- Login shell over serial: **No**
- Hardware serial port enabled: **Yes**

This is how the Pi sends CRSF commands to the flight controller.

### On Your Ground Station PC (Windows)

**Run the setup script** — it handles everything in one go:
```powershell
# Open PowerShell as Administrator, cd to the repo, then:
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\pc\setup.ps1
```

This script:
- Downloads & installs GStreamer (MSVC x64) and SDL2
- Patches the hardcoded SDK paths in the project files
- Compiles UDP_Server and UDP_Video via MSBuild (Release x64)
- Creates Windows Firewall rules for UDP 2222-2224
- Adds GStreamer to system PATH
- Creates desktop launcher shortcuts (`MasinaV3_Launch.bat`, `MasinaV3_Video.bat`, `MasinaV3_Server.bat`)

**Prerequisites**: Visual Studio 2022 with "Desktop development with C++" workload must be installed first.

**After the script**, manually:
- Install No-IP DUC: https://www.noip.com/download?page=win
- Forward UDP ports 2222-2224 on your router to this PC's local IP
- Plug in Xbox/PlayStation controller

### Physical / Hardware

**10. Wire Pi UART to Flight Controller**
```
Pi GPIO 8 (TX) → FC RX pad
Pi GPIO 10 (RX) → FC TX pad
```
Common ground via ESC → buck converter → Pi.

**11. Betaflight Configuration**
- Ports: Enable Serial RX on the UART connected to Pi, set protocol to CRSF
- Ports: Enable GPS on the UART connected to GPS module
- Receiver: Serial (via UART), CRSF protocol
- GPS: UBLOX protocol (for M10)
- Failsafe: **Critical for LTE-only** — configure land or RTH, no ELRS backup
- Modes: Angle mode, RTH, etc.

**12. Xbox/PlayStation Controller**
Plug into ground station PC. The UDP Server reads stick positions and sends to Pi.

---

## Key Differences from README

| README Assumes | This Build |
|---|---|
| Raspberry Pi OS Legacy (Bullseye) | Bookworm |
| OV5647 (Pi Camera V1) | IMX290-83 IR-CUT |
| `gst-rpicamsrc` (MMAL) | `rpicam-vid` (libcamera) |
| `gst-launch-1.0 rpicamsrc ...` | `/usr/bin/rpicam-vid -t 0 --inline ...` |
| Huawei E3372 modem | SIM7600G-H (on order) |
| `raspi-config` Legacy Camera option | Manual `config.txt` edits |
| User `pi` | User `zodiac118` |
| Home `/home/pi/` | Home `/home/zodiac118/` |
| ELRS + 4G dual control | LTE-only, `USE_ELRS_SWITCH=0` |

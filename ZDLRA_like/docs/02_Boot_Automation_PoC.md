# ⌨️ 02 — Boot Automation PoC (`VBoxManage keyboardputscancode`)

[![Sprint](https://img.shields.io/badge/Sprint-0-blue)]()
[![Status](https://img.shields.io/badge/Status-Implemented-success)]()
[![PoC](https://img.shields.io/badge/Type-Proof_of_Concept-orange)]()
[![Lang](https://img.shields.io/badge/PowerShell-5.1%2B-blue)]()
[![VBox](https://img.shields.io/badge/VirtualBox-7.x-darkgreen)]()
[![Layout](https://img.shields.io/badge/Keyboard-US-lightblue)]()

> 🎯 Sprint 0 — proof-of-concept. Goal: fully automated kickstart boot, no manual GRUB editing.

## 🎯 Context

In all existing VMs in the LAB `VMs2-install/`, the installer requires manual user action
during boot from the OL 8.10 ISO:
1. On the GRUB screen press **TAB** (or **e**) to enter entry edit mode
2. Append to the cmdline: `inst.ks=http://... inst.ip=...`
3. Press **Enter** (TAB) or **Ctrl-X** (e) to boot

This document describes the mechanism for full automation of this step via VBoxManage,
eliminating the manual GRUB edit step.

## ⚙️ Mechanism

`VBoxManage controlvm <vm> keyboardputscancode <hex> [<hex>...]` injects raw PC Set 1 scancodes
directly into the VM's keyboard buffer. Each ASCII character requires a **pair**:

- **Make code** — key press
- **Break code** — key release (= Make `OR` 0x80, last byte)

```
Key 'e':           12  92          # make=0x12, break=0x92
Key 'End':         e0 4f  e0 cf    # extended (e0 prefix), make=0x4f, break=0xcf
Key Ctrl-X:        1d 2d  ad 9d    # Ctrl down, X down, X up, Ctrl up
```

The Anaconda installer **reads the entire kernel cmdline** — not only the `quiet` parameter from
the default entry, but also **appended** parameters such as `inst.ks=`, `inst.ip=`, `inst.text`.
It is enough to append them **at the end of the line** `linuxefi /images/pxeboot/vmlinuz ...`.

## 🎹 Keystroke sequence

| Step | Key | Goal |
|---|---|---|
| 0 | `Up` x 3 (default) | Force first menu entry (Install) selection |
| 1 | `e` | Enter GRUB edit mode for the selected entry |
| 2 | `Down` x 2 (default) | Move to the `linuxefi` line |
| 3 | `End` | Cursor to end of line |
| 4 | Payload | Append kickstart params |
| 5 | `Ctrl-X` | Boot the modified entry |

**Step 0 added 2026-05-03 (iteration 2):** GRUB-EFI may remember the previous selection
via `savedefault`. Without `Up x 3` the script entered edit mode for "Test this media & install"
instead of "Install" — mediacheck added 3-5 min to the process. `Up x 3` ensures returning
to the top entry regardless of the previous session state.

### Default payload for rcat01

```
 inst.ks=http://192.168.56.1:8000/ks-rcat01.cfg inst.ip=192.168.56.16::192.168.56.1:255.255.255.0::enp0s3:none inst.text
```

The leading space is intentional — it separates the payload from existing parameters in the line (such as `quiet`).

## 🏗️ Script architecture

```
scripts/boot/
├── scancode_table.ps1          — PC Set 1 mapping (95 ASCII chars + 25 control keys)
├── send_vbox_keystrokes.ps1    — Send-VBoxKeystrokes function with 3 modes
├── start_kickstart_http.ps1    — Python http.server on 8000 (idempotent)
└── boot_rcat_via_scancode.ps1  — orchestrator: HTTP + startvm + key sequence + monitor
```

### scancode_table.ps1

Three hashtables:
- `$UnshiftedMakeCode` — 56 base characters (lowercase letters, digits, `=`, `-`, `.`, `/`, `:`...)
- `$ShiftedMakeCode` — 35 shifted characters (uppercase letters, `!`, `@`, `_`...)
- `$ControlKeys` — 25 control keys (arrows, End, Enter, Ctrl, Shift...)

Plus helpers:
- `Get-CharScancodes -Char 'a'` → `@(0x1e, 0x9e)` (hex pair)
- `ConvertTo-Scancodes -Text "abc"` → flat array of hex codes
- `Get-CtrlKeyScancodes -Char 'x'` → `@(0x1d, 0x2d, 0xad, 0x9d)` (Ctrl-X)

### send_vbox_keystrokes.ps1

The main `Send-VBoxKeystrokes` function has three modes (PowerShell parameter sets):

```powershell
Send-VBoxKeystrokes -VM 'rcat01' -Text 'inst.text'              # Text mode
Send-VBoxKeystrokes -VM 'rcat01' -ControlKey 'End'              # Control mode
Send-VBoxKeystrokes -VM 'rcat01' -ControlKey 'Down' -RepeatControlKey 3
Send-VBoxKeystrokes -VM 'rcat01' -CtrlChord 'x'                 # Ctrl mode
```

Batching: each batch is max 80 pairs (160 bytes), with a 50 ms gap between batches.
Prevents the VBox keyboard buffer from overflowing (~256 events).

### boot_rcat_via_scancode.ps1

Orchestrator. Stages:

1. **Pre-flight** — VM exists, is not running, kickstart present, Host-Only IF #2 with `192.168.56.1`
2. **HTTP server** — starts (or confirms) Python `http.server` on :8000
3. **Start VM** — `VBoxManage startvm <VM> --type {gui|headless}` (`gui` default for debugging)
4. **Wait** — `Start-Sleep $InitialDelaySec` (default 10s) for GRUB to appear
5. **Edit sequence** — 5 keystroke steps (see table above)
6. **Monitor** — `Test-NetConnection -ComputerName 192.168.56.16 -Port 22` every 15s, max 30 min

## ⚠️ Pitfalls and mitigation

### 1. Timing — GRUB appears slower than $InitialDelaySec

**Symptom:** `e` is sent before GRUB shows up — the keystroke is lost,
once GRUB appears the first character `i` of the payload (from `inst.ks=`) selects the entry "Install Oracle Linux"
and **ENTER is not needed** — boot proceeds with the old parameters (without kickstart).

**Mitigation:**
- Increase `-InitialDelaySec` to 15-20
- Or send `e` **multiple times with a gap** — the first catches GRUB, the rest are harmless (they just toggle edit mode)

### 2. `Down` x 2 does not hit the `linuxefi` line

**Symptom:** The payload is appended to a different line (e.g. `set gfxpayload=keep`),
GRUB has no arguments in `linuxefi`, Anaconda starts without kickstart.

**Mitigation:**
- Increase `-DownArrowsCount` (default 2) to 3 or 4
- Inspect the actual grub.cfg from the current ISO: `mount -o loop OracleLinux-R8-U10-x86_64-dvd.iso /mnt/iso`,
  then `cat /mnt/iso/EFI/BOOT/grub.cfg`

### 3. VBox keyboard buffer overflows (~256 events)

**Symptom:** Part of the payload is lost, GRUB compiles a cmdline with holes.

**Mitigation:** Batching in `Send-VBoxKeystrokes` (default 80 pairs/batch + 50ms gap) already handles this.
If you still hit the issue — reduce `-BatchSize` to 40 and increase `-BatchDelayMs` to 100.

### 4. Keyboard layout — German/Polish in VBox

**Symptom:** Characters interpreted as QWERTZ/QWERTY-PL, payload will be incorrect
(e.g. `:` will be inserted as `Ó`).

**Mitigation:** GRUB **always** uses US layout regardless of host settings — this is a GRUB design decision,
our scancode_table.ps1 assumes US and that is correct.
**Do not change** the layout in the script — it will only get worse.

### 5. Anaconda does not download kickstart (HTTP 404)

**Symptom:** Anaconda starts, but enters interactive mode (TUI).

**Mitigation:**
- Check the access log: `_RecoveryAppliance_/kickstart/.http_server.log.err`
  (NOTE: Python http.server logs GET requests to STDERR, not STDOUT.
  The `.http_server.log` file is usually empty — that is STDOUT only.)
- Check reachability from the VM: in GUI mode after Anaconda starts you can open a TTY (Ctrl-Alt-F2)
  and try `curl http://192.168.56.1:8000/ks-rcat01.cfg`
- Check Host-Only IF: `VBoxManage list hostonlyifs | Select-String 'IPAddress'`

## 🔀 Alternatives to scancode injection (for the future)

### A. ISO repackaging

Extract the ISO with `xorriso`, replace `EFI/BOOT/grub.cfg` with a version whose default entry already
contains `inst.ks=...`, repack. Pros: deterministic, no timing issues. Cons: ISO regeneration on every
kickstart URL change, requires extra tooling (xorriso in PATH).

```bash
# Extract
xorriso -osirrox on -indev OL8.10-orig.iso -extract / iso_root/

# Modification
sed -i 's|linuxefi /images/pxeboot/vmlinuz|linuxefi /images/pxeboot/vmlinuz inst.ks=http://192.168.56.1:8000/ks-rcat01.cfg inst.ip=192.168.56.16::192.168.56.1:255.255.255.0::enp0s3:none inst.text|' iso_root/EFI/BOOT/grub.cfg

# Repack (bootable)
xorriso -as mkisofs -o OL8.10-rcat01.iso \
    -b isolinux/isolinux.bin -c isolinux/boot.cat \
    -no-emul-boot -boot-load-size 4 -boot-info-table \
    -eltorito-alt-boot -e images/efiboot.img -no-emul-boot \
    -V 'OL-8-10-rcat' iso_root/
```

### B. OEMDRV (auto-detection)

Anaconda automatically detects a virtual floppy/USB labeled `OEMDRV` containing a `ks.cfg` file.
Pros: clean, no ISO modifications. Cons: requires 1 mini floppy/img per VM.

```powershell
# Create floppy with ks.cfg, label OEMDRV
$flpPath = "D:\VM\rcat01\oemdrv.img"
& dd if=/dev/zero of=$flpPath bs=1024 count=1440
& mkfs.fat -n OEMDRV $flpPath
& mount -o loop $flpPath /mnt/oemdrv
& cp ks-rcat01.cfg /mnt/oemdrv/ks.cfg
& umount /mnt/oemdrv

# Attach as floppy to the VM
VBoxManage storageattach rcat01 --storagectl Floppy --port 0 --device 0 --type fdd --medium $flpPath
```

### When to choose which method

| Method | When to use |
|---|---|
| **scancode** (Sprint 0) | Single VM, fast PoC, easy per-VM parameter changes |
| **ISO repack** | Many VMs of identical configuration, deterministic repeatability |
| **OEMDRV** | Many VMs of DIFFERENT configuration, clean per-VM separation |

## ✅ Sprint 0 validation

```powershell
# 1. Dry-run (preview payload without execution)
.\scripts\boot\boot_rcat_via_scancode.ps1 -DryRun

# 2. Test scancode_table standalone
. .\scripts\boot\scancode_table.ps1
ConvertTo-Scancodes -Text 'abc' | ForEach-Object { '{0:x2}' -f $_ }
# Expected: 1e 9e 30 b0 2e ae

# 3. Test Send-VBoxKeystrokes against a live VM (different than rcat01, e.g. already installed)
. .\scripts\boot\send_vbox_keystrokes.ps1
Send-VBoxKeystrokes -VM 'infra01' -Text 'echo hello' -Verbose

# 4. Full boot (requires ks-rcat01.cfg + vbox_create_rcat.ps1 from Sprint 1)
.\scripts\boot\boot_rcat_via_scancode.ps1
# Expected: after ~15-25 min SSH available on 192.168.56.16:22; password from /root/.lab_secrets ($LAB_PASS, kickstart-managed)
```

## 📈 Scaling

If Sprint 0 works for rcat01, the mechanism can be moved to a separate mini-project
**`VMs2-install/_KickstartAutomation_/`** for all the remaining 5 VMs (`infra01`, `prim01/02`,
`stby01`, `client01`). Per-VM parameter table:

| VM | IP | Kickstart file | DownArrowsCount |
|---|---|---|---|
| infra01 | 192.168.56.10 | ks-infra01.cfg | 2 |
| prim01 | 192.168.56.11 | ks-prim01.cfg | 2 |
| prim02 | 192.168.56.12 | ks-prim02.cfg | 2 |
| stby01 | 192.168.56.13 | ks-stby01.cfg | 2 |
| client01 | 192.168.56.14 | ks-client01.cfg | 2 |
| **rcat01** | **192.168.56.16** | **ks-rcat01.cfg** | **2** |

This is out of scope for this subproject — here we only implement rcat01 as a PoC.

## 🔗 References

- VirtualBox docs — VBoxManage controlvm: <https://www.virtualbox.org/manual/ch08.html#vboxmanage-controlvm>
- PC Set 1 scancode tables (USB HID): <https://wiki.osdev.org/PS/2_Keyboard>
- Anaconda kickstart docs: <https://anaconda-installer.readthedocs.io/en/latest/kickstart.html>
- GRUB EFI cmdline: the line `linuxefi /images/pxeboot/vmlinuz` accepts all kernel parameters

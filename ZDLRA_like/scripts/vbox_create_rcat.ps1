# ==============================================================================
# Tytul:        vbox_create_rcat.ps1
# Opis:         Tworzy 1 VM 'rcat01' dla LAB-u Recovery Appliance (RMAN catalog +
#               ZDLRA-like). Skopiowany z VMs2-install/scripts/vbox_create_vms.ps1
#               i dostosowany dla pojedynczej maszyny (Single Instance, brak ASM).
#
# Description [EN]: Creates 1 VM 'rcat01' for the Recovery Appliance lab.
#                   Adapted from vbox_create_vms.ps1 for a single SI machine.
#
# Autor:        KCB Kris
# Data:         2026-05-01
# Wersja:       1.0
# <repo>:       ZDLRA_like
# Konwencje:    ZDLRA_like/SETTINGS.md
#
# Wymagania [PL]:    - Host Windows z VirtualBox 7.x
#                    - PowerShell jako admin (lub user w grupie vboxusers)
#                    - Hostonly Ethernet Adapter #2 (192.168.56.0/24) skonfigurowany
#                    - Plik ISO Oracle Linux 8.10 w D:\ISOs\
#                    - Katalog D:\OracleBinaries z paczkami DB 23ai (opcjonalnie)
#                    - Katalog D:\_RMAN_BCK_from_Linux_ na hoscie (shared folder dla backupow)
# Requirements [EN]: - Windows host with VirtualBox 7.x, admin PowerShell, host-only IF #2,
#                      OL 8.10 ISO, optional D:\OracleBinaries, D:\_RMAN_BCK_from_Linux_ folder.
#
# Uzycie [PL]:  PowerShell jako admin:
#                 .\scripts\vbox_create_rcat.ps1
# Usage [EN]:   PowerShell as admin: .\scripts\vbox_create_rcat.ps1
# ==============================================================================

$ErrorActionPreference = "Stop"
$VBox       = "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"
$Iso        = "D:\ISOs\OracleLinux-R8-U10-x86_64-dvd.iso"
$VmRoot     = "D:\VM"
$HostOnlyIF = "VirtualBox Host-Only Ethernet Adapter #2"

# --- Definicja VM rcat01 ---
# Wartosci dobrane:
#   2 vCPU, 4 GB RAM - wystarczy dla katalogu RMAN i symulacji ZDLRA-like
#   Disk1 60 GB OS (boot, swap 4 GB, /, /u01 dla DB binaries 23ai)
#   Disk2 200 GB LVM - /u02 (oradata), /u03 (FRA), /u04 (lokalny cache archivelog)
$vm = @{
    Name="rcat01"; Cpus=2; RamMB=4096; Disk1GB=60; Disk2GB=200; Net="rcat"
}

# Sanity check: VBoxManage istnieje
if (-not (Test-Path $VBox)) {
    throw "VBoxManage nie istnieje: $VBox. Zainstaluj VirtualBox 7.x lub popraw sciezke."
}

# Sanity check: ISO istnieje
if (-not (Test-Path $Iso)) {
    throw "ISO Oracle Linux 8.10 nie istnieje: $Iso. Pobierz z https://yum.oracle.com/oracle-linux-isos.html"
}

# Sanity check: Host-Only IF istnieje
$hoifs = & $VBox list hostonlyifs | Select-String "^Name:.*$([regex]::Escape($HostOnlyIF))"
if (-not $hoifs) {
    Write-Host "ERROR: Host-Only IF '$HostOnlyIF' nie istnieje. Stworz w VirtualBox Manager." -ForegroundColor Red
    Write-Host "Dostepne / Available:"
    & $VBox list hostonlyifs | Select-String "^Name:"
    exit 1
}

# === Tworzenie VM rcat01 ===
$name  = $vm.Name
$vmDir = "$VmRoot\$name"

Write-Host "`n========== $name ==========" -ForegroundColor Cyan

# 1. createvm (idempotent - pomijamy jesli istnieje)
if (& $VBox list vms | Select-String "`"$name`"") {
    Write-Host "  $name juz istnieje, pomijam createvm" -ForegroundColor Yellow
} else {
    & $VBox createvm --name $name --ostype Oracle_64 --basefolder $VmRoot --register
}

# 2. modifyvm: paravirt KVM clock + opcje sprzetowe.
# Firmware EFI64: wymagane zeby ISO OL 8.10 zbootowal w trybie EFI-GRUB
# (a nie BIOS-isolinux). Mechanizm scancode w boot_rcat_via_scancode.ps1
# zaprojektowany dla GRUB ('e' + Ctrl-X), nie isolinux ('Tab' + Enter).
# Wymaga partycji /boot/efi w kickstart (ks-rcat01.cfg).
# Powod zmiany: 2026-05-03 - VM domyslnie BIOS, isolinux nie reagowal na 'e'/Ctrl-X.
& $VBox modifyvm $name `
    --firmware efi64 `
    --cpus $vm.Cpus `
    --memory $vm.RamMB `
    --pae on `
    --hwvirtex on `
    --nestedpaging on `
    --largepages on `
    --vtxvpid on `
    --vtxux on `
    --x2apic on `
    --apic on `
    --rtcuseutc on `
    --boot1 disk --boot2 dvd --boot3 none --boot4 none `
    --paravirtprovider kvm `
    --audio none `
    --usb off --usbehci off --usbxhci off

# 3. SATA controller. hostiocache off - Oracle wymaga O_DIRECT.
if (-not (& $VBox showvminfo $name --machinereadable | Select-String 'storagecontrollername0="SATA"')) {
    & $VBox storagectl $name --name SATA --add sata --controller IntelAhci --portcount 4 --hostiocache off
    Write-Host "  [perf] hostiocache off (Oracle wymaga O_DIRECT)" -ForegroundColor Cyan
}

# 4. Disk1 (OS) + Disk2 (oradata/FRA/cache LVM)
$disk1Path = "$vmDir\$name-disk1.vdi"
if (-not (Test-Path $disk1Path)) {
    & $VBox createmedium disk --filename $disk1Path --size ($vm.Disk1GB * 1024) --variant Standard
}
& $VBox storageattach $name --storagectl SATA --port 0 --device 0 --type hdd --medium $disk1Path

$disk2Path = "$vmDir\$name-disk2-storage.vdi"
if (-not (Test-Path $disk2Path)) {
    & $VBox createmedium disk --filename $disk2Path --size ($vm.Disk2GB * 1024) --variant Standard
}
& $VBox storageattach $name --storagectl SATA --port 1 --device 0 --type hdd `
    --medium $disk2Path --nonrotational on
Write-Host "  Disk2 (LVM oradata/FRA/cache): $disk2Path - $($vm.Disk2GB) GB"

# 5. ISO mount.
& $VBox storageattach $name --storagectl SATA --port 3 --device 0 --type dvddrive --medium $Iso

# 6. Sieci - profil 'rcat' (jak stby/client: hostonly + nat, 2 NIC wystarczaja).
& $VBox modifyvm $name --nic1 hostonly --hostonlyadapter1 "$HostOnlyIF" --nictype1 virtio
& $VBox modifyvm $name --nic2 nat --nictype2 virtio
& $VBox modifyvm $name --nic3 none
& $VBox modifyvm $name --nic4 none

# 7. Shared folder OracleBinaries (opcjonalny)
if (Test-Path "D:\OracleBinaries") {
    $sfExists = (& $VBox showvminfo $name --machinereadable) -match '"OracleBinaries"'
    if (-not $sfExists) {
        & $VBox sharedfolder add $name --name OracleBinaries --hostpath "D:\OracleBinaries" --automount
        Write-Host "  Shared folder OracleBinaries dodany"
    } else {
        Write-Host "  Shared folder OracleBinaries juz istnieje, pomijam"
    }
} else {
    Write-Host "  WARN: D:\OracleBinaries nie istnieje - shared folder pominiety" -ForegroundColor Yellow
    Write-Host "        (zainstaluj DB pozniej z ISO/zip rozpakowanego na rcat01)" -ForegroundColor Yellow
}

# 8. Shared folder _RMAN_BCK_from_Linux_ - backupy RMAN
if (Test-Path "D:\_RMAN_BCK_from_Linux_") {
    $sfExists = (& $VBox showvminfo $name --machinereadable) -match '"_RMAN_BCK_from_Linux_"'
    if (-not $sfExists) {
        & $VBox sharedfolder add $name --name _RMAN_BCK_from_Linux_ --hostpath "D:\_RMAN_BCK_from_Linux_" --automount
        Write-Host "  Shared folder _RMAN_BCK_from_Linux_ dodany (backupy RMAN)"
    } else {
        Write-Host "  Shared folder _RMAN_BCK_from_Linux_ juz istnieje, pomijam"
    }
} else {
    Write-Host "  WARN: D:\_RMAN_BCK_from_Linux_ nie istnieje - utworz katalog na hoscie." -ForegroundColor Yellow
    Write-Host "        New-Item -Path D:\_RMAN_BCK_from_Linux_ -ItemType Directory" -ForegroundColor Yellow
}

Write-Host "  $name skonfigurowane: $($vm.Cpus) CPU, $($vm.RamMB) MB RAM, $($vm.Disk1GB)+$($vm.Disk2GB) GB, paravirt=kvm" -ForegroundColor Green

# === Podsumowanie ===
Write-Host "`n========== PODSUMOWANIE ==========" -ForegroundColor Green
Write-Host "Utworzona VM:"
Write-Host "  $($vm.Name): $($vm.Cpus) CPU, $($vm.RamMB / 1024) GB RAM, $($vm.Disk1GB) GB OS + $($vm.Disk2GB) GB storage - paravirt=kvm"

Write-Host "`nNastepne kroki (Sprint 0 - boot kickstart) / Next steps:" -ForegroundColor Yellow
Write-Host "  1. (Opcjonalnie) Test pre-flight bez wykonania:"
Write-Host "     .\scripts\boot\boot_rcat_via_scancode.ps1 -DryRun"
Write-Host ""
Write-Host "  2. Pelny automatyczny boot z kickstart (~15-25 min):"
Write-Host "     .\scripts\boot\boot_rcat_via_scancode.ps1"
Write-Host ""
Write-Host "  3. Po instalacji SSH dostepny na 192.168.56.16:22"
Write-Host "     ssh kris@192.168.56.16   # haslo z /root/.lab_secrets (LAB_PASS, kickstart utworzyl chmod 600)"
Write-Host ""
Write-Host "  4. Sprint 1 (DB install + katalog) - TODO po pelnej weryfikacji Sprintu 0"

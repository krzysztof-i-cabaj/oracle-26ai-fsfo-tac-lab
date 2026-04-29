# ==============================================================================
# Tytul:        vbox_create_vms.ps1 (VMs2-install: paravirt KVM + virtio-net + hostiocache infra01)
# Opis:         Tworzy 5 VM dla labu Oracle 26ai HA (FSFO + TAC) z optymalizacjami:
#                 - infra01: drugi VDI 100 GB pod LVM/iSCSI block backstore
#                 - --paravirtprovider kvm dla wszystkich VM (eliminuje time drift VirtualBox)
#                 - --hostiocache on tylko dla infra01 (Windows page cache dla iSCSI backstore)
#                 - --hostiocache off dla prim01/02/stby01/client01 (Oracle wymaga O_DIRECT)
#                 - virtio-net dla wszystkich NIC (lepszy throughput z paravirt)
#                 - infra01 RAM 8 GB, prim01/02 RAM 9 GB (cluvfy 23.26 wymaga >= 8 GB physical)
# Description [EN]: VM creation script with performance optimizations:
#                 paravirt KVM clock + virtio-net + selective hostiocache.
#
# Autor:        KCB Kris
# Data:         2026-04-27
# Wersja:       1.0 (VMs2-install) - port z VMs/scripts/alt/vbox_create_vms_block.ps1 (F-18.C)
#
# Wymagania [PL]:    - Host Windows z VirtualBox 7.x
#                    - PowerShell jako admin (lub user w grupie vboxusers)
#                    - Hostonly Ethernet Adapter #2 (192.168.56.0/24) skonfigurowany w VirtualBox Manager
#                    - Plik ISO Oracle Linux 8.10 w D:\ISOs\
#                    - Katalog D:\OracleBinaries z paczkami GI/DB/Client (opcjonalnie - shared folder)
# Requirements [EN]: - Windows host with VirtualBox 7.x, admin PowerShell, host-only IF #2,
#                      OL 8.10 ISO and (optional) D:\OracleBinaries shared folder.
#
# Uzycie [PL]:  PowerShell jako admin:
#                 .\scripts\vbox_create_vms.ps1
# Usage [EN]:   PowerShell as admin: .\scripts\vbox_create_vms.ps1
# ==============================================================================

$ErrorActionPreference = "Stop"
$VBox       = "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"
$Iso        = "D:\ISOs\OracleLinux-R8-U10-x86_64-dvd.iso"
$VmRoot     = "D:\VM"
$HostOnlyIF = "VirtualBox Host-Only Ethernet Adapter #2"

# --- Definicje VM ---
# Wartosci RAM dobrane empirycznie:
#   infra01 8 GB - LIO page cache 3-6x speedup dla iSCSI block backstore (F-18.G).
#   prim01/02 9 GB - cluvfy 23.26 wymaga >= 8 GB *physical* (8 GB host -> 7.8 GB available -> FAIL).
#   stby01 6 GB - SI Restart, brak 2x SGA jak na RAC.
#   client01 3 GB - tylko TestHarness Java + Oracle Client.
$vms = @(
    @{ Name="infra01";  Cpus=2; RamMB=8192; Disk1GB=40;  Disk2GB=100; Net="infra"  },
    @{ Name="prim01";   Cpus=4; RamMB=9216; Disk1GB=60;  Disk2GB=0;   Net="rac"    },
    @{ Name="prim02";   Cpus=4; RamMB=9216; Disk1GB=60;  Disk2GB=0;   Net="rac"    },
    @{ Name="stby01";   Cpus=4; RamMB=6144; Disk1GB=100; Disk2GB=0;   Net="stby"   },
    @{ Name="client01"; Cpus=2; RamMB=3072; Disk1GB=30;  Disk2GB=0;   Net="client" }
)

# Sprawdz czy Host-Only IF istnieje.
$hoifs = & $VBox list hostonlyifs | Select-String "^Name:.*$([regex]::Escape($HostOnlyIF))"
if (-not $hoifs) {
    Write-Host "ERROR: Host-Only IF '$HostOnlyIF' nie istnieje. Stworz w VirtualBox Manager." -ForegroundColor Red
    Write-Host "Dostepne / Available:"
    & $VBox list hostonlyifs | Select-String "^Name:"
    exit 1
}

# === Tworzenie VM ===
foreach ($vm in $vms) {
    $name  = $vm.Name
    $vmDir = "$VmRoot\$name"

    Write-Host "`n========== $name ==========" -ForegroundColor Cyan

    # 1. createvm (idempotent - pomijamy jesli istnieje).
    if (& $VBox list vms | Select-String "`"$name`"") {
        Write-Host "  $name juz istnieje, pomijam createvm"
    } else {
        & $VBox createvm --name $name --ostype Oracle_64 --basefolder $VmRoot --register
    }

    # 2. modifyvm: paravirt KVM clock + opcje sprzętowe.
    & $VBox modifyvm $name `
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

    # 3. SATA controller + hostiocache (selektywnie).
    if (-not (& $VBox showvminfo $name --machinereadable | Select-String 'storagecontrollername0="SATA"')) {
        if ($name -eq "infra01") {
            & $VBox storagectl $name --name SATA --add sata --controller IntelAhci --portcount 4 --hostiocache on
            Write-Host "  [perf] infra01: --hostiocache on (Windows page cache dla iSCSI backstore)" -ForegroundColor Yellow
        } else {
            & $VBox storagectl $name --name SATA --add sata --controller IntelAhci --portcount 4 --hostiocache off
            Write-Host "  [perf] ${name}: --hostiocache off (Oracle wymaga O_DIRECT)" -ForegroundColor Cyan
        }
    }

    # 4. Disk1 (OS) + Disk2 (storage extra dla infra01).
    $disk1Path = "$vmDir\$name-disk1.vdi"
    if (-not (Test-Path $disk1Path)) {
        & $VBox createmedium disk --filename $disk1Path --size ($vm.Disk1GB * 1024) --variant Standard
    }
    & $VBox storageattach $name --storagectl SATA --port 0 --device 0 --type hdd --medium $disk1Path

    if ($vm.Disk2GB -gt 0) {
        $disk2Path = "$vmDir\$name-disk2-storage.vdi"
        if (-not (Test-Path $disk2Path)) {
            & $VBox createmedium disk --filename $disk2Path --size ($vm.Disk2GB * 1024) --variant Standard
        }
        & $VBox storageattach $name --storagectl SATA --port 1 --device 0 --type hdd `
            --medium $disk2Path --nonrotational on
        Write-Host "  Disk2 (storage): $disk2Path - $($vm.Disk2GB) GB"
    }

    # 5. ISO mount.
    & $VBox storageattach $name --storagectl SATA --port 3 --device 0 --type dvddrive --medium $Iso

    # 6. Sieci wedlug profilu.
    switch ($vm.Net) {
        "infra" {
            & $VBox modifyvm $name --nic1 hostonly --hostonlyadapter1 "$HostOnlyIF" --nictype1 virtio
            & $VBox modifyvm $name --nic2 intnet --intnet2 rac-priv    --nictype2 virtio
            & $VBox modifyvm $name --nic3 intnet --intnet3 rac-storage --nictype3 virtio
            & $VBox modifyvm $name --nic4 nat --nictype4 virtio
        }
        "rac" {
            & $VBox modifyvm $name --nic1 hostonly --hostonlyadapter1 "$HostOnlyIF" --nictype1 virtio
            & $VBox modifyvm $name --nic2 intnet --intnet2 rac-priv    --nictype2 virtio
            & $VBox modifyvm $name --nic3 intnet --intnet3 rac-storage --nictype3 virtio
            & $VBox modifyvm $name --nic4 nat --nictype4 virtio
        }
        "stby" {
            & $VBox modifyvm $name --nic1 hostonly --hostonlyadapter1 "$HostOnlyIF" --nictype1 virtio
            & $VBox modifyvm $name --nic2 nat --nictype2 virtio
            & $VBox modifyvm $name --nic3 none
            & $VBox modifyvm $name --nic4 none
        }
        "client" {
            & $VBox modifyvm $name --nic1 hostonly --hostonlyadapter1 "$HostOnlyIF" --nictype1 virtio
            & $VBox modifyvm $name --nic2 nat --nictype2 virtio
            & $VBox modifyvm $name --nic3 none
            & $VBox modifyvm $name --nic4 none
        }
    }

    # 7. Shared folder OracleBinaries (opcjonalny, idempotentny).
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
    }

    Write-Host "  $name skonfigurowane: $($vm.Cpus) CPU, $($vm.RamMB) MB RAM, paravirt=kvm" -ForegroundColor Green
}

# === Podsumowanie ===
Write-Host "`n========== PODSUMOWANIE ==========" -ForegroundColor Green
$totalRam = 0; foreach ($v in $vms) { $totalRam += $v.RamMB }
Write-Host "Utworzone VM (suma RAM = $($totalRam / 1024) GB):"
foreach ($vm in $vms) {
    $disk2 = if ($vm.Disk2GB -gt 0) { "+$($vm.Disk2GB) GB storage" } else { "" }
    Write-Host "  $($vm.Name): $($vm.Cpus) CPU, $($vm.RamMB / 1024) GB RAM, $($vm.Disk1GB) GB OS $disk2 - paravirt=kvm"
}

Write-Host "`nNastepne kroki / Next steps:" -ForegroundColor Yellow
Write-Host "  1. Postaw HTTP server na hoscie:  cd kickstart && python -m http.server 8000"
Write-Host "  2. Boot infra01 z ISO, na ekranie GRUB nacisnij TAB i dodaj:"
Write-Host "       inst.ip=192.168.56.10::192.168.56.1:255.255.255.0::enp0s3:none inst.ks=http://192.168.56.1:8000/ks-infra01.cfg"
Write-Host "  3. Po infra01: setup_iscsi_target_infra01.sh, potem boot prim01/prim02/stby01/client01."
Write-Host "  4. Po OS-install na prim01/02: skrypt scripts/tune_storage_runtime.sh --target=initiator (F-18.E)."
Write-Host "  5. Reszta wedlug docs/03..09 + docs/10_Performance_Tuning.md."

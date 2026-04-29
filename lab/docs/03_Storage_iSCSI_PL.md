> [🇬🇧 English](./03_Storage_iSCSI.md) | 🇵🇱 Polski

# 03 — Konfiguracja Storage iSCSI (VMs2-install)

> **Cel:** Skonfigurowanie współdzielonych dysków dla klastra RAC (węzły `prim01` i `prim02`). Używamy konfiguracji **wydajnościowej (Block Backstore + LVM)** na maszynie `infra01` oraz wprowadzamy zaawansowane parametry w iSCSI Initiator, aby wycisnąć maksymalny performance w środowisku VirtualBox.

Dokument opisuje dwie metody wdrożenia: zautomatyzowaną (skryptową) oraz w pełni manualną krok po kroku.

---

## Metoda 1: Szybka Ścieżka Automatyczna (Zalecana)

### 1. iSCSI Target na infra01 (Wydajność LIO Block)

1.  Zaloguj się na `infra01` jako `root` (hasło: `Oracle26ai_LAB!`).
2.  Przekopiuj skrypt `setup_iscsi_target_infra01.sh` z repozytorium do katalogu `/tmp/`.
3.  Uruchom skrypt:
    ```bash
    bash /tmp/scripts/setup_iscsi_target_infra01.sh
    ```

### 2. iSCSI Initiator na prim01 i prim02

1.  Zaloguj się na `prim01` jako `root`.
2.  Uruchom skrypt:
    ```bash
    bash /tmp/scripts/setup_iscsi_initiator_prim.sh
    ```
3.  **Powtórz uruchomienie skryptu dla maszyny `prim02`.**

Przejdź od razu do sekcji **Weryfikacja współdzielenia dysków**.

---

## Metoda 2: Ścieżka Manualna (Krok po kroku)

Dla osób, które chcą dokładnie zrozumieć warstwę Storage iSCSI oraz jak wprowadzane są optymalizacje.

### 1. Konfiguracja iSCSI Target (`infra01`)

Zaloguj się na `infra01` jako `root`. Zmień scheduler I/O dla drugiego dysku, by wspierać równoległy zapis klastrowy:
```bash
echo mq-deadline > /sys/block/sdb/queue/scheduler
```

Teraz uruchom interfejs `targetcli`, aby ręcznie zdefiniować target LIO (korzystający prosto z Logical Volumes na LVM):

```bash
targetcli
```
W konsoli `/>` wklej po kolei (linia po linii):
```text
cd backstores/block
create name=ocr1 dev=/dev/vg_iscsi/lun_ocr1
create name=ocr2 dev=/dev/vg_iscsi/lun_ocr2
create name=ocr3 dev=/dev/vg_iscsi/lun_ocr3
create name=data1 dev=/dev/vg_iscsi/lun_data1
create name=reco1 dev=/dev/vg_iscsi/lun_reco1

# Optymalizacja dla wydajności (Write Cache = 1) dla warstwy DATA i RECO
set attribute emulate_write_cache=1 name=data1
set attribute emulate_write_cache=1 name=reco1

cd /iscsi
create iqn.2026-04.local.lab:infra01.target01
cd iqn.2026-04.local.lab:infra01.target01/tpg1/luns
create /backstores/block/ocr1
create /backstores/block/ocr2
create /backstores/block/ocr3
create /backstores/block/data1
create /backstores/block/reco1

cd ../acls
# Autoryzacja dostępu po IP i nazwie węzła
create iqn.1994-05.com.redhat:prim01
create iqn.1994-05.com.redhat:prim02
cd ../a_cls/iqn.1994-05.com.redhat:prim01
set auth userid=oracle
set auth password=Oracle26ai_LAB!
cd ../iqn.1994-05.com.redhat:prim02
set auth userid=oracle
set auth password=Oracle26ai_LAB!

cd ../../..
saveconfig
exit
```

Upewnij się, że target działa i jest włączony w systemd:
```bash
systemctl enable target
systemctl restart target
```

### 2. Konfiguracja iSCSI Initiator (`prim01` oraz `prim02`)

Wykonaj te same kroki dla `prim01` oraz `prim02`. Zaloguj się jako `root`.

Zmień plik konfiguracyjny usługi iscsid dla zwiększenia stabilności klastra RAC (szybsze odcięcie wadliwych dysków):
```bash
sed -i 's/^node.session.timeo.replacement_timeout.*/node.session.timeo.replacement_timeout = 15/' /etc/iscsi/iscsid.conf
sed -i 's/^node.session.cmds_max.*/node.session.cmds_max = 64/' /etc/iscsi/iscsid.conf
sed -i 's/^node.session.queue_depth.*/node.session.queue_depth = 64/' /etc/iscsi/iscsid.conf
```

Zapisz tożsamość węzła (iqn) odpowiadającą węzłowi i zrestartuj iSCSI:
```bash
# Na prim01:
echo "InitiatorName=iqn.1994-05.com.redhat:prim01" > /etc/iscsi/initiatorname.iscsi
# UWAGA: na prim02 wpisz prim02 zamiast prim01!

systemctl restart iscsid
```

Połącz się z serwerem iSCSI i zapisz hasło:
```bash
iscsiadm -m discovery -t sendtargets -p 10.0.5.15
iscsiadm -m node -T iqn.2026-04.local.lab:infra01.target01 -p 10.0.5.15 --op update -n node.session.auth.authmethod -v CHAP
iscsiadm -m node -T iqn.2026-04.local.lab:infra01.target01 -p 10.0.5.15 --op update -n node.session.auth.username -v oracle
iscsiadm -m node -T iqn.2026-04.local.lab:infra01.target01 -p 10.0.5.15 --op update -n node.session.auth.password -v Oracle26ai_LAB!

# Automatyczny start targetu i zalogowanie
iscsiadm -m node -T iqn.2026-04.local.lab:infra01.target01 -p 10.0.5.15 --op update -n node.startup -v automatic
iscsiadm -m node -T iqn.2026-04.local.lab:infra01.target01 -p 10.0.5.15 --login
```

Teraz skonfiguruj statyczne aliasy (Udev), aby ścieżki ASM były jednoznaczne:
```bash
cat > /etc/udev/rules.d/99-oracle-asmdevices.rules << 'EOF'
KERNEL=="sd*", BUS=="scsi", PROGRAM=="/usr/lib/udev/scsi_id -g -u -d /dev/$parent", RESULT=="36001405a41eaae900134440bbb7bcadd", SYMLINK+="oracleasm/OCR1", OWNER="grid", GROUP="asmadmin", MODE="0660"
KERNEL=="sd*", BUS=="scsi", PROGRAM=="/usr/lib/udev/scsi_id -g -u -d /dev/$parent", RESULT=="3600140590c6198f8cc048689baee433d", SYMLINK+="oracleasm/OCR2", OWNER="grid", GROUP="asmadmin", MODE="0660"
KERNEL=="sd*", BUS=="scsi", PROGRAM=="/usr/lib/udev/scsi_id -g -u -d /dev/$parent", RESULT=="360014056291a18241474ed9bacf8f2be", SYMLINK+="oracleasm/OCR3", OWNER="grid", GROUP="asmadmin", MODE="0660"
KERNEL=="sd*", BUS=="scsi", PROGRAM=="/usr/lib/udev/scsi_id -g -u -d /dev/$parent", RESULT=="36001405ee6efaa3fb3045cb97d8bcf51", SYMLINK+="oracleasm/DATA1", OWNER="grid", GROUP="asmadmin", MODE="0660"
KERNEL=="sd*", BUS=="scsi", PROGRAM=="/usr/lib/udev/scsi_id -g -u -d /dev/$parent", RESULT=="36001405e3ec4f9bcf01460a8cf9bf0b7", SYMLINK+="oracleasm/RECO1", OWNER="grid", GROUP="asmadmin", MODE="0660"
# Wylaczenie IO schedulera na inicjatorze dla maksymalnej wydajnosci ASM
ACTION=="add|change", KERNEL=="sd*", ENV{DEVTYPE}=="disk", RUN+="/bin/sh -c 'echo none > /sys/block/$name/queue/scheduler'"
EOF

udevadm control --reload-rules
udevadm trigger --type=devices --action=change
```

---

## 3. Weryfikacja współdzielenia dysków

Po zainstalowaniu i zalogowaniu na targety na obydwu węzłach RAC (`prim01` i `prim02`), musisz sprawdzić, czy współdzielenie działa i uprawnienia są spójne.

Na OBU węzłach wykonaj komendę:
```bash
ls -l /dev/oracleasm/
```

Wynik musi wyglądać identycznie na obu maszynach (pod kątem nazw, praw i właścicieli):
```text
lrwxrwxrwx. 1 root root 4 kwi 24 15:00 DATA1 -> ../sdb
lrwxrwxrwx. 1 root root 4 kwi 24 15:00 OCR1 -> ../sdc
...
```
*(Litery `sdb`, `sdc` itd. mogą się różnić pomiędzy serwerami – to normalne. Ważne, aby końcowy właściciel w `ls -lL /dev/oracleasm/` należał do `grid:asmadmin` z uprawnieniami rw-rw----)*:
```bash
ls -lL /dev/oracleasm/
```

Dopiero po poprawnej weryfikacji możesz przejść do konfiguracji warstwy Grid Infrastructure.

---
**Następny krok:** `04_Grid_Infrastructure.md`


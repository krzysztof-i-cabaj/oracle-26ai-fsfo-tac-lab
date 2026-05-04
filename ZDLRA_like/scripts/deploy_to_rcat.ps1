# ==============================================================================
# Tytul:        deploy_to_rcat.ps1
# Opis:         Kopiuje caly subtree projektu (scripts, sql, response_files)
#               na rcat01:/tmp/. Idempotent - kazdy run nadpisuje docelowe pliki.
#               Tworzy struktura tak by skrypty znajdowaly siostrzane sql/ przez ../sql.
# Description [EN]: Deploys subproject subtree (scripts, sql, response_files) to
#                   rcat01:/tmp/. Idempotent. Mirrors structure so scripts can
#                   reference sibling sql/ via ../sql.
#
# Autor:        KCB Kris
# Data:         2026-05-03
# Wersja:       1.0
# <repo>:       ZDLRA_like
# Konwencje:    ZDLRA_like/SETTINGS.md
#
# Wymagania [PL]:    - SSH klucz lub haslo do kris@rcat01.lab.local (lub IP)
#                    - DNS dla rcat01 (NRPT) lub uzyj -Host 192.168.56.16
#                    - rsync lub scp w PATH (Windows OpenSSH ma scp built-in)
# Requirements [EN]: - SSH access to kris@rcat01.lab.local; DNS via NRPT or -Host IP fallback
#
# Uzycie [PL]:  .\deploy_to_rcat.ps1                              # default: kris@rcat01.lab.local
#               .\deploy_to_rcat.ps1 -Host 192.168.56.16          # po IP
#               .\deploy_to_rcat.ps1 -RemoteUser oracle           # jako oracle (nie kris)
#               .\deploy_to_rcat.ps1 -DryRun                      # pokaz tylko co zostanie skopiowane
# Usage [EN]:   See above. Default deploys as kris to rcat01.lab.local.
# ==============================================================================

[CmdletBinding()]
param(
    [string]$RemoteHost = "rcat01.lab.local",
    [string]$RemoteUser = "kris",
    [string]$RemoteBase = "/tmp",
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

# Repo root = parent katalogu skryptu
$repo = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Write-Host "Repo root: $repo" -ForegroundColor Cyan
Write-Host "Target:    ${RemoteUser}@${RemoteHost}:${RemoteBase}" -ForegroundColor Cyan

# Co kopiujemy (sciezka lokalna -> sciezka zdalna)
$transfers = @(
    @{ Local = "$repo\scripts";        Remote = "$RemoteBase/scripts";        Pattern = "*.sh"  }
    @{ Local = "$repo\scripts\systemd"; Remote = "$RemoteBase/scripts/systemd"; Pattern = "*"    }
    @{ Local = "$repo\sql";            Remote = "$RemoteBase/sql";            Pattern = "*.sql" }
    @{ Local = "$repo\response_files"; Remote = "$RemoteBase/response_files"; Pattern = "*.rsp" }
)

# Sanity: kazdy local katalog istnieje
foreach ($t in $transfers) {
    if (-not (Test-Path $t.Local)) {
        Write-Host "[WARN] Local path not found: $($t.Local)" -ForegroundColor Yellow
    }
}

# Step 1: utworz katalogi docelowe (jeden ssh mkdir -p)
$mkdirCmd = $transfers | ForEach-Object { "mkdir -p '$($_.Remote)'" } | Sort-Object -Unique
$mkdirJoined = ($mkdirCmd -join ' && ')

Write-Host ""
Write-Host "Step 1: Tworzenie katalogow docelowych..." -ForegroundColor Cyan
Write-Host "  ssh ${RemoteUser}@${RemoteHost} `"$mkdirJoined`""
if (-not $DryRun) {
    & ssh "${RemoteUser}@${RemoteHost}" $mkdirJoined
    if ($LASTEXITCODE -ne 0) { throw "mkdir na zdalnym zakonczony bledem (exit $LASTEXITCODE)" }
}

# Step 2: scp kazdej grupy plikow
Write-Host ""
Write-Host "Step 2: Kopiowanie plikow..." -ForegroundColor Cyan
foreach ($t in $transfers) {
    if (-not (Test-Path $t.Local)) { continue }
    $files = Get-ChildItem -Path $t.Local -Filter $t.Pattern -File -ErrorAction SilentlyContinue
    if (-not $files) {
        Write-Host "  [skip] Brak plikow $($t.Pattern) w $($t.Local)" -ForegroundColor Yellow
        continue
    }
    Write-Host "  $($t.Local)\$($t.Pattern) -> ${RemoteUser}@${RemoteHost}:$($t.Remote)/" -ForegroundColor Green
    Write-Host "    Pliki: $($files.Count) ($([Math]::Round((($files | Measure-Object Length -Sum).Sum / 1KB), 1)) KB)"
    if (-not $DryRun) {
        # scp z multiple files
        $scpArgs = @()
        $scpArgs += $files.FullName
        $scpArgs += "${RemoteUser}@${RemoteHost}:$($t.Remote)/"
        & scp @scpArgs
        if ($LASTEXITCODE -ne 0) { throw "scp $($t.Pattern) zakonczony bledem (exit $LASTEXITCODE)" }
    }
}

# Step 3: walidacja po stronie zdalnej
Write-Host ""
Write-Host "Step 3: Walidacja zdalna..." -ForegroundColor Cyan
$verifyCmd = $transfers | ForEach-Object { "ls -la '$($_.Remote)' 2>/dev/null | head -3" }
$verifyJoined = "echo '--- scripts ---'; $($verifyCmd[0]); echo '--- systemd ---'; $($verifyCmd[1]); echo '--- sql ---'; $($verifyCmd[2]); echo '--- response_files ---'; $($verifyCmd[3])"
if (-not $DryRun) {
    & ssh "${RemoteUser}@${RemoteHost}" $verifyJoined
}

Write-Host ""
if ($DryRun) {
    Write-Host "[DRY-RUN] Nic nie zostalo wykonane. Usun -DryRun zeby wdrozyc." -ForegroundColor Yellow
} else {
    Write-Host "[OK] Deploy zakonczony pomyslnie." -ForegroundColor Green
    Write-Host ""
    Write-Host "Nastepne kroki / Next steps (z hosta):" -ForegroundColor Cyan
    Write-Host "  ssh root@${RemoteHost} 'bash /tmp/scripts/setup_oracle_env_rcat.sh'"
    Write-Host "  ssh oracle@${RemoteHost} 'bash /tmp/scripts/install_db_silent_rcat.sh /tmp/response_files/db_rcat_se2.rsp'"
    Write-Host "  ssh oracle@${RemoteHost} 'bash /tmp/scripts/dbca_create_rcat.sh'"
    Write-Host "  ssh oracle@${RemoteHost} 'bash /tmp/scripts/catalog_create.sh'"
}

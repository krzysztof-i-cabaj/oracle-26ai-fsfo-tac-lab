# ==============================================================================
# Tytul:        start_kickstart_http.ps1
# Opis:         Uruchamia Python http.server na porcie 8000 w katalogu
#               _RecoveryAppliance_/kickstart/. Idempotentny - jesli serwer
#               juz dziala (port zajety), nic nie robi. PID zapisuje do
#               .http_server.pid w katalogu kickstart.
# Description [EN]: Starts Python http.server on port 8000 in the kickstart
#                   directory. Idempotent - does nothing if port already bound.
#                   PID stored in .http_server.pid for later cleanup.
#
# Autor:        KCB Kris
# Data:         2026-05-01
# Wersja:       1.0
# <repo>:       ZDLRA_like
# Konwencje:    ZDLRA_like/SETTINGS.md
#
# Wymagania [PL]:    - Python 3.x w PATH (lub /c/Program Files/Python312/python.exe)
#                    - Port 8000 wolny (lub zajety przez nasz wczesniejszy proces)
#                    - Hostonly IF #2 ma adres 192.168.56.1 (sprawdzane informacyjnie)
# Requirements [EN]: - Python 3.x in PATH, port 8000 free or owned by us, host-only IF #2
#
# Uzycie [PL]:  .\start_kickstart_http.ps1            # start
#               .\start_kickstart_http.ps1 -Stop      # zatrzymaj nasz proces
#               .\start_kickstart_http.ps1 -Status    # sprawdz status
# Usage [EN]:   Start (default) | -Stop | -Status
# ==============================================================================

[CmdletBinding(DefaultParameterSetName='Start')]
param(
    [Parameter(ParameterSetName='Stop')]   [switch]$Stop,
    [Parameter(ParameterSetName='Status')] [switch]$Status,
    [int]$Port = 8000,
    [string]$KickstartDir = ""
)

$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# Resolve sciezki: -KickstartDir lub default = katalog rownolegly z 'boot'
# Resolve paths: -KickstartDir or default sibling of 'boot/'
# ---------------------------------------------------------------------------
if (-not $KickstartDir) {
    $scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
    # scripts/boot -> ../../kickstart
    $KickstartDir = Join-Path (Split-Path -Parent (Split-Path -Parent $scriptRoot)) 'kickstart'
}
if (-not (Test-Path $KickstartDir)) {
    throw "Katalog kickstart nie istnieje: $KickstartDir"
}
$KickstartDir = (Resolve-Path $KickstartDir).Path
$pidFile = Join-Path $KickstartDir '.http_server.pid'

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
function Test-PortListening {
    param([int]$Port)
    $conn = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
    return [bool]$conn
}

function Get-OurServerPid {
    if (-not (Test-Path $pidFile)) { return $null }
    $stored = Get-Content $pidFile -ErrorAction SilentlyContinue
    if (-not $stored) { return $null }
    $pidNum = [int]$stored
    $proc = Get-Process -Id $pidNum -ErrorAction SilentlyContinue
    if ($proc) { return $pidNum } else { return $null }
}

function Find-PythonExe {
    $candidates = @(
        'C:\Program Files\Python312\python.exe',
        'C:\Program Files\Python311\python.exe',
        'C:\Program Files\Python310\python.exe'
    )
    foreach ($c in $candidates) { if (Test-Path $c) { return $c } }
    $cmd = Get-Command python.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    throw "Python nie znaleziony. Zainstaluj Python 3.x lub podaj sciezke."
}

function Show-Status {
    $listening = Test-PortListening -Port $Port
    $ourPid    = Get-OurServerPid

    Write-Host "Katalog kickstart : $KickstartDir"
    Write-Host "Port              : $Port"
    Write-Host "Port nasluchuje   : $listening"
    if ($ourPid) {
        Write-Host "Nasz proces (PID) : $ourPid (z .http_server.pid)" -ForegroundColor Green
    } else {
        Write-Host "Nasz proces       : brak (PID file empty/stale)"  -ForegroundColor Yellow
    }
    if ($listening -and -not $ourPid) {
        Write-Host "UWAGA: Port zajety przez OBCY proces (nie nasz)." -ForegroundColor Red
    }

    # Sanity: list dostepnych kickstart files
    $cfgs = Get-ChildItem -Path $KickstartDir -Filter "ks-*.cfg" -ErrorAction SilentlyContinue
    if ($cfgs) {
        Write-Host ""
        Write-Host "Dostepne kickstarty (URL: http://192.168.56.1:$Port/<filename>):" -ForegroundColor Cyan
        foreach ($cfg in $cfgs) {
            Write-Host "  - $($cfg.Name)  ($($cfg.Length) bajtow)"
        }
    } else {
        Write-Host ""
        Write-Host "BRAK plikow ks-*.cfg w $KickstartDir" -ForegroundColor Yellow
    }
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
switch ($PSCmdlet.ParameterSetName) {
    'Status' { Show-Status; return }

    'Stop' {
        $ourPid = Get-OurServerPid
        if (-not $ourPid) {
            Write-Host "Nasz serwer nie dziala (PID file pusty/stale)." -ForegroundColor Yellow
            if (Test-Path $pidFile) { Remove-Item $pidFile -Force }
            return
        }
        Stop-Process -Id $ourPid -Force
        Remove-Item $pidFile -Force
        Write-Host "Zatrzymano serwer HTTP (PID $ourPid)." -ForegroundColor Green
        return
    }

    'Start' {
        $ourPid = Get-OurServerPid
        if ($ourPid) {
            Write-Host "Serwer juz dziala (PID $ourPid). Pomijam start." -ForegroundColor Yellow
            Show-Status
            return
        }

        if (Test-PortListening -Port $Port) {
            throw "Port $Port juz zajety przez obcy proces. Sprawdz przez 'Get-NetTCPConnection -LocalPort $Port' i zwolnij port."
        }

        $python = Find-PythonExe
        Write-Host "Uruchamiam: $python -m http.server $Port  (cwd: $KickstartDir)" -ForegroundColor Cyan

        # Start as background process; log do pliku w kickstart
        $logFile = Join-Path $KickstartDir '.http_server.log'
        $proc = Start-Process -FilePath $python `
            -ArgumentList @('-m', 'http.server', $Port.ToString(), '--bind', '0.0.0.0') `
            -WorkingDirectory $KickstartDir `
            -RedirectStandardOutput $logFile `
            -RedirectStandardError "$logFile.err" `
            -WindowStyle Hidden `
            -PassThru

        $proc.Id | Out-File -FilePath $pidFile -Encoding ASCII -Force

        # Walidacja: poczekaj na nasluch
        $deadline = (Get-Date).AddSeconds(10)
        while ((Get-Date) -lt $deadline) {
            if (Test-PortListening -Port $Port) {
                Write-Host "Serwer HTTP wystartowal (PID $($proc.Id)) na porcie $Port." -ForegroundColor Green
                Write-Host "URL: http://192.168.56.1:$Port/ks-<vm>.cfg"
                # UWAGA: Python http.server loguje access log do STDERR, nie STDOUT.
                # NOTE: Python http.server logs access log to STDERR, not STDOUT.
                Write-Host "Logi access (GET requests): $logFile.err  <- TUTAJ szukaj 'GET /ks-*.cfg 200'" -ForegroundColor Cyan
                Write-Host "Logi stdout (zwykle pusty):  $logFile" -ForegroundColor DarkGray
                Show-Status
                return
            }
            Start-Sleep -Milliseconds 500
        }
        throw "Python http.server nie wystartowal w ciagu 10s. Sprawdz $logFile.err"
    }
}

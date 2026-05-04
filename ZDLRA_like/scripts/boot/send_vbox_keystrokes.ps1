# ==============================================================================
# Tytul:        send_vbox_keystrokes.ps1
# Opis:         Funkcje wysylajace klawisze do VM przez VBoxManage controlvm
#               keyboardputscancode. Importowac jako dot-source.
#               Trzy tryby wywolania: -Text "abc...", -ControlKey 'End',
#               -CtrlChord 'x' (Ctrl-X). Obsluga batchowania (max 80 par/batch +
#               przerwa) zeby nie przepelnic bufora klawiatury VBox.
# Description [EN]: Functions sending keystrokes to a VM via VBoxManage
#                   keyboardputscancode. Three modes: -Text, -ControlKey, -CtrlChord.
#                   Batching prevents VBox keyboard buffer overflow.
#
# Autor:        KCB Kris
# Data:         2026-05-01
# Wersja:       1.0
# <repo>:       ZDLRA_like
# Konwencje:    ZDLRA_like/SETTINGS.md
#
# Wymagania [PL]:    - VirtualBox 7.x (VBoxManage w PATH lub w stalej sciezce)
#                    - VM w stanie running (poleceniem startvm)
#                    - Plik scancode_table.ps1 obok (dot-source)
# Requirements [EN]: - VirtualBox 7.x, VM running, scancode_table.ps1 alongside
#
# Uzycie [PL]:  Dot-source:    . .\send_vbox_keystrokes.ps1
#               Wywolaj:       Send-VBoxKeystrokes -VM 'rcat01' -Text 'inst.text'
#                              Send-VBoxKeystrokes -VM 'rcat01' -ControlKey 'End'
#                              Send-VBoxKeystrokes -VM 'rcat01' -CtrlChord 'x'
# Usage [EN]:   Dot-source, then call Send-VBoxKeystrokes with one of three modes.
# ==============================================================================

$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# Lokalizacja VBoxManage / VBoxManage location
# ---------------------------------------------------------------------------
$script:VBoxManagePath = "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"
if (-not (Test-Path $script:VBoxManagePath)) {
    # Fallback do PATH
    $cmd = Get-Command VBoxManage.exe -ErrorAction SilentlyContinue
    if ($cmd) { $script:VBoxManagePath = $cmd.Source }
    else { throw "VBoxManage.exe nie znaleziony ani w 'C:\Program Files\Oracle\VirtualBox\' ani w PATH." }
}

# ---------------------------------------------------------------------------
# Import tabeli scancode'ow
# Import scancode table (dot-source from same directory)
# ---------------------------------------------------------------------------
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptRoot 'scancode_table.ps1')

# ---------------------------------------------------------------------------
# Wewnetrzny helper: wysylanie tablicy hex codes batchami
# Internal helper: send hex code array in batches
# ---------------------------------------------------------------------------
function Invoke-VBoxScancodesInternal {
    param(
        [Parameter(Mandatory)][string]$VM,
        [Parameter(Mandatory)][int[]]$Codes,
        [int]$BatchSize = 80,
        [int]$BatchDelayMs = 50
    )

    if ($Codes.Count -eq 0) { return }

    # Sprawdz czy VM running (machinereadable + grep)
    $info = & $script:VBoxManagePath showvminfo $VM --machinereadable 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "VM '$VM' nie istnieje lub VBoxManage zwrocil blad: $info"
    }
    $stateLine = $info | Where-Object { $_ -match '^VMState=' }
    if (-not ($stateLine -match '"running"')) {
        throw "VM '$VM' nie jest w stanie 'running' (aktualnie: $stateLine). Najpierw 'VBoxManage startvm $VM'."
    }

    # Konwersja na hex strings (np. 0x12 -> "12")
    $hexStrings = $Codes | ForEach-Object { '{0:x2}' -f $_ }

    $batches = [math]::Ceiling($hexStrings.Count / $BatchSize)
    Write-Verbose "Wysylam $($hexStrings.Count) bajtow w $batches batchach po max $BatchSize."

    for ($i = 0; $i -lt $batches; $i++) {
        $start = $i * $BatchSize
        $end   = [math]::Min($start + $BatchSize, $hexStrings.Count) - 1
        $slice = $hexStrings[$start..$end]

        $args = @('controlvm', $VM, 'keyboardputscancode') + $slice
        $output = & $script:VBoxManagePath @args 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "VBoxManage keyboardputscancode failed (batch $($i+1)/$batches): $output"
        }

        if ($i -lt $batches - 1) {
            Start-Sleep -Milliseconds $BatchDelayMs
        }
    }
}

# ---------------------------------------------------------------------------
# Glowna funkcja eksportowa / Main exported function
# Trzy tryby wywolania (parameter sets):
#   1. -Text         - string ASCII
#   2. -ControlKey   - pojedynczy klawisz sterujacy (np. 'End', 'Enter', 'Down')
#   3. -CtrlChord    - Ctrl+znak (np. 'x' dla Ctrl-X)
# ---------------------------------------------------------------------------
function Send-VBoxKeystrokes {
    [CmdletBinding(DefaultParameterSetName='Text')]
    param(
        [Parameter(Mandatory)][string]$VM,

        [Parameter(Mandatory, ParameterSetName='Text')]
        [string]$Text,

        [Parameter(Mandatory, ParameterSetName='Control')]
        [ValidateScript({ $script:ControlKeys.ContainsKey($_) })]
        [string]$ControlKey,

        [Parameter(Mandatory, ParameterSetName='Ctrl')]
        [char]$CtrlChord,

        [int]$BatchSize = 80,
        [int]$BatchDelayMs = 50,
        [int]$RepeatControlKey = 1
    )

    switch ($PSCmdlet.ParameterSetName) {
        'Text' {
            $codes = ConvertTo-Scancodes -Text $Text
            Invoke-VBoxScancodesInternal -VM $VM -Codes $codes `
                -BatchSize $BatchSize -BatchDelayMs $BatchDelayMs
        }
        'Control' {
            $pair = $script:ControlKeys[$ControlKey]
            $allCodes = New-Object System.Collections.ArrayList
            for ($r = 0; $r -lt $RepeatControlKey; $r++) {
                foreach ($c in $pair) { [void]$allCodes.Add($c) }
            }
            Invoke-VBoxScancodesInternal -VM $VM -Codes $allCodes.ToArray() `
                -BatchSize $BatchSize -BatchDelayMs $BatchDelayMs
        }
        'Ctrl' {
            $codes = Get-CtrlKeyScancodes -Char $CtrlChord
            Invoke-VBoxScancodesInternal -VM $VM -Codes $codes `
                -BatchSize $BatchSize -BatchDelayMs $BatchDelayMs
        }
    }
}

# ---------------------------------------------------------------------------
# Helper: czeka az VM osiagnie zadany stan (running/poweroff/aborted)
# Helper: wait until VM reaches given state with timeout
# ---------------------------------------------------------------------------
function Wait-VBoxVMState {
    param(
        [Parameter(Mandatory)][string]$VM,
        [Parameter(Mandatory)][string]$State,
        [int]$TimeoutSec = 600,
        [int]$PollIntervalSec = 5
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        $info = & $script:VBoxManagePath showvminfo $VM --machinereadable 2>&1
        $line = $info | Where-Object { $_ -match '^VMState=' }
        if ($line -match "`"$State`"") {
            Write-Verbose "VM '$VM' osiagnal stan '$State' po $((Get-Date) - $deadline.AddSeconds(-$TimeoutSec))."
            return $true
        }
        Start-Sleep -Seconds $PollIntervalSec
    }
    return $false
}

Write-Verbose "send_vbox_keystrokes.ps1 zaladowany. Funkcje: Send-VBoxKeystrokes, Wait-VBoxVMState"

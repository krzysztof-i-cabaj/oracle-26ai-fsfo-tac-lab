# ==============================================================================
# Tytul:        scancode_table.ps1
# Opis:         Tabela scancode'ow PC Set 1 (Make/Break) dla VBoxManage keyboardputscancode.
#               Mapuje znaki ASCII (i wybrane klawisze sterujace) na pary hex.
#               Uzywane przez send_vbox_keystrokes.ps1 do wysylania payloadu do GRUB-a.
# Description [EN]: PC Set 1 scancode table (make/break pairs) for VBoxManage keyboardputscancode.
#                   Maps ASCII chars + control keys to hex pairs. Used by send_vbox_keystrokes.ps1
#                   to inject keystrokes into the GRUB editor.
#
# Autor:        KCB Kris
# Data:         2026-05-01
# Wersja:       1.0
# <repo>:       ZDLRA_like
# Konwencje:    ZDLRA_like/SETTINGS.md
#
# Wymagania [PL]:    - Zaklada uklad klawiatury US (standard GRUB)
#                    - Break code = Make code + 0x80 (ostatni bajt)
#                    - Klawisze rozszerzone (strzalki, End, Home) maja prefix 0xE0
# Requirements [EN]: - Assumes US keyboard layout (GRUB default)
#                    - Break = Make + 0x80, extended keys prefixed with 0xE0
#
# Uzycie [PL]:  Importuj jako dot-source:    . .\scancode_table.ps1
#               Uzyj funkcji Get-Scancode -Char 'a'
#               Uzyj zmiennej $ControlKeys['End']
# Usage [EN]:   Dot-source it, then use Get-Scancode or $ControlKeys.
# ==============================================================================

# ---------------------------------------------------------------------------
# Mapa znakow podstawowych (bez Shift) - Make code (1 bajt)
# Map of unshifted characters - Make code (1 byte)
# ---------------------------------------------------------------------------
$script:UnshiftedMakeCode = @{
    # Letters (US layout positions)
    'a' = 0x1e; 'b' = 0x30; 'c' = 0x2e; 'd' = 0x20; 'e' = 0x12; 'f' = 0x21;
    'g' = 0x22; 'h' = 0x23; 'i' = 0x17; 'j' = 0x24; 'k' = 0x25; 'l' = 0x26;
    'm' = 0x32; 'n' = 0x31; 'o' = 0x18; 'p' = 0x19; 'q' = 0x10; 'r' = 0x13;
    's' = 0x1f; 't' = 0x14; 'u' = 0x16; 'v' = 0x2f; 'w' = 0x11; 'x' = 0x2d;
    'y' = 0x15; 'z' = 0x2c;
    # Digits row (top): 1-0
    '1' = 0x02; '2' = 0x03; '3' = 0x04; '4' = 0x05; '5' = 0x06;
    '6' = 0x07; '7' = 0x08; '8' = 0x09; '9' = 0x0a; '0' = 0x0b;
    # Punctuation (no Shift)
    '-' = 0x0c; '=' = 0x0d;
    '[' = 0x1a; ']' = 0x1b;
    ';' = 0x27; "'" = 0x28; '`' = 0x29;
    '\' = 0x2b;
    ',' = 0x33; '.' = 0x34; '/' = 0x35;
    ' ' = 0x39
}

# ---------------------------------------------------------------------------
# Znaki wymagajace Shift - bazowy klawisz (Shift dodawany dynamicznie)
# Shifted characters - base key code (Shift wrap added dynamically)
# ---------------------------------------------------------------------------
$script:ShiftedMakeCode = @{
    # Uppercase letters share the same key as lowercase
    'A' = 0x1e; 'B' = 0x30; 'C' = 0x2e; 'D' = 0x20; 'E' = 0x12; 'F' = 0x21;
    'G' = 0x22; 'H' = 0x23; 'I' = 0x17; 'J' = 0x24; 'K' = 0x25; 'L' = 0x26;
    'M' = 0x32; 'N' = 0x31; 'O' = 0x18; 'P' = 0x19; 'Q' = 0x10; 'R' = 0x13;
    'S' = 0x1f; 'T' = 0x14; 'U' = 0x16; 'V' = 0x2f; 'W' = 0x11; 'X' = 0x2d;
    'Y' = 0x15; 'Z' = 0x2c;
    # Shifted digits row
    '!' = 0x02; '@' = 0x03; '#' = 0x04; '$' = 0x05; '%' = 0x06;
    '^' = 0x07; '&' = 0x08; '*' = 0x09; '(' = 0x0a; ')' = 0x0b;
    # Shifted punctuation
    '_' = 0x0c; '+' = 0x0d;
    '{' = 0x1a; '}' = 0x1b;
    ':' = 0x27; '"' = 0x28; '~' = 0x29;
    '|' = 0x2b;
    '<' = 0x33; '>' = 0x34; '?' = 0x35
}

# ---------------------------------------------------------------------------
# Klawisze sterujace - pary [make, break] gotowe do wyslania
# Control keys - ready-to-send [make, break] pairs
# ---------------------------------------------------------------------------
$script:ControlKeys = @{
    'Esc'        = @(0x01, 0x81)
    'Tab'        = @(0x0f, 0x8f)
    'Enter'      = @(0x1c, 0x9c)
    'Backspace'  = @(0x0e, 0x8e)
    'Space'      = @(0x39, 0xb9)
    'CapsLock'   = @(0x3a, 0xba)
    'LShift'     = @(0x2a, 0xaa)
    'RShift'     = @(0x36, 0xb6)
    'LCtrl'      = @(0x1d, 0x9d)
    'LAlt'       = @(0x38, 0xb8)
    # Extended keys (E0 prefix) - sequence: e0 XX  e0 (XX|0x80)
    'Up'         = @(0xe0, 0x48, 0xe0, 0xc8)
    'Down'       = @(0xe0, 0x50, 0xe0, 0xd0)
    'Left'       = @(0xe0, 0x4b, 0xe0, 0xcb)
    'Right'      = @(0xe0, 0x4d, 0xe0, 0xcd)
    'Home'       = @(0xe0, 0x47, 0xe0, 0xc7)
    'End'        = @(0xe0, 0x4f, 0xe0, 0xcf)
    'PgUp'       = @(0xe0, 0x49, 0xe0, 0xc9)
    'PgDn'       = @(0xe0, 0x51, 0xe0, 0xd1)
    'Ins'        = @(0xe0, 0x52, 0xe0, 0xd2)
    'Del'        = @(0xe0, 0x53, 0xe0, 0xd3)
    'F1'         = @(0x3b, 0xbb)
    'F2'         = @(0x3c, 0xbc)
    'F10'        = @(0x44, 0xc4)
}

# Eksport dla send_vbox_keystrokes.ps1 / Export for consumer script
$script:ScancodeTableExports = @{
    UnshiftedMakeCode = $script:UnshiftedMakeCode
    ShiftedMakeCode   = $script:ShiftedMakeCode
    ControlKeys       = $script:ControlKeys
}

# ---------------------------------------------------------------------------
# Helper: konwersja znaku ASCII na sekwencje par [make, break] hex
# Helper: convert ASCII char to sequence of [make, break] hex pairs
# Zwraca tablice byte[] gotowa do przekazania do VBoxManage
# Returns byte[] array ready for VBoxManage
# ---------------------------------------------------------------------------
function Get-CharScancodes {
    param([Parameter(Mandatory)][char]$Char)

    $c = [string]$Char
    if ($script:UnshiftedMakeCode.ContainsKey($c)) {
        $make  = $script:UnshiftedMakeCode[$c]
        $break = $make -bor 0x80
        return @($make, $break)
    }
    if ($script:ShiftedMakeCode.ContainsKey($c)) {
        $base       = $script:ShiftedMakeCode[$c]
        $baseBreak  = $base -bor 0x80
        $shiftMake  = $script:ControlKeys['LShift'][0]
        $shiftBreak = $script:ControlKeys['LShift'][1]
        # LShift down -> base down -> base up -> LShift up
        return @($shiftMake, $base, $baseBreak, $shiftBreak)
    }
    throw "Znak '$Char' (0x$([int][char]$Char | ForEach-Object { '{0:x2}' -f $_ })) nie jest w tabeli scancode'ow."
}

# ---------------------------------------------------------------------------
# Helper: konwersja stringa na flat array hex codes
# Helper: convert full string to flat hex array
# ---------------------------------------------------------------------------
function ConvertTo-Scancodes {
    param([Parameter(Mandatory)][string]$Text)
    $result = New-Object System.Collections.ArrayList
    foreach ($ch in $Text.ToCharArray()) {
        $codes = Get-CharScancodes -Char $ch
        foreach ($c in $codes) { [void]$result.Add($c) }
    }
    return ,$result.ToArray()
}

# ---------------------------------------------------------------------------
# Helper: sekwencja Ctrl+klawisz - np. Ctrl-X do bootu z GRUB-a
# Helper: Ctrl+key sequence (e.g. Ctrl-X to boot from GRUB)
# Sekwencja: Ctrl down -> key down -> key up -> Ctrl up
# ---------------------------------------------------------------------------
function Get-CtrlKeyScancodes {
    param([Parameter(Mandatory)][char]$Char)
    $codes = Get-CharScancodes -Char $Char
    if ($codes.Count -ne 2) {
        throw "Ctrl-<char> nie wspiera shifted chars (otrzymano $($codes.Count) bajtow dla '$Char')"
    }
    $ctrlMake  = $script:ControlKeys['LCtrl'][0]
    $ctrlBreak = $script:ControlKeys['LCtrl'][1]
    return @($ctrlMake, $codes[0], $codes[1], $ctrlBreak)
}

Write-Verbose "scancode_table.ps1 zaladowany: $($script:UnshiftedMakeCode.Count) niezmienionych + $($script:ShiftedMakeCode.Count) shifted + $($script:ControlKeys.Count) sterujacych"

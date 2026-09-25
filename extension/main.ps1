param([string]$PLAIN_TEXT)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

try {
    $query = ([string]$PLAIN_TEXT).Replace([string][char]0, '').Trim()
    if ([string]::IsNullOrWhiteSpace($query)) {
        return
    }

    # EscapeDataString encodes UTF-8 as a URI path segment. The preflight
    # prevents the older Windows PowerShell runtime from hitting its URI limit.
    $utf8Length = [System.Text.Encoding]::UTF8.GetByteCount($query)
    if ($utf8Length -gt 8000) {
        throw 'The selected text is too long for Eudic cap-dict.'
    }
    $encodedQuery = [System.Uri]::EscapeDataString($query)
    if ($encodedQuery.Length -gt 24000) {
        throw 'The encoded text is too long for Eudic cap-dict.'
    }

    $candidates = New-Object System.Collections.Generic.List[string]

    # Follow the installed executable, including Store package updates.
    foreach ($process in @(Get-Process -Name 'eudic' -ErrorAction SilentlyContinue)) {
        try {
            if ($process.Path) {
                $candidates.Add($process.Path)
            }
        }
        catch {
            # An inaccessible process is not an installation candidate.
        }
    }

    try {
        $package = Get-AppxPackage -Name 'DD146E41.Eudict' -ErrorAction SilentlyContinue |
            Sort-Object -Property Version -Descending |
            Select-Object -First 1
        if ($package -and $package.InstallLocation) {
            $candidates.Add((Join-Path $package.InstallLocation 'eudic.exe'))
        }
    }
    catch {
        # Portable and conventional installations are checked below.
    }

    foreach ($registryPath in @(
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\App Paths\eudic.exe',
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\App Paths\eudic.exe'
    )) {
        try {
            $registeredPath = (Get-ItemProperty -LiteralPath $registryPath -ErrorAction Stop).'(default)'
            if ($registeredPath) {
                $candidates.Add([string]$registeredPath)
            }
        }
        catch {
            # This registry entry does not exist on every installation.
        }
    }

    $command = Get-Command 'eudic.exe' -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($command -and $command.Source) {
        $candidates.Add($command.Source)
    }

    foreach ($path in @(
        (Join-Path $env:LOCALAPPDATA 'Programs\Eudic\eudic.exe'),
        (Join-Path $env:ProgramFiles 'Eudic\eudic.exe'),
        (Join-Path $env:ProgramFiles 'eusoft\eudic\eudic.exe')
    )) {
        $candidates.Add($path)
    }

    $eudicExecutable = $null
    foreach ($candidate in @($candidates | Select-Object -Unique)) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            $eudicExecutable = (Get-Item -LiteralPath $candidate).FullName
            break
        }
    }
    if (-not $eudicExecutable) {
        throw 'Cannot find eudic.exe. Install or start Eudic, then try again.'
    }

    $requestUri = 'eudic://cap-dict/{0}' -f $encodedQuery
    Start-Process -FilePath $eudicExecutable -ArgumentList @($requestUri) -ErrorAction Stop | Out-Null

    try {
        $logDirectory = Join-Path $env:LOCALAPPDATA 'EudicSnipDo'
        if (-not (Test-Path -LiteralPath $logDirectory)) {
            New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
        }
        $logPath = Join-Path $logDirectory 'bridge.log'
        if ((Test-Path -LiteralPath $logPath) -and (Get-Item -LiteralPath $logPath).Length -gt 1MB) {
            Move-Item -LiteralPath $logPath -Destination (Join-Path $logDirectory 'bridge.previous.log') -Force
        }
        $line = '{0}  Opened cap-dict; UTF-8 bytes={1}.' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'), $utf8Length
        Add-Content -LiteralPath $logPath -Value $line -Encoding UTF8
    }
    catch {
        # A logging error must not stop the dictionary popup.
    }
}
catch {
    throw
}

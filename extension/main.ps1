param(
    [string]$PLAIN_TEXT
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Write-BridgeLog {
    param([string]$Message)

    try {
        $logDirectory = Join-Path $env:LOCALAPPDATA 'EudicSnipDo'
        if (-not (Test-Path -LiteralPath $logDirectory)) {
            New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
        }

        $logPath = Join-Path $logDirectory 'bridge.log'
        if ((Test-Path -LiteralPath $logPath) -and (Get-Item -LiteralPath $logPath).Length -gt 1MB) {
            Move-Item -LiteralPath $logPath -Destination (Join-Path $logDirectory 'bridge.previous.log') -Force
        }

        $line = '{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'), $Message
        Add-Content -LiteralPath $logPath -Value $line -Encoding UTF8
    }
    catch {
        # Logging must never prevent lookup.
    }
}

function ConvertTo-Rfc3986PathSegment {
    param([Parameter(Mandatory = $true)][string]$Value)

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
    $builder = New-Object System.Text.StringBuilder ($bytes.Length * 3)

    foreach ($byte in $bytes) {
        $isUnreserved =
            ($byte -ge 0x41 -and $byte -le 0x5A) -or
            ($byte -ge 0x61 -and $byte -le 0x7A) -or
            ($byte -ge 0x30 -and $byte -le 0x39) -or
            $byte -eq 0x2D -or $byte -eq 0x2E -or
            $byte -eq 0x5F -or $byte -eq 0x7E

        if ($isUnreserved) {
            [void]$builder.Append([char]$byte)
        }
        else {
            [void]$builder.AppendFormat('%{0:X2}', $byte)
        }
    }

    return $builder.ToString()
}

function Find-EudicExecutable {
    $candidates = New-Object System.Collections.Generic.List[string]

    # Prefer the executable belonging to the already-running instance. This
    # automatically follows Microsoft Store updates and portable installs.
    try {
        foreach ($process in @(Get-Process -Name 'eudic' -ErrorAction SilentlyContinue)) {
            if ($process.Path) {
                $candidates.Add($process.Path)
            }
        }
    }
    catch {
        # Continue with installation discovery.
    }

    # Resolve the current Microsoft Store package dynamically. Never embed a
    # versioned WindowsApps path because it changes after each update.
    try {
        $package = Get-AppxPackage -Name 'DD146E41.Eudict' -ErrorAction SilentlyContinue |
            Sort-Object -Property Version -Descending |
            Select-Object -First 1
        if ($package -and $package.InstallLocation) {
            $candidates.Add((Join-Path $package.InstallLocation 'eudic.exe'))
        }
    }
    catch {
        # The bridge also supports non-Store installations below.
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
            # This installation type is not present.
        }
    }

    try {
        $command = Get-Command 'eudic.exe' -CommandType Application -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($command -and $command.Source) {
            $candidates.Add($command.Source)
        }
    }
    catch {
        # Continue with common locations.
    }

    foreach ($path in @(
        (Join-Path $env:LOCALAPPDATA 'Programs\Eudic\eudic.exe'),
        (Join-Path $env:ProgramFiles 'Eudic\eudic.exe'),
        (Join-Path $env:ProgramFiles 'eusoft\eudic\eudic.exe')
    )) {
        $candidates.Add($path)
    }

    foreach ($candidate in @($candidates | Select-Object -Unique)) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return (Get-Item -LiteralPath $candidate).FullName
        }
    }

    throw 'Cannot find eudic.exe. Install or start Eudic, then try again.'
}

try {
    # Remove only outer whitespace and NUL characters. Internal whitespace,
    # punctuation, line breaks, CJK text and emoji are preserved.
    $query = ([string]$PLAIN_TEXT).Replace([string][char]0, '').Trim()
    if ([string]::IsNullOrWhiteSpace($query)) {
        Write-BridgeLog 'Ignored an empty selection.'
        return
    }

    $encodedQuery = ConvertTo-Rfc3986PathSegment -Value $query

    # Leave ample room below Windows' command-line length limit. A dictionary
    # popup is not suitable for extremely large selections; fail explicitly
    # instead of silently truncating the user's text.
    if ($encodedQuery.Length -gt 24000) {
        throw 'The selected text is too long for the Eudic cap-dict interface.'
    }

    $eudicExecutable = Find-EudicExecutable
    $requestUri = 'eudic://cap-dict/{0}' -f $encodedQuery

    # The URI contains only RFC 3986 unreserved characters and percent escapes,
    # so it is safe as a single native-process argument and cannot be interpreted
    # as PowerShell code or extra command-line switches.
    Start-Process -FilePath $eudicExecutable -ArgumentList @($requestUri) -ErrorAction Stop | Out-Null
    Write-BridgeLog ('Opened cap-dict via {0}; UTF-8 bytes={1}.' -f $eudicExecutable, [System.Text.Encoding]::UTF8.GetByteCount($query))
}
catch {
    Write-BridgeLog ('ERROR: {0}' -f $_.Exception.Message)

    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        [void][System.Windows.Forms.MessageBox]::Show(
            $_.Exception.Message,
            'SnipDo to Eudic',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
    }
    catch {
        # SnipDo/PowerShell will still receive the terminating error below.
    }

    throw
}

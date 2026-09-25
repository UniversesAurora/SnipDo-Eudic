param(
    [string]$PLAIN_TEXT
)

& (Join-Path $PSScriptRoot 'Open-EudicCapture.ps1') -Text $PLAIN_TEXT

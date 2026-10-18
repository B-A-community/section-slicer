# Copyright 2026 B&A community. Apache-2.0.
# Полный прогон в живом SketchUp 2024 через мост sketchup-mcp (localhost:8080).
# Шаги с окном разбиты на несколько запросов: HtmlDialog загружается и
# обрабатывает клики только между запросами.
param([switch]$SkipExcel)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$su = Join-Path $PSScriptRoot 'su.ps1'
New-Item -ItemType Directory -Force (Join-Path $root 'build') | Out-Null
Start-Transcript -Path (Join-Path $root 'build/su2024-checks.log') -Force | Out-Null
try {
    foreach ($file in 'geometry', 'workflow', 'context', 'performance', 'interactive', 'interactive_dialog', 'interactive_check') {
        & $su -File (Join-Path $root "test/$file.rb")
        Start-Sleep -Seconds 2
    }
    if (-not $SkipExcel) {
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'test/excel_paste.ps1')
        if ($LASTEXITCODE -ne 0) { throw 'Excel paste check failed' }
    }
    Write-Host 'ALL LIVE SKETCHUP 2024 CHECKS PASSED'
} finally {
    Stop-Transcript | Out-Null
}
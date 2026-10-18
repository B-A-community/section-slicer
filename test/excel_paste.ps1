# Шаг 2: «Копировать» в окне → буфер Windows → вставка в Excel через COM.
# Проверяет приёмку ТЗ: таблица раскладывается по ячейкам, номер контура
# остаётся текстом, итоги совпадают с суммой граней. Буфер пользователя
# сохраняется и восстанавливается.
$ErrorActionPreference = 'Stop'
$su = Join-Path $PSScriptRoot '..\tools\su.ps1'
Add-Type -AssemblyName System.Windows.Forms
$saved = [System.Windows.Forms.Clipboard]::GetDataObject()
$savedText = if ([System.Windows.Forms.Clipboard]::ContainsText()) { [System.Windows.Forms.Clipboard]::GetText() } else { $null }
[System.Windows.Forms.Clipboard]::Clear()

& $su -File (Join-Path $PSScriptRoot 'clipboard.rb')
Start-Sleep -Seconds 2
& $su -File (Join-Path $PSScriptRoot 'clipboard_click.rb')
Start-Sleep -Seconds 2

$excel = $null
try {
    $text = [System.Windows.Forms.Clipboard]::GetText()
    $html = [System.Windows.Forms.Clipboard]::GetData('HTML Format')
    if (-not $text) { throw 'clipboard is empty after Copy' }
    if (-not $html) { throw 'no HTML flavour in clipboard' }
    Write-Host "PASS clipboard holds TSV and HTML ($($text.Split("`n").Count - 1) lines)"

    $excel = New-Object -ComObject Excel.Application
    $excel.Visible = $false
    $excel.DisplayAlerts = $false
    $book = $excel.Workbooks.Add()
    $sheet = $book.Worksheets.Item(1)
    $sheet.Range('A1').Select() | Out-Null
    $sheet.Paste()
    $used = $sheet.UsedRange
    $rows = $used.Rows.Count
    $cols = $used.Columns.Count
    if ($cols -ne 6) { throw "expected 6 columns, got $cols" }
    if ($sheet.Cells.Item(1, 4).Text -notlike 'Площадь*') { throw "header D1: $($sheet.Cells.Item(1, 4).Text)" }
    $contour = $sheet.Cells.Item(2, 3)
    if ($contour.Text -ne '1.1') { throw "contour C2 should stay text 1.1, got '$($contour.Text)'" }
    $sum = 0.0
    for ($r = 2; $r -lt $rows; $r++) {
        $c = $sheet.Cells.Item($r, 3).Text
        if ($c -match '^\d+\.\d+$') {
            $v = $sheet.Cells.Item($r, 4).Value2
            if ($v -isnot [double]) { throw "area in row $r is not a number: $v" }
            $sum += $v
        }
    }
    $grand = $sheet.Cells.Item($rows, 4).Value2
    if ($grand -isnot [double]) { throw "grand total is not a number: $grand" }
    if ([math]::Abs($grand - $sum) -gt 1e-6) { throw "grand $grand != sum of faces $sum" }
    $z = $sheet.Cells.Item(2, 2).Value2
    if ($z -isnot [double]) { throw "elevation is not a number: $z" }
    Write-Host "PASS Excel: $rows rows x $cols columns, contour as text, elevation $z numeric, total $grand = sum of faces"
    $book.Close($false)
} finally {
    if ($excel) { $excel.Quit(); [Runtime.InteropServices.Marshal]::ReleaseComObject($excel) | Out-Null }
    if ($savedText) { [System.Windows.Forms.Clipboard]::SetText($savedText) }
    elseif ($saved) { [System.Windows.Forms.Clipboard]::SetDataObject($saved, $true) }
    & $su -File (Join-Path $PSScriptRoot 'clipboard_cleanup.rb')
}

# build-fonts.ps1 —— 按页面实际用字重新生成 fonts/ 下的 woff2 子集
#
# 什么时候要跑：改了页面文案、加了新字、UI 里换了符号之后。
# 不跑的话 check-offline.ps1 会在 (b) 字符覆盖 报缺字。
#
# 用法:
#   powershell -ExecutionPolicy Bypass -File tools\build-fonts.ps1
#   powershell -ExecutionPolicy Bypass -File tools\build-fonts.ps1 -Extra "◐★"   # 追加页面尚未出现的字符
#   powershell -ExecutionPolicy Bypass -File tools\build-fonts.ps1 -SkipDownload  # 只打印字符集
[CmdletBinding()]
param(
    [string[]]$Extra = @(),
    [switch]$SkipDownload
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$fontDir = Join-Path $repoRoot 'fonts'

$pages = @(
    (Join-Path $repoRoot 'index.html'),
    (Join-Path $repoRoot '深空当铺\index.html')
) | Where-Object { Test-Path -LiteralPath $_ }

if ($pages.Count -eq 0) { Write-Host "[错误] 没有找到页面"; exit 2 }

# ── 1. 提取字符集：与 check-offline.ps1 完全相同的口径 ─────────
# 取全文（含 style/script/注释），去掉控制字符、代理区、BOM
$seen = New-Object 'System.Collections.Generic.HashSet[int]'
$sb = New-Object System.Text.StringBuilder
foreach ($p in $pages) {
    $html = Get-Content -LiteralPath $p -Raw -Encoding utf8
    foreach ($ch in $html.ToCharArray()) {
        $cp = [int]$ch
        if ($cp -lt 0x20) { continue }
        if ($cp -ge 0xD800 -and $cp -le 0xDFFF) { continue }
        if ($cp -eq 0xFEFF) { continue }
        if ($seen.Add($cp)) { [void]$sb.Append($ch) }
    }
}
foreach ($e in $Extra) { foreach ($ch in $e.ToCharArray()) { if ($seen.Add([int]$ch)) { [void]$sb.Append($ch) } } }
$charset = $sb.ToString()

Write-Host "页面: $($pages.Count) 个"
Write-Host "字符集: $($charset.Length) 个字符"

if ($SkipDownload) {
    $tmp = Join-Path $env:TEMP 'skdp-charset.txt'
    [System.IO.File]::WriteAllText($tmp, $charset, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "已写入 $tmp"
    exit 0
}

# ── 2. 印章字体只取固定用字（印章、签名、年份）────────────────
$brushChars = '鉴酿烧鹅濑酱—·0123456789'

# ── 3. 逐个 face 拉取子集 ─────────────────────────────────────
$ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36'
$faces = @(
    @{ Family = 'Noto Serif SC'; Weight = 500; Name = 'noto-serif-sc-500';    Chars = $charset },
    @{ Family = 'Noto Serif SC'; Weight = 600; Name = 'noto-serif-sc-600';    Chars = $charset },
    @{ Family = 'Noto Serif SC'; Weight = 700; Name = 'noto-serif-sc-700';    Chars = $charset },
    @{ Family = 'Noto Sans SC';  Weight = 400; Name = 'noto-sans-sc-400';     Chars = $charset },
    @{ Family = 'Noto Sans SC';  Weight = 500; Name = 'noto-sans-sc-500';     Chars = $charset },
    @{ Family = 'Noto Sans SC';  Weight = 600; Name = 'noto-sans-sc-600';     Chars = $charset },
    @{ Family = 'Noto Sans SC';  Weight = 700; Name = 'noto-sans-sc-700';     Chars = $charset },
    @{ Family = 'Ma Shan Zheng'; Weight = 400; Name = 'ma-shan-zheng-400';    Chars = $brushChars }
)

if (-not (Test-Path -LiteralPath $fontDir)) { New-Item -ItemType Directory -Path $fontDir | Out-Null }

$total = 0
foreach ($f in $faces) {
    $fam = $f.Family -replace ' ', '+'
    $api = 'https://fonts.googleapis.com/css2?family=' + $fam + ':wght@' + $f.Weight + '&text=' + [uri]::EscapeDataString($f.Chars)
    try {
        $css = (Invoke-WebRequest -Uri $api -UseBasicParsing -Headers @{ 'User-Agent' = $ua } -TimeoutSec 150).Content
        $m = [regex]::Match($css, 'url\((https://fonts\.gstatic\.com/[^)]+)\)')
        if (-not $m.Success) { Write-Host "  [跳过] $($f.Name): CSS 中没有 woff2 地址" -ForegroundColor DarkYellow; continue }
        $out = Join-Path $fontDir ($f.Name + '.woff2')
        Invoke-WebRequest -Uri $m.Groups[1].Value -UseBasicParsing -Headers @{ 'User-Agent' = $ua } -OutFile $out -TimeoutSec 150
        $len = (Get-Item -LiteralPath $out).Length
        $total += $len
        Write-Host ("  {0,-24} {1,9} bytes" -f $f.Name, $len)
    } catch {
        Write-Host "  [失败] $($f.Name): $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host ''
Write-Host ("完成：{0} 个 face，合计 {1} KB / 预算 1200 KB" -f $faces.Count, [math]::Round($total / 1024, 1))
Write-Host "下一步: powershell -ExecutionPolicy Bypass -File tools\check-offline.ps1"

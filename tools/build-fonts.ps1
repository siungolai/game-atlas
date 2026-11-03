# build-fonts.ps1 —— 按页面实际用字重新生成 fonts/ 下的 woff2 子集
#
# 什么时候要跑：改了页面文案、加了新字、UI 里换了符号之后。
# 不跑的话 check-offline.ps1 会在 (b) 字符覆盖 报缺字。
#
# 用法:
#   powershell -ExecutionPolicy Bypass -File tools\build-fonts.ps1
#   powershell -ExecutionPolicy Bypass -File tools\build-fonts.ps1 -Extra "◐★"   # 追加页面尚未出现的字符
#   powershell -ExecutionPolicy Bypass -File tools\build-fonts.ps1 -SkipDownload  # 只打印字符集
#
# 依赖（本机已装 fontTools 4.65.0 + brotli）:
#   python -m pip install fonttools brotli
#   Python 3.10+，需要 fontTools>=4（Merger 用于把分块下载的子集合并成单文件）
#
# 为什么不能一次把所有字塞进 text=:
#   Google Fonts css2 的 text= 参数在 URL 过长时会「静默失效」——不报错，改回返回
#   整套 unicode-range 切片 CSS（101 个 @font-face）。实测 800 字 / 6603 字节仍正常，
#   900 字 / 7503 字节就退化成 101 个 face；页面实际 1000+ 字必然触发。
#   旧脚本用正则取第一个 url()，于是只下到一个 2.3 KB 的小切片，页面满屏豆腐块，
#   脚本却照样 exit 0。现在改为：
#     1) 按 600 字分块请求（每块都是单 face），各块各下各的 woff2；
#     2) 用 fontTools.merge.Merger 合并成一个 woff2；
#     3) 三道断言：CSS 里 @font-face 只能有 1 个；合并后 cmap 必须覆盖本 face 的全部
#        请求字符（缺一个字就失败）；体积必须过下限（正文 20 KB，印章 4 KB）。
[CmdletBinding()]
param(
    [string[]]$Extra = @(),
    [switch]$SkipDownload
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$fontDir = Join-Path $repoRoot 'fonts'

# 分块大小：实测 800 字还安全、900 字就退化，取 600 留足余量
$ChunkSize = 600
# 每个 face 合并后的体积下限（字节）：残缺子集通常只有 2–3 KB
#   正文 face（1000+ 字）：20 KB
#   印章 face Ma Shan Zheng：只取 18 个固定用字，正常就是 5.7 KB 左右，故单独取 4 KB
$MinFaceBytes = 20480
$MinBrushBytes = 4096
# 字体体积预算，与 check-offline.ps1 保持一致
$BudgetKB = 1200

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
# 注意：Ma Shan Zheng 这套字体里没有中点 U+00B7，页面上的「·」是 Noto Sans SC 回退渲染的。
# 所以请求里带上它（有就下），但覆盖断言只要求其余 17 字——Expect 才是校验用的字符集。
$brushChars = '鉴酿烧鹅濑酱—·0123456789'
$brushExpect = '鉴酿烧鹅濑酱—0123456789'

# ── 3. 预处理：python / fontTools 是否可用 ──────────────────────
$python = $null
foreach ($cand in @('python', 'python3', 'py')) {
    $cmd = Get-Command $cand -ErrorAction SilentlyContinue
    if ($cmd) { $python = $cmd.Source; break }
}
if (-not $python) {
    Write-Host '[错误] 找不到 python。请先安装 Python 3.10+ 并执行: python -m pip install fonttools brotli' -ForegroundColor Red
    exit 4
}
& $python -c "import fontTools, brotli" 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host '[错误] 缺少 python 依赖。请执行: python -m pip install fonttools brotli' -ForegroundColor Red
    Write-Host "       当前解释器: $python" -ForegroundColor DarkYellow
    exit 4
}

$tmpRoot = Join-Path $env:TEMP ('ga-fontbuild-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $tmpRoot | Out-Null

$mergePy = Join-Path $tmpRoot 'merge.py'
$pyCode = @'
import io
import sys
from fontTools.merge import Merger

if len(sys.argv) < 4:
    sys.exit("usage: merge.py <chars-file> <out.woff2> <in1.woff2> [in2.woff2 ...]")

chars_file, out, ins = sys.argv[1], sys.argv[2], sys.argv[3:]
with io.open(chars_file, encoding="utf-8") as fh:
    expected = fh.read()

font = Merger().merge(ins)

try:
    cmap = font.getBestCmap() or {}
except Exception as exc:  # noqa: BLE001
    print("NO-CMAP %s" % exc)
    sys.exit(6)

missing = [c for c in expected if ord(c) not in cmap]
if missing:
    print("MISSING %d: %s" % (len(missing), " ".join("U+%04X" % ord(c) for c in missing[:40])))
    sys.exit(5)

font.flavor = "woff2"
font.save(out)
'@
[System.IO.File]::WriteAllText($mergePy, $pyCode, (New-Object System.Text.UTF8Encoding($false)))

# ── 4. 逐个 face 分块拉取并合并 ────────────────────────────────
$ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36'
$faces = @(
    @{ Family = 'Noto Serif SC'; Weight = 500; Name = 'noto-serif-sc-500';    Chars = $charset;    Expect = $charset;     MinBytes = $MinFaceBytes },
    @{ Family = 'Noto Serif SC'; Weight = 600; Name = 'noto-serif-sc-600';    Chars = $charset;    Expect = $charset;     MinBytes = $MinFaceBytes },
    @{ Family = 'Noto Serif SC'; Weight = 700; Name = 'noto-serif-sc-700';    Chars = $charset;    Expect = $charset;     MinBytes = $MinFaceBytes },
    @{ Family = 'Noto Sans SC';  Weight = 400; Name = 'noto-sans-sc-400';     Chars = $charset;    Expect = $charset;     MinBytes = $MinFaceBytes },
    @{ Family = 'Noto Sans SC';  Weight = 500; Name = 'noto-sans-sc-500';     Chars = $charset;    Expect = $charset;     MinBytes = $MinFaceBytes },
    @{ Family = 'Noto Sans SC';  Weight = 600; Name = 'noto-sans-sc-600';     Chars = $charset;    Expect = $charset;     MinBytes = $MinFaceBytes },
    @{ Family = 'Noto Sans SC';  Weight = 700; Name = 'noto-sans-sc-700';     Chars = $charset;    Expect = $charset;     MinBytes = $MinFaceBytes },
    @{ Family = 'Ma Shan Zheng'; Weight = 400; Name = 'ma-shan-zheng-400';    Chars = $brushChars; Expect = $brushExpect; MinBytes = $MinBrushBytes }
)

if (-not (Test-Path -LiteralPath $fontDir)) { New-Item -ItemType Directory -Path $fontDir | Out-Null }

$total = 0
$failed = 0
foreach ($f in $faces) {
    $fam = $f.Family -replace ' ', '+'
    $chars = [string]$f.Chars

    # 切块（字符集里已剔除代理区，全部是 BMP 字符，按 char 切不会劈开代理对）
    $chunks = @()
    for ($i = 0; $i -lt $chars.Length; $i += $ChunkSize) {
        $chunks += $chars.Substring($i, [Math]::Min($ChunkSize, $chars.Length - $i))
    }

    $parts = @()
    $aborted = $false
    for ($ci = 0; $ci -lt $chunks.Count; $ci++) {
        $api = 'https://fonts.googleapis.com/css2?family=' + $fam + ':wght@' + $f.Weight + '&text=' + [uri]::EscapeDataString($chunks[$ci])
        try {
            $css = (Invoke-WebRequest -Uri $api -UseBasicParsing -Headers @{ 'User-Agent' = $ua } -TimeoutSec 150).Content
        } catch {
            Write-Host "  [失败] $($f.Name) 第 $($ci + 1)/$($chunks.Count) 块请求失败: $($_.Exception.Message)" -ForegroundColor Red
            $aborted = $true; break
        }

        # 关键断言：text= 生效时只会有 1 个 @font-face；多于 1 个说明参数被忽略，拿到的是整套切片
        $faceCount = ([regex]::Matches($css, '@font-face')).Count
        if ($faceCount -gt 1) {
            Write-Host ("  [错误] {0} 第 {1} 块的 CSS 返回了 {2} 个 @font-face（text= 参数失效，请求 URL {3} 字节）" -f $f.Name, ($ci + 1), $faceCount, $api.Length) -ForegroundColor Red
            Write-Host "         Google 忽略了 text=，拿到的是整套 unicode-range 切片，拒绝继续。" -ForegroundColor Red
            Write-Host "         处理办法：把脚本里的 `$ChunkSize 调小（当前 $ChunkSize）后重试。" -ForegroundColor Red
            exit 3
        }

        $m = [regex]::Match($css, 'url\((https://fonts\.gstatic\.com/[^)]+)\)')
        if (-not $m.Success) {
            Write-Host "  [失败] $($f.Name) 第 $($ci + 1)/$($chunks.Count) 块: CSS 中没有 woff2 地址" -ForegroundColor Red
            $aborted = $true; break
        }

        $part = Join-Path $tmpRoot ($f.Name + '.' + $ci + '.woff2')
        try {
            Invoke-WebRequest -Uri $m.Groups[1].Value -UseBasicParsing -Headers @{ 'User-Agent' = $ua } -OutFile $part -TimeoutSec 150
        } catch {
            Write-Host "  [失败] $($f.Name) 第 $($ci + 1)/$($chunks.Count) 块下载失败: $($_.Exception.Message)" -ForegroundColor Red
            $aborted = $true; break
        }
        $parts += $part
    }

    if ($aborted) {
        Write-Host "  [失败] $($f.Name): 分块未全部就绪，跳过该 face（fonts/ 中原文件保持不变）" -ForegroundColor Red
        $failed++
        continue
    }

    # 合并成一个 woff2，并校验合并结果覆盖了本 face 期望的全部字符
    $charsFile = Join-Path $tmpRoot ($f.Name + '.chars.txt')
    [System.IO.File]::WriteAllText($charsFile, [string]$f.Expect, (New-Object System.Text.UTF8Encoding($false)))

    $merged = Join-Path $tmpRoot ($f.Name + '.merged.woff2')
    & $python $mergePy $charsFile $merged @parts
    $mergeExit = $LASTEXITCODE
    if ($mergeExit -eq 5) {
        Write-Host "  [错误] $($f.Name): 合并后 cmap 缺字（见上一行 MISSING 输出），fonts/ 未写入" -ForegroundColor Red
        exit 3
    }
    if ($mergeExit -eq 6) {
        Write-Host "  [错误] $($f.Name): 合并结果没有可用 cmap，fonts/ 未写入" -ForegroundColor Red
        exit 3
    }
    if ($mergeExit -ne 0 -or -not (Test-Path -LiteralPath $merged)) {
        Write-Host "  [失败] $($f.Name): fontTools 合并失败（exit $mergeExit）" -ForegroundColor Red
        $failed++
        continue
    }

    # 体积下限：残缺子集只有 2–3 KB，低于下限直接判失败，绝不写进 fonts/
    $len = (Get-Item -LiteralPath $merged).Length
    if ($len -lt $f.MinBytes) {
        Write-Host ("  [错误] {0}: 合并后仅 {1} bytes，低于 {2} bytes 下限，判为残缺子集" -f $f.Name, $len, $f.MinBytes) -ForegroundColor Red
        Write-Host "         多半是分块请求被 Google 忽略或字符集为空，fonts/ 未写入。" -ForegroundColor Red
        exit 3
    }

    $out = Join-Path $fontDir ($f.Name + '.woff2')
    Move-Item -LiteralPath $merged -Destination $out -Force
    $total += $len
    Write-Host ("  {0,-24} {1,9} bytes" -f $f.Name, $len)
}

Remove-Item -LiteralPath $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ''
if ($failed -gt 0) {
    Write-Host ("完成：{0}/{1} 个 face 成功，{2} 个失败，合计 {3} KB / 预算 {4} KB" -f ($faces.Count - $failed), $faces.Count, $failed, [math]::Round($total / 1024, 1), $BudgetKB) -ForegroundColor Red
    Write-Host "失败的 face 未写入 fonts/（仍是旧文件），修好后再跑一次，不要直接提交。" -ForegroundColor Red
    exit 1
}
Write-Host ("完成：{0} 个 face，合计 {1} KB / 预算 {2} KB" -f $faces.Count, [math]::Round($total / 1024, 1), $BudgetKB)
Write-Host "下一步: powershell -ExecutionPolicy Bypass -File tools\check-offline.ps1"

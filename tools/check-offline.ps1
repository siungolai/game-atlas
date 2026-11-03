# check-offline.ps1 —— 离线可用性验收
#
# 用法:
#   powershell -ExecutionPolicy Bypass -File tools\check-offline.ps1
#       → 自动检查仓库内的 index.html 与 深空当铺/index.html
#   powershell -ExecutionPolicy Bypass -File tools\check-offline.ps1 <某个.html>
#       → 只检查指定页面
#
# 输出三项判定：
#   (a) 外部资源引用数（link/script/img/iframe/source 的 href|src，以及 CSS url()），必须为 0
#   (b) 页面字符集 与 本地字体 cmap 的差集，必须为空
#   (c) 页面引用的字体文件总体积，必须 ≤ 1.2 MB
#
# 退出码: 0 全部通过 / 1 存在失败项 / 2 参数或环境错误
[CmdletBinding()]
param(
    [Parameter(Position = 0, Mandatory = $false)]
    [string]$HtmlPath
)

$ErrorActionPreference = 'Stop'
$BudgetBytes = 1258291   # 1.2 MB
$RepoRoot = Split-Path -Parent $PSScriptRoot

function Fail-Env([string]$msg) {
    Write-Host "[错误] $msg" -ForegroundColor Red
    exit 2
}

$mjs = Join-Path $PSScriptRoot 'font-coverage.mjs'
if (-not (Test-Path -LiteralPath $mjs)) { Fail-Env "缺少依赖脚本: $mjs" }
if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    Fail-Env "未找到 node —— 读取 woff2 的 cmap 需要一个 Node 运行时"
}

function Test-OnePage([string]$path) {
    $item = Get-Item -LiteralPath $path -ErrorAction SilentlyContinue
    if (-not $item) {
        Write-Host "[错误] 文件不存在: $path" -ForegroundColor Red
        return $false
    }
    $htmlDir = $item.DirectoryName
    $html = Get-Content -LiteralPath $item.FullName -Raw -Encoding utf8

    Write-Host ''
    $rel = $item.FullName
    if ($rel.StartsWith($RepoRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        $rel = $rel.Substring($RepoRoot.Length).TrimStart('\', '/')
    }
    Write-Host "=== 离线可用性检查: $rel ===" -ForegroundColor Cyan
    Write-Host "路径: $($item.FullName)"

    # ── (a) 外部资源引用 ──────────────────────────────────────
    $extRefs = New-Object System.Collections.ArrayList
    $tagRe = [regex]'(?is)<(link|script|img|iframe|source)\b[^>]*>'
    $attrRe = [regex]'(?is)\b(?:href|src)\s*=\s*(?:"([^"]*)"|''([^'']*)'')'
    foreach ($m in $tagRe.Matches($html)) {
        $tagName = $m.Groups[1].Value.ToLower()
        foreach ($am in $attrRe.Matches($m.Value)) {
            if ($am.Groups[1].Success) { $val = $am.Groups[1].Value } else { $val = $am.Groups[2].Value }
            if ($val -match '^https?://') {
                [void]$extRefs.Add([pscustomobject]@{ Kind = "<$tagName>"; Url = $val })
            }
        }
    }
    $cssRe = [regex]'(?is)url\(\s*[''"]?(https?://[^)''"]+)'
    foreach ($m in $cssRe.Matches($html)) {
        [void]$extRefs.Add([pscustomobject]@{ Kind = 'url()'; Url = $m.Groups[1].Value })
    }
    $srcsetRe = [regex]'(?is)\bsrcset\s*=\s*(?:"([^"]*)"|''([^'']*)'')'
    foreach ($m in $srcsetRe.Matches($html)) {
        if ($m.Groups[1].Success) { $val = $m.Groups[1].Value } else { $val = $m.Groups[2].Value }
        foreach ($piece in ($val -split ',')) {
            $u = ($piece -split '\s+')[0]
            if ($u -match '^https?://') { [void]$extRefs.Add([pscustomobject]@{ Kind = 'srcset'; Url = $u }) }
        }
    }
    $passA = ($extRefs.Count -eq 0)
    Write-Host ("  (a) 外部资源引用        {0} 处{1}" -f $extRefs.Count, $(if ($passA) { '' } else { '   << 未通过' }))
    if (-not $passA) {
        $extRefs | Group-Object Url | Sort-Object Count -Descending | Select-Object -First 10 | ForEach-Object {
            Write-Host ("        [{0}] {1}" -f $_.Group[0].Kind, $_.Name) -ForegroundColor DarkYellow
        }
    }

    # ── (c) 字体体积 ─────────────────────────────────────────
    $faceRe = [regex]'(?is)@font-face\s*\{(.*?)\}'
    $urlInFaceRe = [regex]'(?is)url\(\s*[''"]?([^)''"]+\.woff2?)(?:\?[^)''"]*)?[''"]?\s*\)'
    $fontFiles = New-Object System.Collections.ArrayList
    $missingFonts = New-Object System.Collections.ArrayList
    foreach ($fm in $faceRe.Matches($html)) {
        foreach ($um in $urlInFaceRe.Matches($fm.Groups[1].Value)) {
            $rel = $um.Groups[1].Value.Trim()
            if ($rel -match '^https?://') { continue }
            $abs = [System.IO.Path]::GetFullPath((Join-Path $htmlDir $rel))
            if (Test-Path -LiteralPath $abs) {
                if (-not $fontFiles.Contains($abs)) { [void]$fontFiles.Add($abs) }
            } elseif (-not $missingFonts.Contains($abs)) {
                [void]$missingFonts.Add($abs)
            }
        }
    }
    $fontBytes = 0
    foreach ($f in $fontFiles) { $fontBytes += (Get-Item -LiteralPath $f).Length }
    $fontKb = [math]::Round($fontBytes / 1024, 1)
    $passC = ($fontBytes -le $BudgetBytes) -and ($missingFonts.Count -eq 0)
    Write-Host ("  (c) 字体体积            {0} KB / 1.2 MB ({1} 个 woff2){2}" -f $fontKb, $fontFiles.Count, $(if ($passC) { '' } else { '   << 未通过' }))
    foreach ($mf in $missingFonts) { Write-Host "        缺少字体文件: $mf" -ForegroundColor DarkYellow }

    # ── (b) 字符覆盖 ─────────────────────────────────────────
    $need = New-Object 'System.Collections.Generic.List[char]'
    $seen = New-Object 'System.Collections.Generic.HashSet[int]'
    foreach ($ch in $html.ToCharArray()) {
        $cp = [int]$ch
        if ($cp -lt 0x20) { continue }
        if ($cp -ge 0xD800 -and $cp -le 0xDFFF) { continue }
        if ($cp -eq 0xFEFF) { continue }
        if ($seen.Add($cp)) { [void]$need.Add($ch) }
    }

    $passB = $false
    if ($fontFiles.Count -eq 0) {
        Write-Host "  (b) 字符覆盖            页面未声明本地 @font-face   << 未通过"
        Write-Host "        页面共需 $($need.Count) 个字符，但没有本地字体可判定" -ForegroundColor DarkYellow
    } else {
        $jsonRaw = & node $mjs @($fontFiles) '--json' 2>$null
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($jsonRaw)) {
            Write-Host "  (b) 字符覆盖            无法解析字体 cmap   << 未通过"
        } else {
            $cov = $jsonRaw | ConvertFrom-Json
            $have = New-Object 'System.Collections.Generic.HashSet[int]'
            foreach ($c in $cov.codes) { [void]$have.Add([int]$c) }
            $covered = 0
            $missing = New-Object 'System.Collections.Generic.List[char]'
            foreach ($ch in $need) {
                if ($have.Contains([int]$ch)) { $covered++ } else { [void]$missing.Add($ch) }
            }
            if ($need.Count -gt 0) { $pct = [math]::Round($covered * 100.0 / $need.Count, 2) } else { $pct = 100 }
            $passB = ($missing.Count -eq 0)
            Write-Host ("  (b) 字符覆盖            {0} / {1} ({2}%){3}" -f $covered, $need.Count, $pct, $(if ($passB) { '' } else { '   << 未通过' }))
            if (-not $passB) {
                $previewArr = @($missing | Select-Object -First 50)
                $preview = -join $previewArr
                Write-Host ("        缺字 {0} 个，前 50 个: {1}" -f $missing.Count, $preview) -ForegroundColor DarkYellow
            }
        }
    }

    $allPass = $passA -and $passB -and $passC
    Write-Host ''
    if ($allPass) {
        Write-Host "  → 通过: 零外部依赖，字体自包含且覆盖全部字符" -ForegroundColor Green
    } else {
        $failed = @()
        if (-not $passA) { $failed += '外部资源引用' }
        if (-not $passB) { $failed += '字符覆盖' }
        if (-not $passC) { $failed += '字体体积' }
        Write-Host ("  → 未通过: {0}" -f ($failed -join ' / ')) -ForegroundColor Red
    }
    return $allPass
}

# ── 主流程 ──────────────────────────────────────────────────
$targets = @()
if (-not [string]::IsNullOrWhiteSpace($HtmlPath)) {
    $targets = @($HtmlPath)
} else {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $candidates = @(
        (Join-Path $repoRoot 'index.html'),
        (Join-Path $repoRoot '深空当铺\index.html')
    )
    foreach ($c in $candidates) { if (Test-Path -LiteralPath $c) { $targets += $c } }
    if ($targets.Count -eq 0) { Fail-Env "未找到任何页面，请显式传入 HTML 路径" }
}

$results = @()
foreach ($t in $targets) { $results += (Test-OnePage $t) }

Write-Host ''
Write-Host ('─' * 60)
$failCount = @($results | Where-Object { -not $_ }).Count
if ($failCount -eq 0) {
    Write-Host ("总结: 全部通过（{0} 个页面）" -f $results.Count) -ForegroundColor Green
    exit 0
} else {
    Write-Host ("总结: {0}/{1} 个页面未通过" -f $failCount, $results.Count) -ForegroundColor Red
    exit 1
}

#requires -Version 5.1
<#
  run.ps1 -- 最小实验 harness
  用法:
    .\run.ps1 extract.py data\sample.txt   跑一次脚本，自动归档到 runs\<时间戳>\
    .\run.ps1 list                          看最近的运行记录
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Script = "",

    [Parameter(Position = 1, ValueFromRemainingArguments = $true)]
    [string[]]$ScriptArgs = @()
)

$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot
$Utf8 = New-Object System.Text.UTF8Encoding $false

function Write-Utf8([string]$Path, [string]$Text) {
    [System.IO.File]::WriteAllText($Path, $Text, $Utf8)
}

# ---------- 子命令: list ----------
if ($Script -eq 'list' -or $Script -eq '-list') {
    $idx = Join-Path $Root 'runs\index.csv'
    if (-not (Test-Path $idx)) {
        Write-Host '还没有任何运行记录。先跑一次:  .\run.ps1 extract.py data\sample.txt'
        return
    }
    $rows = @(Import-Csv $idx)
    if ($rows.Count -eq 0) { Write-Host 'index.csv 还是空的。'; return }
    Write-Host ("最近 " + $rows.Count + " 条记录 (旧的在上):`n")
    $rows | Select-Object -Last 20 | Format-Table run_id, script, args, exit, sec, tokens -AutoSize
    return
}

# ---------- 子命令: 跑脚本 ----------
if ([string]::IsNullOrWhiteSpace($Script)) {
    Write-Host '用法:  .\run.ps1 <脚本> [参数...]'
    Write-Host '示例:  .\run.ps1 extract.py data\sample.txt'
    Write-Host '       .\run.ps1 list'
    return
}

$scriptPath = Join-Path $Root $Script
if (-not (Test-Path $scriptPath)) { throw "找不到脚本: $scriptPath" }

$Py = Join-Path $Root '.venv\Scripts\python.exe'
if (-not (Test-Path $Py)) { $Py = 'python' }

# 中文输出不乱码
$env:PYTHONIOENCODING = 'utf-8'
try { [Console]::OutputEncoding = $Utf8 } catch { }

$start = Get-Date
$runId = $start.ToString('yyyy-MM-dd_HHmmss')
$runDir = Join-Path $Root ('runs\' + $runId)
New-Item -ItemType Directory -Path $runDir -Force | Out-Null

# 跑脚本: 一边打印到屏幕, 一边存进 logLines
Push-Location $Root
try {
    & $Py $Script @ScriptArgs 2>&1 | Tee-Object -Variable logLines | Out-Host
    $code = $LASTEXITCODE
    if ($null -eq $code) { $code = 0 }
}
catch {
    $code = 1
    $logLines = @($_.Exception.Message)
    Write-Host $_.Exception.Message -ForegroundColor Red
}
finally {
    Pop-Location
}

$dur = [math]::Round(((Get-Date) - $start).TotalSeconds, 2)
$logText = (@($logLines) | ForEach-Object { "$_" }) -join "`r`n"
Write-Utf8 (Join-Path $runDir 'log.txt') $logText

# ---------- 归档 prompt 原文 + 指纹 ----------
$promptInfo = @()
$promptDir = Join-Path $Root 'prompts'
if (Test-Path $promptDir) {
    $dst = Join-Path $runDir 'prompts'
    New-Item -ItemType Directory -Path $dst -Force | Out-Null
    Get-ChildItem $promptDir -Filter *.txt -File | ForEach-Object {
        $bytes = [System.IO.File]::ReadAllBytes($_.FullName)
        $sha = [System.Security.Cryptography.SHA256]::Create().ComputeHash($bytes)
        $hex = -join ($sha | ForEach-Object { $_.ToString('x2') })
        $promptInfo += [pscustomobject]@{
            file   = 'prompts/' + $_.Name
            sha256 = $hex.Substring(0, 16)
            bytes  = $bytes.Length
        }
        Copy-Item $_.FullName $dst -Force
    }
}

# ---------- 归档 output/ ----------
$outFiles = @()
$outSrc = Join-Path $Root 'output'
if (Test-Path $outSrc) {
    $dst = Join-Path $runDir 'output'
    New-Item -ItemType Directory -Path $dst -Force | Out-Null
    Get-ChildItem $outSrc -File | ForEach-Object {
        Copy-Item $_.FullName $dst -Force
        $outFiles += $_.Name
    }
}

# ---------- 从日志里抓 token 用量 ----------
$tokens = $null
$m = [regex]::Matches($logText, 'token \u7528\u91cf[:\uFF1A]\s*(\d+)')
if ($m.Count -gt 0) {
    $tokens = [int]$m[$m.Count - 1].Groups[1].Value
}
else {
    $m2 = [regex]::Match($logText, 'total_tokens=(\d+)')
    if ($m2.Success) { $tokens = [int]$m2.Groups[1].Value }
}

# ---------- 环境指纹 ----------
$pyVer = 'unknown'
try { $pyVer = (& $Py -c "import sys;print(sys.version.split()[0])") 2>$null } catch { }

# ---------- meta.json ----------
$meta = [ordered]@{
    run_id       = $runId
    script       = $Script
    args         = @($ScriptArgs)
    exit_code    = $code
    duration_sec = $dur
    tokens       = $tokens
    started      = $start.ToString('yyyy-MM-dd HH:mm:ss')
    python       = $pyVer
    python_exe   = $Py
    prompts      = @($promptInfo)
    outputs      = @($outFiles)
}
Write-Utf8 (Join-Path $runDir 'meta.json') ($meta | ConvertTo-Json -Depth 6)

# ---------- index.csv (一行一次运行, 方便横向对比) ----------
$idxPath = Join-Path $Root 'runs\index.csv'
if (-not (Test-Path $idxPath)) {
    Write-Utf8 $idxPath "run_id,script,args,exit,sec,tokens`r`n"
}
$tokCell = ''
if ($null -ne $tokens) { $tokCell = "$tokens" }
$csvLine = '"{0}","{1}","{2}","{3}","{4}","{5}"' -f $runId, $Script, ($ScriptArgs -join ' '), $code, $dur, $tokCell
Add-Content -Path $idxPath -Value $csvLine -Encoding UTF8

# ---------- 收尾摘要 ----------
Write-Host ''
if ($code -eq 0) {
    Write-Host ("[ok] " + $runId + "  用时 " + $dur + "s   tokens " + $(if ($null -eq $tokens) { '?' } else { $tokens })) -ForegroundColor Green
}
else {
    Write-Host ("[失败] " + $runId + "  退出码 " + $code + "  用时 " + $dur + "s") -ForegroundColor Red
}
Write-Host ('     日志  runs\' + $runId + '\log.txt')
Write-Host ('     参数  runs\' + $runId + '\meta.json')
foreach ($f in $outFiles) {
    Write-Host ('     产物  runs\' + $runId + '\output\' + $f)
}
if ($code -ne 0) {
    Write-Host ''
    Write-Host '出错时先看日志最后几行:' -ForegroundColor Yellow
    Write-Host ('  Get-Content runs\' + $runId + '\log.txt -Tail 20')
    exit 1
}

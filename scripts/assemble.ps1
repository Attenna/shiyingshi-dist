# scripts/assemble.ps1
# 按 manifest.json 组装交付物：core 导出 exe/pck + 各插件复制到 mods/。
# 每次运行清空 .work/ 与 dist/，保证可重复执行。
#
# 用法：
#   .\scripts\assemble.ps1 -Godot "D:\...\Godot_v4.5.1-stable_mono_win64_console.exe"
#   .\scripts\assemble.ps1 -SkipExport     # 只收集插件，不导出
[CmdletBinding()]
param(
    [string]$Manifest = "",
    [string]$Output = "",
    [string]$Work = "",
    [string]$Godot = $env:GODOT_BIN,
    [switch]$SkipExport
)

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $Manifest) { $Manifest = Join-Path $scriptDir '..\manifest.json' }
if (-not $Output) { $Output = Join-Path $scriptDir '..\dist' }
if (-not $Work) { $Work = Join-Path $scriptDir '..\.work' }
$Manifest = [IO.Path]::GetFullPath($Manifest)
$Output = [IO.Path]::GetFullPath($Output)
$Work = [IO.Path]::GetFullPath($Work)

if (-not (Test-Path $Manifest)) { throw "找不到 manifest: $Manifest" }
$config = Get-Content $Manifest -Raw -Encoding UTF8 | ConvertFrom-Json

function Invoke-Native {
    param([string]$File, [string[]]$Arguments, [switch]$Quiet)
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        if ($Quiet) {
            & $File @Arguments 2>&1 | Out-Null
        } else {
            & $File @Arguments 2>&1 | ForEach-Object { Write-Host $_ }
        }
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $old
    }
    return $code
}

function Invoke-Git {
    param([string[]]$Arguments)
    $code = Invoke-Native git $Arguments -Quiet
    if ($code -ne 0) { throw "git 失败（$code）: git $($Arguments -join ' ')" }
}

function Get-Checkout {
    param([string]$Repo, [string]$Ref, [string]$Dest)
    if (Test-Path $Dest) { Remove-Item -LiteralPath $Dest -Recurse -Force }
    $code = Invoke-Native git @('clone', '--quiet', '--depth', '1', '--branch', $Ref, $Repo, $Dest) -Quiet
    if ($code -eq 0) { return }
    if (Test-Path $Dest) { Remove-Item -LiteralPath $Dest -Recurse -Force }
    Write-Host "  ref 不是分支/tag，回退到 commit 检出: $Ref"
    Invoke-Git @('clone', '--quiet', '--depth', '1', $Repo, $Dest)
    Invoke-Git @('-C', $Dest, 'fetch', '--quiet', '--depth', '1', 'origin', $Ref)
    Invoke-Git @('-C', $Dest, 'checkout', '--quiet', '--detach', 'FETCH_HEAD')
}

function Copy-Plugin {
    param([string]$Source, [string]$Dest, [string]$Id)
    if (-not (Test-Path (Join-Path $Source 'plugin.json'))) {
        throw "插件缺少 plugin.json: $Id（$Source）"
    }
    New-Item -ItemType Directory -Force -Path (Split-Path $Dest -Parent) | Out-Null
    Copy-Item -LiteralPath $Source -Destination $Dest -Recurse -Force
    Get-ChildItem -LiteralPath $Dest -Recurse -Directory -Force -Filter '.godot' -ErrorAction SilentlyContinue |
        Remove-Item -Recurse -Force
}

Write-Host "清理输出与工作目录 ..."
Remove-Item -LiteralPath $Output -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $Work -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $Output, $Work | Out-Null

Write-Host "检出 core: $($config.core.repo)@$($config.core.ref)"
$coreRoot = Join-Path $Work 'core'
Get-Checkout $config.core.repo $config.core.ref $coreRoot
$coreDir = $coreRoot
if ($config.core.subdir -and $config.core.subdir -ne '.') {
    $coreDir = Join-Path $coreRoot $config.core.subdir
}

$modsOut = Join-Path $Output 'mods'
New-Item -ItemType Directory -Force -Path $modsOut | Out-Null
$enabled = 0
$skipped = 0
foreach ($plugin in $config.plugins) {
    if ($plugin.PSObject.Properties.Name -contains 'enabled' -and -not $plugin.enabled) {
        Write-Host "跳过（未启用）: $($plugin.id)"
        $skipped++
        continue
    }
    $source = $null
    if ($plugin.repo -eq $config.core.repo -and $plugin.ref -eq $config.core.ref) {
        $source = Join-Path $coreRoot $plugin.subdir
    } else {
        $clone = Join-Path $Work ("plugins\" + $plugin.id)
        Write-Host "检出插件 $($plugin.id): $($plugin.repo)@$($plugin.ref)"
        Get-Checkout $plugin.repo $plugin.ref $clone
        $source = Join-Path $clone $plugin.subdir
    }
    Copy-Plugin $source (Join-Path $modsOut $plugin.id) $plugin.id
    Write-Host "已收集插件: $($plugin.id)"
    $enabled++
}

if (-not $SkipExport) {
    if (-not $Godot -or -not (Test-Path $Godot)) {
        throw "未找到 Godot 可执行文件：请用 -Godot 指定（或设置 GODOT_BIN）"
    }
    Write-Host "导入 core 资源（生成类缓存）..."
    Invoke-Native $Godot @('--headless', '--path', $coreDir, '--import') -Quiet | Out-Null
    $exe = Join-Path $Output '演播室2.exe'
    Write-Host "导出 Windows Desktop: $exe"
    $code = Invoke-Native $Godot @('--headless', '--path', $coreDir, '--export-release', 'Windows Desktop', $exe)
    if ($code -ne 0) { throw "导出失败（退出码 $code）" }
    if (-not (Test-Path $exe)) { throw "导出后缺少 exe: $exe" }
    $pck = [IO.Path]::ChangeExtension($exe, '.pck')
    if (-not (Test-Path $pck)) { throw "导出后缺少 pck: $pck" }
}

Write-Host ''
Write-Host "完成：$enabled 个插件，跳过 $skipped 个 -> $Output"
Get-ChildItem -LiteralPath $Output | ForEach-Object { Write-Host "  $($_.Name)" }
if (Test-Path $modsOut) {
    Get-ChildItem -LiteralPath $modsOut -Directory | ForEach-Object { Write-Host "  mods/$($_.Name)/" }
}

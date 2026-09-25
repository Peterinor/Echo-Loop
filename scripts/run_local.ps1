param([string]$Device = 'emulator-5554')

$ErrorActionPreference = 'Stop'
if (Test-Path 'D:\env\echo-loop\Activate.ps1') {
    . 'D:\env\echo-loop\Activate.ps1'
}
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    # 模型凭据在应用设置中填写，不注入构建产物或提交到仓库。
    flutter run --flavor dev --target lib/main.dart --dart-define=APP_EDITION=local -d $Device
    if ($LASTEXITCODE -ne 0) { throw '本地版启动失败，请查看 Flutter 输出。' }
} finally {
    Pop-Location
}

[CmdletBinding()]
param(
    [string]$GodotExe,
    [string]$JavaSdk = $env:JAVA_HOME,
    [string]$AndroidSdk = $env:ANDROID_HOME,
    [string]$Python = 'python',
    [string]$Node = 'node'
)
$ErrorActionPreference = 'Stop'
$ConvoiProject = Split-Path -Parent $PSScriptRoot
$ConvoiBuild = Join-Path $ConvoiProject 'build'
function Invoke-ConvoiPython {
    param([string[]]$Arguments)
    & $Python @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Python build step failed: $LASTEXITCODE" }
}
if (-not $JavaSdk -or -not $AndroidSdk) { throw 'Provide -JavaSdk and -AndroidSdk, or set JAVA_HOME and ANDROID_HOME.' }
$ConvoiVariables = @{
    JAVA_HOME = (Resolve-Path -LiteralPath $JavaSdk).Path
    ANDROID_HOME = (Resolve-Path -LiteralPath $AndroidSdk).Path
    ANDROID_SDK_ROOT = (Resolve-Path -LiteralPath $AndroidSdk).Path
    ANDROID_USER_HOME = (Join-Path $ConvoiBuild 'user/android')
    GRADLE_USER_HOME = (Join-Path $ConvoiBuild 'user/gradle')
    APPDATA = (Join-Path $ConvoiBuild 'user/appdata')
    LOCALAPPDATA = (Join-Path $ConvoiBuild 'user/localappdata')
    TEMP = (Join-Path $ConvoiBuild 'tmp')
    TMP = (Join-Path $ConvoiBuild 'tmp')
    PYTHONDONTWRITEBYTECODE = '1'
}
$ConvoiPrevious = @{}
try {
    foreach ($ConvoiName in $ConvoiVariables.Keys) {
        $ConvoiPrevious[$ConvoiName] = [Environment]::GetEnvironmentVariable($ConvoiName, 'Process')
        [Environment]::SetEnvironmentVariable($ConvoiName, $ConvoiVariables[$ConvoiName], 'Process')
    }
    foreach ($ConvoiDirectory in @('logs', 'android', 'web-raw', 'web-pages', 'signing', 'tmp', 'user/android', 'user/gradle', 'user/appdata', 'user/localappdata')) {
        New-Item -ItemType Directory -Force -Path (Join-Path $ConvoiBuild $ConvoiDirectory) | Out-Null
    }
    New-Item -ItemType File -Force -Path (Join-Path $ConvoiBuild '.gdignore') | Out-Null
    if (-not $GodotExe) {
        $ConvoiGodotRoot = Join-Path $ConvoiBuild 'toolchain/godot'
        Invoke-ConvoiPython -Arguments @((Join-Path $PSScriptRoot 'fetch-godot.py'), '--destination', $ConvoiGodotRoot, '--platform', 'windows')
        $GodotExe = (Get-Content -LiteralPath (Join-Path $ConvoiGodotRoot 'install.json') -Raw | ConvertFrom-Json).executable
    }
    $GodotExe = (Resolve-Path -LiteralPath $GodotExe).Path
    $ConvoiVersion = & $GodotExe --headless --version
    if ($LASTEXITCODE -ne 0 -or ($ConvoiVersion -join "`n").Trim() -ne '4.7.2.stable.official.ed1daf0bf') { throw 'This build requires the official Godot 4.7.2 standard editor.' }
    $ConvoiKeystore = Join-Path $ConvoiBuild 'signing/local.keystore'
    if (-not (Test-Path -LiteralPath $ConvoiKeystore)) {
        & (Join-Path $JavaSdk 'bin/keytool.exe') -genkeypair -noprompt -keystore $ConvoiKeystore -alias androiddebugkey -storepass android -keypass android -dname 'CN=Android Debug,O=Android,C=US' -keyalg RSA -keysize 2048 -validity 10000
        if ($LASTEXITCODE -ne 0) { throw 'Could not generate local development key.' }
    }
    Invoke-ConvoiPython -Arguments @((Join-Path $PSScriptRoot 'configure-godot.py'), '--executable', $GodotExe, '--java-sdk', $JavaSdk, '--android-sdk', $AndroidSdk, '--keystore', $ConvoiKeystore, '--disable-safe-save')
    foreach ($ConvoiName in @('GODOT_ANDROID_KEYSTORE_RELEASE_PATH', 'GODOT_ANDROID_KEYSTORE_RELEASE_USER', 'GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD')) {
        $ConvoiPrevious[$ConvoiName] = [Environment]::GetEnvironmentVariable($ConvoiName, 'Process')
    }
    $env:GODOT_ANDROID_KEYSTORE_RELEASE_PATH = $ConvoiKeystore
    $env:GODOT_ANDROID_KEYSTORE_RELEASE_USER = 'androiddebugkey'
    $env:GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD = 'android'
    $ConvoiRunner = Join-Path $PSScriptRoot 'run-godot.py'
    Invoke-ConvoiPython -Arguments @($ConvoiRunner, '--executable', $GodotExe, '--log', (Join-Path $ConvoiBuild 'logs/import.log'), '--', '--path', $ConvoiProject, '--editor', '--quit')
    Invoke-ConvoiPython -Arguments @($ConvoiRunner, '--executable', $GodotExe, '--log', (Join-Path $ConvoiBuild 'logs/tests.log'), '--', '--path', $ConvoiProject, '--script', 'res://tests/test_state.gd')
    $ConvoiTestAppdata = $env:APPDATA
    $ConvoiTestData = $env:XDG_DATA_HOME
    try {
        $env:APPDATA = Join-Path $ConvoiBuild 'convoi-ui-test/appdata'
        $env:XDG_DATA_HOME = Join-Path $ConvoiBuild 'convoi-ui-test/data'
        New-Item -ItemType Directory -Force -Path $env:APPDATA, $env:XDG_DATA_HOME | Out-Null
        Invoke-ConvoiPython -Arguments @($ConvoiRunner, '--executable', $GodotExe, '--log', (Join-Path $ConvoiBuild 'logs/ui-tests.log'), '--', '--path', $ConvoiProject, '--script', 'res://tests/test_ui.gd')
    } finally {
        $env:APPDATA = $ConvoiTestAppdata
        $env:XDG_DATA_HOME = $ConvoiTestData
    }
    Invoke-ConvoiPython -Arguments @($ConvoiRunner, '--executable', $GodotExe, '--log', (Join-Path $ConvoiBuild 'logs/android-export.log'), '--expect', (Join-Path $ConvoiBuild 'android/le-dernier-convoi.apk'), '--', '--path', $ConvoiProject, '--export-release', 'Android', (Join-Path $ConvoiBuild 'android/le-dernier-convoi.apk'))
    Invoke-ConvoiPython -Arguments @($ConvoiRunner, '--executable', $GodotExe, '--log', (Join-Path $ConvoiBuild 'logs/web-export.log'), '--expect', (Join-Path $ConvoiBuild 'web-raw/index.html'), '--', '--path', $ConvoiProject, '--export-release', 'Web', (Join-Path $ConvoiBuild 'web-raw/index.html'))
    & $Node (Join-Path $PSScriptRoot 'pack-web.cjs') (Join-Path $ConvoiBuild 'web-raw') (Join-Path $ConvoiBuild 'web-pages')
    if ($LASTEXITCODE -ne 0) { throw 'Web packaging failed.' }
    foreach ($ConvoiNotice in @('LICENSE', 'GODOT_LICENSE.txt', 'GODOT_THIRD_PARTY_LICENSES.txt')) {
        foreach ($ConvoiDestination in @('android', 'web-raw', 'web-pages')) {
            Copy-Item -LiteralPath (Join-Path $ConvoiProject $ConvoiNotice) -Destination (Join-Path $ConvoiBuild $ConvoiDestination) -Force
        }
    }
    Write-Output "Exports: $ConvoiBuild"
} finally {
    foreach ($ConvoiName in $ConvoiPrevious.Keys) { [Environment]::SetEnvironmentVariable($ConvoiName, $ConvoiPrevious[$ConvoiName], 'Process') }
}

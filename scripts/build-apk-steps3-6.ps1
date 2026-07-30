param()
$ErrorActionPreference = 'Continue'
$script:ProjectDir = Split-Path -Parent $PSScriptRoot
$BT = "C:\Users\ASUS\AppData\Local\Android\Sdk\build-tools\34.0.0"
$PLATFORM = "C:\Users\ASUS\AppData\Local\Android\Sdk\platforms\android-34\android.jar"
$OBJ = "$script:ProjectDir\apk-build\_build\obj"
$DEX = "$script:ProjectDir\apk-build\_build\dex"
$BASE = "$script:ProjectDir\apk-build\_build\base-res.apk"
$OUT_DIR = "$script:ProjectDir\dist-apk"
$BT_BAT = "$BT\d8.bat"

Write-Host "=== Step 3: D8 (classes -> dex) ==="
New-Item -ItemType Directory -Force -Path $DEX | Out-Null
$classFiles = @(Get-ChildItem $OBJ -Recurse -Filter *.class | ForEach-Object { $_.FullName })

$listPath = "$env:TEMP\d8classlist-$(Get-Random).txt"
Set-Content -Path $listPath -Value ($classFiles -join "`r`n")

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('@echo off')
$cmd = """$BT_BAT"" --lib ""$PLATFORM"" --min-api 24 --output ""$DEX"""
foreach ($c in $classFiles) {
    $cmd = $cmd + " """ + $c + """"
}
[void]$sb.AppendLine($cmd)
$batPath = Join-Path $env:TEMP "d8run-$(Get-Random).bat"
[System.IO.File]::WriteAllText($batPath, $sb.ToString())

Write-Host "Using: $batPath"
& $batPath 2>&1 | ForEach-Object { Write-Host "D8: $_" }
Write-Host "D8 exit: $LASTEXITCODE"

if (-not (Test-Path "$DEX\classes.dex")) {
    Write-Host "FAIL: classes.dex not produced in $DEX"
    exit 1
}
Write-Host ("classes.dex: {0:N1} KB" -f ((Get-Item "$DEX\classes.dex").Length/1KB))

Write-Host "=== Step 4: Inject classes.dex into APK zip ==="
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::Open($BASE, 'Update')
try {
    $existing = $zip.GetEntry('classes.dex')
    if ($existing) { $existing.Delete() }
    [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, "$DEX\classes.dex", 'classes.dex') | Out-Null
}
finally { $zip.Dispose() }
Write-Host "Injected classes.dex"

Write-Host "=== Step 5: Zip-align ==="
New-Item -ItemType Directory -Force -Path $OUT_DIR | Out-Null
$UNALIGNED = "$OUT_DIR\_app-unsigned-unaligned.apk"
& "$BT\zipalign.exe" -f -p 4 "$BASE" "$UNALIGNED" 2>&1 | ForEach-Object { "ZIPALIGN: $_" }
if (-not (Test-Path $UNALIGNED)) { Copy-Item "$BASE" "$UNALIGNED" -Force }
Write-Host ("Unaligned APK: {0:N1} KB" -f ((Get-Item $UNALIGNED).Length/1KB))

Write-Host "=== Step 6: Sign APK ==="
$ksPath = "$env:USERPROFILE\.android\debug.keystore"
if (-not (Test-Path $ksPath)) {
    Write-Host "Creating debug keystore..."
    New-Item -ItemType Directory -Force (Split-Path $ksPath) | Out-Null
    $keytool = (Get-Command keytool -ErrorAction Stop).Source
    & $keytool -genkeypair -v -keystore "$ksPath" -alias androiddebugkey -keyalg RSA -keysize 2048 -validity 10000 -storepass android -keypass android -dname "CN=Android Debug,O=Android,C=US" 2>&1 | ForEach-Object { "KEYTOOL: $_" }
}
$APK = "$OUT_DIR\成都麻将缺一门计分-v1.0.0.apk"
& "$BT\apksigner.bat" sign --ks "$ksPath" --ks-pass pass:android --ks-key-alias androiddebugkey --key-pass pass:android --out "$APK" "$UNALIGNED" 2>&1 | ForEach-Object { "SIGN: $_" }

Write-Host "=== RESULT ==="
if (Test-Path $APK) {
    Write-Host ("SUCCESS: {0}  ({1:N2} MB)" -f $APK, ((Get-Item $APK).Length/1MB))
} else {
    Write-Host "FAIL: $APK not produced"
    exit 1
}
Remove-Item $batPath -ErrorAction SilentlyContinue
Remove-Item $listPath -ErrorAction SilentlyContinue

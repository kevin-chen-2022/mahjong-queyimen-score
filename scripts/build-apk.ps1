# Build APK using Android SDK build-tools - simplified with aapt package (v1) approach
param([string]$ProjectDir = (Get-Location).Path)

$ErrorActionPreference = 'Continue'

# ---- Paths ----
$ANDROID_HOME = "C:\Users\ASUS\AppData\Local\Android\Sdk"
$BT = "$ANDROID_HOME\build-tools\34.0.0"
$PLATFORM = "$ANDROID_HOME\platforms\android-34\android.jar"
$APK_ROOT = "$ProjectDir\apk-build"
$OUT_DIR = "$ProjectDir\dist-apk"
$WORK = "$APK_ROOT\_build"
$OBJ = "$WORK\obj"
$DEX = "$WORK\dex"
$ASSETS = "$APK_ROOT\assets"
$RES = "$APK_ROOT\res"
$MANIFEST = "$APK_ROOT\AndroidManifest.xml"
$JAVA_SRC = "$APK_ROOT\src\main\java"

# ---- Prep ----
Remove-Item $WORK -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $OUT_DIR,$OBJ,$DEX,$ASSETS | Out-Null
Copy-Item "$APK_ROOT\public\index.html" "$ASSETS\index.html" -Force
if (Test-Path "$APK_ROOT\public\作者赞赏码.png") {
  Copy-Item "$APK_ROOT\public\作者赞赏码.png" "$ASSETS\" -Force
}

# Tools
$AAPT2 = "$BT\aapt2.exe"
$AAPT  = "$BT\aapt.exe"
$D8    = "$BT\d8.bat"
$ZIPALIGN = "$BT\zipalign.exe"
$APKSIGNER = "$BT\apksigner.bat"

# ---- 1) Generate R.java + base resources APK via aapt package ----
Write-Host "--- Step 1: aapt package to generate R.java and base resource APK ---"
$RGenDir = "$WORK\rgen"
New-Item -ItemType Directory -Force -Path $RGenDir | Out-Null
$BASE_RES_APK = "$WORK\base-res.apk"

& $AAPT package -f -m `
  -J "$RGenDir" `
  -S "$RES" `
  -I "$PLATFORM" `
  -M "$MANIFEST" `
  -A "$ASSETS" `
  -F "$BASE_RES_APK" `
  --min-sdk-version 24 `
  --target-sdk-version 34 `
  --version-code 1 `
  --version-name "1.0.0" `
  --rename-manifest-package "com.youxunchen.mahjong.queyimen" 2>&1 | ForEach-Object { "$_" }

Write-Host "base-res.apk exists: $(Test-Path $BASE_RES_APK)"
$RJavaSource = Get-ChildItem "$RGenDir" -Recurse -Filter R.java -ErrorAction SilentlyContinue
if ($RJavaSource) { Write-Host "R.java at: $($RJavaSource.FullName)" } else { Write-Host "R.java not found" }

# ---- 2) Compile Java (MainActivity + R.java) using javac ----
Write-Host "--- Step 2: javac compile MainActivity + R.java ---"
$javaFiles = @(Get-ChildItem $JAVA_SRC -Recurse -Filter *.java | ForEach-Object { $_.FullName })
if ($RJavaSource) { $javaFiles += $RJavaSource.FullName }

$javacExe = (Get-Command javac -ErrorAction Stop).Source
& $javacExe -encoding UTF-8 -source 17 -target 17 -classpath "$PLATFORM" -d "$OBJ" $javaFiles 2>&1 | ForEach-Object { "$_" }
Write-Host "ecj exit code: $LASTEXITCODE"
$classesCount = (Get-ChildItem $OBJ -Recurse -Filter *.class -ErrorAction SilentlyContinue).Count
Write-Host "Produced .class files: $classesCount"
if ($classesCount -eq 0) { throw "ECJ produced no .class files" }

# ---- 3) D8 classes -> classes.dex ----
Write-Host "--- Step 3: d8 classes -> dex ---"
$classFiles = Get-ChildItem $OBJ -Recurse -Filter *.class | ForEach-Object { $_.FullName }
$d8Bat = "$env:TEMP\d8run-$(Get-Random).bat"
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('@echo off')
$d8Cmd = """$D8"" --lib ""$PLATFORM"" --min-api 24 --output ""$DEX"""
foreach ($c in $classFiles) { $d8Cmd = $d8Cmd + " """ + $c + """" }
[void]$sb.AppendLine($d8Cmd)
[System.IO.File]::WriteAllText($d8Bat, $sb.ToString())
& $d8Bat 2>&1 | ForEach-Object { "$_" }
Remove-Item $d8Bat -ErrorAction SilentlyContinue
if (-not (Test-Path "$DEX\classes.dex")) { throw "d8 failed to produce classes.dex" }
Write-Host "classes.dex exists: Yes"

# ---- 4) Insert classes.dex into base-res.apk (they're zip files) ----
Write-Host "--- Step 4: insert classes.dex into APK zip ---"
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::Open("$BASE_RES_APK", 'Update')
try {
  $existing = $zip.GetEntry('classes.dex')
  if ($existing) { $existing.Delete() }
  [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, "$DEX\classes.dex", 'classes.dex') | Out-Null
} finally {
  $zip.Dispose()
}

# ---- 5) Zip-align ----
Write-Host "--- Step 5: Zip-align ---"
$UNALIGNED = "$OUT_DIR\_app-unsigned-unaligned.apk"
& $ZIPALIGN -f -p 4 "$BASE_RES_APK" "$UNALIGNED" 2>&1 | ForEach-Object { "$_" }
if (-not (Test-Path $UNALIGNED)) { Copy-Item "$BASE_RES_APK" "$UNALIGNED" -Force }
Write-Host "Unaligned apk size: $([math]::Round((Get-Item $UNALIGNED).Length/1KB,1)) KB"

# ---- 6) Sign with debug keystore ----
Write-Host "--- Step 6: Sign APK ---"
$ksPath = "$env:USERPROFILE\.android\debug.keystore"
if (-not (Test-Path $ksPath)) {
  Write-Host "Creating debug keystore at $ksPath ..."
  New-Item -ItemType Directory -Force (Split-Path $ksPath) | Out-Null
  $keytool = Join-Path (Split-Path (Get-Command javac -ErrorAction Stop).Source -Parent) "keytool.exe"
  if (-not (Test-Path $keytool)) { $keytool = (Get-Command keytool -ErrorAction Stop).Source }
  & $keytool -genkeypair -v -keystore "$ksPath" -alias androiddebugkey `
    -keyalg RSA -keysize 2048 -validity 10000 `
    -storepass android -keypass android `
    -dname "CN=Android Debug,O=Android,C=US" 2>&1 | ForEach-Object { "$_" }
}
$APK_SIGNED_ASCII = "$OUT_DIR\mahjong-v1.0.0.apk"
$APK_SIGNED = "$OUT_DIR\成都麻将缺一门计分-v1.0.0.apk"
& $APKSIGNER sign `
  --ks "$ksPath" --ks-pass pass:android --ks-key-alias androiddebugkey --key-pass pass:android `
  --out "$APK_SIGNED_ASCII" "$UNALIGNED" 2>&1 | ForEach-Object { "$_" }
# Rename to Chinese name after signing
if (Test-Path $APK_SIGNED_ASCII) { Copy-Item $APK_SIGNED_ASCII $APK_SIGNED -Force }

Write-Host "==== APK BUILD RESULT ===="
if (Test-Path $APK_SIGNED) {
  $sz = [math]::Round((Get-Item $APK_SIGNED).Length/1MB,2)
  Write-Host "SUCCESS: $APK_SIGNED ($sz MB)"
} else {
  Write-Host "FAIL: Signed APK not produced"
  exit 1
}

param(
  [string]$ConfigPath = "release.env",
  [switch]$SkipChecks,
  [switch]$RequireFirebase
)

$ErrorActionPreference = "Stop"

function Read-EnvFile {
  param([string]$Path)

  if (-not (Test-Path -LiteralPath $Path)) {
    throw "Khong tim thay file cau hinh: $Path. Hay copy release.env.example thanh release.env va dien gia tri that."
  }

  $values = @{}
  foreach ($line in Get-Content -LiteralPath $Path) {
    $trimmed = $line.Trim()
    if ($trimmed.Length -eq 0 -or $trimmed.StartsWith("#")) {
      continue
    }

    $parts = $trimmed -split "=", 2
    if ($parts.Count -ne 2) {
      continue
    }

    $key = $parts[0].Trim()
    $value = $parts[1].Trim().Trim('"').Trim("'")
    if ($key.Length -gt 0 -and $value.Length -gt 0) {
      $values[$key] = $value
    }
  }

  return $values
}

function Require-Key {
  param(
    [hashtable]$Values,
    [string]$Key
  )

  if (-not $Values.ContainsKey($Key) -or [string]::IsNullOrWhiteSpace($Values[$Key])) {
    throw "Thieu $Key trong release.env"
  }
}

$values = Read-EnvFile -Path $ConfigPath
Require-Key -Values $values -Key "GOOGLE_DRIVE_API_KEY"

$firebaseKeys = @(
  "FIREBASE_API_KEY",
  "FIREBASE_APP_ID",
  "FIREBASE_MESSAGING_SENDER_ID",
  "FIREBASE_PROJECT_ID"
)

$missingFirebase = @()
foreach ($key in $firebaseKeys) {
  if (-not $values.ContainsKey($key) -or [string]::IsNullOrWhiteSpace($values[$key])) {
    $missingFirebase += $key
  }
}

if ($RequireFirebase -and $missingFirebase.Count -gt 0) {
  throw "Thieu cau hinh Firebase: $($missingFirebase -join ', ')"
}

if ($missingFirebase.Count -gt 0) {
  Write-Host "Canh bao: chua du Firebase config, APK se doc Drive/offline nhung dang nhap-chat-dong bo se tam tat." -ForegroundColor Yellow
}

$defineKeys = @(
  "GOOGLE_DRIVE_API_KEY",
  "GOOGLE_DRIVE_FOLDER_URL",
  "GOOGLE_DRIVE_FOLDER_URLS",
  "FIREBASE_API_KEY",
  "FIREBASE_APP_ID",
  "FIREBASE_MESSAGING_SENDER_ID",
  "FIREBASE_PROJECT_ID",
  "FIREBASE_AUTH_DOMAIN",
  "FIREBASE_STORAGE_BUCKET",
  "FIREBASE_MEASUREMENT_ID",
  "FIREBASE_IOS_BUNDLE_ID",
  "VBOOK_ADMIN_EMAILS"
)

$buildArgs = @("build", "apk", "--release")
foreach ($key in $defineKeys) {
  if ($values.ContainsKey($key) -and -not [string]::IsNullOrWhiteSpace($values[$key])) {
    $buildArgs += "--dart-define=$key=$($values[$key])"
  }
}

flutter clean
flutter pub get

if (-not $SkipChecks) {
  flutter analyze
  flutter test
}

flutter @buildArgs

$apkPath = Join-Path (Get-Location) "build\app\outputs\flutter-apk\app-release.apk"
if (-not (Test-Path -LiteralPath $apkPath)) {
  throw "Build xong nhung khong tim thay APK tai $apkPath"
}

$apk = Get-Item -LiteralPath $apkPath
Write-Host "APK da san sang: $($apk.FullName)" -ForegroundColor Green
Write-Host "Dung luong: $([Math]::Round($apk.Length / 1MB, 1)) MB" -ForegroundColor Green

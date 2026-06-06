param(
  [string]$ProjectId = ""
)

$ErrorActionPreference = "Stop"

if (-not (Get-Command firebase -ErrorAction SilentlyContinue)) {
  throw "Chua cai Firebase CLI. Cai bang: npm install -g firebase-tools, sau do chay firebase login"
}

if ([string]::IsNullOrWhiteSpace($ProjectId)) {
  firebase deploy --only firestore:rules
} else {
  firebase deploy --project $ProjectId --only firestore:rules
}

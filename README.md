# vBook

Flutter app doc truyen EPUB, PDF va TXT. App lay catalog/file truyen truc tiep
tu Google Drive, con tai khoan, xac nhan email, chat cong dong, thu vien ca
nhan va tien do doc duoc luu bang Firebase Auth + Cloud Firestore.

## Kien truc release

```text
Flutter APK
  -> Google Drive API: catalog va file truyen
  -> Firebase Auth: dang ky, dang nhap, gui link xac nhan email
  -> Cloud Firestore: profile, chat cong dong, thu vien, tien do doc
  -> Local storage: cache truyen, file offline, vi tri doc gan nhat
```

APK release khong can chay backend Python tren may tinh. Khi mo app, app goi
Firebase va Google Drive truc tiep.

## Chay app

```sh
flutter pub get
flutter run
```

Man Kham pha lay danh sach truyen truc tiep tu Google Drive. Link Drive co the
truyen bang `--dart-define` hoac dung danh sach demo trong
`lib/services/google_drive_service.dart` tai `demoFolderUrls`.

```sh
flutter run --dart-define=GOOGLE_DRIVE_API_KEY=your_drive_key
```

Neu co nhieu thu muc Drive, dung `GOOGLE_DRIVE_FOLDER_URLS` va ngan cach bang
dau phay, dau cham phay, dau `|`, hoac xuong dong.

## Cau hinh Firebase

1. Tao Firebase project.
2. Them Android app voi package name `com.vbook.reader`.
3. Bat `Authentication > Sign-in method > Email/Password`.
4. Tao Cloud Firestore database.
5. Sua email admin trong `firestore.rules`.
6. Deploy rules:

```sh
firebase deploy --only firestore:rules
```

Chay app voi Firebase:

```sh
flutter run ^
  --dart-define=FIREBASE_API_KEY=your_firebase_api_key ^
  --dart-define=FIREBASE_APP_ID=your_firebase_app_id ^
  --dart-define=FIREBASE_MESSAGING_SENDER_ID=your_sender_id ^
  --dart-define=FIREBASE_PROJECT_ID=your_project_id ^
  --dart-define=FIREBASE_STORAGE_BUCKET=your_project.appspot.com ^
  --dart-define=VBOOK_ADMIN_EMAILS=vglduc25@gmail.com
```

Co the dien cac gia tri public cua Firebase truc tiep vao
`lib/firebase_config.dart` neu khong muon truyen `--dart-define` moi lan build.
Cac gia tri nay khong phai mat khau; bao mat du lieu nam o Firebase Auth va
Firestore Rules.

## Build APK release

Nhanh nhat nen dung file `release.env` de khong phai go nhieu `--dart-define`.

```powershell
Copy-Item release.env.example release.env
```

Dien gia tri that vao `release.env`, sau do build:

```powershell
.\scripts\build_release_apk.ps1 -RequireFirebase
```

Neu chi muon build ban doc Drive/offline, bo `-RequireFirebase`.

```sh
flutter build apk --release ^
  --dart-define=GOOGLE_DRIVE_API_KEY=your_drive_key ^
  --dart-define=FIREBASE_API_KEY=your_firebase_api_key ^
  --dart-define=FIREBASE_APP_ID=your_firebase_app_id ^
  --dart-define=FIREBASE_MESSAGING_SENDER_ID=your_sender_id ^
  --dart-define=FIREBASE_PROJECT_ID=your_project_id ^
  --dart-define=FIREBASE_STORAGE_BUCKET=your_project.appspot.com ^
  --dart-define=VBOOK_ADMIN_EMAILS=vglduc25@gmail.com
```

Android package hien tai: `com.vbook.reader`.

## Kiem tra

```sh
flutter analyze
flutter test
flutter build apk --debug
```

## Ghi chu bao mat

- Google Drive API key neu nam trong APK thi khong bi xem la bi mat tuyet doi.
  Hay restrict key theo Android package `com.vbook.reader`, SHA-1 release va
  chi cho phep Google Drive API.
- Firebase API key/config la dinh danh public cua app, khong phai mat khau.
  Bao mat Firestore bang `firestore.rules`.
- SMTP password/backend secret khong can dua vao APK nua vi app da chuyen sang
  Firebase Auth gui email xac nhan.

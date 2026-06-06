# vBook - Ung Dung Doc Truyen Flutter

vBook la ung dung doc truyen tren Android duoc xay dung bang Flutter. Ung dung
huong toi trai nghiem gan voi cac app doc truyen quen thuoc nhu Tachiyomi,
VBook va cac web doc light novel/truyen chu: co ke sach ca nhan, kham pha truyen,
doc EPUB/PDF/TXT, luu tien do, doc offline, nghe truyen bang TTS va dong bo tai
khoan bang Firebase.

Du an duoc hoan thien theo huong co the cai APK va test truc tiep, khong can mo
server rieng tren may tinh.

## Thong Tin Do An

| Muc | Noi dung |
| --- | --- |
| Ten ung dung | vBook |
| Nen tang | Flutter / Android |
| Ngon ngu | Dart |
| Backend | Firebase Auth + Cloud Firestore |
| Nguon truyen | Google Drive API, file local, offline assets |
| Dinh dang doc | EPUB, PDF, TXT |
| Package Android | `com.vbook.reader` |
| Trang thai | San sang test APK thuc te |

## Muc Tieu

vBook duoc xay dung de giai quyet bai toan doc va quan ly truyen tren dien
thoai:

- Nguoi dung co the doc truyen online tu Google Drive ma khong can backend rieng.
- Nguoi dung co the tai truyen ve may de doc offline.
- Ung dung ho tro nhieu dinh dang pho bien: EPUB, PDF va TXT.
- Tai khoan, thu vien ca nhan, tien do doc va cong dong duoc luu bang Firebase.
- Giao dien gon, de dung, phu hop voi thoi quen doc truyen tren mobile.

## Chuc Nang Chinh

### 1. Ke sach ca nhan

- Hien thi truyen da them vao thu vien.
- Ho tro xem dang danh sach va dang luoi.
- Tim kiem truyen trong thu vien.
- Sap xep theo gan day, ten truyen va tien do doc.
- Hien thi truyen doc gan nhat de tiep tuc doc nhanh.
- Xoa truyen va don file thuoc du lieu cua app.

### 2. Kham pha truyen

- Lay danh sach truyen tu Google Drive.
- Ho tro nhieu thu muc Drive.
- Ho tro `catalog.json` neu thu muc co metadata.
- Neu khong co catalog, app tu quet file EPUB/PDF/TXT trong thu muc.
- Co cache danh sach truyen de giam tinh trang man hinh trong khi mang yeu.
- Hien thi bia truyen, tac gia, the loai va thong tin co ban.

### 3. Chi tiet truyen

- Hien thi bia, ten truyen, tac gia, mo ta, the loai va dinh dang file.
- Doc online doi voi EPUB/PDF tu Drive.
- Tai truyen ve may de doc offline.
- Them truyen vao thu vien ca nhan.
- Tu lay metadata EPUB neu co: bia, tac gia, mo ta, so chuong.

### 4. Man hinh doc

- Doc EPUB theo chuong.
- Doc PDF bang trinh doc PDF rieng.
- Doc TXT voi noi dung text.
- Luu chuong dang doc va vi tri doc.
- Tuy chinh co chu, font, nen doc va gian dong.
- Ho tro dark mode/light mode.

### 5. Audio doc truyen

- Ho tro Text-to-Speech cho EPUB/TXT.
- Dieu chinh toc do doc, cao do va am luong.
- Co dieu khien phat/dung.
- Ho tro tiep tuc doc theo noi dung dang mo.

### 6. Tai khoan va dong bo

- Dang ky tai khoan bang email va mat khau.
- Dang nhap bang Firebase Authentication.
- Gui email xac minh tai khoan.
- Luu profile nguoi dung tren Cloud Firestore.
- Dong bo thu vien va tien do doc theo user.
- Co che do fallback local neu Firebase chua cau hinh.

### 7. Cong dong

- Hien thi tin nhan cong dong.
- Nguoi dung da dang nhap va xac minh email co the gui tin nhan.
- Tin nhan duoc luu tren Cloud Firestore.
- Admin co the quan ly du lieu theo rules.

### 8. Nhan dien ung dung

- Da co icon app rieng.
- Da co splash screen khi mo ung dung.
- Da co anh bia mac dinh cho truyen khong co anh hoac anh bi loi.

## Kien Truc He Thong

```text
Flutter APK
  |
  |-- Google Drive API
  |     |-- Lay catalog truyen
  |     |-- Quet file EPUB/PDF/TXT
  |     |-- Tai file truyen ve may
  |
  |-- Firebase Authentication
  |     |-- Dang ky
  |     |-- Dang nhap
  |     |-- Xac minh email
  |
  |-- Cloud Firestore
  |     |-- users/{uid}
  |     |-- users/{uid}/library/{storyId}
  |     |-- community_messages/{messageId}
  |
  |-- Local Storage
        |-- Truyen da tai ve
        |-- Cache danh sach truyen
        |-- Cai dat doc
        |-- Tien do doc gan nhat
```

## Cau Truc Thu Muc

```text
lib/
  models/                 Model du lieu cua app
  screens/                Cac man hinh chinh
  services/               Xu ly Drive, Firebase, local storage
  theme/                  Theme, user provider, reading settings
  widgets/                Widget dung chung

assets/
  branding/               Icon/splash trong app
  covers/                 Anh bia mac dinh
  offline_stories/        Truyen offline demo

android/
  app/google-services.json Cau hinh Firebase Android

firestore.rules           Rules bao mat Cloud Firestore
scripts/                  Script build/deploy ho tro
test/                     Smoke test Flutter
```

## Database Firestore

### `users/{uid}`

Luu thong tin tai khoan:

```json
{
  "uid": "firebase_uid",
  "email": "user@example.com",
  "displayName": "User",
  "avatarUrl": "",
  "role": "user",
  "emailVerified": true,
  "createdAt": "...",
  "updatedAt": "..."
}
```

### `users/{uid}/library/{storyId}`

Luu thu vien va tien do doc:

```json
{
  "storyId": "story_id",
  "story": {},
  "savedChapterIndex": 0,
  "totalChapters": 10,
  "scrollOffset": 0,
  "lastReadAt": "...",
  "updatedAt": "..."
}
```

### `community_messages/{messageId}`

Luu tin nhan cong dong:

```json
{
  "userId": "firebase_uid",
  "displayName": "User",
  "avatarUrl": "",
  "text": "Noi dung tin nhan",
  "createdAt": "..."
}
```

## Cau Hinh Firebase

Ung dung dang dung Firebase Android config qua file:

```text
android/app/google-services.json
```

Can thuc hien tren Firebase Console:

1. Tao Firebase project.
2. Them Android app voi package name `com.vbook.reader`.
3. Bat `Authentication > Sign-in method > Email/Password`.
4. Tao Cloud Firestore database.
5. Dan noi dung `firestore.rules` vao tab Rules va bam Publish.

Email admin hien tai trong rules:

```text
vglduc25@gmail.com
```

Firebase API key trong `google-services.json` khong phai mat khau database.
Quyen truy cap du lieu duoc bao ve bang Firebase Auth va Firestore Rules.

Tai lieu tham khao:

- Firebase Android setup: https://firebase.google.com/docs/android/setup
- Firebase Auth email/password: https://firebase.google.com/docs/auth/flutter/password-auth
- Firebase API keys: https://firebase.google.com/docs/projects/api-keys

## Cau Hinh Google Drive

App lay truyen tu Google Drive thong qua Drive API. API key duoc truyen khi
build/chay app:

```powershell
flutter run --dart-define "GOOGLE_DRIVE_API_KEY=your_drive_key"
```

Co the truyen them thu muc Drive:

```powershell
flutter run `
  --dart-define "GOOGLE_DRIVE_API_KEY=your_drive_key" `
  --dart-define "GOOGLE_DRIVE_FOLDER_URLS=https://drive.google.com/drive/folders/..."
```

Neu khong truyen folder rieng, app dung danh sach demo folder trong
`GoogleDriveService.demoFolderUrls`.

## Chay Ung Dung

```powershell
flutter pub get
flutter run
```

Neu muon test doc Drive that:

```powershell
flutter run --dart-define "GOOGLE_DRIVE_API_KEY=your_drive_key"
```

## Build APK Release

APK release moi nhat duoc tao tai:

```text
build/app/outputs/flutter-apk/app-release.apk
```

Build nhanh:

```powershell
flutter build apk --release --dart-define "GOOGLE_DRIVE_API_KEY=your_drive_key"
```

Build bang file cau hinh:

```powershell
Copy-Item release.env.example release.env
.\scripts\build_release_apk.ps1
```

Neu muon yeu cau day du Firebase config bang `release.env`:

```powershell
.\scripts\build_release_apk.ps1 -RequireFirebase
```

## Kiem Thu

Da kiem tra trong qua trinh hoan thien:

```powershell
flutter analyze
flutter test
flutter build apk --release
```

Ket qua gan nhat:

- `flutter analyze`: khong loi.
- `flutter test`: pass.
- APK release build thanh cong.

Checklist test tren dien thoai that:

- Cai APK va mo app lan dau.
- Kiem tra icon app va splash screen.
- Vao Kham pha, tai danh sach truyen tu Drive.
- Mo mot truyen EPUB.
- Mo mot truyen PDF.
- Mo mot truyen TXT.
- Tai truyen ve may va doc offline.
- Doi theme sang/toi.
- Thay doi co chu, font va nen doc.
- Bat TTS nghe truyen.
- Dang ky tai khoan moi.
- Bam link xac minh email.
- Dang nhap lai.
- Gui tin nhan cong dong.
- Doc vai chuong, thoat app, mo lai va kiem tra tien do doc.

## Diem Hoan Thien

Muc do hoan thien hien tai co the danh gia khoang 90-95% cho muc tieu do an:

- Luong doc truyen chinh da co.
- APK co the build va cai truc tiep.
- Firebase da du cau hinh Android.
- Firestore Rules da co san va co email admin.
- Google Drive doc truyen truc tiep.
- UI da du cac man hinh can thiet cho app doc truyen.

Phan con lai chu yeu la test thuc te tren dien thoai, sua loi phat sinh va chup
anh minh chung cho bao cao/trinh bay.

## Huong Phat Trien

- Them bookmark va ghi chu trong man hinh doc.
- Them lich su doc chi tiet hon.
- Them danh gia/binh luan theo tung truyen.
- Toi uu cache anh bia va file lon.
- Them App Check cho Firebase khi dua vao su dung cong khai.
- Ky APK bang release key rieng thay vi debug signing.

## Ket Luan

vBook da dat muc co the demo va bao ve do an: co giao dien doc truyen, nguon
truyen truc tuyen, doc offline, tai khoan, dong bo, cong dong va APK release.
Trong giai doan cuoi, viec quan trong nhat la test tren may that, ghi lai loi
neu co va chuan bi minh chung cac man hinh chinh.

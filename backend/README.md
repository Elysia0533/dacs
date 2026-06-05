# vBook Backend

> Legacy: App release hien da chuyen sang Firebase Auth + Cloud Firestore cho
> tai khoan, xac nhan email, chat, thu vien va tien do doc. Backend Python nay
> chi giu lai de tham khao hoac demo SQLite local, khong bat buoc khi build APK.

Backend REST API cho do an vBook. Backend nay dung Python standard library va
SQLite, nen khong can cai package ngoai.

## Chay server

```sh
cd backend
python server.py
```

Mac dinh server chay tai:

```text
http://127.0.0.1:8080
```

Database SQLite duoc tao tu dong tai:

```text
backend/data/vbook.db
```

Co the doi cau hinh bang bien moi truong:

```sh
$env:VBOOK_PORT="8080"
$env:VBOOK_SECRET="change-this-secret"
$env:VBOOK_DB="data/vbook.db"
python server.py
```

## Xac thuc email that

Luon dang ky tai khoan theo luong:

1. `POST /auth/register` de tao tai khoan va gui ma xac nhan.
2. Nguoi dung nhap ma 6 so trong app, app goi `POST /auth/verify-email`.
3. Backend moi tra `token`, luc nay nguoi dung moi dang nhap that.

Backend tu doc cau hinh trong `backend/.env`. File nay da duoc git ignore.
Dung `backend/.env.example` lam mau, sau do dien email va mat khau SMTP that.

Vi du `backend/.env` voi Gmail:

```env
VBOOK_SECRET=change-this-secret-before-release
VBOOK_PUBLIC_BASE_URL=http://127.0.0.1:8080
VBOOK_REQUIRE_SMTP=1
VBOOK_SMTP_HOST=smtp.gmail.com
VBOOK_SMTP_PORT=587
VBOOK_SMTP_TLS=1
VBOOK_SMTP_USER=your_email@gmail.com
VBOOK_SMTP_PASS=your_16_character_app_password
VBOOK_SMTP_FROM=your_email@gmail.com
```

Voi Gmail, `VBOOK_SMTP_PASS` phai la App Password 16 ky tu, khong phai mat
khau dang nhap Gmail thong thuong. Tai khoan Google can bat xac minh 2 buoc
truoc khi tao App Password.

Neu `VBOOK_REQUIRE_SMTP=1` ma thieu/cau hinh sai SMTP, API dang ky se bao loi
va khong tra `devVerificationCode`.

Neu deploy backend len internet, doi `VBOOK_PUBLIC_BASE_URL` thanh domain/URL
public cua backend de link trong email mo dung noi.

## Kiem tra nhanh

Mo terminal 1:

```sh
cd backend
python server.py
```

Mo terminal 2:

```sh
cd backend
python smoke_test.py
```

## Noi voi Flutter

Chay Flutter desktop/web tren cung may:

```sh
flutter run --dart-define=VBOOK_API_BASE_URL=http://127.0.0.1:8080
```

Chay Android Emulator:

```sh
flutter run --dart-define=VBOOK_API_BASE_URL=http://10.0.2.2:8080
```

Chay dien thoai that: thay `127.0.0.1` bang IP LAN cua may dang chay backend.

## API chinh

### Health

```http
GET /health
```

### Dang ky

Nguoi dung dau tien xac nhan email se duoc gan role `admin` de tien demo.

```http
POST /auth/register
Content-Type: application/json

{
  "email": "admin@example.com",
  "password": "123456",
  "displayName": "Admin"
}
```

Response chua xac nhan:

```json
{
  "user": {"email": "admin@example.com", "emailVerified": false},
  "emailVerificationRequired": true,
  "verificationExpiresInSeconds": 900
}
```

Khi chay dev mode khong SMTP, response co them `devVerificationCode`.

### Xac nhan email

```http
POST /auth/verify-email
Content-Type: application/json

{
  "email": "admin@example.com",
  "code": "123456"
}
```

Response co `token`. Co the gui lai ma:

```http
POST /auth/resend-verification
Content-Type: application/json

{
  "email": "admin@example.com"
}
```

Email that cung co link dang:

```http
GET /auth/verify-email?token=<verification-token>
```

### Dang nhap

```http
POST /auth/login
Content-Type: application/json

{
  "email": "admin@example.com",
  "password": "123456"
}
```

Response co `token`. Cac API ca nhan dung header:

```http
Authorization: Bearer <token>
```

### Danh sach truyen legacy/tuy chon

App Flutter hien lay catalog truyen truc tiep tu Google Drive. Cac endpoint nay
duoc giu de demo/tuong thich cu, khong phai nguon chinh cho man Kham pha.

```http
GET /stories
GET /stories?search=thanh&genre=hoc
GET /stories/story_thanh_xuan_vol_1
```

### Quan tri truyen

Can role `admin`.

```http
POST /stories
PUT /stories/{storyId}
DELETE /stories/{storyId}
```

Body mau:

```json
{
  "title": "Truyen moi",
  "author": "Tac gia",
  "description": "Mo ta",
  "genres": ["Tien hiep", "Phieu luu"],
  "totalChapters": 42,
  "iconUrl": "https://example.com/cover.jpg",
  "driveFileId": "google-drive-file-id",
  "fileType": "epub"
}
```

### Thu vien ca nhan

Can dang nhap.

```http
GET /me/library
POST /me/library
PUT /me/library/{storyId}/progress
DELETE /me/library/{storyId}
```

Them vao thu vien. Neu `storyId` chua ton tai trong backend, backend se tao
snapshot metadata rieng cho thu vien ca nhan, khong publish thanh catalog chung:

```json
{
  "storyId": "google-drive-file-id",
  "title": "Ten truyen",
  "author": "Tac gia",
  "genres": ["Tien hiep", "Phieu luu"],
  "totalChapters": 12,
  "iconUrl": "https://example.com/cover.jpg",
  "driveFileId": "google-drive-file-id"
}
```

Luu tien do doc:

```json
{
  "savedChapterIndex": 3,
  "totalChapters": 12,
  "scrollOffset": 180.5
}
```

### Cong dong

```http
GET /community/messages
POST /community/messages
```

Gui tin nhan:

```json
{
  "text": "Xin chao vBook!"
}
```

## Bang du lieu

- `users`: tai khoan nguoi dung.
- `stories`: metadata snapshot/legacy cho cac truyen da nam trong thu vien; khong con la catalog chinh cua app.
- `user_library`: thu vien va tien do doc theo tung user.
- `community_messages`: tin nhan cong dong.

## Ghi chu trien khai

- Backend hien tai phu hop chay local/demo do an.
- Khi deploy that can doi `VBOOK_SECRET`.
- File va catalog truyen nen luu tren Google Drive. Backend chi luu tai khoan,
  thu vien ca nhan, tien do doc, metadata snapshot can thiet va chat cong dong.
- Neu can dung MySQL/PostgreSQL, co the giu nguyen API va thay lop SQLite ben trong.

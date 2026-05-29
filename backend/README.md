# vBook Backend

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

Nguoi dung dau tien dang ky se duoc gan role `admin` de tien demo.

```http
POST /auth/register
Content-Type: application/json

{
  "email": "admin@example.com",
  "password": "123456",
  "displayName": "Admin"
}
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

### Danh sach truyen

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

Them vao thu vien:

```json
{
  "storyId": "story_thanh_xuan_vol_1"
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
- `stories`: danh sach truyen online.
- `user_library`: thu vien va tien do doc theo tung user.
- `community_messages`: tin nhan cong dong.

## Ghi chu trien khai

- Backend hien tai phu hop chay local/demo do an.
- Khi deploy that can doi `VBOOK_SECRET`.
- File truyen nen tiep tuc luu tren Google Drive hoac storage rieng; backend chi luu metadata va `driveFileId`.
- Neu can dung MySQL/PostgreSQL, co the giu nguyen API va thay lop SQLite ben trong.

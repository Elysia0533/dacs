# vBook - Ứng Dụng Đọc Truyện Flutter

vBook là ứng dụng đọc truyện trên Android được xây dựng bằng Flutter. Ứng dụng
hướng đến trải nghiệm quen thuộc với các app đọc truyện như Tachiyomi, VBook và
các website đọc light novel/truyện chữ: có kệ sách cá nhân, khám phá truyện,
đọc EPUB/PDF/TXT, tải truyện từ Google Drive, lưu tiến độ đọc, nghe truyện bằng
Text-to-Speech và đồng bộ tài khoản bằng Firebase.

Dự án được hoàn thiện theo hướng có thể build APK và cài trực tiếp trên điện
thoại, không cần chạy web server hoặc backend riêng trên máy cá nhân.

## Thông Tin Đồ Án

| Mục | Nội dung |
| --- | --- |
| Tên ứng dụng | vBook |
| Nền tảng | Flutter / Android |
| Ngôn ngữ | Dart |
| Backend | Firebase Authentication + Cloud Firestore |
| Nguồn truyện | Google Drive, file local, offline assets |
| Định dạng đọc | EPUB, PDF, TXT |
| Package Android | `com.vbook.reader` |
| Trạng thái | Sẵn sàng test APK thực tế |

## Mục Tiêu

vBook được xây dựng để hỗ trợ người dùng đọc và quản lý truyện trên điện thoại:

- Đọc truyện trực tiếp từ Google Drive.
- Tải truyện về máy để đọc offline.
- Quản lý thư viện cá nhân và tiến độ đọc.
- Hỗ trợ tài khoản người dùng bằng Firebase.
- Có khu vực cộng đồng để người dùng trao đổi.
- Giao diện tối ưu cho thói quen đọc truyện trên mobile.

## Chức Năng Chính

### Kệ Sách Cá Nhân

- Hiển thị truyện đã thêm vào thư viện.
- Hỗ trợ dạng lưới và dạng danh sách.
- Tìm kiếm truyện theo tên, tác giả, thể loại.
- Sắp xếp theo gần đây, tên truyện và tiến độ đọc.
- Hiển thị truyện đang đọc gần nhất để tiếp tục nhanh.
- Xóa truyện và dọn dữ liệu thuộc phạm vi app.

### Khám Phá Truyện

- Lấy danh sách truyện từ nhiều thư mục Google Drive.
- Hỗ trợ `catalog.json` nếu thư mục có metadata.
- Nếu không có catalog, app tự quét file EPUB/PDF/TXT trong thư mục.
- Cache danh sách truyện để giảm thời gian tải lại.
- Tự xử lý ảnh bìa từ Drive, ảnh rời hoặc ảnh bìa nằm trong EPUB.

### Chi Tiết Truyện

- Hiển thị ảnh bìa, tên truyện, tác giả, mô tả, thể loại và định dạng file.
- Cho phép đọc trực tiếp truyện từ Drive.
- Cho phép tải truyện về máy để đọc offline.
- Tự đọc metadata EPUB như bìa, tác giả, mô tả và số chương.

### Màn Hình Đọc

- Đọc EPUB theo chương.
- Đọc PDF bằng trình đọc PDF riêng.
- Đọc TXT bằng trình đọc văn bản.
- Lưu chương đang đọc và vị trí cuộn.
- Tùy chỉnh cỡ chữ, font, nền đọc và giãn dòng.
- Hỗ trợ giao diện sáng/tối.

### Audio Đọc Truyện

- Hỗ trợ Text-to-Speech cho EPUB/TXT.
- Có điều khiển phát, dừng và tiếp tục.
- Điều chỉnh tốc độ đọc, cao độ và âm lượng.
- Phù hợp khi người dùng muốn nghe truyện thay vì đọc thủ công.

### Tài Khoản Và Đồng Bộ

- Đăng ký bằng email và mật khẩu.
- Đăng nhập bằng Firebase Authentication.
- Gửi email xác minh tài khoản.
- Lưu hồ sơ người dùng trên Cloud Firestore.
- Đồng bộ thư viện cá nhân và tiến độ đọc theo từng user.
- Có fallback local để app vẫn dùng được khi Firebase chưa sẵn sàng.

### Cộng Đồng

- Hiển thị tin nhắn cộng đồng.
- Người dùng đã đăng nhập và xác minh email có thể gửi tin nhắn.
- Tin nhắn được lưu trên Cloud Firestore.
- Admin có thể quản lý dữ liệu theo Firestore Rules.

## Kiến Trúc Tổng Quan

```text
Flutter APK
  |
  |-- Google Drive API
  |     |-- Quét thư mục truyện
  |     |-- Đọc catalog.json nếu có
  |     |-- Tải EPUB/PDF/TXT
  |     |-- Lấy ảnh bìa từ ảnh rời hoặc EPUB
  |
  |-- Firebase Authentication
  |     |-- Đăng ký
  |     |-- Đăng nhập
  |     |-- Xác minh email
  |
  |-- Cloud Firestore
  |     |-- users/{uid}
  |     |-- users/{uid}/library/{storyId}
  |     |-- community_messages/{messageId}
  |
  |-- Local Storage
        |-- Truyện đã tải về
        |-- Cache danh sách Drive
        |-- Ảnh bìa đã trích xuất
        |-- Cài đặt đọc
        |-- Tiến độ đọc
```

## Cấu Trúc Thư Mục

```text
lib/
  models/                 Model dữ liệu
  screens/                Các màn hình chính
  services/               Drive, Firebase, local storage
  theme/                  Theme và provider
  widgets/                Widget dùng chung

assets/
  branding/               Icon và splash
  covers/                 Ảnh bìa mặc định
  offline_stories/        Truyện offline mẫu

scripts/                  Script build/deploy hỗ trợ
test/                     Smoke test Flutter
firestore.rules           Rules bảo mật Cloud Firestore
```

## Database Firestore

### `users/{uid}`

Lưu thông tin tài khoản:

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

Lưu truyện trong thư viện và tiến độ đọc:

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

Lưu tin nhắn cộng đồng:

```json
{
  "userId": "firebase_uid",
  "displayName": "User",
  "avatarUrl": "",
  "text": "Nội dung tin nhắn",
  "createdAt": "..."
}
```

## Cấu Hình Firebase

Ứng dụng dùng Firebase Android config tại:

```text
android/app/google-services.json
```

Các bước cần có trên Firebase Console:

1. Tạo Firebase project.
2. Thêm Android app với package name `com.vbook.reader`.
3. Bật `Authentication > Sign-in method > Email/Password`.
4. Tạo Cloud Firestore database.
5. Dán nội dung `firestore.rules` vào Firestore Rules và Publish.

Email admin trong rules hiện tại:

```text
vglduc25@gmail.com
```

## Cấu Hình Google Drive

App đọc truyện từ Google Drive qua Drive API. API key được truyền khi chạy hoặc
build app:

```powershell
flutter run --dart-define "GOOGLE_DRIVE_API_KEY=your_drive_key"
```

Có thể truyền thêm thư mục Drive:

```powershell
flutter run `
  --dart-define "GOOGLE_DRIVE_API_KEY=your_drive_key" `
  --dart-define "GOOGLE_DRIVE_FOLDER_URLS=https://drive.google.com/drive/folders/..."
```

Nếu không truyền folder riêng, app dùng danh sách thư mục demo trong
`GoogleDriveService.demoFolderUrls`.

## Chạy Ứng Dụng

```powershell
flutter pub get
flutter run --dart-define "GOOGLE_DRIVE_API_KEY=your_drive_key"
```

## Build APK Release

APK release được tạo tại:

```text
build/app/outputs/flutter-apk/app-release.apk
```

Build trực tiếp:

```powershell
flutter build apk --release --dart-define "GOOGLE_DRIVE_API_KEY=your_drive_key"
```

Build bằng script:

```powershell
.\scripts\build_release_apk.ps1
```

Nếu muốn bắt buộc cấu hình Firebase khi build:

```powershell
.\scripts\build_release_apk.ps1 -RequireFirebase
```

## Kiểm Thử

Các lệnh kiểm tra chính:

```powershell
flutter analyze
flutter test
flutter build apk --release
```

Checklist test trên điện thoại:

- Cài APK và mở app.
- Kiểm tra icon app và splash screen.
- Vào Khám phá, tải danh sách truyện từ Drive.
- Mở truyện EPUB/PDF/TXT.
- Kiểm tra ảnh bìa truyện trong danh sách và chi tiết.
- Tải truyện về máy và đọc offline.
- Đổi theme sáng/tối.
- Tùy chỉnh font, cỡ chữ và nền đọc.
- Bật Text-to-Speech.
- Đăng ký tài khoản mới.
- Xác minh email.
- Đăng nhập lại.
- Gửi tin nhắn cộng đồng.
- Đọc vài chương, thoát app, mở lại và kiểm tra tiến độ đọc.

## Trạng Thái Hoàn Thiện

Dự án hiện đã có các phần quan trọng cho một app đọc truyện hoàn chỉnh:

- Giao diện chính cho kệ sách, khám phá, chi tiết truyện, đọc truyện, cộng đồng
  và cá nhân.
- Đọc được EPUB/PDF/TXT.
- Tải truyện từ Google Drive và đọc offline.
- Trích xuất ảnh bìa từ EPUB, kể cả EPUB tải từ Drive.
- Đăng ký, đăng nhập và xác minh email bằng Firebase.
- Đồng bộ thư viện, tiến độ đọc và tin nhắn cộng đồng bằng Firestore.
- Có rules bảo mật Firestore.
- Có APK release để test trên thiết bị thật.

Mức độ hoàn thiện hiện tại phù hợp để demo và bảo vệ đồ án. Phần còn lại chủ yếu
là test thực tế trên điện thoại, ghi nhận lỗi nhỏ nếu có và chuẩn bị ảnh minh
họa cho báo cáo/trình bày.

## Hướng Phát Triển

- Thêm bookmark và ghi chú khi đọc.
- Thêm lịch sử đọc chi tiết hơn.
- Thêm bình luận/đánh giá theo từng truyện.
- Tối ưu cache ảnh bìa cho EPUB dung lượng lớn.
- Thêm App Check cho Firebase nếu đưa vào sử dụng công khai.
- Ký APK bằng release key riêng.

## Kết Luận

vBook đáp ứng mục tiêu đồ án: có nguồn truyện online, đọc offline, tài khoản,
đồng bộ dữ liệu, cộng đồng, giao diện đọc và APK cài trực tiếp. Ứng dụng có thể
dùng để test thực tế và tiếp tục hoàn thiện dựa trên phản hồi khi chạy trên máy
Android thật.

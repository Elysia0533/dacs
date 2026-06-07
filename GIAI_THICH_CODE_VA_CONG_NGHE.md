# Giải Thích Code Và Công Nghệ Trong App vBook

Tài liệu này dùng để ôn lại code khi bảo vệ đồ án. Nội dung tập trung vào việc
giải thích file nào làm gì, công nghệ nào được dùng ở đâu, và vì sao dùng Google
Drive API trong ứng dụng.

## 1. Tổng Quan Luồng Hoạt Động

App được viết bằng Flutter, chia thành các nhóm:

```text
lib/
  models/      Định nghĩa dữ liệu
  screens/     Màn hình giao diện
  services/    Xử lý dữ liệu, Drive, Firebase, local cache
  theme/       Provider quản lý trạng thái
  widgets/     Widget tái sử dụng
```

Luồng cơ bản:

```text
Màn hình Flutter
  -> gọi Provider hoặc ApiService
  -> ApiService điều phối
  -> GoogleDriveService / FirebaseBackendService / SharedPreferences
  -> trả dữ liệu về màn hình
```

`ApiService` là lớp trung gian quan trọng nhất. UI không gọi trực tiếp quá nhiều
vào Firebase hoặc Drive, mà đi qua `ApiService` để dễ kiểm soát logic.

## 2. Nhóm File Gốc

### `lib/main.dart`

Mục đích:

- Điểm khởi động của app.
- Khởi tạo Firebase nếu có cấu hình.
- Đăng ký các Provider như theme, user, reading settings.
- Chạy widget gốc của ứng dụng.

Công nghệ dùng:

- Flutter.
- Provider.
- Firebase Core.

Khi được hỏi:

> `main.dart` là nơi app bắt đầu chạy. Em dùng file này để khởi tạo các service
> cần thiết và bọc app bằng Provider để các màn hình có thể dùng chung trạng
> thái.

### `lib/firebase_config.dart`

Mục đích:

- Chứa cấu hình Firebase lấy từ `--dart-define` hoặc native Android config.
- Kiểm tra app đã có cấu hình Firebase hay chưa.
- Chứa danh sách email admin mặc định và email admin truyền thêm khi build.

Công nghệ dùng:

- Firebase Options.
- Dart `String.fromEnvironment`.

Khi được hỏi:

> File này giúp app chạy linh hoạt. Khi build release có thể truyền Firebase key
> bằng dart-define, còn Android có thể dùng `google-services.json`.

Lưu ý về admin:

> Firestore Rules và Flutter UI là hai lớp khác nhau. Rules cấp quyền phía
> database, còn UI cần biết email nào là admin để hiện nhãn Quản trị viên và các
> tác vụ admin. Vì vậy app có danh sách admin trong `firebase_config.dart`.

## 3. Nhóm Models

### `lib/models/story.dart`

Mục đích:

- Model chính của truyện.
- Lưu thông tin như id, title, author, genres, iconUrl, localPath, driveFileId,
  fileType, totalChapters, savedChapterIndex.
- Có `toJson`, `fromJson`, `copyWith` để lưu và cập nhật dữ liệu.

Công nghệ dùng:

- Dart class.
- JSON serialization thủ công.

Khi được hỏi:

> `Story` đại diện cho một truyện trong app. Dù truyện đến từ Drive, local hay
> offline assets thì app đều quy về model này để UI xử lý thống nhất.

### `lib/models/app_user.dart`

Mục đích:

- Model người dùng.
- Lưu id, email, displayName, avatarUrl, role, emailVerified.
- Có `copyWith` để cập nhật profile.

Công nghệ dùng:

- Dart model.
- JSON mapping.

Khi được hỏi:

> `AppUser` là lớp dữ liệu trung gian giữa Firebase user và UI. UI không cần biết
> chi tiết Firebase Auth mà chỉ cần AppUser.

### `lib/models/community_message.dart`

Mục đích:

- Model tin nhắn cộng đồng.
- Lưu userId, displayName, avatarUrl, text, createdAt.

Công nghệ dùng:

- Dart model.
- Firestore document mapping.

## 4. Nhóm Services

### `lib/services/api_service.dart`

Mục đích:

- Lớp trung gian điều phối dữ liệu của app.
- Quản lý truyện local bằng SharedPreferences.
- Gọi Google Drive để lấy truyện.
- Gọi FirebaseBackendService để đăng nhập, đồng bộ, cộng đồng.
- Trích xuất metadata EPUB: title, author, description, số chương, ảnh bìa.
- Cache danh sách truyện Drive và ảnh bìa.
- Tự phục hồi ảnh bìa EPUB local nếu đường dẫn cũ bị mất.

Công nghệ dùng:

- SharedPreferences.
- path_provider.
- epubx/epub_view.
- archive/xml/image để đọc cấu trúc EPUB và ảnh bìa.
- FirebaseBackendService.
- GoogleDriveService.

Vai trò quan trọng:

> Đây là service trung tâm. UI gọi ApiService thay vì tự xử lý nhiều nguồn dữ
> liệu. Nhờ vậy app có thể fallback local nếu Firebase chưa sẵn sàng.

Ví dụ luồng lấy ảnh bìa EPUB:

```text
File EPUB
  -> đọc bằng epub_view nếu thư viện trả CoverImage
  -> nếu không được thì mở EPUB như file ZIP
  -> đọc META-INF/container.xml
  -> tìm content.opf
  -> tìm item cover-image hoặc file tên cover.jpg
  -> decode ảnh và lưu thành file jpg local
```

Khi được hỏi vì sao phải làm vậy:

> EPUB thực chất là một file ZIP có cấu trúc bên trong. Không phải EPUB nào thư
> viện cũng đọc được cover trực tiếp, nên em có thêm nhánh đọc thủ công để app
> ổn định hơn.

### `lib/services/google_drive_service.dart`

Mục đích:

- Làm việc với Google Drive API.
- Lấy danh sách file/folder trong thư mục Drive.
- Quét folder con để tìm EPUB/PDF/TXT.
- Đọc `catalog.json` nếu có.
- Tìm ảnh bìa rời nếu thư mục có ảnh.
- Tạo link tải file.
- Tải file Drive bằng stream ra file local.
- Xử lý fallback khi endpoint Drive API bị 403 hoặc Drive trả trang xác nhận.

Công nghệ dùng:

- Google Drive API v3.
- HTTP package.
- Dart stream.
- File IO.

Các hàm quan trọng:

- `fetchStoriesFromConfiguredFolder`: lấy danh sách truyện từ các folder cấu hình.
- `fetchStoriesFromFolder`: quét một folder Drive.
- `_scanDriveItem`: quét đệ quy folder con.
- `_storyFromDriveFile`: chuyển file Drive thành model `Story`.
- `downloadFileBytes`: tải file nhỏ hoặc phục vụ tác vụ cần bytes.
- `downloadFileToFile`: tải stream thẳng ra file, dùng cho tải truyện lớn.
- `coverImageCandidates`: tạo danh sách link ảnh có thể thử.

Khi được hỏi tại sao tải stream:

> Ban đầu nếu tải toàn bộ file vào RAM thì EPUB lớn có thể làm app lag hoặc lỗi
> bộ nhớ. Sau đó em đổi sang stream file về bộ nhớ máy trước, nên ổn định hơn khi
> tải truyện dung lượng lớn.

### `lib/services/firebase_backend_service.dart`

Mục đích:

- Giao tiếp trực tiếp với Firebase.
- Đăng ký, đăng nhập, đăng xuất.
- Gửi email xác minh.
- Gửi email khôi phục mật khẩu.
- Cập nhật thông tin cá nhân.
- Lưu profile người dùng vào Firestore.
- Đồng bộ thư viện và tiến độ đọc.
- Gửi/lấy tin nhắn cộng đồng.
- Nhận diện tài khoản admin theo email cấu hình.

Công nghệ dùng:

- Firebase Core.
- Firebase Authentication.
- Cloud Firestore.

Khi được hỏi:

> Đây mới là backend chính cho phần tài khoản và dữ liệu người dùng. Firebase
> quản lý xác thực, còn Firestore lưu dữ liệu động như thư viện, tiến độ đọc và
> tin nhắn.

## 5. Nhóm Screens

### `lib/screens/splash_screen.dart`

Mục đích:

- Màn hình mở đầu.
- Hiển thị branding/splash trước khi vào app chính.

### `lib/screens/home_screen.dart`

Mục đích:

- Màn Kệ sách cá nhân.
- Hiển thị truyện đã thêm/tải.
- Tìm kiếm, sắp xếp, đổi layout lưới/danh sách.
- Import truyện từ máy.
- Mở chi tiết truyện.

Công nghệ dùng:

- Flutter UI.
- File picker.
- SharedPreferences qua ApiService.

### `lib/screens/explore_screen.dart`

Mục đích:

- Màn Khám phá.
- Lấy danh sách truyện từ Drive.
- Hiển thị truyện theo grid.
- Lọc theo thể loại, tìm kiếm.
- Nếu user là admin thì hiển thị nút quét thư mục Drive.

Công nghệ dùng:

- Google Drive API qua ApiService.
- Widget `StoryCoverImage`.

### `lib/screens/story_detail_screen.dart`

Mục đích:

- Hiển thị chi tiết truyện.
- Đọc online nếu truyện từ Drive.
- Tải truyện về máy.
- Thêm truyện vào thư viện.
- Khi tải về, app stream file Drive ra file local rồi đọc metadata.

Công nghệ dùng:

- GoogleDriveService.
- ApiService.
- path_provider.
- File IO.

Khi được hỏi:

> Đây là màn nối giữa online và offline. Người dùng có thể đọc từ Drive hoặc lưu
> truyện về máy. Khi lưu, app tải bằng stream để tránh lag với file lớn.

### `lib/screens/chapter_reader_screen.dart`

Mục đích:

- Màn đọc EPUB local theo chương.
- Flatten danh sách chương.
- Hiển thị HTML chương bằng flutter_html.
- Lưu tiến độ đọc.
- Tích hợp Text-to-Speech.
- Kiểm soát chuyển chương ở cuối nội dung: app chỉ chuyển sang chương tiếp khi
  người dùng đã chạm cuối chương và vuốt thêm một lần nữa.

Công nghệ dùng:

- epubx.
- flutter_html.
- flutter_tts.
- Provider reading settings.

Khi được hỏi vì sao không tự nhảy chương ngay:

> Nếu tự chuyển ngay khi scroll tới cuối thì người đọc dễ bị mất nhịp, đặc biệt
> khi chỉ muốn dừng lại đọc đoạn cuối. Vì vậy em dùng `ScrollNotification` và
> `OverscrollNotification`: lần đầu tới cuối chỉ đánh dấu đã hết chương, lần
> vuốt thêm qua đáy mới gọi hàm chuyển chương.

### `lib/screens/epub_reader_screen.dart`

Mục đích:

- Màn đọc EPUB dùng `epub_view`.
- Hỗ trợ đọc EPUB từ Drive bằng cách cache file về máy trước.
- Có progress khi chuẩn bị truyện Drive.
- Có mục lục.

Công nghệ dùng:

- epub_view.
- GoogleDriveService.
- path_provider.
- File cache.

### `lib/screens/pdf_reader_screen.dart`

Mục đích:

- Màn đọc PDF.
- Nếu PDF ở Drive thì tải/cache file trước rồi mở bằng file local.
- Tránh mở trực tiếp link Drive bị lỗi trang xác nhận hoặc 403.

Công nghệ dùng:

- syncfusion_flutter_pdfviewer.
- GoogleDriveService.
- path_provider.

### `lib/screens/reading_screen.dart`

Mục đích:

- Màn đọc TXT hoặc nội dung text.
- Hiển thị nội dung với cài đặt đọc.

### `lib/screens/community_screen.dart`

Mục đích:

- Hiển thị tin nhắn cộng đồng.
- Gửi tin nhắn nếu đã đăng nhập/xác minh email.

Công nghệ dùng:

- Firebase Firestore qua ApiService.
- UserProvider.

### `lib/screens/profile_screen.dart`

Mục đích:

- Màn Cá nhân.
- Đăng ký, đăng nhập, xác minh email.
- Khôi phục mật khẩu.
- Chỉnh sửa tên hiển thị và màu avatar.
- Đăng xuất.
- Cài đặt theme và audio.
- Hiển thị nhãn Quản trị viên và mục tác vụ admin nếu user có role admin.

Công nghệ dùng:

- Firebase Auth qua UserProvider/ApiService.
- Provider.
- SharedPreferences cho màu avatar local.

Các tác vụ admin đang có trong màn Cá nhân:

- Mở màn Khám phá để quét/thử link Drive.
- Mở màn Cộng đồng để kiểm tra gửi/đọc tin nhắn.
- Làm mới quyền admin từ phiên đăng nhập hiện tại.

## 6. Nhóm Theme Và Provider

### `lib/theme/user_provider.dart`

Mục đích:

- Quản lý trạng thái người dùng.
- Lưu tên, email, role, token, màu avatar.
- Gọi ApiService để đăng nhập, đăng ký, reset password, update profile.
- Cung cấp `isAdmin` để UI quyết định có hiện tác vụ admin hay không.
- Thông báo UI cập nhật bằng `notifyListeners`.

Công nghệ dùng:

- Provider.
- SharedPreferences.

### `lib/theme/theme_provider.dart`

Mục đích:

- Quản lý dark mode/light mode.
- Lưu lựa chọn theme.

### `lib/theme/reading_settings_provider.dart`

Mục đích:

- Quản lý cài đặt đọc: font, cỡ chữ, nền đọc, giãn dòng.
- Quản lý cài đặt TTS: tốc độ, cao độ, âm lượng, tự chuyển chương.

## 7. Nhóm Widgets

### `lib/widgets/story_cover_image.dart`

Mục đích:

- Widget hiển thị ảnh bìa truyện.
- Hỗ trợ ảnh network, ảnh local, ảnh fallback.
- Nếu truyện Drive là EPUB và không có ảnh mạng, app tải EPUB để trích bìa nếu
  file không quá lớn.

Công nghệ dùng:

- Image.network.
- Image.file.
- GoogleDriveService.
- ApiService cover cache.

### `lib/widgets/app_state_widgets.dart`

Mục đích:

- Các widget trạng thái dùng chung như loading/empty/error.
- Giúp UI nhất quán hơn.

## 8. Firestore Rules

### `firestore.rules`

Mục đích:

- Bảo vệ dữ liệu Firestore.
- User chỉ đọc/ghi thư viện của chính mình.
- Tin nhắn cộng đồng ai cũng đọc được nhưng chỉ user đã xác minh email mới gửi.
- Admin có quyền quản lý nâng cao.

Công nghệ dùng:

- Firebase Security Rules.

Khi được hỏi:

> Firestore Rules là lớp bảo mật phía server. Dù app bị sửa ở client, Firestore
> vẫn kiểm tra request.auth.uid và emailVerified trước khi cho ghi dữ liệu.

## 9. Google Drive API Là Gì?

Google Drive API là API do Google cung cấp để ứng dụng có thể làm việc với file
trong Google Drive bằng HTTP request.

Trong app này Drive API dùng để:

- Liệt kê file trong thư mục.
- Lấy thông tin file: id, name, mimeType, thumbnailLink.
- Tải file truyện.
- Tải ảnh bìa rời nếu có.

App gọi endpoint dạng:

```text
https://www.googleapis.com/drive/v3/files
```

và truyền query để lấy file trong folder:

```text
'folderId' in parents and trashed = false
```

## 10. Drive API Có Phải Backend Không?

Câu trả lời ngắn:

> Không. Google Drive API không phải backend đầy đủ của app. Nó là dịch vụ lưu
> trữ file và nguồn dữ liệu truyện.

Giải thích kỹ:

- Backend thật thường xử lý logic nghiệp vụ, tài khoản, phân quyền, database,
  thống kê, bình luận, tìm kiếm, quản trị nội dung.
- Google Drive chỉ giúp lưu file và cho app tải file.
- Trong app này, Drive thay thế phần **kho file truyện**, không thay thế toàn bộ
  backend.

Backend thật của app gồm:

- Firebase Authentication: xác thực người dùng.
- Cloud Firestore: lưu dữ liệu người dùng, thư viện, tiến độ, cộng đồng.

Google Drive chỉ là:

- File storage cho EPUB/PDF/TXT.
- Nguồn import truyện.
- Cách demo dữ liệu nhanh cho đồ án.

## 11. Drive API Có Tốt Hơn Backend Thật Không?

Không hoàn toàn. Drive API có ưu điểm và nhược điểm riêng.

Ưu điểm:

- Dễ chuẩn bị dữ liệu.
- Không cần viết server upload file.
- Dễ chia sẻ folder truyện.
- Phù hợp đồ án, demo và app nhỏ.
- Có thể thay đổi file truyện bằng cách cập nhật Drive.

Nhược điểm:

- Không tối ưu cho truy vấn phức tạp.
- Không có database metadata chuyên nghiệp.
- Không phù hợp nếu có nhiều người dùng tải cùng lúc.
- File lớn có thể tải chậm.
- Phân quyền không linh hoạt bằng backend riêng.
- Không có quản trị truyện, lịch sử duyệt, thống kê như backend thật.

Kết luận nên trả lời:

> Với đồ án, Drive API là lựa chọn hợp lý để làm kho truyện nhanh và dễ test.
> Nhưng nếu phát triển thành sản phẩm thật, nên xây backend riêng hoặc dùng cloud
> storage/CDN kết hợp database metadata.

## 12. Vì Sao Vẫn Cần Firebase Nếu Đã Có Drive?

Drive chỉ chứa file truyện, không quản lý tốt các dữ liệu như:

- Ai đang đăng nhập.
- User đã đọc đến chương nào.
- User có những truyện nào trong thư viện.
- Tin nhắn cộng đồng.
- Quyền admin.

Firebase giải quyết các phần đó:

- Firebase Auth quản lý tài khoản.
- Firestore lưu dữ liệu động.
- Firestore Rules bảo vệ dữ liệu.

Vì vậy Drive và Firebase không trùng vai trò. Chúng bổ sung cho nhau.

## 13. Luồng Tải Truyện Từ Drive

```text
Người dùng bấm Lưu về máy
  -> StoryDetailScreen
  -> GoogleDriveService.downloadFileToFile
  -> thử Drive API media URL
  -> nếu lỗi thì thử link download công khai
  -> nếu Drive trả trang xác nhận thì lấy confirm URL
  -> stream dữ liệu ra file .download
  -> tải xong rename thành file thật
  -> ApiService đọc metadata EPUB
  -> lưu Story vào thư viện local và đồng bộ Firestore
```

Điểm cần nhớ:

> App dùng stream download để tránh giữ toàn bộ file trong RAM. Đây là tối ưu
> quan trọng cho EPUB/PDF dung lượng lớn.

## 14. Luồng Đọc Truyện Drive Chưa Tải

```text
Người dùng bấm Đọc
  -> nếu truyện là EPUB/PDF từ Drive
  -> app tải/cache file vào drive_read_cache
  -> hiển thị progress
  -> mở file local bằng reader
```

Vì sao không đọc thẳng link?

- Link Drive có thể trả 403.
- Link Drive có thể trả trang xác nhận download.
- EPUB/PDF lớn mở trực tiếp qua network dễ lag.
- Cache local giúp mở lại nhanh hơn.

## 15. Luồng Đăng Nhập Và Cộng Đồng

```text
Người dùng đăng nhập
  -> ProfileScreen
  -> UserProvider
  -> ApiService
  -> FirebaseBackendService
  -> Firebase Auth
  -> lưu AppUser local
```

Gửi tin nhắn:

```text
CommunityScreen
  -> ApiService.sendCommunityMessage
  -> FirebaseBackendService
  -> kiểm tra user đã xác minh email
  -> ghi vào community_messages
```

## 16. Các Câu Hỏi Dễ Bị Hỏi

### Vì sao dùng Flutter?

Flutter giúp xây UI nhanh, chạy tốt trên Android, có hệ sinh thái package mạnh
cho Firebase, PDF, EPUB, TTS và local storage.

### Vì sao dùng Provider?

Provider đơn giản, phù hợp app đồ án, dễ quản lý theme/user/settings mà không
cần kiến trúc quá phức tạp.

### Vì sao dùng Firebase?

Firebase giúp làm nhanh phần backend như đăng ký, đăng nhập, xác minh email,
khôi phục mật khẩu và lưu dữ liệu Firestore mà không cần tự viết server.

### API key Drive có phải mật khẩu không?

Không. API key là khóa định danh project gọi API, không phải mật khẩu database.
Tuy nhiên vẫn nên giới hạn API key theo package/app khi phát hành thật.

### `google-services.json` có phải database không?

Không. File đó là cấu hình để app Android kết nối đúng Firebase project.

### Vì sao Firestore cần rules?

Vì client app có thể bị sửa. Rules đảm bảo server chỉ cho phép user đọc/ghi dữ
liệu hợp lệ.

### Vì sao đã thêm email admin vào Firestore Rules nhưng app chưa hiện admin?

Vì đó là hai tầng khác nhau. Firestore Rules chỉ quyết định request lên database
có được phép hay không. Còn việc app có hiện nhãn Admin hay không phụ thuộc vào
logic Flutter, cụ thể là danh sách email admin trong `firebase_config.dart` và
role được nạp vào `UserProvider`.

### Vì sao app có SharedPreferences?

Để lưu dữ liệu nhỏ trên máy như session, cài đặt đọc, cache danh sách truyện,
tiến độ local.

### Vì sao ảnh bìa không lấy trực tiếp từ EPUB bằng thư viện?

Không phải EPUB nào thư viện cũng đọc cover ổn định. Vì EPUB là ZIP nên app có
nhánh tự đọc OPF/XML để tìm ảnh bìa chắc hơn.

### App đã có backend chưa?

Có backend cho phần người dùng bằng Firebase. Còn phần file truyện dùng Google
Drive như một kho file thay cho server upload truyện riêng.

### Nếu làm sản phẩm thật sẽ thay gì?

Nên thay Drive bằng backend/storage chuyên dụng, ví dụ Cloud Storage hoặc server
riêng + database metadata + CDN.

## 17. Điểm Mạnh Khi Trình Bày

Nên nhấn mạnh:

- App đọc được nhiều định dạng.
- Có nguồn truyện online từ Drive.
- Có tải offline.
- Có Firebase Auth và Firestore.
- Có cộng đồng.
- Có khôi phục mật khẩu, chỉnh sửa thông tin cá nhân và tác vụ admin.
- Có TTS.
- Có xử lý ảnh bìa EPUB tương đối kỹ.
- Có tối ưu tải Drive bằng stream và cache.
- Có kiểm soát chuyển chương: đọc tới cuối chương không tự nhảy, phải vuốt thêm.
- Có Firestore Rules bảo mật.

## 18. Điểm Hạn Chế Nên Nói Thật

Nếu thầy/cô hỏi về hạn chế, có thể trả lời:

> Do thời gian đồ án có hạn, app dùng Google Drive làm kho truyện để dễ demo và
> triển khai nhanh. Với sản phẩm thật, em sẽ tách metadata truyện vào database,
> lưu file ở cloud storage/CDN và xây admin quản lý truyện riêng.

> Với EPUB rất lớn, app vẫn có thể mất thời gian parse vì thư viện đọc EPUB phải
> xử lý nội dung file. Em đã tối ưu phần tải bằng stream và cache để giảm treo
> khi tải từ Drive.

## 19. Câu Kết Khi Bảo Vệ

> Qua đồ án này, em đã xây dựng được một ứng dụng đọc truyện Flutter có đầy đủ
> các phần chính: đọc truyện, tải truyện online/offline, tài khoản, đồng bộ dữ
> liệu, cộng đồng và cài đặt đọc. Dù vẫn còn hướng phát triển, app hiện đã có thể
> build APK và test trên thiết bị thật.

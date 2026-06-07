# Script Giới Thiệu Đồ Án vBook

## 1. Mở Đầu

Kính chào thầy/cô và các bạn.  
Em xin trình bày đồ án ứng dụng đọc truyện **vBook**, được xây dựng bằng Flutter
cho nền tảng Android.

Ý tưởng của app xuất phát từ nhu cầu đọc truyện chữ, light novel và tài liệu
truyện trên điện thoại. Người dùng hiện nay thường đọc trên các app như
Tachiyomi, VBook hoặc các website như DocLN, Hako. Vì vậy em xây dựng vBook theo
hướng có kệ sách cá nhân, khám phá truyện, đọc nhiều định dạng, tải truyện về
máy và đồng bộ tài khoản.

## 2. Mục Tiêu Của Ứng Dụng

Mục tiêu chính của vBook là:

- Cho phép người dùng đọc truyện từ Google Drive.
- Hỗ trợ đọc EPUB, PDF và TXT.
- Cho phép tải truyện về máy để đọc offline.
- Lưu tiến độ đọc và cài đặt đọc.
- Có tài khoản người dùng bằng Firebase.
- Có khu vực cộng đồng để người dùng gửi tin nhắn.
- Có giao diện thân thiện, phù hợp với app đọc truyện trên điện thoại.

## 3. Các Chức Năng Chính

### Kệ Sách Cá Nhân

Đây là nơi hiển thị các truyện người dùng đã thêm hoặc đã tải về máy.  
Người dùng có thể xem dạng lưới/danh sách, tìm kiếm truyện, sắp xếp theo tên,
tiến độ đọc hoặc truyện đọc gần đây.

### Khám Phá Truyện

Màn hình Khám phá lấy danh sách truyện từ các thư mục Google Drive.  
App hỗ trợ quét thư mục Drive, đọc file EPUB/PDF/TXT, lấy ảnh bìa từ ảnh rời
hoặc từ bên trong file EPUB.

### Chi Tiết Truyện

Màn hình chi tiết hiển thị ảnh bìa, tên truyện, tác giả, mô tả, thể loại và
định dạng file. Người dùng có thể đọc trực tiếp từ Drive hoặc tải truyện về máy.

### Màn Hình Đọc

App hỗ trợ:

- Đọc EPUB theo chương.
- Đọc PDF bằng trình đọc PDF.
- Đọc TXT bằng màn đọc văn bản.
- Lưu chương đang đọc và vị trí cuộn.
- Tùy chỉnh font, cỡ chữ, nền đọc, khoảng cách dòng.
- Khi người dùng đọc tới cuối chương, app không tự nhảy chương ngay. Người dùng
  cần vuốt thêm một lần nữa hoặc bấm nút chương tiếp để chuyển chương, giúp việc
  đọc tự nhiên hơn.

### Audio Đọc Truyện

App tích hợp Text-to-Speech để đọc nội dung truyện bằng giọng nói. Người dùng có
thể điều chỉnh tốc độ đọc, cao độ và âm lượng.

### Tài Khoản Và Cộng Đồng

Người dùng có thể đăng ký, đăng nhập, xác minh email, khôi phục mật khẩu và chỉnh
sửa thông tin cá nhân.  
Khu vực cộng đồng cho phép người dùng đã xác minh email gửi tin nhắn, dữ liệu
được lưu trên Cloud Firestore.

### Quản Trị

Tài khoản admin được nhận diện theo email cấu hình trong app và Firestore Rules.
Khi đăng nhập bằng tài khoản admin, màn Cá nhân hiển thị nhãn quản trị viên và
có mục tác vụ riêng để mở nhanh Khám phá, kiểm tra cộng đồng và làm mới quyền
tài khoản. Trong màn Khám phá, admin có thể quét thêm thư mục Drive để kiểm tra
dữ liệu truyện.

## 4. Công Nghệ Sử Dụng

Ứng dụng sử dụng các công nghệ chính sau:

- **Flutter/Dart**: xây dựng giao diện và logic app Android.
- **Provider**: quản lý trạng thái như theme, user, cài đặt đọc.
- **Google Drive API**: lấy danh sách và tải file truyện từ Google Drive.
- **Firebase Authentication**: đăng ký, đăng nhập, xác minh email, khôi phục mật
  khẩu.
- **Cloud Firestore**: lưu profile người dùng, thư viện cá nhân, tiến độ đọc và
  tin nhắn cộng đồng.
- **SharedPreferences**: lưu cache local, trạng thái đăng nhập, cài đặt đọc.
- **epubx/epub_view**: đọc metadata và hiển thị EPUB.
- **syncfusion_flutter_pdfviewer**: đọc PDF.
- **flutter_html**: hiển thị nội dung chương EPUB dạng HTML.
- **flutter_tts**: đọc truyện bằng giọng nói.
- **path_provider**: lưu file tải về, cache ảnh bìa và cache truyện Drive.
- **archive/xml/image**: đọc cấu trúc EPUB, tìm ảnh bìa và xử lý ảnh.

## 5. Kiến Trúc Tổng Quan

App được chia theo các nhóm chính:

- `models`: định nghĩa dữ liệu như Story, AppUser, CommunityMessage.
- `screens`: các màn hình giao diện.
- `services`: xử lý Google Drive, Firebase, local storage và logic dữ liệu.
- `theme`: quản lý theme, user provider, reading settings.
- `widgets`: các widget dùng chung như ảnh bìa truyện.

Luồng dữ liệu tổng quát:

```text
Người dùng
  -> Flutter UI
  -> ApiService
  -> GoogleDriveService / FirebaseBackendService / SharedPreferences
  -> Trả dữ liệu về UI
```

## 6. Google Drive API Được Dùng Như Thế Nào?

Trong app này, Google Drive API được dùng để:

- Lấy danh sách file trong thư mục Drive.
- Quét các file truyện EPUB/PDF/TXT.
- Tải file truyện về máy.
- Lấy ảnh bìa nếu thư mục có ảnh rời.
- Tải EPUB để trích ảnh bìa bên trong.

Google Drive API **không phải backend đầy đủ**. Nó đóng vai trò như một nguồn lưu
trữ file truyện và nguồn dữ liệu truyện. Backend thật của app là Firebase, vì
Firebase xử lý tài khoản, phân quyền, đồng bộ thư viện, tiến độ đọc và cộng đồng.

Có thể hiểu đơn giản:

- Google Drive: nơi chứa file truyện.
- Firebase Auth: nơi quản lý đăng nhập.
- Firestore: nơi lưu dữ liệu người dùng và cộng đồng.
- SharedPreferences/file local: nơi lưu cache và truyện offline trên thiết bị.

## 7. Vì Sao Dùng Google Drive Thay Vì Backend Truyện Riêng?

Google Drive phù hợp cho đồ án vì:

- Dễ chuẩn bị dữ liệu truyện.
- Không cần xây server upload file riêng.
- Có thể dùng thư mục Drive làm kho truyện.
- Phù hợp demo và test nhanh trên APK thật.

Tuy nhiên Drive không tốt hơn backend thật trong mọi trường hợp. Nếu app phát
hành công khai với nhiều người dùng, backend thật sẽ tốt hơn vì:

- Tối ưu truy vấn, tìm kiếm, phân trang.
- Quản lý metadata truyện tốt hơn.
- Kiểm soát phân quyền và tốc độ tải tốt hơn.
- Có thể xử lý ảnh bìa, CDN, thống kê, bình luận, báo cáo lỗi.

Vì vậy trong đồ án này, Drive là giải pháp thay thế phần **kho file truyện**, còn
Firebase vẫn là backend cho phần **người dùng và dữ liệu động**.

## 8. Điểm Đã Tối Ưu

App đã được tối ưu ở một số điểm:

- Tải truyện Drive bằng stream ra file, không giữ toàn bộ file trong RAM.
- Cache file đọc từ Drive để mở lại nhanh hơn.
- Giới hạn tải EPUB quá lớn chỉ để lấy ảnh bìa.
- Tự phục hồi ảnh bìa EPUB nếu dữ liệu cũ bị mất.
- Dừng ở cuối chương và chỉ chuyển chương khi người dùng chủ động vuốt thêm.
- Có fallback local nếu Firebase chưa sẵn sàng.
- Có Firestore Rules để giới hạn quyền truy cập dữ liệu.

## 9. Demo Nên Trình Bày Theo Thứ Tự

1. Mở app, giới thiệu giao diện chính.
2. Vào Khám phá, tải danh sách truyện từ Drive.
3. Mở chi tiết một truyện.
4. Đọc thử truyện EPUB/PDF.
5. Tải truyện về máy.
6. Quay lại Kệ sách, mở truyện offline.
7. Chỉnh cỡ chữ/theme/cài đặt đọc.
8. Thử Text-to-Speech.
9. Đăng ký/đăng nhập tài khoản.
10. Chỉnh sửa thông tin cá nhân.
11. Khôi phục mật khẩu bằng email.
12. Gửi tin nhắn cộng đồng.
13. Đăng nhập tài khoản admin và kiểm tra mục Quản trị.

## 10. Hạn Chế Hiện Tại

Một số hạn chế còn tồn tại:

- EPUB dung lượng rất lớn vẫn có thể mất thời gian khi parse nội dung.
- Google Drive không linh hoạt bằng backend truyện riêng.
- Chưa có hệ thống bình luận theo từng truyện.
- Chưa có bookmark/ghi chú nâng cao.
- APK release hiện phục vụ test đồ án, chưa tối ưu như app phát hành thương mại.
- Các tác vụ admin hiện phục vụ kiểm tra và demo, chưa phải trang quản trị nội
  dung đầy đủ như sản phẩm thương mại.

## 11. Hướng Phát Triển

Trong tương lai app có thể phát triển thêm:

- Backend riêng để quản lý truyện chuyên nghiệp hơn.
- Tìm kiếm và lọc truyện nâng cao.
- Bình luận/đánh giá theo từng truyện.
- Bookmark, ghi chú, lịch sử đọc chi tiết.
- CDN ảnh bìa và file truyện để tải nhanh hơn.
- Firebase App Check và release signing đầy đủ.

## 12. Kết Luận

Tóm lại, vBook là ứng dụng đọc truyện Flutter có đầy đủ các phần chính: đọc
truyện, tải truyện từ Drive, đọc offline, tài khoản, đồng bộ, cộng đồng và cài
đặt đọc. Hiện tại app đã đạt khoảng 90-95% phạm vi đồ án, phần còn lại chủ yếu
là test APK thực tế và chỉnh các lỗi nhỏ nếu phát sinh.  
Ứng dụng phù hợp để demo đồ án vì có thể build APK và test trực tiếp trên điện
thoại thật.

Em xin cảm ơn thầy/cô và các bạn đã lắng nghe.

# vBook

Flutter app doc truyen EPUB, PDF va TXT. App co thu vien offline tu
`assets/offline_stories/`, ho tro import file tu may, doc tiep, tuy chinh
font/co chu/mau nen, tai truyen tu Google Drive va luu ve may de doc offline.

## Chay app

```sh
flutter pub get
flutter run
```

Neu can tai danh sach truyen tu Google Drive, truyen API key bang
`--dart-define`:

```sh
flutter run --dart-define=GOOGLE_DRIVE_API_KEY=your_key
```

Neu muon app Flutter goi backend local, chay backend truoc roi truyen dia chi
API bang `VBOOK_API_BASE_URL`:

```sh
flutter run --dart-define=VBOOK_API_BASE_URL=http://127.0.0.1:8080
```

Khi chay tren Android Emulator, dung dia chi may host:

```sh
flutter run --dart-define=VBOOK_API_BASE_URL=http://10.0.2.2:8080
```

Co the truyen ca backend va Google Drive key cung luc:

```sh
flutter run --dart-define=VBOOK_API_BASE_URL=http://10.0.2.2:8080 --dart-define=GOOGLE_DRIVE_API_KEY=your_key
```

Build APK debug:

```sh
flutter build apk --debug
```

Android package hien tai: `com.vbook.reader`.

## Chay backend local

Backend mau nam trong thu muc `backend/`, dung Python standard library va
SQLite nen khong can cai Node/npm hay package ngoai.

```sh
cd backend
python server.py
```

Kiem tra nhanh backend:

```sh
cd backend
python smoke_test.py
```

API mac dinh: `http://127.0.0.1:8080`. Tai lieu chi tiet nam tai
`backend/README.md`.

## Kiem tra

```sh
flutter analyze
flutter test
python -m py_compile backend/server.py backend/smoke_test.py
```

## Ghi chu

Khong commit API key truc tiep vao source. Android release da khai bao quyen
Internet trong manifest chinh. Android hien cho phep cleartext HTTP de goi
backend local; khi phat hanh that nen doi backend sang HTTPS. Truoc khi phat
hanh that, can tao keystore rieng va cau hinh signing release thay cho debug
signing.

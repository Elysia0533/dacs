from __future__ import annotations

import base64
import hashlib
import hmac
import json
import os
import re
import secrets
import sqlite3
import smtplib
import time
import uuid
from datetime import datetime, timezone
from email.message import EmailMessage
from html import escape
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import parse_qs, urlparse


ROOT_DIR = Path(__file__).resolve().parent
SCHEMA_PATH = ROOT_DIR / "schema.sql"


def load_env_file(path: Path) -> None:
    if not path.exists():
        return

    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        if key and key not in os.environ:
            os.environ[key] = value


ENV_FILE = os.environ.get("VBOOK_ENV_FILE", str(ROOT_DIR / ".env"))
if ENV_FILE != "0":
    load_env_file(Path(ENV_FILE))

DB_PATH = Path(os.environ.get("VBOOK_DB", ROOT_DIR / "data" / "vbook.db"))
HOST = os.environ.get("VBOOK_HOST", "0.0.0.0")
PORT = int(os.environ.get("VBOOK_PORT", "8080"))
SECRET = os.environ.get("VBOOK_SECRET", "dev-secret-change-me")
TOKEN_TTL_SECONDS = int(os.environ.get("VBOOK_TOKEN_TTL", str(60 * 60 * 24 * 7)))
EMAIL_VERIFICATION_TTL_SECONDS = int(
    os.environ.get("VBOOK_EMAIL_VERIFICATION_TTL", str(15 * 60))
)
PUBLIC_BASE_URL = os.environ.get("VBOOK_PUBLIC_BASE_URL", f"http://{HOST}:{PORT}")
SMTP_HOST = os.environ.get("VBOOK_SMTP_HOST", "")
SMTP_PORT = int(os.environ.get("VBOOK_SMTP_PORT", "587"))
SMTP_USER = os.environ.get("VBOOK_SMTP_USER", "")
SMTP_PASS = os.environ.get("VBOOK_SMTP_PASS", "")
SMTP_FROM = os.environ.get("VBOOK_SMTP_FROM", SMTP_USER or "no-reply@vbook.local")
SMTP_TLS = os.environ.get("VBOOK_SMTP_TLS", "1") != "0"
REQUIRE_SMTP = os.environ.get("VBOOK_REQUIRE_SMTP", "0") == "1"


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def json_dumps(data: Any) -> bytes:
    return json.dumps(data, ensure_ascii=False, separators=(",", ":")).encode("utf-8")


def b64url_encode(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).decode("ascii").rstrip("=")


def b64url_decode(data: str) -> bytes:
    padding = "=" * (-len(data) % 4)
    return base64.urlsafe_b64decode(data + padding)


def make_id(prefix: str) -> str:
    return f"{prefix}_{uuid.uuid4().hex}"


def hash_password(password: str) -> str:
    salt = os.urandom(16)
    iterations = 120_000
    digest = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt, iterations)
    return "pbkdf2_sha256${}${}${}".format(
        iterations,
        b64url_encode(salt),
        b64url_encode(digest),
    )


def verify_password(password: str, password_hash: str) -> bool:
    try:
        algorithm, iterations_raw, salt_raw, digest_raw = password_hash.split("$")
        if algorithm != "pbkdf2_sha256":
            return False
        iterations = int(iterations_raw)
        salt = b64url_decode(salt_raw)
        expected = b64url_decode(digest_raw)
        actual = hashlib.pbkdf2_hmac(
            "sha256",
            password.encode("utf-8"),
            salt,
            iterations,
        )
        return hmac.compare_digest(actual, expected)
    except (ValueError, TypeError):
        return False


def create_token(user: sqlite3.Row) -> str:
    header = {"alg": "HS256", "typ": "JWT"}
    payload = {
        "sub": user["id"],
        "email": user["email"],
        "role": user["role"],
        "exp": int(time.time()) + TOKEN_TTL_SECONDS,
    }
    header_part = b64url_encode(json_dumps(header))
    payload_part = b64url_encode(json_dumps(payload))
    signing_input = f"{header_part}.{payload_part}".encode("ascii")
    signature = hmac.new(SECRET.encode("utf-8"), signing_input, hashlib.sha256).digest()
    return f"{header_part}.{payload_part}.{b64url_encode(signature)}"


def parse_token(token: str) -> dict[str, Any] | None:
    try:
        header_part, payload_part, signature_part = token.split(".")
        signing_input = f"{header_part}.{payload_part}".encode("ascii")
        expected = hmac.new(
            SECRET.encode("utf-8"),
            signing_input,
            hashlib.sha256,
        ).digest()
        actual = b64url_decode(signature_part)
        if not hmac.compare_digest(actual, expected):
            return None
        payload = json.loads(b64url_decode(payload_part))
        if int(payload.get("exp", 0)) < int(time.time()):
            return None
        return payload
    except (ValueError, TypeError, json.JSONDecodeError):
        return None


def connect_db() -> sqlite3.Connection:
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    con = sqlite3.connect(DB_PATH)
    con.row_factory = sqlite3.Row
    con.execute("PRAGMA foreign_keys = ON")
    return con


def init_db() -> None:
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    with connect_db() as con:
        con.executescript(SCHEMA_PATH.read_text(encoding="utf-8"))
        run_migrations(con)
        if os.environ.get("VBOOK_SEED_DEMO", "1") != "0":
            seed_demo_stories(con)


def run_migrations(con: sqlite3.Connection) -> None:
    columns = {row["name"] for row in con.execute("PRAGMA table_info(users)")}
    migrations = {
        "email_verified": "INTEGER NOT NULL DEFAULT 1",
        "email_verification_code": "TEXT NOT NULL DEFAULT ''",
        "email_verification_token": "TEXT NOT NULL DEFAULT ''",
        "email_verification_expires_at": "INTEGER",
    }
    for column, definition in migrations.items():
        if column not in columns:
            con.execute(f"ALTER TABLE users ADD COLUMN {column} {definition}")


def seed_demo_stories(con: sqlite3.Connection) -> None:
    count = con.execute("SELECT COUNT(*) FROM stories").fetchone()[0]
    if count > 0:
        return

    created = now_iso()
    stories = [
        {
            "id": "story_thanh_xuan_vol_1",
            "title": "Thanh Xuan Vol 1",
            "author": "vBook Demo",
            "description": "Truyen mau dung de demo backend SQLite.",
            "genres": ["Hoc duong", "Tinh cam"],
            "total_chapters": 12,
            "file_type": "epub",
        },
        {
            "id": "story_thanh_xuan_vol_2",
            "title": "Thanh Xuan Vol 2",
            "author": "vBook Demo",
            "description": "Phan tiep theo cua bo truyen demo.",
            "genres": ["Hoc duong", "Doi thuong"],
            "total_chapters": 10,
            "file_type": "epub",
        },
        {
            "id": "story_txt_demo",
            "title": "Truyen TXT Demo",
            "author": "vBook Demo",
            "description": "Ban ghi demo cho luong doc TXT/offline.",
            "genres": ["Ngan", "Demo"],
            "total_chapters": 1,
            "file_type": "txt",
        },
    ]
    for story in stories:
        con.execute(
            """
            INSERT INTO stories (
              id, title, author, description, genres, total_chapters,
              file_type, created_at, updated_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                story["id"],
                story["title"],
                story["author"],
                story["description"],
                json.dumps(story["genres"], ensure_ascii=False),
                story["total_chapters"],
                story["file_type"],
                created,
                created,
            ),
        )


def row_to_user(row: sqlite3.Row) -> dict[str, Any]:
    return {
        "id": row["id"],
        "email": row["email"],
        "displayName": row["display_name"],
        "avatarUrl": row["avatar_url"],
        "role": row["role"],
        "emailVerified": bool(row["email_verified"]),
        "createdAt": row["created_at"],
        "updatedAt": row["updated_at"],
    }


def row_to_story(row: sqlite3.Row) -> dict[str, Any]:
    return {
        "id": row["id"],
        "title": row["title"],
        "titleEng": row["title_eng"],
        "author": row["author"],
        "description": row["description"],
        "genres": json.loads(row["genres"] or "[]"),
        "totalChapters": row["total_chapters"],
        "iconUrl": row["icon_url"],
        "driveFileId": row["drive_file_id"],
        "fileType": row["file_type"],
        "isPublished": bool(row["is_published"]),
        "createdAt": row["created_at"],
        "updatedAt": row["updated_at"],
    }


def row_to_library_item(row: sqlite3.Row) -> dict[str, Any]:
    story = row_to_story(row)
    return {
        "story": story,
        "localPath": row["local_path"],
        "savedChapterIndex": row["saved_chapter_index"],
        "totalChapters": row["library_total_chapters"],
        "scrollOffset": row["scroll_offset"],
        "lastReadAt": row["last_read_at"],
        "createdAt": row["library_created_at"],
        "updatedAt": row["library_updated_at"],
    }


def row_to_message(row: sqlite3.Row) -> dict[str, Any]:
    return {
        "id": row["id"],
        "userId": row["user_id"],
        "displayName": row["display_name"],
        "avatarUrl": row["avatar_url"],
        "text": row["text"],
        "createdAt": row["created_at"],
    }


def normalize_email(value: Any) -> str:
    return str(value or "").strip().lower()


def make_verification_code() -> str:
    return f"{secrets.randbelow(1_000_000):06d}"


def make_verification_token() -> str:
    return secrets.token_urlsafe(32)


def verification_expires_at() -> int:
    return int(time.time()) + EMAIL_VERIFICATION_TTL_SECONDS


def verification_link(token: str) -> str:
    return f"{PUBLIC_BASE_URL.rstrip('/')}/auth/verify-email?token={token}"


def send_verification_email(email: str, display_name: str, code: str, token: str) -> bool:
    link = verification_link(token)
    if not SMTP_HOST:
        if REQUIRE_SMTP:
            raise RuntimeError(
                "Chua cau hinh VBOOK_SMTP_HOST nen khong the gui email that"
            )
        print("")
        print("==== vBook email verification (dev mode) ====")
        print(f"To: {email}")
        print(f"Code: {code}")
        print(f"Link: {link}")
        print("Configure VBOOK_SMTP_HOST to send a real email.")
        print("============================================")
        print("")
        return False

    safe_name = display_name or email
    message = EmailMessage()
    message["From"] = SMTP_FROM
    message["To"] = email
    message["Subject"] = "vBook email verification"
    message.set_content(
        "\n".join(
            [
                f"Xin chao {safe_name},",
                "",
                f"Ma xac nhan vBook cua ban la: {code}",
                f"Ma het han sau {EMAIL_VERIFICATION_TTL_SECONDS // 60} phut.",
                "",
                f"Hoac mo link nay de xac nhan: {link}",
                "",
                "Neu ban khong tao tai khoan vBook, hay bo qua email nay.",
            ]
        )
    )
    message.add_alternative(
        f"""
        <html>
          <body>
            <p>Xin chao {escape(safe_name)},</p>
            <p>Ma xac nhan vBook cua ban la:</p>
            <p style="font-size:24px;font-weight:700;letter-spacing:4px;">{code}</p>
            <p>Ma het han sau {EMAIL_VERIFICATION_TTL_SECONDS // 60} phut.</p>
            <p><a href="{escape(link)}">Xac nhan email</a></p>
            <p>Neu ban khong tao tai khoan vBook, hay bo qua email nay.</p>
          </body>
        </html>
        """,
        subtype="html",
    )

    if SMTP_PORT == 465:
        with smtplib.SMTP_SSL(SMTP_HOST, SMTP_PORT, timeout=15) as smtp:
            if SMTP_USER:
                smtp.login(SMTP_USER, SMTP_PASS)
            smtp.send_message(message)
    else:
        with smtplib.SMTP(SMTP_HOST, SMTP_PORT, timeout=15) as smtp:
            if SMTP_TLS:
                smtp.starttls()
            if SMTP_USER:
                smtp.login(SMTP_USER, SMTP_PASS)
            smtp.send_message(message)
    return True


def clamp_int(value: Any, default: int, minimum: int, maximum: int) -> int:
    try:
        parsed = int(value)
    except (TypeError, ValueError):
        parsed = default
    return max(minimum, min(maximum, parsed))


class ApiError(Exception):
    def __init__(self, status: HTTPStatus, message: str):
        self.status = status
        self.message = message
        super().__init__(message)


class VBookHandler(BaseHTTPRequestHandler):
    server_version = "vBookBackend/1.0"

    def do_OPTIONS(self) -> None:
        self.send_response(HTTPStatus.NO_CONTENT)
        self.send_cors_headers()
        self.end_headers()

    def do_GET(self) -> None:
        self.handle_request()

    def do_POST(self) -> None:
        self.handle_request()

    def do_PUT(self) -> None:
        self.handle_request()

    def do_PATCH(self) -> None:
        self.handle_request()

    def do_DELETE(self) -> None:
        self.handle_request()

    def log_message(self, fmt: str, *args: Any) -> None:
        print("[%s] %s" % (now_iso(), fmt % args))

    def send_cors_headers(self) -> None:
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET,POST,PUT,PATCH,DELETE,OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type,Authorization")

    def respond(self, status: HTTPStatus, data: Any) -> None:
        body = json_dumps(data)
        self.send_response(status)
        self.send_cors_headers()
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def respond_html(self, status: HTTPStatus, html: str) -> None:
        body = html.encode("utf-8")
        self.send_response(status)
        self.send_cors_headers()
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def parse_json_body(self) -> dict[str, Any]:
        content_length = int(self.headers.get("Content-Length", "0"))
        if content_length == 0:
            return {}
        raw = self.rfile.read(content_length)
        try:
            payload = json.loads(raw.decode("utf-8"))
        except json.JSONDecodeError as exc:
            raise ApiError(HTTPStatus.BAD_REQUEST, "Body JSON khong hop le") from exc
        if not isinstance(payload, dict):
            raise ApiError(HTTPStatus.BAD_REQUEST, "Body phai la JSON object")
        return payload

    def current_user(self, required: bool = True) -> sqlite3.Row | None:
        authorization = self.headers.get("Authorization", "")
        match = re.match(r"^Bearer\s+(.+)$", authorization)
        if not match:
            if required:
                raise ApiError(HTTPStatus.UNAUTHORIZED, "Can dang nhap")
            return None

        payload = parse_token(match.group(1))
        if not payload:
            if required:
                raise ApiError(HTTPStatus.UNAUTHORIZED, "Token khong hop le hoac da het han")
            return None

        with connect_db() as con:
            user = con.execute(
                "SELECT * FROM users WHERE id = ?",
                (payload["sub"],),
            ).fetchone()
        if user is None and required:
            raise ApiError(HTTPStatus.UNAUTHORIZED, "Nguoi dung khong ton tai")
        if user is not None and not bool(user["email_verified"]) and required:
            raise ApiError(HTTPStatus.FORBIDDEN, "Email chua duoc xac nhan")
        return user

    def require_admin(self) -> sqlite3.Row:
        user = self.current_user(required=True)
        assert user is not None
        if user["role"] != "admin":
            raise ApiError(HTTPStatus.FORBIDDEN, "Can quyen admin")
        return user

    def handle_request(self) -> None:
        parsed = urlparse(self.path)
        path = parsed.path.rstrip("/") or "/"
        query = parse_qs(parsed.query)

        try:
            if self.command == "GET" and path == "/health":
                self.respond(
                    HTTPStatus.OK,
                    {
                        "ok": True,
                        "service": "vbook-backend",
                        "database": str(DB_PATH),
                        "time": now_iso(),
                    },
                )
                return

            if self.command == "POST" and path == "/auth/register":
                self.register()
                return

            if self.command == "POST" and path == "/auth/login":
                self.login()
                return

            if self.command == "POST" and path == "/auth/verify-email":
                self.verify_email()
                return

            if self.command == "GET" and path == "/auth/verify-email":
                self.verify_email_link(query)
                return

            if self.command == "POST" and path == "/auth/resend-verification":
                self.resend_verification()
                return

            if self.command == "GET" and path == "/auth/me":
                user = self.current_user(required=True)
                assert user is not None
                self.respond(HTTPStatus.OK, {"user": row_to_user(user)})
                return

            if self.command == "GET" and path == "/stories":
                self.list_stories(query)
                return

            story_match = re.fullmatch(r"/stories/([^/]+)", path)
            if story_match:
                story_id = story_match.group(1)
                if self.command == "GET":
                    self.get_story(story_id)
                    return
                if self.command in {"PUT", "PATCH"}:
                    self.update_story(story_id)
                    return
                if self.command == "DELETE":
                    self.delete_story(story_id)
                    return

            if self.command == "POST" and path == "/stories":
                self.create_story()
                return

            if self.command == "GET" and path == "/me/library":
                self.list_library()
                return

            if self.command == "POST" and path == "/me/library":
                self.add_to_library()
                return

            library_match = re.fullmatch(r"/me/library/([^/]+)", path)
            if library_match:
                story_id = library_match.group(1)
                if self.command == "DELETE":
                    self.remove_from_library(story_id)
                    return

            progress_match = re.fullmatch(r"/me/library/([^/]+)/progress", path)
            if progress_match and self.command in {"PUT", "PATCH"}:
                self.update_progress(progress_match.group(1))
                return

            if self.command == "GET" and path == "/community/messages":
                self.list_messages(query)
                return

            if self.command == "POST" and path == "/community/messages":
                self.create_message()
                return

            raise ApiError(HTTPStatus.NOT_FOUND, "Khong tim thay endpoint")
        except ApiError as exc:
            self.respond(exc.status, {"error": exc.message})
        except sqlite3.IntegrityError as exc:
            self.respond(HTTPStatus.CONFLICT, {"error": str(exc)})
        except Exception as exc:  # noqa: BLE001 - keep API alive during local development.
            self.respond(HTTPStatus.INTERNAL_SERVER_ERROR, {"error": str(exc)})

    def register(self) -> None:
        body = self.parse_json_body()
        email = normalize_email(body.get("email"))
        password = str(body.get("password") or "")
        display_name = str(body.get("displayName") or body.get("display_name") or "").strip()

        if not re.fullmatch(r"[^@\s]+@[^@\s]+\.[^@\s]+", email):
            raise ApiError(HTTPStatus.BAD_REQUEST, "Email khong hop le")
        if len(password) < 6:
            raise ApiError(HTTPStatus.BAD_REQUEST, "Mat khau toi thieu 6 ky tu")
        if not display_name:
            display_name = email.split("@", 1)[0]

        created = now_iso()
        code = make_verification_code()
        token = make_verification_token()
        expires_at = verification_expires_at()
        email_sent = False
        with connect_db() as con:
            existing = con.execute("SELECT * FROM users WHERE email = ?", (email,)).fetchone()
            if existing is not None:
                if bool(existing["email_verified"]):
                    raise ApiError(HTTPStatus.CONFLICT, "Email da duoc dang ky")
                con.execute(
                    """
                    UPDATE users
                    SET display_name = ?, password_hash = ?, avatar_url = ?,
                        email_verification_code = ?,
                        email_verification_token = ?,
                        email_verification_expires_at = ?,
                        updated_at = ?
                    WHERE id = ?
                    """,
                    (
                        display_name,
                        hash_password(password),
                        str(body.get("avatarUrl") or ""),
                        code,
                        token,
                        expires_at,
                        created,
                        existing["id"],
                    ),
                )
                user = con.execute("SELECT * FROM users WHERE id = ?", (existing["id"],)).fetchone()
            else:
                user_count = con.execute("SELECT COUNT(*) FROM users").fetchone()[0]
                role = "admin" if user_count == 0 else "user"
                user_id = make_id("usr")
                con.execute(
                    """
                    INSERT INTO users (
                      id, email, password_hash, display_name, avatar_url,
                      role, email_verified, email_verification_code,
                      email_verification_token, email_verification_expires_at,
                      created_at, updated_at
                    )
                    VALUES (?, ?, ?, ?, ?, ?, 0, ?, ?, ?, ?, ?)
                    """,
                    (
                        user_id,
                        email,
                        hash_password(password),
                        display_name,
                        str(body.get("avatarUrl") or ""),
                        role,
                        code,
                        token,
                        expires_at,
                        created,
                        created,
                    ),
                )
                user = con.execute("SELECT * FROM users WHERE id = ?", (user_id,)).fetchone()

            assert user is not None
            try:
                email_sent = send_verification_email(email, display_name, code, token)
            except Exception as exc:  # noqa: BLE001 - surface SMTP setup problems clearly.
                raise ApiError(
                    HTTPStatus.BAD_GATEWAY,
                    f"Khong gui duoc email xac nhan: {exc}",
                ) from exc

        response = {
            "user": row_to_user(user),
            "emailVerificationRequired": True,
            "verificationExpiresInSeconds": EMAIL_VERIFICATION_TTL_SECONDS,
        }
        if not email_sent:
            response["devVerificationCode"] = code
            response["devVerificationLink"] = verification_link(token)
        self.respond(HTTPStatus.CREATED, response)

    def verify_email(self) -> None:
        body = self.parse_json_body()
        email = normalize_email(body.get("email"))
        code = str(body.get("code") or "").strip()
        token = str(body.get("token") or "").strip()
        user = self._verify_email_record(email=email, code=code, token=token)
        self.respond(HTTPStatus.OK, {"user": row_to_user(user), "token": create_token(user)})

    def verify_email_link(self, query: dict[str, list[str]]) -> None:
        token = (query.get("token", [""])[0] or "").strip()
        try:
            user = self._verify_email_record(email="", code="", token=token)
        except ApiError as exc:
            self.respond_html(
                exc.status,
                f"""
                <!doctype html>
                <html lang="vi">
                  <head><meta charset="utf-8"><title>vBook</title></head>
                  <body style="font-family:Arial,sans-serif;padding:32px;">
                    <h2>Khong xac nhan duoc email</h2>
                    <p>{escape(exc.message)}</p>
                  </body>
                </html>
                """,
            )
            return

        self.respond_html(
            HTTPStatus.OK,
            f"""
            <!doctype html>
            <html lang="vi">
              <head><meta charset="utf-8"><title>vBook</title></head>
              <body style="font-family:Arial,sans-serif;padding:32px;">
                <h2>Email da duoc xac nhan</h2>
                <p>Tai khoan {escape(user["email"])} da san sang dang nhap trong ung dung vBook.</p>
              </body>
            </html>
            """,
        )

    def resend_verification(self) -> None:
        body = self.parse_json_body()
        email = normalize_email(body.get("email"))
        if not re.fullmatch(r"[^@\s]+@[^@\s]+\.[^@\s]+", email):
            raise ApiError(HTTPStatus.BAD_REQUEST, "Email khong hop le")

        code = make_verification_code()
        token = make_verification_token()
        expires_at = verification_expires_at()
        updated = now_iso()
        email_sent = False

        with connect_db() as con:
            user = con.execute("SELECT * FROM users WHERE email = ?", (email,)).fetchone()
            if user is None:
                raise ApiError(HTTPStatus.NOT_FOUND, "Email chua dang ky")
            if bool(user["email_verified"]):
                self.respond(HTTPStatus.OK, {"ok": True, "alreadyVerified": True})
                return

            con.execute(
                """
                UPDATE users
                SET email_verification_code = ?,
                    email_verification_token = ?,
                    email_verification_expires_at = ?,
                    updated_at = ?
                WHERE id = ?
                """,
                (code, token, expires_at, updated, user["id"]),
            )
            user = con.execute("SELECT * FROM users WHERE email = ?", (email,)).fetchone()
            assert user is not None
            try:
                email_sent = send_verification_email(
                    email,
                    user["display_name"],
                    code,
                    token,
                )
            except Exception as exc:  # noqa: BLE001
                raise ApiError(
                    HTTPStatus.BAD_GATEWAY,
                    f"Khong gui duoc email xac nhan: {exc}",
                ) from exc

        response = {
            "ok": True,
            "emailVerificationRequired": True,
            "verificationExpiresInSeconds": EMAIL_VERIFICATION_TTL_SECONDS,
        }
        if not email_sent:
            response["devVerificationCode"] = code
            response["devVerificationLink"] = verification_link(token)
        self.respond(HTTPStatus.OK, response)

    def _verify_email_record(self, email: str, code: str, token: str) -> sqlite3.Row:
        if token:
            lookup_sql = "SELECT * FROM users WHERE email_verification_token = ?"
            lookup_args = (token,)
        else:
            if not email or not code:
                raise ApiError(HTTPStatus.BAD_REQUEST, "Can nhap email va ma xac nhan")
            lookup_sql = "SELECT * FROM users WHERE email = ?"
            lookup_args = (email,)

        updated = now_iso()
        with connect_db() as con:
            user = con.execute(lookup_sql, lookup_args).fetchone()
            if user is None:
                raise ApiError(HTTPStatus.BAD_REQUEST, "Ma xac nhan khong dung")
            if bool(user["email_verified"]):
                raise ApiError(HTTPStatus.CONFLICT, "Email da xac nhan. Hay dang nhap.")
            if not token and not hmac.compare_digest(
                str(user["email_verification_code"] or ""),
                code,
            ):
                raise ApiError(HTTPStatus.BAD_REQUEST, "Ma xac nhan khong dung")
            expires_at = int(user["email_verification_expires_at"] or 0)
            if expires_at and expires_at < int(time.time()):
                raise ApiError(HTTPStatus.GONE, "Ma xac nhan da het han")

            user_count = con.execute("SELECT COUNT(*) FROM users").fetchone()[0]
            con.execute(
                """
                UPDATE users
                SET email_verified = 1,
                    email_verification_code = '',
                    email_verification_token = '',
                    email_verification_expires_at = NULL,
                    role = CASE WHEN ? = 1 THEN 'admin' ELSE role END,
                    updated_at = ?
                WHERE id = ?
                """,
                (user_count == 1, updated, user["id"]),
            )
            verified_user = con.execute("SELECT * FROM users WHERE id = ?", (user["id"],)).fetchone()

        assert verified_user is not None
        return verified_user

    def login(self) -> None:
        body = self.parse_json_body()
        email = normalize_email(body.get("email"))
        password = str(body.get("password") or "")

        with connect_db() as con:
            user = con.execute("SELECT * FROM users WHERE email = ?", (email,)).fetchone()

        if user is None or not verify_password(password, user["password_hash"]):
            raise ApiError(HTTPStatus.UNAUTHORIZED, "Email hoac mat khau khong dung")
        if not bool(user["email_verified"]):
            raise ApiError(
                HTTPStatus.FORBIDDEN,
                "Email chua xac nhan. Hay nhap ma xac nhan hoac gui lai ma.",
            )

        self.respond(HTTPStatus.OK, {"user": row_to_user(user), "token": create_token(user)})

    def list_stories(self, query: dict[str, list[str]]) -> None:
        search = (query.get("search", [""])[0] or "").strip().lower()
        genre = (query.get("genre", [""])[0] or "").strip().lower()
        limit = clamp_int(query.get("limit", [50])[0], 50, 1, 100)
        offset = clamp_int(query.get("offset", [0])[0], 0, 0, 100_000)

        clauses = ["is_published = 1"]
        params: list[Any] = []
        if search:
            clauses.append("(lower(title) LIKE ? OR lower(author) LIKE ?)")
            params.extend([f"%{search}%", f"%{search}%"])
        if genre:
            clauses.append("lower(genres) LIKE ?")
            params.append(f"%{genre}%")

        where_sql = " AND ".join(clauses)
        with connect_db() as con:
            rows = con.execute(
                f"""
                SELECT * FROM stories
                WHERE {where_sql}
                ORDER BY updated_at DESC, title ASC
                LIMIT ? OFFSET ?
                """,
                (*params, limit, offset),
            ).fetchall()
            total = con.execute(
                f"SELECT COUNT(*) FROM stories WHERE {where_sql}",
                params,
            ).fetchone()[0]

        self.respond(
            HTTPStatus.OK,
            {
                "items": [row_to_story(row) for row in rows],
                "total": total,
                "limit": limit,
                "offset": offset,
            },
        )

    def get_story(self, story_id: str) -> None:
        with connect_db() as con:
            story = con.execute(
                "SELECT * FROM stories WHERE id = ? AND is_published = 1",
                (story_id,),
            ).fetchone()
        if story is None:
            raise ApiError(HTTPStatus.NOT_FOUND, "Khong tim thay truyen")
        self.respond(HTTPStatus.OK, {"story": row_to_story(story)})

    def story_payload(self, body: dict[str, Any], existing: sqlite3.Row | None = None) -> dict[str, Any]:
        title = str(body.get("title", existing["title"] if existing else "") or "").strip()
        if not title:
            raise ApiError(HTTPStatus.BAD_REQUEST, "title la bat buoc")

        raw_genres = body.get("genres", json.loads(existing["genres"]) if existing else [])
        if isinstance(raw_genres, str):
            genres = [item.strip() for item in raw_genres.split(",") if item.strip()]
        elif isinstance(raw_genres, list):
            genres = [str(item).strip() for item in raw_genres if str(item).strip()]
        else:
            genres = []

        return {
            "title": title,
            "title_eng": str(body.get("titleEng", existing["title_eng"] if existing else "") or ""),
            "author": str(body.get("author", existing["author"] if existing else "") or ""),
            "description": str(body.get("description", existing["description"] if existing else "") or ""),
            "genres": json.dumps(genres, ensure_ascii=False),
            "total_chapters": max(1, int(body.get("totalChapters", existing["total_chapters"] if existing else 1) or 1)),
            "icon_url": str(body.get("iconUrl", existing["icon_url"] if existing else "") or ""),
            "drive_file_id": str(body.get("driveFileId", existing["drive_file_id"] if existing else "") or ""),
            "file_type": str(body.get("fileType", existing["file_type"] if existing else "") or ""),
            "is_published": 1 if bool(body.get("isPublished", bool(existing["is_published"]) if existing else True)) else 0,
        }

    def story_snapshot_payload(
        self,
        story_id: str,
        body: dict[str, Any],
        existing: sqlite3.Row | None = None,
    ) -> dict[str, Any]:
        title = str(body.get("title", existing["title"] if existing else story_id) or story_id).strip()

        raw_genres = body.get("genres", json.loads(existing["genres"]) if existing else [])
        if isinstance(raw_genres, str):
            genres = [item.strip() for item in raw_genres.split(",") if item.strip()]
        elif isinstance(raw_genres, list):
            genres = [str(item).strip() for item in raw_genres if str(item).strip()]
        else:
            genres = []

        return {
            "title": title or story_id,
            "title_eng": str(body.get("titleEng", existing["title_eng"] if existing else "") or ""),
            "author": str(body.get("author", existing["author"] if existing else "") or ""),
            "description": str(body.get("description", existing["description"] if existing else "") or ""),
            "genres": json.dumps(genres, ensure_ascii=False),
            "total_chapters": clamp_int(
                body.get("totalChapters"),
                existing["total_chapters"] if existing else 1,
                1,
                100_000,
            ),
            "icon_url": str(body.get("iconUrl", existing["icon_url"] if existing else "") or ""),
            "drive_file_id": str(body.get("driveFileId", existing["drive_file_id"] if existing else story_id) or story_id),
            "file_type": str(body.get("fileType", existing["file_type"] if existing else "") or ""),
        }

    def create_story(self) -> None:
        self.require_admin()
        body = self.parse_json_body()
        payload = self.story_payload(body)
        story_id = str(body.get("id") or make_id("story"))
        created = now_iso()

        with connect_db() as con:
            con.execute(
                """
                INSERT INTO stories (
                  id, title, title_eng, author, description, genres,
                  total_chapters, icon_url, drive_file_id, file_type,
                  is_published, created_at, updated_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    story_id,
                    payload["title"],
                    payload["title_eng"],
                    payload["author"],
                    payload["description"],
                    payload["genres"],
                    payload["total_chapters"],
                    payload["icon_url"],
                    payload["drive_file_id"],
                    payload["file_type"],
                    payload["is_published"],
                    created,
                    created,
                ),
            )
            story = con.execute("SELECT * FROM stories WHERE id = ?", (story_id,)).fetchone()

        assert story is not None
        self.respond(HTTPStatus.CREATED, {"story": row_to_story(story)})

    def update_story(self, story_id: str) -> None:
        self.require_admin()
        body = self.parse_json_body()
        updated = now_iso()

        with connect_db() as con:
            existing = con.execute("SELECT * FROM stories WHERE id = ?", (story_id,)).fetchone()
            if existing is None:
                raise ApiError(HTTPStatus.NOT_FOUND, "Khong tim thay truyen")
            payload = self.story_payload(body, existing)
            con.execute(
                """
                UPDATE stories
                SET title = ?, title_eng = ?, author = ?, description = ?,
                    genres = ?, total_chapters = ?, icon_url = ?,
                    drive_file_id = ?, file_type = ?, is_published = ?,
                    updated_at = ?
                WHERE id = ?
                """,
                (
                    payload["title"],
                    payload["title_eng"],
                    payload["author"],
                    payload["description"],
                    payload["genres"],
                    payload["total_chapters"],
                    payload["icon_url"],
                    payload["drive_file_id"],
                    payload["file_type"],
                    payload["is_published"],
                    updated,
                    story_id,
                ),
            )
            story = con.execute("SELECT * FROM stories WHERE id = ?", (story_id,)).fetchone()

        assert story is not None
        self.respond(HTTPStatus.OK, {"story": row_to_story(story)})

    def delete_story(self, story_id: str) -> None:
        self.require_admin()
        with connect_db() as con:
            result = con.execute("DELETE FROM stories WHERE id = ?", (story_id,))
        if result.rowcount == 0:
            raise ApiError(HTTPStatus.NOT_FOUND, "Khong tim thay truyen")
        self.respond(HTTPStatus.OK, {"ok": True})

    def ensure_library_story(
        self,
        con: sqlite3.Connection,
        story_id: str,
        body: dict[str, Any],
    ) -> sqlite3.Row:
        existing = con.execute("SELECT * FROM stories WHERE id = ?", (story_id,)).fetchone()
        payload = self.story_snapshot_payload(story_id, body, existing)
        updated = now_iso()

        if existing is None:
            con.execute(
                """
                INSERT INTO stories (
                  id, title, title_eng, author, description, genres,
                  total_chapters, icon_url, drive_file_id, file_type,
                  is_published, created_at, updated_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?)
                """,
                (
                    story_id,
                    payload["title"],
                    payload["title_eng"],
                    payload["author"],
                    payload["description"],
                    payload["genres"],
                    payload["total_chapters"],
                    payload["icon_url"],
                    payload["drive_file_id"],
                    payload["file_type"],
                    updated,
                    updated,
                ),
            )
        else:
            con.execute(
                """
                UPDATE stories
                SET title = ?, title_eng = ?, author = ?, description = ?,
                    genres = ?, total_chapters = ?, icon_url = ?,
                    drive_file_id = ?, file_type = ?, updated_at = ?
                WHERE id = ?
                """,
                (
                    payload["title"],
                    payload["title_eng"],
                    payload["author"],
                    payload["description"],
                    payload["genres"],
                    payload["total_chapters"],
                    payload["icon_url"],
                    payload["drive_file_id"],
                    payload["file_type"],
                    updated,
                    story_id,
                ),
            )

        story = con.execute("SELECT * FROM stories WHERE id = ?", (story_id,)).fetchone()
        assert story is not None
        return story

    def list_library(self) -> None:
        user = self.current_user(required=True)
        assert user is not None
        with connect_db() as con:
            rows = con.execute(
                """
                SELECT
                  s.*,
                  l.local_path,
                  l.saved_chapter_index,
                  l.total_chapters AS library_total_chapters,
                  l.scroll_offset,
                  l.last_read_at,
                  l.created_at AS library_created_at,
                  l.updated_at AS library_updated_at
                FROM user_library l
                JOIN stories s ON s.id = l.story_id
                WHERE l.user_id = ?
                ORDER BY COALESCE(l.last_read_at, l.updated_at) DESC
                """,
                (user["id"],),
            ).fetchall()
        self.respond(HTTPStatus.OK, {"items": [row_to_library_item(row) for row in rows]})

    def add_to_library(self) -> None:
        user = self.current_user(required=True)
        assert user is not None
        body = self.parse_json_body()
        story_id = str(body.get("storyId") or body.get("story_id") or "").strip()
        if not story_id:
            raise ApiError(HTTPStatus.BAD_REQUEST, "storyId la bat buoc")

        created = now_iso()
        with connect_db() as con:
            story = self.ensure_library_story(con, story_id, body)
            con.execute(
                """
                INSERT INTO user_library (
                  user_id, story_id, local_path, saved_chapter_index,
                  total_chapters, scroll_offset, last_read_at, created_at, updated_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(user_id, story_id) DO UPDATE SET
                  local_path = excluded.local_path,
                  updated_at = excluded.updated_at
                """,
                (
                    user["id"],
                    story_id,
                    str(body.get("localPath") or ""),
                    clamp_int(body.get("savedChapterIndex"), 0, 0, 100_000),
                    clamp_int(body.get("totalChapters"), story["total_chapters"], 1, 100_000),
                    float(body.get("scrollOffset") or 0),
                    created,
                    created,
                    created,
                ),
            )

        self.respond(HTTPStatus.CREATED, {"ok": True})

    def remove_from_library(self, story_id: str) -> None:
        user = self.current_user(required=True)
        assert user is not None
        with connect_db() as con:
            result = con.execute(
                "DELETE FROM user_library WHERE user_id = ? AND story_id = ?",
                (user["id"], story_id),
            )
        if result.rowcount == 0:
            raise ApiError(HTTPStatus.NOT_FOUND, "Truyen khong co trong thu vien")
        self.respond(HTTPStatus.OK, {"ok": True})

    def update_progress(self, story_id: str) -> None:
        user = self.current_user(required=True)
        assert user is not None
        body = self.parse_json_body()
        updated = now_iso()
        saved_chapter_index = clamp_int(body.get("savedChapterIndex"), 0, 0, 100_000)
        total_chapters = clamp_int(body.get("totalChapters"), 1, 1, 100_000)
        scroll_offset = float(body.get("scrollOffset") or 0)

        with connect_db() as con:
            self.ensure_library_story(con, story_id, body)
            con.execute(
                """
                INSERT INTO user_library (
                  user_id, story_id, saved_chapter_index, total_chapters,
                  scroll_offset, last_read_at, created_at, updated_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(user_id, story_id) DO UPDATE SET
                  saved_chapter_index = excluded.saved_chapter_index,
                  total_chapters = excluded.total_chapters,
                  scroll_offset = excluded.scroll_offset,
                  last_read_at = excluded.last_read_at,
                  updated_at = excluded.updated_at
                """,
                (
                    user["id"],
                    story_id,
                    saved_chapter_index,
                    total_chapters,
                    scroll_offset,
                    updated,
                    updated,
                    updated,
                ),
            )

        self.respond(HTTPStatus.OK, {"ok": True})

    def list_messages(self, query: dict[str, list[str]]) -> None:
        limit = clamp_int(query.get("limit", [50])[0], 50, 1, 100)
        with connect_db() as con:
            rows = con.execute(
                """
                SELECT m.*, u.display_name, u.avatar_url
                FROM community_messages m
                JOIN users u ON u.id = m.user_id
                ORDER BY m.created_at DESC
                LIMIT ?
                """,
                (limit,),
            ).fetchall()
        items = [row_to_message(row) for row in reversed(rows)]
        self.respond(HTTPStatus.OK, {"items": items})

    def create_message(self) -> None:
        user = self.current_user(required=True)
        assert user is not None
        body = self.parse_json_body()
        text = str(body.get("text") or "").strip()
        if not text:
            raise ApiError(HTTPStatus.BAD_REQUEST, "Noi dung tin nhan khong duoc rong")
        if len(text) > 1000:
            raise ApiError(HTTPStatus.BAD_REQUEST, "Tin nhan toi da 1000 ky tu")

        created = now_iso()
        message_id = make_id("msg")
        with connect_db() as con:
            con.execute(
                "INSERT INTO community_messages (id, user_id, text, created_at) VALUES (?, ?, ?, ?)",
                (message_id, user["id"], text, created),
            )
            row = con.execute(
                """
                SELECT m.*, u.display_name, u.avatar_url
                FROM community_messages m
                JOIN users u ON u.id = m.user_id
                WHERE m.id = ?
                """,
                (message_id,),
            ).fetchone()

        assert row is not None
        self.respond(HTTPStatus.CREATED, {"message": row_to_message(row)})


def main() -> None:
    init_db()
    httpd = ThreadingHTTPServer((HOST, PORT), VBookHandler)
    print(f"vBook backend running at http://{HOST}:{PORT}")
    print(f"SQLite database: {DB_PATH}")
    if SECRET == "dev-secret-change-me":
        print("Warning: set VBOOK_SECRET before using this backend outside local demo.")
    httpd.serve_forever()


if __name__ == "__main__":
    main()

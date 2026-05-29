from __future__ import annotations

import base64
import hashlib
import hmac
import json
import os
import re
import sqlite3
import time
import uuid
from datetime import datetime, timezone
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import parse_qs, urlparse


ROOT_DIR = Path(__file__).resolve().parent
SCHEMA_PATH = ROOT_DIR / "schema.sql"
DB_PATH = Path(os.environ.get("VBOOK_DB", ROOT_DIR / "data" / "vbook.db"))
HOST = os.environ.get("VBOOK_HOST", "127.0.0.1")
PORT = int(os.environ.get("VBOOK_PORT", "8080"))
SECRET = os.environ.get("VBOOK_SECRET", "dev-secret-change-me")
TOKEN_TTL_SECONDS = int(os.environ.get("VBOOK_TOKEN_TTL", str(60 * 60 * 24 * 7)))


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
        if os.environ.get("VBOOK_SEED_DEMO", "1") != "0":
            seed_demo_stories(con)


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
        with connect_db() as con:
            user_count = con.execute("SELECT COUNT(*) FROM users").fetchone()[0]
            role = "admin" if user_count == 0 else "user"
            user_id = make_id("usr")
            con.execute(
                """
                INSERT INTO users (
                  id, email, password_hash, display_name, avatar_url,
                  role, created_at, updated_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    user_id,
                    email,
                    hash_password(password),
                    display_name,
                    str(body.get("avatarUrl") or ""),
                    role,
                    created,
                    created,
                ),
            )
            user = con.execute("SELECT * FROM users WHERE id = ?", (user_id,)).fetchone()

        assert user is not None
        self.respond(
            HTTPStatus.CREATED,
            {
                "user": row_to_user(user),
                "token": create_token(user),
            },
        )

    def login(self) -> None:
        body = self.parse_json_body()
        email = normalize_email(body.get("email"))
        password = str(body.get("password") or "")

        with connect_db() as con:
            user = con.execute("SELECT * FROM users WHERE email = ?", (email,)).fetchone()

        if user is None or not verify_password(password, user["password_hash"]):
            raise ApiError(HTTPStatus.UNAUTHORIZED, "Email hoac mat khau khong dung")

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
            story = con.execute("SELECT * FROM stories WHERE id = ?", (story_id,)).fetchone()
            if story is None:
                raise ApiError(HTTPStatus.NOT_FOUND, "Khong tim thay truyen")
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
            story = con.execute("SELECT * FROM stories WHERE id = ?", (story_id,)).fetchone()
            if story is None:
                raise ApiError(HTTPStatus.NOT_FOUND, "Khong tim thay truyen")
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

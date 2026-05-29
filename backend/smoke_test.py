from __future__ import annotations

import json
import sys
import time
import urllib.error
import urllib.request


BASE_URL = sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:8080"


def request(method: str, path: str, body: dict | None = None, token: str | None = None) -> dict:
    data = None
    headers = {"Content-Type": "application/json"}
    if body is not None:
        data = json.dumps(body).encode("utf-8")
    if token:
        headers["Authorization"] = f"Bearer {token}"
    req = urllib.request.Request(
        f"{BASE_URL}{path}",
        data=data,
        headers=headers,
        method=method,
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as res:
            return json.loads(res.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        payload = exc.read().decode("utf-8")
        raise RuntimeError(f"{method} {path} failed: {exc.code} {payload}") from exc


def main() -> None:
    health = request("GET", "/health")
    assert health["ok"] is True

    email = f"demo_{int(time.time())}@vbook.local"
    registered = request(
        "POST",
        "/auth/register",
        {"email": email, "password": "123456", "displayName": "Demo User"},
    )
    token = registered["token"]
    assert registered["user"]["email"] == email

    stories = request("GET", "/stories")
    assert stories["total"] >= 1
    story_id = stories["items"][0]["id"]

    request("POST", "/me/library", {"storyId": story_id}, token)
    request(
        "PUT",
        f"/me/library/{story_id}/progress",
        {"savedChapterIndex": 2, "totalChapters": 10, "scrollOffset": 120.5},
        token,
    )
    library = request("GET", "/me/library", token=token)
    assert len(library["items"]) >= 1

    message = request("POST", "/community/messages", {"text": "Xin chao vBook!"}, token)
    assert message["message"]["text"] == "Xin chao vBook!"

    print("Smoke test passed")


if __name__ == "__main__":
    main()

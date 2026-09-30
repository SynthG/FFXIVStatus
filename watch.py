import json
import os
import urllib.request
from pathlib import Path

HANDLE = "FortniteStatus"
WEBHOOK = os.environ["TEAMS_WEBHOOK_URL"]
STATE = Path("seen.json")
API = f"https://api.fxtwitter.com/2/profile/{HANDLE}/statuses?count=20"
HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/120.0.0.0 Safari/537.36"
    ),
    "Accept": "application/json",
}


def get(url: str):
    req = urllib.request.Request(url, headers=HEADERS)
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read().decode())


def load_seen():
    if STATE.exists():
        raw = STATE.read_text(encoding="utf-8").strip()
        if not raw:
            return set()
        return set(json.loads(raw))
    return set()


def save_seen(ids):
    STATE.write_text(json.dumps(sorted(ids)[-200:], indent=2), encoding="utf-8")


def is_reply(post: dict) -> bool:
    text = (post.get("text") or "").lstrip()
    if text.startswith("@"):
        return True
    if post.get("replying_to") or post.get("in_reply_to"):
        return True
    reply = post.get("reply") or {}
    return bool(reply.get("in_reply_to_status_id") or reply.get("in_reply_to_screen_name"))


def post_url(post: dict) -> str:
    return post.get("url") or f"https://x.com/{HANDLE}/status/{post.get('id')}"


def notify(text: str, url: str) -> None:
    card = {
        "type": "message",
        "attachments": [
            {
                "contentType": "application/vnd.microsoft.card.adaptive",
                "contentUrl": None,
                "content": {
                    "$schema": "http://adaptivecards.io/schemas/adaptive-card.json",
                    "type": "AdaptiveCard",
                    "version": "1.3",
                    "body": [
                        {
                            "type": "TextBlock",
                            "weight": "Bolder",
                            "size": "Medium",
                            "text": "Fortnite Status",
                        },
                        {
                            "type": "TextBlock",
                            "wrap": True,
                            "text": text,
                        },
                        {
                            "type": "TextBlock",
                            "wrap": True,
                            "isSubtle": True,
                            "text": url,
                        },
                    ],
                },
            }
        ],
    }
    data = json.dumps(card).encode()
    req = urllib.request.Request(
        WEBHOOK,
        data=data,
        method="POST",
        headers={
            "Content-Type": "application/json; charset=utf-8",
            "User-Agent": HEADERS["User-Agent"],
        },
    )
    with urllib.request.urlopen(req, timeout=30) as r:
        r.read()


def normalize(item: dict) -> dict:
    if item.get("type") == "status" and isinstance(item.get("status"), dict):
        return item["status"]
    return item


def main() -> None:
    seen = load_seen()
    first_run = not seen
    payload = get(API)
    posts = payload.get("results") or payload.get("timeline") or []

    found_ids = []
    to_send = []
    for item in posts:
        if not isinstance(item, dict):
            continue
        post = normalize(item)
        post_id = str(post.get("id") or "")
        if not post_id:
            continue
        found_ids.append(post_id)
        if post_id in seen or is_reply(post):
            continue
        to_send.append(post)

    if first_run:
        save_seen(set(found_ids) | seen)
        print(f"Primed {len(found_ids)} posts, nothing sent")
        return

    to_send.sort(key=lambda p: int(p.get("id") or 0))
    for post in to_send:
        notify(post.get("text") or "", post_url(post))
        print("Sent", post.get("id"))

    save_seen(seen | set(found_ids))


if __name__ == "__main__":
    main()

import json
import os
import urllib.request
from pathlib import Path

HANDLES = ["FFXIV_NEWS_EN", "FFXIV_NEWS_DE", "FFXIV_NEWS_FR"]
WEBHOOK = os.environ["TEAMS_WEBHOOK_URL"]
STATE = Path("seen.json")
HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/120.0.0.0 Safari/537.36"
    ),
    "Accept": "application/json",
}


def timeline_url(handle: str) -> str:
    return f"https://api.fxtwitter.com/2/profile/{handle}/statuses?count=20"


def get(url: str):
    req = urllib.request.Request(url, headers=HEADERS)
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read().decode())


def load_seen():
    if STATE.exists():
        raw = STATE.read_text(encoding="utf-8").strip()
        if not raw:
            return set()
        return {str(x) for x in json.loads(raw)}
    return set()


def save_seen(ids):
    STATE.write_text(json.dumps(sorted(ids)[-400:], indent=2), encoding="utf-8")


def is_reply(post: dict) -> bool:
    text = (post.get("text") or "").lstrip()
    if text.startswith("@"):
        return True
    if post.get("replying_to") or post.get("in_reply_to"):
        return True
    reply = post.get("reply") or {}
    return bool(reply.get("in_reply_to_status_id") or reply.get("in_reply_to_screen_name"))


def post_url(handle: str, post: dict) -> str:
    return post.get("url") or f"https://x.com/{handle}/status/{post.get('id')}"


def notify(handle: str, text: str, url: str) -> None:
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
                            "text": f"A new post from {handle}!",
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


def collect_posts(handle: str):
    payload = get(timeline_url(handle))
    items = payload.get("results") or payload.get("timeline") or []
    posts = []
    for item in items:
        if not isinstance(item, dict):
            continue
        post = normalize(item)
        if post.get("id"):
            posts.append(post)
    return posts


def newest_seen_id(seen):
    if not seen:
        return 0
    return max(int(x) for x in seen if str(x).isdigit())


def main() -> None:
    seen = load_seen()
    cutoff = newest_seen_id(seen)

    for handle in HANDLES:
        posts = collect_posts(handle)
        found_ids = [str(post.get("id")) for post in posts]
        known = [post_id for post_id in found_ids if post_id in seen]

        if not known and not seen:
            seen.update(found_ids)
            print(f"Primed {handle}: {len(found_ids)} posts, nothing sent")
            continue

        to_send = []
        for post in posts:
            post_id = str(post.get("id"))
            if post_id in seen or is_reply(post):
                continue
            if not known and int(post_id) <= cutoff:
                continue
            to_send.append(post)

        to_send.sort(key=lambda p: int(p.get("id") or 0))
        for post in to_send:
            notify(handle, post.get("text") or "", post_url(handle, post))
            print(f"Sent {handle} {post.get('id')}")

        seen.update(found_ids)

    save_seen(seen)


if __name__ == "__main__":
    main()

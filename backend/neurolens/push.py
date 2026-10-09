"""Web Push: lets the browser show a notification even when the site isn't open. Keys are generated once and kept in data/vapid.json."""

import base64
import json
import threading

from cryptography.hazmat.primitives import serialization
from py_vapid import Vapid01

from neurolens import logstore, monitorstore

KEY_FILE = logstore.DATA_DIR / "vapid_private.pem"
CONTACT = "mailto:owner@neurolens.local"
_lock = threading.Lock()


def _vapid():
    with _lock:
        v = Vapid01()
        if KEY_FILE.exists():
            return Vapid01.from_file(str(KEY_FILE))
        v.generate_keys()
        v.save_key(str(KEY_FILE))
        return v


def public_key():
    raw = _vapid().public_key.public_bytes(serialization.Encoding.X962, serialization.PublicFormat.UncompressedPoint)
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode()


def send(title, body, url="pages/feed.html"):
    subs = monitorstore.subs()
    if not subs:
        return 0
    from pywebpush import WebPushException, webpush

    payload = json.dumps({"title": title, "body": body, "url": url})
    sent = 0
    for sub in subs:
        try:
            webpush(sub, payload, vapid_private_key=str(KEY_FILE), vapid_claims={"sub": CONTACT})
            sent += 1
        except WebPushException as e:
            if getattr(e.response, "status_code", 0) in (404, 410):
                monitorstore.drop_sub(sub["endpoint"])  # the browser unsubscribed
            else:
                print(f"push failed: {e!r}"[:200], flush=True)
        except Exception as e:
            print(f"push failed: {e!r}"[:200], flush=True)
    return sent

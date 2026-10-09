"""Background loop for child monitoring: every minute, start a feed check for each enabled profile whose time has come."""

import random
import threading
import time

from neurolens import monitorstore, scanner

CHECK_EVERY = 60  # seconds between looks at the schedule
MIN_INTERVAL = 30  # minutes: never check a profile more often than this
_started = False


def _tick():
    now = time.time()
    for m in monitorstore.due_monitors(now):
        interval = max(MIN_INTERVAL, int(m.get("interval_min") or 120))
        monitorstore.save_monitor(m["profile_id"], next_scan=now + interval * 60 + random.uniform(0, 300))
        scanner.start(m["profile_id"], "explore", {"limit": 8, "new_only": True, "alerts": True})


def start():
    global _started
    if _started:
        return
    _started = True

    def loop():
        time.sleep(20)
        while True:
            try:
                _tick()
            except Exception as e:
                print(f"monitor tick failed: {e!r}", flush=True)
            time.sleep(CHECK_EVERY)

    threading.Thread(target=loop, daemon=True).start()

"""Turns scan results into notifications: saved in the alerts table (the in-app bell) and pushed to subscribed browsers."""

from neurolens import monitorstore, push

LEVEL_RANK = {"info": 0, "watch": 1, "high": 2}


def _name(pid):
    m = monitorstore.get_monitor(pid)
    return (m and m.get("name")) or ("you" if pid == "me" else "your child")


def _emit(pid, level, kind, title, body, link=None, job_id=None, scan_id=None, notify=True):
    aid = monitorstore.add_alert(pid, level, kind, title, body, link, job_id, scan_id)
    if notify:
        push.send(title, body, link or "pages/feed.html")
    return aid


def for_item(pid, scan_id, rec, assessment):
    """One alert per item that needs a look. rec = scanner item record, assessment = wellbeing.assess()."""
    who = _name(pid)
    reasons, level = [], "info"
    if assessment["level"] == "high":
        level = "high"
        reasons.append("a heavy emotional tone" + (f" ({', '.join(m for m, _ in assessment['drivers'][:3])})" if assessment["drivers"] else ""))
    elif assessment["level"] == "watch":
        level = "watch"
        reasons.append("some heavier emotions" + (f" ({', '.join(m for m, _ in assessment['drivers'][:2])})" if assessment["drivers"] else ""))
    if rec.get("safety") == "review":
        level = "high" if level == "high" else "watch"
        reasons.append("revealing or suggestive footage")
    if not reasons:
        return None
    what = "reel" if rec.get("kind") == "reel" else "post"
    title = f"{'High concern' if level == 'high' else 'Worth a look'}: {who}'s feed"
    body = f"A {rec.get('mood', 'mixed')} {what} in {who}'s feed has " + " and ".join(reasons) + "."
    return _emit(pid, level, "item", title, body, f"pages/results.html?id={rec['jobId']}", rec["jobId"], scan_id)


def digest(pid, scan_id, summary):
    if not summary.get("analyzed"):
        return
    who = _name(pid)
    flagged = len(summary.get("flagged") or [])
    body = " ".join(summary.get("lines") or [])[:300]
    _emit(pid, "watch" if flagged else "info", "digest", f"Feed check for {who}: {summary['analyzed']} checked" + (f", {flagged} worth a look" if flagged else ""),
          body, f"pages/feed.html?profile={pid}&scan={scan_id}", None, scan_id, notify=False)  # the per-item alerts already pushed


def needs_login(pid):
    _emit(pid, "watch", "login", f"Reconnect Instagram for {_name(pid)}", "The saved Instagram session expired, so automatic checks are paused. Log in again to resume.", f"pages/feed.html?profile={pid}")

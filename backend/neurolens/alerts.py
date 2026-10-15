"""Turns scan results into notifications: saved in the alerts table (the in-app bell) and pushed to subscribed browsers."""

from neurolens import accounts, monitorstore, platforms, push

LEVEL_RANK = {"info": 0, "watch": 1, "high": 2}


def _name(pid):
    m = monitorstore.get_monitor(pid)
    return (m and m.get("name")) or ("you" if pid == "me" else "your child")


def _emit(pid, level, kind, title, body, link=None, job_id=None, scan_id=None, notify=True):
    aid = monitorstore.add_alert(pid, level, kind, title, body, link, job_id, scan_id)
    if notify:  # each person's own browsers only: the owner's, or the signed-in user's
        push.send(title, body, link or "pages/feed.html", uid=accounts.uid_of(pid))
    return aid


def for_item(pid, scan_id, rec, assessment):
    """One alert per item that needs a look. rec = scanner item record, assessment = wellbeing.assess()."""
    who = _name(pid)
    site = platforms.name(platforms.plat_of(pid))
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
    what = ("reel" if site == "Instagram" else "video") if rec.get("kind") == "reel" else "post"
    title = f"{'High concern' if level == 'high' else 'Worth a look'}: {who}'s {site} feed"
    body = f"A {rec.get('mood', 'mixed')} {what} in {who}'s {site} feed has " + " and ".join(reasons) + "."
    return _emit(pid, level, "item", title, body, f"pages/results.html?id={rec['jobId']}", rec["jobId"], scan_id)


def digest(pid, scan_id, summary):
    if not summary.get("analyzed"):
        return
    who = _name(pid)
    site = platforms.name(platforms.plat_of(pid))
    flagged = len(summary.get("flagged") or [])
    body = " ".join(summary.get("lines") or [])[:300]
    _emit(pid, "watch" if flagged else "info", "digest", f"{site} feed check for {who}: {summary['analyzed']} checked" + (f", {flagged} worth a look" if flagged else ""),
          body, f"pages/feed.html?{_where(pid)}&scan={scan_id}", None, scan_id, notify=False)  # the per-item alerts already pushed


def _where(pid):
    """The profile and site part of a link into the feed page."""
    base, code = platforms.split_key(pid)
    return f"profile={base}&platform={code}"


def needs_login(pid):
    site = platforms.name(platforms.plat_of(pid))
    _emit(pid, "watch", "login", f"Reconnect {site} for {_name(pid)}", f"The saved {site} session expired, so automatic checks are paused. Log in again to resume.", f"pages/feed.html?{_where(pid)}")

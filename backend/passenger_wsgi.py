"""cPanel entry point (Setup Python App: application startup file passenger_wsgi.py, entry point `application`).

Passenger speaks WSGI and this app is ASGI (FastAPI), so a2wsgi bridges the two. A WSGI host never sends the ASGI startup event,
so the database setup, the monitor loop and the model warm-up are started here, once per process.

Settings come from the environment variables of the cPanel app (see DEPLOY_CPANEL.md); these are only the safe defaults."""

import sys
from os import environ
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

environ.setdefault("NL_DEPLOYED", "1")  # nobody is "on the server computer": the owner-only routes need the owner token

try:
    from a2wsgi import ASGIMiddleware  # noqa: E402

    from neurolens.main import app, startup  # noqa: E402

    startup()
    application = ASGIMiddleware(app)
except Exception:  # Passenger only says "could not be started"; keep the real reason where the owner can read it
    import traceback

    _why = traceback.format_exc()
    try:
        (Path(__file__).resolve().parent / "startup_error.log").write_text(_why, encoding="utf-8")
    except OSError:
        pass

    def application(env, start_response):
        # the traceback is only shown on the page while NL_SHOW_ERRORS=1 is set on the cPanel app (it can contain server paths)
        body = (_why if environ.get("NL_SHOW_ERRORS") == "1" else "NeuroLens could not start. See startup_error.log in the backend folder.").encode("utf-8")
        start_response("500 Internal Server Error", [("Content-Type", "text/plain; charset=utf-8"), ("Content-Length", str(len(body)))])
        return [body]

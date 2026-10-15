"""cPanel entry point (Setup Python App: application startup file passenger_wsgi.py, entry point `application`).

Passenger speaks WSGI and this app is ASGI (FastAPI), so a2wsgi bridges the two. A WSGI host never sends the ASGI startup event,
so the database setup, the monitor loop and the model warm-up are started here, once per process.

Settings come from the environment variables of the cPanel app (see DEPLOY_CPANEL.md); these are only the safe defaults."""

import sys
from os import environ
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

environ.setdefault("NL_DEPLOYED", "1")  # nobody is "on the server computer": the owner-only routes need the owner token

from a2wsgi import ASGIMiddleware  # noqa: E402

from neurolens.main import app, startup  # noqa: E402

startup()
application = ASGIMiddleware(app)

# Deploying the backend on cPanel

The backend is a FastAPI app that also serves the website (`frontend/`), so one cPanel Python app is the whole site.

## What to expect

| Feature | cPanel Python app (Passenger) | Own server / VPS with root |
|---|---|---|
| Website, accounts, plans, upload and link analysis, results, history | Works | Works |
| Models (CLIP, CLAP, safety classifier) | Works, **needs about 2 GB of RAM** | Works |
| Instagram sign-in, feed scans, monitoring and alerts | **Switched off** (clean 503) | Works (needs Playwright's browser and a WebSocket proxy) |

Why the Instagram features are off on cPanel: they drive a real Chromium browser and stream it to the page over a WebSocket. Passenger speaks only WSGI, which has no WebSockets, and shared hosting has no Chromium. The routes answer `503 Instagram checks aren't available on this server.` instead of failing halfway.

**Check your plan before starting.** With the models loaded the app measured **1.77 GB** of memory, and the models download **about 1.6 GB**. Many shared plans cap a process at 1 GB, and the process is killed when it goes over. You want about 2.5 GB of RAM for the app and 4 GB of free disk (packages about 1.5 GB, models 1.6 GB). If RAM is tight, set `NL_WARMUP=0` (models load on the first analysis instead of at start), but the peak is the same, so the cap still has to fit it. Ask your host for the per-process memory limit if unsure.

You also need **Python 3.12 or 3.13** in cPanel's Python selector (Linux x86_64).

## Before you start: neurolens.moveneticsdigital.com already answers

When checked, `https://neurolens.moveneticsdigital.com/` showed a bare "Index of /" page and `/api/...` and `/pages/habits.html` returned **500**. So something is already attached to that name and it is broken or empty. Before step 2:

- cPanel > **Setup Python App**: if an app already exists for this domain, open it and note its application root. Either delete it or reuse it (set the same values as step 2 below).
- cPanel > **File Manager**: look in the domain's document root for an old `.htaccess` that mentions Passenger or Python. Rename it to `.htaccess.old`; Setup Python App writes a correct one itself.
- The real error is in `~/neurolens/backend/stderr.log` (or the Passenger log shown next to the app) once the new app is in place.

## Steps

1. **Upload the package.** Build it with `python backend/scripts/build_package.py` (or use `dist/neurolens-cpanel.zip` from this PC). In cPanel > **File Manager**, go to your home folder, upload `neurolens-cpanel.zip` and **Extract** it there. You get `~/neurolens/backend` and `~/neurolens/frontend`. The package already leaves out the virtualenv, `backend/data` (databases, accounts, keys), tests, the Flutter app and your personal export files.
2. **cPanel > Setup Python App > Create Application**
   - Python version: 3.12 (or 3.13)
   - Application root: `neurolens/backend`
   - Application URL: `neurolens.moveneticsdigital.com` (the root of that name)
   - Application startup file: `passenger_wsgi.py`
   - Application Entry point: `application`
3. **Environment variables** (same screen, "Add Variable"):

   | Variable | Value | Why |
   |---|---|---|
   | `NL_DATA_DIR` | `/home/USER/neurolens_data` | Database, thumbnails, accounts, keys. Outside the app folder so a redeploy never wipes it. **Back this folder up.** |
   | `HF_HOME` | `/home/USER/hf_cache` | Where the models are stored. |
   | `NL_WARMUP` | `0` | Optional. Skip loading the models at start (small plans). |
   | `NL_PAYMENTS` | leave unset | `demo` by default: choosing a plan switches it on **without charging anyone**. Real billing is not built. |

   `NL_DEPLOYED=1` is already the default in `passenger_wsgi.py`. It makes the owner-only routes refuse everyone who has no owner token, which is the safe setting because a proxy in front of the app (Apache, LiteSpeed, Cloudflare) can make visitors appear to come from the server itself, and the app would then treat them as the owner.
4. **Install packages.** cPanel shows a line starting with `source /home/USER/virtualenv/...`. Run it in Terminal, then:
   ```
   cd ~/neurolens/backend
   pip install -r requirements-cpanel.txt
   ```
   This uses CPU-only PyTorch and headless OpenCV. Do not use `requirements.txt` here (it pulls the CUDA build of torch, about 2 GB more, and Playwright).
5. **Download the models** once, so no visitor waits on it:
   ```
   python scripts/prefetch_models.py
   ```
6. **Restart** the app (Restart button, or `touch ~/neurolens/backend/tmp/restart.txt`).
7. **Turn on HTTPS** (cPanel > SSL/TLS Status > Run AutoSSL). Sign-in tokens and browser notifications need it.
8. **Check it**, from the server terminal or any machine with `requests`:
   ```
   python scripts/smoke_test.py https://neurolens.moveneticsdigital.com --deployed
   ```
   It signs up a throwaway account, uploads a generated video, waits for the analysis, checks the owner-only routes are closed to the public, and deletes the account. Add `--no-analyze` to skip the model run.

## Updating

Rebuild the package, upload and extract it over `~/neurolens` (choose overwrite), and restart. Never replace `NL_DATA_DIR`. If `requirements-cpanel.txt` changed, run the `pip install` again.

## Owner access

Nobody is "local" on a server, so owner-only routes (for example `/api/feedback/recent`, the list of everyone's analyses) need the owner token. It is created on first use in `NL_DATA_DIR/owner_token.txt`; send it as the header `X-Owner-Token`. Keep it private.

## Limits to know about

- **Analyses are held in memory per process.** The page polls a job id; if your host runs two or more app processes, a poll can land on the other one and report "Unknown or expired job". cPanel normally runs one. If you see this, ask the host for a single process.
- **Upload size** is capped at 300 MB by the app; your host's request-body limit may be lower.
- **Links** from a server's address are often refused: Instagram, TikTok and Facebook commonly block hosting addresses (and YouTube sometimes does), and the app says so in plain words. Uploading a screen recording always works. A successful download of a real TikTok or Facebook video from a server was **not** tested; only the failure handling was.
- Passenger may stop an idle app and start it again on the next visit. Nothing is lost (it is all in `NL_DATA_DIR`); the first request after a stop is slow while the models load.

## On a VPS or dedicated server (untested)

You can also run `python -m uvicorn neurolens.main:app --host 127.0.0.1 --port 8000` as a service behind Apache or Nginx with the WebSocket upgrade passed through, install `requirements.txt` plus `playwright install chromium --with-deps`, and set `NL_DEPLOYED=1`. That is the only way to get the Instagram features online. It was not tried.

## What was tested

- **Everything, before this release:** website unit tests (24), backend unit tests (13), the 27-check server smoke test with a real analysis, 36 page loads in a real browser (desktop and phone, no errors, no missing files, no sideways scrolling), 31 browser checks on the Goals tab, 55 browser checks of a four-platform import and every report, and the whole Flutter suite (138 tests plus a clean analyzer). Reports for Instagram and YouTube built from real exports are byte-identical to the previous version.

- **The package itself:** `dist/neurolens-cpanel.zip` was extracted into an empty folder and run through `passenger_wsgi.py` in a fresh environment built only from `requirements-cpanel.txt`: the 27-check smoke test (real analysis included) and the 31-check browser run of the Goals tab on desktop and phone sizes all passed.

- The app served through `passenger_wsgi.py` with a WSGI server (waitress, on Windows) in deployed mode: all pages, accounts, plans, a real analysis from upload to results, and the owner-only routes closed to the public. 23/23 checks in `scripts/smoke_test.py`.
- `NL_FEED=0` (clean 503s) and `NL_WARMUP=0`.
- A fresh environment built from `requirements-cpanel.txt` alone (no Playwright, no uvicorn) ran the same test: 27/27, and the Instagram routes returned the clean 503.
- Linux wheels exist for every pin on Python 3.12 and 3.13 (checked with pip's cross-platform resolver; `pywebpush`'s `http-ece` is pure Python and builds on install).

**Not tested:** a real cPanel host, Passenger itself, or Linux. The first run there is the real test, which is what `smoke_test.py --deployed` is for.

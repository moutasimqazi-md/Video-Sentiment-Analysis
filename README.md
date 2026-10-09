# NeuroLens — Video Sentiment Analysis

AI that reads the visuals, soundtrack and pacing of a Reel/short video and reports the emotion it makes viewers feel.

```
frontend/                     static site (no build step)
├── index.html · 404.html · site.webmanifest
├── pages/                    import · habits (report) · dashboard · analyze · results · report · family · history · pricing · checkout · login · account · about · privacy · terms
├── css/                      base.css (tokens, layout) · components.css · pages.css · dashboard.css
├── js/
│   ├── core/                 moods · icons (SVG set) · charts (SVG chart library) · analytics (dashboard metrics, demo data)
│   │                         · imports/ (zip reader, parse, habits, themes, store) · store (account, plan, quota, profiles, history) · wellbeing (concern scoring) · api · layout
│   ├── pages/                one script per page
│   └── data/sample.js        built-in sample report (works without the backend)
└── assets/img/               logo.png (source sheet) · logo-mark / logo-full / favicons / app icons / og-image (cut from it)

backend/                      FastAPI service
├── neurolens/                main.py (API + serves frontend) · analyzer · audio_analyzer · downloader · logstore
├── scripts/                  run_server.bat · run_ngrok.bat (+ hidden .vbs launchers)
├── data/                     SQLite log, embeddings, thumbnails, restart logs (git-ignored)
└── requirements.txt
```

## Run
```
cd backend
python -m venv .venv
.venv\Scripts\pip install -r requirements.txt
scripts\run_server.bat        # http://localhost:8000  (serves the frontend and /api, auto-restarts on crash)
scripts\run_ngrok.bat         # public tunnel to :8000 (auto-restarts)
```
`run_server_hidden.vbs` / `run_ngrok_hidden.vbs` start the same loops with no window. Two shortcuts in the Windows Startup folder
(`VideoSentimentServer.lnk`, `VideoSentimentNgrok.lnk`) launch them at login, so the site comes back after a reboot.
The public URL is the ngrok account's static domain (`https://absurd-chasing-deflector.ngrok-free.dev`).
Restart/crash logs go to `backend/data/*_restarts.log`.

Without the backend, open `frontend/index.html` and use "See sample report" to preview the results page.

## The analysis engine (backend)
Videos and images are scored on what the camera sees; sound is a supporting signal (20%), captions play no part in a result.
- **Frames:** 12–40 frames per video, each scored as three square views (start/middle/end of a tall frame) so vertical Reels aren't cropped to their centre. Images get the same treatment. `neurolens/analyzer.py`.
- **Learns from your ratings:** every "Spot on" / correction becomes a labelled example; the engine blends per-mood averages of those examples into its scores and rebuilds after each rating (`neurolens/calibration.py`; ~64% → ~73% accuracy in leave-one-out tests). `GET /api/model/info` shows whether it's active.
- **Evidence:** each result carries a confidence level (clear / leaning / mixed), up to four key-moment frames (`/api/keyframes/{job}/{n}.jpg`) and a visual check for revealing or suggestive footage with the flagged frame (`neurolens/safety.py`). The check is strict, so everyday dance or swimwear footage can trip it; it flags for a human to look, it does not call anything explicit. Violence, weapons and drugs are not detected.
- **Images:** `.jpg`, `.jpeg`, `.png`, `.webp` upload through the same `/api/analyze` and return `kind: "image"` (no timeline or audio).
- **Background queue:** the site runs analyses in the background (`js/core/jobs.js`, tray in the header), so you can add up to 10 links or files and keep browsing.
- Offline experiments live in `backend/eval/` (`pip install -r backend/requirements-dev.txt`).

## Feed check, account review and child monitoring
`pages/feed.html` (sidebar: Feed check). Sign in to Instagram once inside a **private browser shown in the page** (like the isolated-browser step in savv-mvp; no new window or tab): an isolated headless Chrome with its own profile in `backend/data/sessions/` is streamed to a canvas over a WebSocket (Chrome screencast, `backend/neurolens/live.py`, `frontend/js/core/browserview.js`) and your clicks and typing are sent back. Your password goes straight to Instagram. Then run a check: **Explore**, **For You reels**, **search topics**, or an **Account review** of the account's own posts. Everything found goes through the same engine and produces a short report.
- It reads what Instagram *serves* that account, not what was watched. For You scrolling counts as viewing those reels.
- **Child monitoring:** needs a consent confirmation (stored with a date), runs on a schedule (30 min to daily, explore grid only), only checks items it has not seen, and raises alerts for heavy-tone or revealing content, plus a digest per check. The child profile shows "Monitoring on". No hidden mode.
- **Alerts:** the bell in the header (unread count, list, mark read) plus browser push notifications through a service worker (`frontend/sw.js`, VAPID keys in `backend/data/`), so they arrive even when the site is closed. Turn them on from the bell.
- **Owner lock:** these routes work with no setup on the computer running the server. Other devices (the public ngrok address, a phone) connect once through a single-use link made on that computer (Feed check > Use on another device, valid 10 minutes). A request that comes through the proxy without that pairing is refused.
- Code: `backend/neurolens/{live,browser,scanner,monitor,monitorstore,alerts,push,guard,wellbeing,feed_api}.py`, `frontend/js/pages/feed.js`, `js/core/{owner,notify}.js`. Instagram's page layout changes; the selectors in `browser.py` read links, not styling, but may need a tweak if Instagram changes its routes.
- Tests use a fake Instagram (`NL_IG_BASE=http://localhost:8765`, `NL_BROWSER_HEADLESS=1`).

## Design system
Light-first theme (dark mode via the header toggle) with tokens in `css/base.css`: coral/blue palette, Inter + Plus Jakarta Sans, an AA-contrast `--coral-ink` for text, spacing scale, shadows and a focus ring. Icons are inline SVG (`js/core/icons.js`, use `<i data-icon="name">`). Sections fade in on scroll (`.reveal`) and respect `prefers-reduced-motion`.

## Import your Instagram & YouTube history
`pages/import.html` reads Instagram's "Download your information" ZIP and Google Takeout (YouTube) ZIPs, folders or loose JSON/CSV files **in the browser** (nothing is uploaded; messages and personal details are never opened). `pages/habits.html` turns each platform into its own separate habits report (Instagram and YouTube are never combined into one score; a previous combined report is split automatically): a 0–100 score and verdict with transparent rules, when/how much charts, content themes (keyword estimate from captions and titles), an optional video check of a sample of links through the analyzer, a browsable item list, CSV and print.
- Code: `js/core/zip.js` (streaming ZIP reader, ZIP64), `js/core/imports/` (`parse.js` adapters, `habits.js` analysis + judgement, `themes.js` + `js/data/lexicon.js`, `store.js` IndexedDB + localStorage).
- Instagram exports only about 7 days of watched reels; likes can go back a year. YouTube history has titles and channels but no watch time. Both are stated in the UI.
- Personal exports are git-ignored (`*.zip`, `instagram-*/`, `Takeout/`). Never commit them.

## Accessibility
Targets WCAG 2.2 AA. All text meets 4.5:1 contrast (tokens in `css/base.css`; white-on-coral buttons use the darker `--grad-text`). Every chart has a text alternative and a "View data as a table" fallback; controls expose `aria-pressed` / `aria-expanded` / `aria-current`; the upgrade dialog and mobile menu trap and restore focus; dashboard changes are announced through a live region; `prefers-reduced-motion` is honoured; no page scrolls horizontally at 320px. The axe-core audit reports zero violations on every page in light, dark and mobile.

## Use cases
1. **Self-analysis** — paste an Instagram Reel link (or upload a recording) → results page → "Download report (PDF)" (print view). Log in to keep history.
2. **Parent monitoring** — Family page: add child profiles, analyze Reels under their profile, get a concern alert when a Reel's tone is heavy, and a 7-day report.

## Notes
- **Wellbeing signal is tone-based.** It weights the sad / depressed / heartbroken / lost / angry / tired scores (thresholds in `js/core/wellbeing.js`). It cannot detect explicit, violent or self-harm content, and it cannot read captions, comments or Instagram watch history — Reels must be supplied as links or recordings.
- **Alerts are in-app only.** Email/push alerts need server-side accounts.
- **Subscription is a front-end demo.** Plans, quota (5 / 100 / 500 analyses per month), history and login are stored in the browser's localStorage, and checkout takes no payment. Real billing needs a payment provider (e.g. Stripe) plus server-side accounts and quota enforcement.
- Plan limits (monthly quota, child profiles) are enforced on the client only.

"""Download the three models once (about 1.6 GB into the Hugging Face cache) and prove they load.

    python scripts/prefetch_models.py

Run it on the server, from the app's virtualenv, before the first visit: the first analysis then doesn't wait on a download that
a web request would time out on. It uses the app's own warm-up, so it fetches exactly what the app needs. HF_HOME moves the cache."""

import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from neurolens import analyzer  # noqa: E402

start = time.time()
analyzer.warm_up()  # CLIP, the safety classifier and the CLAP audio model
print(f"models ready in {time.time() - start:.0f}s")

"""Test setup. Runs before any test module imports the app, so tests use a throwaway data folder (never backend/data) and a sign-in
browser that needs no visible window."""
import atexit
import os
import shutil
import tempfile

_data = tempfile.mkdtemp(prefix="nl_test_data_")
os.environ["NL_DATA_DIR"] = _data
os.environ["NL_LIVE_HEADLESS"] = "1"
atexit.register(lambda: shutil.rmtree(_data, ignore_errors=True))

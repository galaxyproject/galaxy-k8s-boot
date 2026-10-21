"""Briefly cache Rainstone's Batch pause state; failures admit jobs."""

import json
import threading
import time
import urllib.request
from pathlib import Path

_lock = threading.Lock()
_cached = (0.0, False)
TOKEN_FILE = Path('/galaxy/server/config/rainstone-dispatch/token')
ENDPOINT = 'http://rainstone:8000/api/internal/batch-dispatch'
CACHE_SECONDS = 5
TIMEOUT_SECONDS = 2


def paused():
    global _cached
    now = time.monotonic()
    if now < _cached[0]:
        return _cached[1]
    with _lock:
        if time.monotonic() < _cached[0]:
            return _cached[1]
        value = False
        try:
            token = TOKEN_FILE.read_text().strip()
            if token:
                request = urllib.request.Request(ENDPOINT, headers={'Authorization': 'Bearer ' + token})
                with urllib.request.urlopen(request, timeout=TIMEOUT_SECONDS) as response:
                    answer = json.loads(response.read(1024))
                    value = answer.get('paused') is True
        except (OSError, ValueError, TypeError, AttributeError):
            # A report/control service outage must not prevent Galaxy use.
            pass
        _cached = (time.monotonic() + CACHE_SECONDS, value)
        return value

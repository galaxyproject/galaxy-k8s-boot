"""The TPV pause check must bound latency and admit jobs on failures."""
import importlib.util
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

path = Path(__file__).resolve().parents[1] / 'roles/galaxy_k8s_deployment/files/rainstone_guard.py'
spec = importlib.util.spec_from_file_location('rainstone_guard', path)
guard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guard)


class GuardTests(unittest.TestCase):
    def setUp(self):
        guard._cached = (0, False)
        self.token = patch.object(guard, 'TOKEN_FILE', MagicMock(read_text=lambda: 'test-token'))
        self.token.start()
        self.addCleanup(self.token.stop)

    def test_pause_is_cached_and_expires(self):
        response = MagicMock()
        response.__enter__.return_value.read.return_value = b'{"paused":true}'
        with patch.object(guard.urllib.request, 'urlopen', return_value=response) as request:
            with patch.object(guard.time, 'monotonic', return_value=10):
                self.assertTrue(guard.paused())
                self.assertTrue(guard.paused())
                self.assertEqual(request.call_count, 1)
            response.__enter__.return_value.read.return_value = b'{"paused":false}'
            with patch.object(guard.time, 'monotonic', return_value=16):
                self.assertFalse(guard.paused())
                self.assertEqual(request.call_count, 2)
            self.assertEqual(request.call_args.kwargs['timeout'], 2)

    def test_outage_and_malformed_response_admit_jobs(self):
        with patch.object(guard.urllib.request, 'urlopen', side_effect=TimeoutError):
            self.assertFalse(guard.paused())
        for answer in (b'bad json', b'[]', b'{"paused":"true"}'):
            guard._cached = (0, False)
            response = MagicMock()
            response.__enter__.return_value.read.return_value = answer
            with patch.object(guard.urllib.request, 'urlopen', return_value=response):
                self.assertFalse(guard.paused())

    def test_absent_credential_admits_without_network(self):
        with patch.object(guard.TOKEN_FILE, 'read_text', side_effect=FileNotFoundError):
            with patch.object(guard.urllib.request, 'urlopen') as request:
                self.assertFalse(guard.paused())
                request.assert_not_called()

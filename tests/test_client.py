import contextlib
from http.server import BaseHTTPRequestHandler, HTTPServer
import io
import json
from pathlib import Path
import tempfile
import threading
import unittest
from unittest.mock import patch

from tools import pageturner


class ClientTests(unittest.TestCase):
    def setUp(self):
        self.requests = []
        requests = self.requests

        class Handler(BaseHTTPRequestHandler):
            def do_POST(self):
                requests.append((self.path, self.headers.get("Authorization"),
                                 self.rfile.read(int(self.headers.get("Content-Length", 0)))))
                status = 202 if self.path == "/next" else 409
                body = b"accepted next request=1\n" if status == 202 else b"Reader not ready\n"
                self.send_response(status)
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, *args):
                pass

        self.server = HTTPServer(("127.0.0.1", 0), Handler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.port = self.server.server_port
        self.token = "a" * 48

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()

    def test_next_sends_one_bodyless_authenticated_post_and_times_ack(self):
        record = pageturner.send_command("127.0.0.1", self.port, self.token, "next")
        self.assertTrue(record["accepted"])
        self.assertEqual(record["status"], 202)
        self.assertGreaterEqual(record["round_trip_ms"], 0)
        self.assertEqual(self.requests, [("/next", "Bearer " + self.token, b"")])
        self.assertNotIn(self.token, json.dumps(record))

    def test_failure_response_is_not_retried(self):
        record = pageturner.send_command("127.0.0.1", self.port, self.token, "back")
        self.assertFalse(record["accepted"])
        self.assertEqual(record["status"], 409)
        self.assertEqual(len(self.requests), 1)

    def test_network_failure_reports_unknown_outcome_without_retry(self):
        with patch.object(pageturner.http.client, "HTTPConnection") as connection:
            connection.return_value.getresponse.side_effect = TimeoutError("timed out")
            record = pageturner.send_command("127.0.0.1", self.port, self.token, "next")
            self.assertEqual(connection.return_value.request.call_count, 1)
            connection.return_value.close.assert_called_once()
        self.assertFalse(record["accepted"])
        self.assertIn("unknown", record["outcome"])
        self.assertIsNone(record["status"])

    def test_invalid_command_or_token_never_connects(self):
        with self.assertRaises(ValueError):
            pageturner.send_command("127.0.0.1", self.port, self.token, "delete")
        with self.assertRaises(ValueError):
            pageturner.send_command("127.0.0.1", self.port, "bad\r\nHeader: x", "next")
        self.assertEqual(self.requests, [])

    def test_cli_logs_json_and_returns_success(self):
        with tempfile.TemporaryDirectory() as directory:
            token_file = Path(directory) / "token"
            token_file.write_text(self.token)
            log = Path(directory) / "timing.jsonl"
            stdout = io.StringIO()
            with contextlib.redirect_stdout(stdout):
                result = pageturner.main(["next", "--host", "127.0.0.1", "--port", str(self.port),
                                         "--token-file", str(token_file), "--log", str(log)])
            self.assertEqual(result, 0)
            self.assertEqual(json.loads(log.read_text()), json.loads(stdout.getvalue()))
            self.assertNotIn(self.token, log.read_text())

    def test_configuration_contains_only_port_and_is_not_overwritten(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "pageturner.koplugin").mkdir()
            with patch.object(pageturner, "ROOT", root):
                with contextlib.redirect_stdout(io.StringIO()) as stdout:
                    pageturner.configure(8088)
                config = root / "pageturner.koplugin" / "config.lua"
                self.assertEqual(config.read_text(), "return { port = 8088 }\n")
                self.assertIn("in-memory bearer token", stdout.getvalue())
                self.assertEqual(config.stat().st_mode & 0o777, 0o600)
                with self.assertRaises(ValueError):
                    pageturner.configure(8088)
                self.assertEqual(config.read_text(), "return { port = 8088 }\n")


if __name__ == "__main__":
    unittest.main()

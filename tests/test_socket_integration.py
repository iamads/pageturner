"""Optional: PAGETURNER_SOCKET_TESTS=1 python3 -m unittest discover -s tests.
Requires luajit and LuaSocket in its module path; no Kindle is emulated.
"""
import os
from pathlib import Path
import select
import socket
import subprocess
import unittest

from tools.pageturner import send_command


@unittest.skipUnless(os.environ.get("PAGETURNER_SOCKET_TESTS") == "1", "optional LuaSocket integration")
class SocketIntegrationTests(unittest.TestCase):
    def setUp(self):
        self.process = subprocess.Popen(
            ["luajit", "tests/socket_server.lua"], cwd=Path(__file__).resolve().parent.parent,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        )
        self.addCleanup(self.cleanup)
        ready, _, _ = select.select([self.process.stdout], [], [], 5)
        self.assertTrue(ready, "Lua server did not start")
        line = self.process.stdout.readline()
        if not line:
            self.fail("Lua server failed: " + self.process.stderr.read())
        self.port = int(line)
        self.token = "a" * 48

    def cleanup(self):
        self.process.terminate()
        self.process.communicate(timeout=5)

    def connect(self):
        return socket.create_connection(("127.0.0.1", self.port), timeout=3)

    @staticmethod
    def read_all(connection):
        chunks = []
        while True:
            chunk = connection.recv(4096)
            if not chunk:
                return b"".join(chunks)
            chunks.append(chunk)

    def test_twenty_alternating_requests_and_unauthorized_rejection(self):
        rejected = send_command("127.0.0.1", self.port, "b" * 48, "next")
        self.assertEqual(rejected["status"], 401)
        for number in range(1, 21):
            command = "next" if number % 2 else "back"
            result = send_command("127.0.0.1", self.port, self.token, command)
            self.assertEqual(result["status"], 202)
            self.assertEqual(result["response"], f"accepted {command} request={number}")

    def test_fragmented_request_and_slow_client_do_not_block_other_commands(self):
        with self.connect() as slow:
            slow.sendall(b"POST /next HTTP/1.1\r\n")
            result = send_command("127.0.0.1", self.port, self.token, "back")
            self.assertEqual(result["status"], 202)
            slow.sendall(f"Authorization: Bearer {self.token}\r\nContent-Length: 0\r\n\r\n".encode())
            response = self.read_all(slow)
            self.assertIn(b"202 Accepted", response)
            self.assertIn(b"accepted next request=2", response)

    def test_oversized_header_and_get_are_rejected(self):
        with self.connect() as connection:
            connection.sendall(b"x" * 4096)
            self.assertIn(b"431", self.read_all(connection))
        with self.connect() as connection:
            connection.sendall(f"GET /next HTTP/1.1\r\nAuthorization: Bearer {self.token}\r\n\r\n".encode())
            self.assertIn(b"405", self.read_all(connection))


if __name__ == "__main__":
    unittest.main()

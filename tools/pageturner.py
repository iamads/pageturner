#!/usr/bin/env python3
"""Configure the plugin and send one page-turn command, without automatic retries."""
import argparse
from datetime import datetime, timezone
import http.client
import json
import os
from pathlib import Path
import re
import sys
import time

ROOT = Path(__file__).resolve().parent.parent
TOKEN_FILE = ROOT / ".pageturner-token"


def configure(port):
    config = ROOT / "pageturner.koplugin" / "config.lua"
    if config.exists():
        raise ValueError("Configuration already exists; refusing to replace it.")
    fd = os.open(config, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w") as file:
        file.write(f"return {{ port = {port} }}\n")
    print(f"Created {config}.")
    print("The Kindle generates a new in-memory bearer token on each manual start.")
    print("Copy pageturner.koplugin to your Kindle's koreader/plugins directory.")


def send_command(host, port, token, command, timeout=3):
    """RTT includes TCP connection setup and the complete acknowledgement body.

    202 means accepted, not rendered. A timeout has an unknown outcome: never retry
    automatically, because the page might already have turned.
    """
    if command not in ("next", "back"):
        raise ValueError("Command must be next or back")
    if not re.fullmatch(r"[A-Za-z0-9_-]{32,128}", token):
        raise ValueError("Invalid token format")
    record = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "host": host, "port": port, "command": command,
        "status": None, "accepted": False,
    }
    connection = http.client.HTTPConnection(host, port, timeout=timeout)
    start = time.perf_counter()
    try:
        connection.request("POST", "/" + command, body=b"", headers={
            "Authorization": "Bearer " + token,
            "Connection": "close",
        })
        response = connection.getresponse()
        body = response.read(1024).decode("utf-8", errors="replace").strip()
        record.update(status=response.status, accepted=response.status == 202, response=body)
    except (OSError, http.client.HTTPException) as error:
        record.update(error=str(error), outcome="unknown; inspect Kindle before retrying")
    finally:
        record["round_trip_ms"] = round((time.perf_counter() - start) * 1000, 3)
        connection.close()
    return record


def port_number(value):
    value = int(value)
    if not 1024 <= value <= 65535:
        raise argparse.ArgumentTypeError("port must be between 1024 and 65535")
    return value


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    setup = commands.add_parser("configure", help="generate the plugin port configuration")
    setup.add_argument("--port", type=port_number, default=8088)
    for name in ("next", "back"):
        command = commands.add_parser(name)
        command.add_argument("--host", required=True, help="Kindle Wi-Fi IPv4 address")
        command.add_argument("--port", type=port_number, default=8088)
        command.add_argument("--token-file", type=Path, default=TOKEN_FILE)
        command.add_argument("--timeout", type=float, default=3)
        command.add_argument("--log", type=Path, help="append timing records as JSON lines")
    args = parser.parse_args(argv)
    try:
        if args.command == "configure":
            configure(args.port)
            return 0
        if args.timeout <= 0:
            raise ValueError("timeout must be positive")
        token = args.token_file.read_text().strip()
        record = send_command(args.host, args.port, token, args.command, args.timeout)
        line = json.dumps(record)
        print(line)
        if args.log:
            with args.log.open("a") as file:
                file.write(line + "\n")
        return 0 if record["accepted"] else 1
    except (OSError, ValueError) as error:
        print(f"Error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())

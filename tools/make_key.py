#!/usr/bin/env python3
"""Issue and verify Project X licence keys.

The algorithm is shared with the iOS app (Discord/Discord/engine/LicenseGate.swift)
and the website (website/app.js):

    X-YYYYMMDD-PAYLOAD-CHECK
    CHECK = SHA256("zada-license-v1|YYYYMMDD|PAYLOAD")[:4].upper()

Generate a key and send the string to another person. The app binds it to the
first iPhone that activates it, and the expiry date is embedded in the key.
"""

import argparse
import hashlib
import secrets
import string
from datetime import date, datetime, timedelta, timezone

SALT = "zada-license-v1"
ALPHABET = string.ascii_uppercase + string.digits


def checksum(date_text: str, payload: str) -> str:
    return hashlib.sha256(f"{SALT}|{date_text}|{payload}".encode()).hexdigest()[:4].upper()


def issue(days: int) -> str:
    expiry = datetime.now(timezone.utc).date() + timedelta(days=days)
    date_text = expiry.strftime("%Y%m%d")
    payload = "".join(secrets.choice(ALPHABET) for _ in range(8))
    return f"X-{date_text}-{payload}-{checksum(date_text, payload)}"


def verify(key: str) -> str:
    key = key.strip().upper()
    parts = key.split("-")
    if len(parts) != 4 or parts[0] != "X":
        return "rejected (bad format)"
    _, date_text, payload, provided = parts
    if len(date_text) != 8 or len(payload) != 8 or len(provided) != 4:
        return "rejected (bad length)"
    if checksum(date_text, payload) != provided:
        return "rejected (bad checksum)"
    try:
        expiry = datetime.strptime(date_text, "%Y%m%d").replace(tzinfo=timezone.utc).date()
    except ValueError:
        return "unreadable_response"
    if expiry <= datetime.now(timezone.utc).date():
        return f"expired ({expiry.isoformat()})"
    return f"valid · granted until {expiry.isoformat()}"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("days", nargs="?", type=int, default=1,
                        help="days the key stays valid (default: 1)")
    parser.add_argument("--count", type=int, default=1, help="how many keys")
    parser.add_argument("--check", metavar="KEY", help="verify a key instead")
    args = parser.parse_args()

    if args.check:
        print(f"{args.check}\n  -> {verify(args.check)}")
        return
    if args.days < 1:
        parser.error("days must be positive")

    for _ in range(args.count):
        key = issue(args.days)
        print(f"{key}\n  -> {verify(key)}")


if __name__ == "__main__":
    main()

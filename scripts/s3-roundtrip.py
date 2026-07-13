#!/usr/bin/env python3
"""Minimal SigV4 S3 round-trip check (stdlib only): create bucket, PUT an object,
GET it back, verify the body. Used by image smoke tests to prove a gateway
actually serves object storage. Usage:

    s3-roundtrip.py <endpoint> <access-key> <secret-key> [region]

Exits 0 on a successful round-trip, non-zero (with a message) otherwise.
"""
import datetime
import hashlib
import hmac
import sys
import urllib.error
import urllib.request


def _sign(key, msg):
    return hmac.new(key, msg.encode(), hashlib.sha256).digest()


def _request(method, endpoint, bucket, key, access, secret, region, body=b""):
    host = endpoint.split("://", 1)[1]
    path = "/" + bucket + ("/" + key if key else "")
    service = "s3"
    now = datetime.datetime.now(datetime.timezone.utc)
    amzdate = now.strftime("%Y%m%dT%H%M%SZ")
    datestamp = now.strftime("%Y%m%d")
    payload_hash = hashlib.sha256(body).hexdigest()

    canonical_headers = (
        f"host:{host}\n"
        f"x-amz-content-sha256:{payload_hash}\n"
        f"x-amz-date:{amzdate}\n"
    )
    signed_headers = "host;x-amz-content-sha256;x-amz-date"
    # Path-style, no query: canonical URI is the (encoded) path, canonical query empty.
    canonical_request = "\n".join(
        [method, path, "", canonical_headers, signed_headers, payload_hash]
    )
    scope = f"{datestamp}/{region}/{service}/aws4_request"
    string_to_sign = "\n".join(
        [
            "AWS4-HMAC-SHA256",
            amzdate,
            scope,
            hashlib.sha256(canonical_request.encode()).hexdigest(),
        ]
    )
    k_date = _sign(("AWS4" + secret).encode(), datestamp)
    k_region = _sign(k_date, region)
    k_service = _sign(k_region, service)
    k_signing = _sign(k_service, "aws4_request")
    signature = hmac.new(
        k_signing, string_to_sign.encode(), hashlib.sha256
    ).hexdigest()
    authorization = (
        f"AWS4-HMAC-SHA256 Credential={access}/{scope}, "
        f"SignedHeaders={signed_headers}, Signature={signature}"
    )

    req = urllib.request.Request(endpoint + path, data=body or None, method=method)
    req.add_header("Host", host)
    req.add_header("x-amz-date", amzdate)
    req.add_header("x-amz-content-sha256", payload_hash)
    req.add_header("Authorization", authorization)
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            return resp.status, resp.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()


def main():
    if len(sys.argv) < 4:
        print("usage: s3-roundtrip.py <endpoint> <access-key> <secret-key> [region]")
        return 2
    endpoint, access, secret = sys.argv[1:4]
    region = sys.argv[4] if len(sys.argv) > 4 else "us-east-1"
    bucket, key, body = "smoke-bucket", "hello.txt", b"versitygw round-trip ok"

    status, resp = _request("PUT", endpoint, bucket, "", access, secret, region)
    if status not in (200, 204):
        print(f"create bucket failed: HTTP {status}: {resp[:300]!r}")
        return 1
    status, resp = _request(
        "PUT", endpoint, bucket, key, access, secret, region, body
    )
    if status not in (200, 204):
        print(f"put object failed: HTTP {status}: {resp[:300]!r}")
        return 1
    status, resp = _request("GET", endpoint, bucket, key, access, secret, region)
    if status != 200:
        print(f"get object failed: HTTP {status}: {resp[:300]!r}")
        return 1
    if resp != body:
        print(f"body mismatch: sent {body!r}, got {resp!r}")
        return 1
    print("round-trip ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())

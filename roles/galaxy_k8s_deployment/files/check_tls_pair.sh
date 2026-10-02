#!/bin/sh
# Validate a TLS certificate and private key before handing them to the ingress
# controller:
#
#   check_tls_pair.sh CERT_FILE KEY_FILE
#
# Each file holds PEM, or base64-encoded PEM (how a value may arrive through
# instance metadata). Exit 0 and print the certificate's subject, subject
# alternative names and expiry when the certificate parses, the key parses, the
# key belongs to the certificate and the certificate is currently valid. Exit 1
# with the reason on stderr otherwise, exit 2 on usage errors.
#
# nginx silently keeps its own certificate when the configured one is unusable,
# which would leave a client that validates the connection failing with no clue
# on the server side; failing here gives the reason at deploy time instead.
set -eu

if [ $# -ne 2 ]; then
    echo "usage: $0 CERT_FILE KEY_FILE" >&2
    exit 2
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# Leave PEM alone; decode anything else as base64. Either way the result must
# be PEM for openssl to parse it below. openssl does the decoding because the
# base64 utility's flags differ between GNU (-d) and BSD/macOS (-D); whitespace
# is stripped first so wrapped and single-line input both work with -A.
decode() {
    if grep -q -- '-----BEGIN' "$1"; then
        cat "$1"
    else
        tr -d '\n\r\t ' < "$1" | openssl base64 -d -A 2>/dev/null || true
    fi
}
decode "$1" > "$work/cert.pem"
decode "$2" > "$work/key.pem"

if ! openssl x509 -in "$work/cert.pem" -noout 2>/dev/null; then
    echo "certificate does not parse as PEM X.509 (or base64 of it)" >&2
    exit 1
fi
if ! openssl pkey -in "$work/key.pem" -noout 2>/dev/null; then
    echo "private key does not parse as PEM (or base64 of it)" >&2
    exit 1
fi
cert_pub=$(openssl x509 -in "$work/cert.pem" -noout -pubkey)
key_pub=$(openssl pkey -in "$work/key.pem" -pubout 2>/dev/null)
if [ "$cert_pub" != "$key_pub" ]; then
    echo "private key does not match the certificate" >&2
    exit 1
fi
if ! openssl x509 -in "$work/cert.pem" -noout -checkend 0 >/dev/null 2>&1; then
    echo "certificate has expired ($(openssl x509 -in "$work/cert.pem" -noout -enddate))" >&2
    exit 1
fi

# Check notBefore as well as notAfter. Trust the supplied leaf for this check:
# the launcher's issuer need not be installed in the VM's system trust store.
if ! validity=$(openssl verify -partial_chain -trusted "$work/cert.pem" "$work/cert.pem" 2>&1); then
    echo "certificate is not currently valid: $validity" >&2
    exit 1
fi

# RFC 2253 keeps the subject format stable across OpenSSL versions (3.0 prints
# "CN = x" by default, 3.6 "CN=x").
openssl x509 -in "$work/cert.pem" -noout -subject -nameopt RFC2253 -enddate
openssl x509 -in "$work/cert.pem" -noout -ext subjectAltName 2>/dev/null | sed -n '2s/^ *//p'

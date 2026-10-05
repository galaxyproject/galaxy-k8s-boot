#!/bin/sh
# Validate the CA certificate (or chain) the ingress controller will verify
# client certificates against:
#
#   check_ca_cert.sh CA_FILE
#
# The file holds one or more PEM certificates, or base64-encoded PEM (how a
# value may arrive through instance metadata). Exit 0 and print each
# certificate's subject, expiry and CA flag when every certificate parses and is
# currently valid. Exit 1 with the reason on stderr otherwise, exit 2 on usage
# errors. A certificate without the CA flag is accepted (nginx takes any
# certificate as a trust anchor) and reported as CA:FALSE so the operator can
# see it.
#
# nginx fails to start, or silently ignores the setting, when the CA file is
# unusable; failing here gives the reason at deploy time instead.
set -eu

if [ $# -ne 1 ]; then
    echo "usage: $0 CA_FILE" >&2
    exit 2
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# Leave PEM alone; decode anything else as base64 (openssl rather than the
# base64 utility, whose flags differ between GNU and BSD/macOS).
if grep -q -- '-----BEGIN' "$1"; then
    cat "$1" > "$work/ca.pem"
else
    tr -d '\n\r\t ' < "$1" | openssl base64 -d -A > "$work/ca.pem" 2>/dev/null || true
fi

# Split the bundle into one file per certificate.
awk -v dir="$work" '
    /-----BEGIN CERTIFICATE-----/ { n++; out = dir "/cert" n ".pem" }
    out { print > out }
    /-----END CERTIFICATE-----/ { close(out); out = "" }
' "$work/ca.pem"

count=$(ls "$work"/cert*.pem 2>/dev/null | wc -l | tr -d ' ')
if [ "$count" -eq 0 ]; then
    echo "CA certificate does not parse as PEM X.509 (or base64 of it)" >&2
    exit 1
fi

for cert in "$work"/cert*.pem; do
    if ! openssl x509 -in "$cert" -noout 2>/dev/null; then
        echo "CA certificate does not parse as PEM X.509 (or base64 of it)" >&2
        exit 1
    fi
    if ! openssl x509 -in "$cert" -noout -checkend 0 >/dev/null 2>&1; then
        echo "CA certificate has expired ($(openssl x509 -in "$cert" -noout -enddate))" >&2
        exit 1
    fi
    # Check notBefore as well as notAfter. Trust the certificate for this check:
    # the launcher's CA need not be installed in the VM's system trust store.
    if ! validity=$(openssl verify -partial_chain -trusted "$cert" "$cert" 2>&1); then
        echo "CA certificate is not currently valid: $validity" >&2
        exit 1
    fi
    # RFC 2253 keeps the subject format stable across OpenSSL versions.
    openssl x509 -in "$cert" -noout -subject -nameopt RFC2253 -enddate
    if openssl x509 -in "$cert" -noout -ext basicConstraints 2>/dev/null | grep -q 'CA:TRUE'; then
        echo "CA:TRUE"
    else
        echo "CA:FALSE"
    fi
done

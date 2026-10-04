#!/bin/sh
# Fails if any networking API appears in the sources. macrecord must never send data anywhere.
set -eu
cd "$(dirname "$0")/.."
PATTERN='URLSession|NSURLConnection|NWConnection|NWListener|import Network|CFSocket|CFStream|(^|[^A-Za-z_])(socket|connect)\(|getaddrinfo|WKWebView|Sparkle|URLRequest|NSURLRequest|curl_'
if grep -rEn "$PATTERN" Sources; then
    echo "error: networking API found in Sources/ (see above). macrecord must stay offline." >&2
    exit 1
fi
echo "OK: no networking APIs in Sources/"

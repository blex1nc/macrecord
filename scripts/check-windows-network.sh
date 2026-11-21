#!/bin/sh
# The Windows app may reach the network only for the opt-out update check in UpdateChecker.cs, and only GitHub.
set -eu
cd "$(dirname "$0")/.."
PATTERN='HttpClient|WebClient|WebRequest|Socket|TcpClient|UdpClient|WebSocket|HttpListener'
OFFENDERS=$(grep -rlE "$PATTERN" windows/src --include='*.cs' | grep -v 'windows/src/Macrecord.Windows/UpdateChecker.cs' || true)
if [ -n "$OFFENDERS" ]; then
    echo "error: networking API outside UpdateChecker.cs:" >&2
    echo "$OFFENDERS" >&2
    exit 1
fi
HOSTS=$(grep -oE 'https?://[A-Za-z0-9.-]+' windows/src/Macrecord.Windows/UpdateChecker.cs | sort -u)
for host in $HOSTS; do
    case "$host" in
        https://api.github.com|https://github.com) ;;
        *) echo "error: unexpected host in UpdateChecker.cs: $host" >&2; exit 1 ;;
    esac
done
echo "OK: Windows network access limited to the GitHub update check"

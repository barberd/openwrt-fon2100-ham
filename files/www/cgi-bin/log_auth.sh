#!/bin/sh
# /www/cgi-bin/log_auth.sh
# Logs callsign, returns 1x1 transparent GIF

CALLSIGN=$(echo "$QUERY_STRING" | sed -n 's/.*callsign=\([^&]*\).*/\1/p' | tr 'a-z' 'A-Z')

logger -t hamradio "CONNECT: callsign=$CALLSIGN ip=$REMOTE_ADDR"

echo "Content-Type: image/gif"
echo ""
printf 'GIF89a\x01\x00\x01\x00\x80\x00\x00\xff\xff\xff\x00\x00\x00!\xf9\x04\x00\x00\x00\x00\x00,\x00\x00\x00\x00\x01\x00\x01\x00\x00\x02\x02D\x01\x00;'

#!/usr//bin/env bash

CURL=$(command -v curl) || exit 1
TOKEN=" " # Token of the Telegram bot

CHATID="$1"
TEXT=" $2"

if [[ -z $CHATID ]] || [[ -z $TEXT ]]; then
  exit 1
fi

${CURL} \
  -X "POST" \
  -H 'Content-Type: application/x-www-form-urlencoded; charset=utf-8' \
  --data-urlencode "chat_id=${CHATID}" \
  --data-urlencode "text=${TEXT}" \
  --data-urlencode "disable_web_page_preview=true" \
  --data-urlencode "parse_mode=markdown" \
  --silent --output /dev/null "https://api.telegram.org/bot${TOKEN}/sendMessage"

exit $?

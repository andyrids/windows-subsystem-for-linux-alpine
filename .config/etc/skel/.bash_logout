# ~/.bash_logout executed by bash(1) when login shell exits
reset
echo
echo "executing: apk cache clean" && doas apk cache clean 2>/dev/null
echo "executing: history -c && history -w" && history -c && history -w 2>/dev/null || true
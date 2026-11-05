#!/bin/zsh
# game.exe가 켜질 때까지 기다렸다가, 꺼질 때까지 20초마다 스레드별 CPU를 기록한다.
OUT="${1:-$HOME/Games/thread-samples}"
mkdir -p "$OUT"; rm -f "$OUT"/*.txt
until P=$(pgrep -f "/game.exe" | head -1); [ -n "$P" ]; do sleep 2; done
echo "game pid $P started $(date +%T)" > "$OUT/info.txt"
i=0
while kill -0 "$P" 2>/dev/null; do
  i=$((i+1)); f="$OUT/$(printf %03d $i)"
  date +%T > "$f-ps.txt"; ps -M -p "$P" >> "$f-ps.txt" 2>/dev/null
  sample "$P" 2 -mayDie -file "$f-sample.txt" >/dev/null 2>&1
  sleep 18
done
echo "game exited $(date +%T), $i samples" >> "$OUT/info.txt"

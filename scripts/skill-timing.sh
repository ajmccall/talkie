#!/bin/zsh
# Measures how long a Claude Code skill run takes, split into CLI boot and
# API time, with the exact flags Talkie uses. Each run makes one tiny API
# call on your subscription, so run it by hand, not in CI.
#
#   scripts/skill-timing.sh            # haiku and sonnet, cold and pre-warmed
#   MODELS="haiku" RUNS=1 scripts/skill-timing.sh
#
# "cold" is `claude -p` launched with the prompt on stdin, as Talkie did
# before 0.3.0. "warm" launches the CLI in stream-json mode, waits 4 s (the
# boot overlaps the recording in Talkie), then sends the prompt; the time
# reported is from sending the prompt to exit, which is what the user waits.
set -u
export CLAUDE_CODE_DISABLE_CLAUDE_MDS=1 CLAUDE_CODE_DISABLE_AUTO_MEMORY=1 DISABLE_AUTOUPDATER=1 NO_COLOR=1
unset ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN ANTHROPIC_BASE_URL ANTHROPIC_PROFILE
MODELS=${MODELS:-"haiku sonnet"}
RUNS=${RUNS:-3}
SCHEMA='{"type":"object","properties":{"text":{"type":"string"}},"required":["text"],"additionalProperties":false}'
SYSTEM='You are a text transformation engine. Follow the instructions in the message, use no tools, and reply with only the JSON object the response schema requires.'
PROMPT='Return the transcript with filler words removed: {"transcript":"um so yeah the deploy is uh basically done"}'
COMMON=(-p --json-schema "$SCHEMA" --system-prompt "$SYSTEM" --effort low
        --tools "" --disallowedTools 'mcp__*' --strict-mcp-config
        --disable-slash-commands --no-session-persistence --permission-prompts none)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

now() { date +%s.%N }
elapsed() { printf '%.2f' $(echo "$2 - $1" | bc) }
# "inside=<duration_ms> api=<duration_api_ms>" from a result event: time the CLI
# spent from receiving the prompt to the result, and the API share of it.
inside() { python3 -c 'import json,sys; o=json.load(sys.stdin); print("inside=%.2fs api=%.2fs" % (o.get("duration_ms",0)/1000, o.get("duration_api_ms",0)/1000))' 2>/dev/null }

s=$(now); claude --version >/dev/null 2>&1; e=$(now)
echo "claude --version (process boot only): $(elapsed $s $e)s"

for model in ${=MODELS}; do
for run in $(seq $RUNS); do
  s=$(now)
  echo "$PROMPT" | claude "${COMMON[@]}" --output-format json --model "$model" >"$WORK/cold.out" 2>"$WORK/cold.err"
  e=$(now)
  text=$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("structured_output",{}).get("text","<none>"))' <"$WORK/cold.out" 2>/dev/null)
  echo "cold  $model: $(elapsed $s $e)s  $(inside <"$WORK/cold.out")  -> ${text:-<failed: $(tail -c 300 "$WORK/cold.out" "$WORK/cold.err" | tr '\n' ' ')>}"

  fifo="$WORK/in.$model"; mkfifo "$fifo"
  claude "${COMMON[@]}" --input-format stream-json --output-format stream-json --verbose --model "$model" \
    <"$fifo" >"$WORK/warm.out" 2>"$WORK/warm.err" &
  pid=$!
  exec 3>"$fifo"
  sleep 4
  s=$(now)
  printf '{"type":"user","message":{"role":"user","content":%s}}\n' "$(printf '%s' "$PROMPT" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')" >&3
  exec 3>&-
  # The session stays alive after stdin closes, so stop at the result event
  # (Talkie does the same) rather than waiting for exit.
  until grep -q '"type":"result"' "$WORK/warm.out" || ! kill -0 $pid 2>/dev/null; do sleep 0.05; done
  e=$(now)
  kill $pid 2>/dev/null; wait $pid 2>/dev/null
  text=$(grep '"type":"result"' "$WORK/warm.out" | tail -1 | python3 -c 'import json,sys; print(json.load(sys.stdin).get("structured_output",{}).get("text","<none>"))' 2>/dev/null)
  echo "warm  $model: $(elapsed $s $e)s  $(grep '"type":"result"' "$WORK/warm.out" | tail -1 | inside)  -> ${text:-<failed: $(tail -c 300 "$WORK/warm.out" "$WORK/warm.err" | tr '\n' ' ')>}"
  rm -f "$fifo" "$WORK/warm.out" "$WORK/warm.err"
done
done

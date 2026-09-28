"""Web chat UI for the Goose Town BMAD crew.

Serves a chat page and a POST /api/chat endpoint. Each message the board types is
treated as a *crew goal*: the server runs the BMAD crew recipe
(recipes/04-bmad-crew.yaml) with `--params goal=<message>`, which spawns the five
BMAD delegates (analyst -> pm -> architect -> dev -> qa) as their own goose
subagent sessions. They broadcast on the shared Town Wall and light up the
Goose Town map.

Guardrail: the crew recipe is READ-ONLY (every delegate's GitHub MCP runs with
--read-only and the Developer delegate plans but never writes), and this server
also exports GITHUB_READ_ONLY=1 as defence-in-depth, so a board prompt can never
trigger an unintended GitHub write.

The final reply is captured from stdout; the goose wrapper's telepathy/wall lines
go to stderr and are ignored.
"""
import json
import os
import re
import subprocess
from datetime import datetime

from starlette.applications import Starlette
from starlette.responses import HTMLResponse, JSONResponse
from starlette.routing import Route

WALL_FILE = os.environ.get("GOOSE_GTWALL_FILE", os.path.expanduser("~/.goosetown/walls/wall.log"))
# The crew recipe each chat goal drives. Overridable for testing.
CREW_RECIPE = os.environ.get("GOOSE_CHAT_RECIPE", "/recipes/04-bmad-crew.yaml")
# A five-delegate crew can take a while on the local Ollama; give it room.
RUN_TIMEOUT = int(os.environ.get("GOOSE_CHAT_TIMEOUT", "1800"))


def post_to_wall(sender: str, message: str) -> None:
    """Append a line to the shared Town Wall so the goosetown dashboard sees it.

    Wall line format is `<HH:MM:SS>|<sender_id>|<message>` (see parse_wall_line
    in goosetown-ui). Single-line message only (no embedded newlines).
    """
    try:
        safe_msg = message.replace("\n", " ").replace("|", "\\|")
        ts = datetime.now().strftime("%H:%M:%S")
        line = f"{ts}|{sender}|{safe_msg}"
        os.makedirs(os.path.dirname(WALL_FILE), exist_ok=True)
        with open(WALL_FILE, "a", encoding="utf-8") as f:
            f.write(line + "\n")
    except OSError:
        pass  # wall is best-effort; the chat reply still returns

INDEX_HTML = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Goose Town — BMAD Crew</title>
<style>
  :root { --bg:#1A1210; --panel:#2D2118; --accent:#B87333; --text:#FFFDD0; }
  * { box-sizing: border-box; }
  body { margin:0; font-family:'JetBrains Mono',monospace; background:var(--bg); color:var(--text); height:100vh; display:flex; flex-direction:column; }
  header { padding:14px 20px; background:var(--panel); color:var(--accent); font-size:20px; }
  #log { flex:1; overflow-y:auto; padding:20px; display:flex; flex-direction:column; gap:12px; }
  .msg { max-width:72%; padding:10px 14px; border-radius:10px; white-space:pre-wrap; line-height:1.45; }
  .user { align-self:flex-end; background:#3D2B1F; }
  .agent { align-self:flex-start; background:var(--panel); border:1px solid #4a3424; }
  .sys  { align-self:center; color:#8a7a6a; font-size:12px; }
  form { display:flex; gap:8px; padding:14px; background:var(--panel); }
  input { flex:1; padding:12px; background:#1A1210; border:1px solid #4a3424; color:var(--text); border-radius:8px; font-family:inherit; font-size:15px; }
  button { padding:12px 18px; background:var(--accent); color:#1A1210; border:none; border-radius:8px; cursor:pointer; font-weight:bold; }
  button:disabled { opacity:.5; cursor:default; }
  .spinner { align-self:flex-start; color:#8a7a6a; }
</style>
</head>
<body>
<header>🦆 Goose Town — BMAD Crew &nbsp;<span style="font-size:12px;color:#8a7a6a">type a goal → watch the geese move on the map</span></header>
<div id="log"></div>
<form id="f">
  <input id="i" autocomplete="off" placeholder="Give the crew a goal, e.g. “Add a /healthz endpoint to the sample service”…" />
  <button id="b" type="submit">Run crew</button>
</form>
<script>
const log = document.getElementById('log');
const input = document.getElementById('i');
const btn = document.getElementById('b');
let session = null;

function add(cls, text) {
  const d = document.createElement('div');
  d.className = 'msg ' + cls;
  d.textContent = text;
  log.appendChild(d);
  log.scrollTop = log.scrollHeight;
}

async function send() {
  const text = input.value.trim();
  if (!text) return;
  input.value = '';
  add('user', text);
  const sp = document.createElement('div');
  sp.className = 'msg spinner';
  sp.textContent = '…';
  log.appendChild(sp);
  btn.disabled = true;
  try {
    const r = await fetch('/api/chat', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ message: text, session }),
    });
    const j = await r.json();
    session = j.session;
    sp.remove();
    if (j.error) add('sys', '⚠ ' + j.error);
    else add('agent', j.reply || '(no response)');
  } catch (e) {
    sp.remove();
    add('sys', '⚠ ' + e);
  } finally {
    btn.disabled = false;
    input.focus();
  }
}
document.getElementById('f').addEventListener('submit', (e) => { e.preventDefault(); send(); });
</script>
</body>
</html>
"""


def run_goose(message: str, session: str | None) -> dict:
    """Run the BMAD crew for one goal.

    Each chat message is an independent crew goal: we launch the conductor recipe
    (which spawns the five BMAD delegates) as a fresh named session so the map
    shows one conductor + its delegates per run. `session` is not resumed — a
    crew run is one-shot — but we echo it back so the UI can label the thread.
    """
    env = dict(os.environ)
    # Defence-in-depth guardrail: force the GitHub MCP read-only for every
    # delegate spawned by this run (on top of --read-only in the recipes).
    env["GITHUB_READ_ONLY"] = "1"

    name = f"bmad-conductor-{datetime.now().strftime('%H%M%S')}"
    cmd = [
        "goose", "run", "--name", name,
        "--recipe", CREW_RECIPE,
        "--params", f"goal={message}",
        "--quiet",
    ]
    # The human's goal onto the wall first, so the dashboard shows the ask.
    post_to_wall("board", message)
    try:
        proc = subprocess.run(
            cmd, capture_output=True, text=True, timeout=RUN_TIMEOUT, env=env,
        )
    except subprocess.TimeoutExpired:
        return {"session": name, "error": f"crew run timed out (>{RUN_TIMEOUT}s)"}

    reply = (proc.stdout or "").strip()
    if proc.returncode != 0 and not reply:
        return {"session": name, "error": (proc.stderr or "unknown error").strip()[-500:]}

    # Reflect the conductor's summary onto the shared Town Wall.
    post_to_wall("bmad-conductor", reply)
    return {"session": name, "reply": reply}


async def chat_page(request):
    return HTMLResponse(INDEX_HTML)


async def api_chat(request):
    try:
        body = await request.json()
    except Exception:
        return JSONResponse({"error": "invalid JSON"}, status_code=400)
    message = (body.get("message") or "").strip()
    session = body.get("session") or None
    if not message:
        return JSONResponse({"error": "empty message"}, status_code=400)
    result = await run_in_thread(run_goose, message, session)
    return JSONResponse(result)


async def run_in_thread(fn, *args):
    import asyncio
    return await asyncio.to_thread(fn, *args)


app = Starlette(
    routes=[
        Route("/", chat_page),
        Route("/api/chat", api_chat, methods=["POST"]),
    ]
)


if __name__ == "__main__":
    import argparse

    import uvicorn

    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=4250)
    args = parser.parse_args()
    uvicorn.run(app, host=args.host, port=args.port, log_level="warning")

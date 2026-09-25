"""Minimal web chat UI for goose.

Serves a chat page and a POST /api/chat endpoint that drives `goose run` with
session resume (`--name` / `--resume`) so the conversation is multi-turn and can
survive the agent asking for choices.

The response is captured from stdout; the goose wrapper's telepathy/wall lines
go to stderr and are ignored.
"""
import json
import os
import re
import subprocess

from starlette.applications import Starlette
from starlette.responses import HTMLResponse, JSONResponse
from starlette.routing import Route

INDEX_HTML = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Goose Chat</title>
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
<header>🦆 Goose Chat</header>
<div id="log"></div>
<form id="f">
  <input id="i" autocomplete="off" placeholder="Ask goose something…" />
  <button id="b" type="submit">Send</button>
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
    env = dict(os.environ)
    cmd = ["goose", "run", "--text", message, "--quiet"]
    if session:
        cmd = ["goose", "run", "--resume", "--name", session, "--text", message, "--quiet"]
    else:
        cmd = ["goose", "run", "--name", "webchat", "--text", message, "--quiet"]
        session = "webchat"
    try:
        proc = subprocess.run(
            cmd, capture_output=True, text=True, timeout=600, env=env,
        )
    except subprocess.TimeoutExpired:
        return {"session": session, "error": "goose run timed out (>10 min)"}

    reply = (proc.stdout or "").strip()
    # The wrapper writes telepathy/wall chatter to stderr; pull the session id if printed.
    m = re.search(r"(\d{8}_\d+)", proc.stderr or "")
    if not session or session == "webchat":
        if m:
            session = m.group(1)
    if proc.returncode != 0 and not reply:
        return {"session": session, "error": (proc.stderr or "unknown error").strip()[-500:]}
    return {"session": session, "reply": reply}


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

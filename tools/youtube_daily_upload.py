#!/usr/bin/env python3
"""
Daily Minion Lord VS Minion Lord video generator & YouTube Data API v3 uploader.

Usage:
  1) Authenticate once (after placing Google Cloud OAuth client_secret.json):
       python tools/youtube_daily_upload.py --auth
  2) Generate & render today's MP4 only (no upload):
       python tools/youtube_daily_upload.py --render-only
  3) Full daily pipeline (pick/simulate -> render 60fps MP4 -> upload to YouTube):
       python tools/youtube_daily_upload.py
     Optional overrides:
       --red 滾石 --blue 奇美拉 --privacy public
"""

from __future__ import annotations

import argparse
import base64
import datetime as dt
import hashlib
import http.server
import json
import os
import secrets
import shutil
import subprocess
import sys
import time
import urllib.parse
import webbrowser
from pathlib import Path

import requests

YOUTUBE_SCOPE = "https://www.googleapis.com/auth/youtube.upload https://www.googleapis.com/auth/youtube"
TOKEN_URL = "https://oauth2.googleapis.com/token"
AUTH_URL = "https://accounts.google.com/o/oauth2/v2/auth"
UPLOAD_INIT_URL = "https://www.googleapis.com/upload/youtube/v3/videos"
VIDEOS_API_URL = "https://www.googleapis.com/youtube/v3/videos"

PROJECT_DIR = Path(__file__).resolve().parent.parent
OUT_DIR = PROJECT_DIR / "recordings" / "daily_yt"
DEFAULT_SECRETS_DIR = Path.home() / ".gemini" / "yt_oauth"


def find_godot_exe() -> str:
    found = shutil.which("godot_console") or shutil.which("godot_console.exe") or shutil.which("godot")
    if found:
        return found
    winget = Path.home() / "AppData/Local/Microsoft/WinGet/Links/godot_console.exe"
    if winget.exists():
        return str(winget)
    raise FileNotFoundError("Cannot find godot_console.exe in PATH or WinGet Links.")


def load_client_config(secrets_dir: Path) -> dict:
    secret_path = secrets_dir / "client_secret.json"
    if not secret_path.exists():
        raise FileNotFoundError(
            f"Missing OAuth client file: {secret_path}\n"
            "Please download your Desktop App OAuth JSON from Google Cloud Console "
            f"(YouTube Data API v3) and save it as:\n  {secret_path}"
        )
    data = json.loads(secret_path.read_text(encoding="utf-8"))
    cfg = data.get("installed") or data.get("web")
    if not cfg or "client_id" not in cfg or "client_secret" not in cfg:
        raise ValueError(f"Invalid OAuth client_secret.json format at {secret_path}")
    return cfg


def run_oauth_login(secrets_dir: Path) -> Path:
    cfg = load_client_config(secrets_dir)
    secrets_dir.mkdir(parents=True, exist_ok=True)
    token_path = secrets_dir / "token.json"

    verifier = secrets.token_urlsafe(64)
    challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode("ascii")).digest()).rstrip(b"=").decode("ascii")
    state = secrets.token_urlsafe(24)

    result: dict[str, str] = {}

    class CallbackHandler(http.server.BaseHTTPRequestHandler):
        def do_GET(self) -> None:
            parsed = urllib.parse.urlparse(self.path)
            qs = urllib.parse.parse_qs(parsed.query)
            if qs.get("state", [""])[0] != state:
                self.send_response(400)
                self.end_headers()
                self.wfile.write(b"Invalid OAuth state.")
                return
            if "error" in qs:
                result["error"] = qs["error"][0]
                self.send_response(400)
                self.end_headers()
                self.wfile.write(f"OAuth failed: {result['error']}".encode("utf-8"))
                return
            if "code" in qs:
                result["code"] = qs["code"][0]
                self.send_response(200)
                self.send_header("Content-Type", "text/html; charset=utf-8")
                self.end_headers()
                self.wfile.write(
                    "<html><body><h2>YouTube 授權完成！可以關閉這個視窗並回到終端機。</h2></body></html>".encode("utf-8")
                )

        def log_message(self, format: str, *args: object) -> None:
            return

    server = http.server.HTTPServer(("127.0.0.1", 0), CallbackHandler)
    port = server.server_address[1]
    redirect_uri = f"http://127.0.0.1:{port}/"

    params = urllib.parse.urlencode(
        {
            "client_id": cfg["client_id"],
            "redirect_uri": redirect_uri,
            "response_type": "code",
            "scope": YOUTUBE_SCOPE,
            "access_type": "offline",
            "prompt": "consent",
            "code_challenge": challenge,
            "code_challenge_method": "S256",
            "state": state,
        }
    )
    auth_url = f"{AUTH_URL}?{params}"
    print(f"Opening browser for YouTube OAuth consent:\n{auth_url}\n", flush=True)
    webbrowser.open(auth_url)

    deadline = time.time() + 600
    server.timeout = 1.0
    while "code" not in result and "error" not in result and time.time() < deadline:
        server.handle_request()
    server.server_close()

    if "error" in result:
        raise RuntimeError(f"OAuth authorization error: {result['error']}")
    if "code" not in result:
        raise TimeoutError("Timed out waiting for Google OAuth browser callback.")

    resp = requests.post(
        TOKEN_URL,
        data={
            "code": result["code"],
            "client_id": cfg["client_id"],
            "client_secret": cfg["client_secret"],
            "redirect_uri": redirect_uri,
            "grant_type": "authorization_code",
            "code_verifier": verifier,
        },
        timeout=30,
    )
    resp.raise_for_status()
    tok = resp.json()
    tok["expires_at"] = int(time.time()) + int(tok.get("expires_in", 3600)) - 60
    token_path.write_text(json.dumps(tok, indent=2), encoding="utf-8")
    print(f"Saved YouTube OAuth token to: {token_path}")
    return token_path


def get_valid_access_token(secrets_dir: Path) -> str:
    cfg = load_client_config(secrets_dir)
    token_path = secrets_dir / "token.json"
    if not token_path.exists():
        raise FileNotFoundError(
            f"Missing OAuth token: {token_path}\n"
            "Run once interactively first:\n  python tools/youtube_daily_upload.py --auth"
        )
    tok = json.loads(token_path.read_text(encoding="utf-8"))
    if tok.get("access_token") and time.time() < float(tok.get("expires_at", 0)):
        return tok["access_token"]
    refresh = tok.get("refresh_token")
    if not refresh:
        raise RuntimeError("No refresh_token found in token.json; re-run with --auth.")

    resp = requests.post(
        TOKEN_URL,
        data={
            "client_id": cfg["client_id"],
            "client_secret": cfg["client_secret"],
            "refresh_token": refresh,
            "grant_type": "refresh_token",
        },
        timeout=30,
    )
    resp.raise_for_status()
    fresh = resp.json()
    tok["access_token"] = fresh["access_token"]
    tok["expires_at"] = int(time.time()) + int(fresh.get("expires_in", 3600)) - 60
    if "refresh_token" in fresh:
        tok["refresh_token"] = fresh["refresh_token"]
    token_path.write_text(json.dumps(tok, indent=2), encoding="utf-8")
    return tok["access_token"]


def generate_duel(godot_exe: str, date_str: str, red: str, blue: str, out_dir: Path, seed: int | None, night: bool = False) -> dict:
    out_dir.mkdir(parents=True, exist_ok=True)
    history_path = out_dir / "history.json"
    cmd = [
        godot_exe,
        "--headless",
        "--path",
        str(PROJECT_DIR),
        "-s",
        "tools/minion_duel_gen.gd",
        "--",
        f"--date={date_str}",
        f"--out-dir={out_dir}",
        f"--history={history_path}",
    ]
    if red:
        cmd.append(f"--red={red}")
    if blue:
        cmd.append(f"--blue={blue}")
    if seed is not None:
        cmd.append(f"--seed={seed}")
    if night:
        cmd.append("--night")

    proc = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace", check=True)
    meta_path = None
    for line in proc.stdout.splitlines():
        print(line, flush=True)
        if line.startswith("META_JSON: "):
            meta_path = Path(line.split("META_JSON: ", 1)[1].strip())
    if not meta_path or not meta_path.exists():
        raise RuntimeError(f"minion_duel_gen.gd did not report META_JSON.\nSTDOUT:\n{proc.stdout}\nSTDERR:\n{proc.stderr}")
    return json.loads(meta_path.read_text(encoding="utf-8"))


def render_mp4(godot_exe: str, meta: dict) -> Path:
    replay_path = Path(meta["replay_path"])
    mp4_path = Path(meta["mp4_path"])
    raw_avi = replay_path.with_name(replay_path.stem + "_raw.avi")
    ps1 = PROJECT_DIR / "tools" / "export_movie.ps1"
    cmd = [
        "powershell.exe",
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        str(ps1),
        "-GodotExe",
        godot_exe,
        "-ProjectDir",
        str(PROJECT_DIR),
        "-ReplayPath",
        str(replay_path),
        "-RawAvi",
        str(raw_avi),
        "-Mp4Path",
        str(mp4_path),
        "-NoOpen",
    ]
    print(f"Rendering 60fps MP4 -> {mp4_path} ...", flush=True)
    subprocess.run(cmd, check=True)
    if not mp4_path.exists():
        raise RuntimeError(f"Expected MP4 not created at {mp4_path}")
    return mp4_path


def upload_to_youtube(access_token: str, mp4_path: Path, meta: dict, privacy: str) -> str:
    file_size = mp4_path.stat().st_size
    body = {
        "snippet": {
            "title": meta["title"],
            "description": meta["description"],
            "tags": meta.get("tags", []),
            "categoryId": "20",  # Gaming
            "defaultLanguage": "zh-TW",
        },
        "status": {
            "privacyStatus": privacy,
            "selfDeclaredMadeForKids": False,
        },
    }
    init_resp = requests.post(
        f"{UPLOAD_INIT_URL}?uploadType=resumable&part=snippet,status",
        headers={
            "Authorization": f"Bearer {access_token}",
            "Content-Type": "application/json; charset=UTF-8",
            "X-Upload-Content-Length": str(file_size),
            "X-Upload-Content-Type": "video/mp4",
        },
        data=json.dumps(body, ensure_ascii=False).encode("utf-8"),
        timeout=30,
    )
    init_resp.raise_for_status()
    upload_url = init_resp.headers["Location"]

    chunk_size = 8 * 1024 * 1024  # 8 MB aligned chunks
    with mp4_path.open("rb") as fh:
        offset = 0
        while offset < file_size:
            chunk = fh.read(chunk_size)
            end = offset + len(chunk) - 1
            up_resp = requests.put(
                upload_url,
                headers={
                    "Authorization": f"Bearer {access_token}",
                    "Content-Length": str(len(chunk)),
                    "Content-Type": "video/mp4",
                    "Content-Range": f"bytes {offset}-{end}/{file_size}",
                },
                data=chunk,
                timeout=120,
            )
            if up_resp.status_code in (200, 201):
                video_id = up_resp.json()["id"]
                return f"https://youtu.be/{video_id}"
            if up_resp.status_code == 308:
                offset += len(chunk)
                print(f"Uploaded {offset}/{file_size} bytes ({offset * 100 // file_size}%)", flush=True)
                continue
            up_resp.raise_for_status()
    raise RuntimeError("Upload finished without receiving YouTube video ID.")


def set_video_privacy(access_token: str, video_id: str, privacy: str) -> dict:
    resp = requests.put(
        f"{VIDEOS_API_URL}?part=status",
        headers={"Authorization": f"Bearer {access_token}", "Content-Type": "application/json; charset=UTF-8"},
        json={"id": video_id, "status": {"privacyStatus": privacy, "selfDeclaredMadeForKids": False}},
        timeout=30,
    )
    resp.raise_for_status()
    return resp.json()


def delete_video(access_token: str, video_id: str) -> None:
    resp = requests.delete(
        f"{VIDEOS_API_URL}?id={video_id}",
        headers={"Authorization": f"Bearer {access_token}"},
        timeout=30,
    )
    resp.raise_for_status()


def record_history(out_dir: Path, meta: dict, video_url: str) -> None:
    history_path = out_dir / "history.json"
    hist = {"pairs": [], "recent_lords": [], "uploads": []}
    if history_path.exists():
        try:
            hist = json.loads(history_path.read_text(encoding="utf-8"))
        except Exception:
            pass
    a, b = meta["red_lord"], meta["blue_lord"]
    pair = f"{a}|{b}" if a < b else f"{b}|{a}"
    hist.setdefault("pairs", []).append(pair)
    hist.setdefault("recent_lords", []).extend([a, b])
    hist.setdefault("uploads", []).append(
        {
            "date": meta["date"],
            "pair": pair,
            "title": meta["title"],
            "url": video_url,
            "mp4": meta["mp4_path"],
        }
    )
    history_path.write_text(json.dumps(hist, indent=2, ensure_ascii=False), encoding="utf-8")


def main() -> int:
    ap = argparse.ArgumentParser(description="Daily Minion Lord VS Minion Lord YouTube uploader")
    ap.add_argument("--auth", action="store_true", help="Run one-time browser OAuth setup")
    ap.add_argument("--render-only", action="store_true", help="Generate replay & MP4 without uploading")
    ap.add_argument("--red", default="", help="Red minion lord id or name")
    ap.add_argument("--blue", default="", help="Blue minion lord id or name")
    ap.add_argument("--date", default=dt.date.today().strftime("%Y%m%d"), help="YYYYMMDD date key")
    ap.add_argument("--seed", type=int, default=None, help="Optional fixed RNG seed")
    ap.add_argument("--night", action="store_true", help="Find a late-night decisive match (>= 6:50)")
    ap.add_argument("--publish", default="", help="Set privacy=public on an existing YouTube video ID")
    ap.add_argument("--delete", nargs="*", default=[], help="Delete existing YouTube video IDs")
    ap.add_argument("--privacy", default="public", choices=["public", "unlisted", "private"])
    ap.add_argument("--out-dir", default=str(OUT_DIR))
    ap.add_argument("--secrets-dir", default=str(DEFAULT_SECRETS_DIR))
    args = ap.parse_args()

    secrets_dir = Path(args.secrets_dir)
    if args.auth:
        run_oauth_login(secrets_dir)
        return 0

    if args.publish or args.delete:
        token = get_valid_access_token(secrets_dir)
        if args.publish:
            res = set_video_privacy(token, args.publish, "public")
            print(f"UPDATED {args.publish}: status={res.get('status', {})}")
        for vid in args.delete:
            delete_video(token, vid)
            print(f"DELETED {vid}")
        return 0

    godot_exe = find_godot_exe()
    out_dir = Path(args.out_dir)
    meta = generate_duel(godot_exe, args.date, args.red, args.blue, out_dir, args.seed, args.night)
    mp4_path = render_mp4(godot_exe, meta)
    print(f"MP4 READY: {mp4_path}")

    if args.render_only:
        return 0

    token = get_valid_access_token(secrets_dir)
    video_url = upload_to_youtube(token, mp4_path, meta, args.privacy)
    record_history(out_dir, meta, video_url)
    print(f"UPLOADED TO YOUTUBE ({args.privacy}): {video_url}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)

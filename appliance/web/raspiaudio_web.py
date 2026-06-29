#!/usr/bin/env python3
import argparse
import html
import json
import os
import pathlib
import subprocess
import sys
import tempfile
import urllib.parse
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


MODES = [
    {
        "id": "usb_7_1_to_8out",
        "title": "PC USB 7.1 to 8 analog outputs",
        "body": "Default safe passthrough. Use this first to prove every output.",
        "requires": ["analog_out"],
    },
    {
        "id": "toslink_stereo",
        "title": "PC USB front L/R to optical TOSLINK stereo",
        "body": "Routes the USB front left/right channels to the Pi 5 GPIO12 optical output.",
        "requires": ["toslink"],
    },
    {
        "id": "active_crossover_3way",
        "title": "Stereo active crossover to 8 outputs",
        "body": "Open miniDSP-style preset with safe gain, crossover, PEQ and delay placeholders.",
        "requires": ["analog_out"],
    },
    {
        "id": "analog_input_monitor",
        "title": "8 analog inputs monitor/test",
        "body": "For RASPIAUDIO 8xIN+8xOUT only. Routes ADC inputs to analog outputs for lab checks.",
        "hardware": ["8xin8xout"],
        "requires": ["analog_in", "analog_out"],
    },
]

LAB_MODE_FILE = pathlib.Path("/etc/raspiaudio/lab-mode")
VERSION_FILE = pathlib.Path("/etc/raspiaudio/version")

REQUIREMENT_LABELS = {
    "analog_out": "8 analog outputs not detected",
    "analog_in": "8 analog inputs not detected",
    "toslink": "TOSLINK output not detected",
}


def health_command():
    env_cmd = os.environ.get("RASPIAUDIO_HEALTH_CMD")
    if env_cmd:
        return [env_cmd]
    installed = pathlib.Path("/usr/local/sbin/raspiaudio-health")
    if installed.exists():
        return [str(installed)]
    local = pathlib.Path(__file__).resolve().parent.parent / "bin" / "raspiaudio-health"
    if local.exists():
        return [sys.executable, str(local)]
    return [str(installed)]


def run_command(args, timeout=20):
    try:
        completed = subprocess.run(
            args,
            check=False,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=timeout,
        )
        return {
            "ok": completed.returncode == 0,
            "returncode": completed.returncode,
            "output": completed.stdout[-8000:],
        }
    except Exception as exc:
        return {"ok": False, "returncode": -1, "output": str(exc)}


def start_lab_update():
    log_path = "/var/log/raspiaudio-lab-update.log"
    try:
        subprocess.Popen(
            [
                "/bin/bash",
                "-lc",
                f"sleep 1; /usr/local/sbin/raspiaudio-dev-update fast >{log_path} 2>&1",
            ],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
        return {
            "ok": True,
            "returncode": 0,
            "output": (
                "Lab update started from GitHub. "
                "Refresh this page after 30 seconds. "
                f"Log: {log_path}"
            ),
        }
    except Exception as exc:
        return {"ok": False, "returncode": -1, "output": str(exc)}


def load_status():
    result = run_command(["/usr/local/sbin/raspiaudio-mode", "status-json"], timeout=5)
    if not result["ok"]:
        return {
            "hardware": "unknown",
            "active_mode": "unknown",
            "active_mode_label": "Unknown",
            "sample_rate": "48000",
            "current_config": "",
            "camilladsp": "unknown",
            "camillagui": "unknown",
            "spdif_present": False,
            "error": result["output"],
        }
    try:
        return json.loads(result["output"])
    except json.JSONDecodeError:
        return {"error": result["output"]}


def load_health():
    result = run_command([*health_command(), "--json"], timeout=8)
    if not result["ok"]:
        return {"status": "unknown", "checks": [], "error": result["output"]}
    try:
        return json.loads(result["output"])
    except json.JSONDecodeError:
        return {"status": "unknown", "checks": [], "error": result["output"]}


def read_body(handler):
    length = int(handler.headers.get("Content-Length", "0") or "0")
    raw = handler.rfile.read(length).decode("utf-8", errors="replace")
    ctype = handler.headers.get("Content-Type", "")
    if "application/json" in ctype:
        return json.loads(raw or "{}")
    parsed = urllib.parse.parse_qs(raw)
    return {key: values[-1] for key, values in parsed.items()}


def check_ok_map(health):
    checks = {}
    for check in health.get("checks", []):
        checks[str(check.get("key", ""))] = bool(check.get("ok", False))
    return checks


def check_by_key(health):
    checks = {}
    for check in health.get("checks", []):
        key = str(check.get("key", ""))
        if key:
            checks[key] = check
    return checks


def load_version():
    candidates = [
        VERSION_FILE,
        pathlib.Path(__file__).resolve().parent.parent / "VERSION",
    ]
    for path in candidates:
        try:
            if path.exists():
                value = path.read_text(encoding="utf-8").strip()
                if value:
                    return value
        except OSError:
            pass
    return "unknown"


def hardware_label(status):
    hardware = str(status.get("hardware", "unknown"))
    if hardware == "8xin8xout":
        return "8xIN+8xOUT detected"
    if hardware == "8xout":
        return "8xOUT detected"
    return "Hardware not detected"


def status_level(ok, fallback="warning"):
    return "ok" if ok else fallback


def mode_availability(mode, status, health):
    hardware = str(status.get("hardware", "unknown"))
    supported_hardware = mode.get("hardware")
    if supported_hardware and hardware not in supported_hardware:
        return "hidden", f"Requires {', '.join(supported_hardware)}"

    checks = check_ok_map(health)
    missing = []
    for requirement in mode.get("requires", []):
        ok = bool(checks.get(requirement, False))
        if requirement == "toslink":
            ok = ok or bool(status.get("spdif_present", False))
        if not ok:
            missing.append(REQUIREMENT_LABELS.get(requirement, requirement))

    if missing:
        return "disabled", "; ".join(missing)
    return "enabled", ""


def render_page():
    health = load_health()
    status = health.get("mode") if isinstance(health.get("mode"), dict) else load_status()
    active = status.get("active_mode", "")
    camilla = status.get("camilladsp", "unknown")
    health_status = health.get("status", "unknown")
    version = load_version()
    checks_ok = check_ok_map(health)
    checks_by_key = check_by_key(health)

    hardware_ok = checks_ok.get("hardware_autodetect", False)
    analog_out_ok = checks_ok.get("analog_out", False)
    usb_ok = (
        checks_ok.get("g_audio", False)
        and checks_ok.get("usb_link_state", False)
        and checks_ok.get("uac2_capture", False)
    )
    audio_test_ok = analog_out_ok and camilla == "active"

    usb_message = "Connected to computer" if usb_ok else "Plug the USB data cable"
    hardware_message = hardware_label(status)
    audio_message = "Ready to test OUT1 to OUT8" if audio_test_ok else "Audio test is not ready yet"

    def step_card(number, title, message, ok, action_html=""):
        level = status_level(ok)
        return f"""
        <article class="step {level}">
          <div class="step-index">{number}</div>
          <div>
            <span>{'OK' if ok else 'CHECK'}</span>
            <h2>{html.escape(title)}</h2>
            <p>{html.escape(message)}</p>
            {action_html}
          </div>
        </article>
        """

    restart_usb_button = '<button data-action="restart-usb" class="secondary">Restart USB</button>'
    output_buttons = "".join(
        f'<button data-output="{idx}">OUT{idx}</button>' for idx in range(1, 9)
    )

    recommended = MODES[0]
    recommended_availability, recommended_reason = mode_availability(recommended, status, health)
    recommended_disabled = recommended_availability != "enabled"
    recommended_selected = active == recommended["id"]
    if recommended_disabled:
        recommended_button = '<button disabled>Unavailable</button>'
    elif recommended_selected:
        recommended_button = '<button data-mode="usb_7_1_to_8out">Use this mode</button>'
    else:
        recommended_button = '<button data-mode="usb_7_1_to_8out">Use this mode</button>'
    recommended_reason_html = (
        f'<small>{html.escape(recommended_reason)}</small>' if recommended_reason else ""
    )

    advanced_cards = []
    for mode in MODES[1:]:
        availability, reason = mode_availability(mode, status, health)
        if availability == "hidden":
            continue
        selected = " selected" if mode["id"] == active else ""
        disabled = availability == "disabled"
        disabled_class = " disabled" if disabled else ""
        reason_html = (
            f'<small>{html.escape(reason)}</small>'
            if reason
            else ""
        )
        if disabled:
            button_html = '<button disabled>Unavailable</button>'
        else:
            button_html = f'<button data-mode="{html.escape(mode["id"])}">Choose mode</button>'
        advanced_cards.append(
            f"""
            <article class="card{selected}{disabled_class}">
              <h3>{html.escape(mode["title"])}</h3>
              <p>{html.escape(mode["body"])}</p>
              {reason_html}
              {button_html}
            </article>
            """
        )
    advanced_cards.append(
        """
        <article class="card">
          <h3>Advanced CamillaDSP editor</h3>
          <p>Edit filters, mixers, gains, delays, PEQ, FIR and crossover settings.</p>
          <a class="button secondary" href="http://raspiaudio.local:5005/gui/index.html">Open editor</a>
        </article>
        """
    )

    lab_button = ""
    if LAB_MODE_FILE.exists():
        lab_button = '<button data-action="lab-update" class="secondary">Lab update from GitHub</button>'

    checks = health.get("checks", [])
    if checks:
        health_cards = []
        for check in checks:
            level = html.escape(str(check.get("level", "unknown")))
            action = str(check.get("action", ""))
            action_html = (
                f'<small>{html.escape(action)}</small>'
                if action and level != "ok"
                else ""
            )
            health_cards.append(
                f"""
                <article class="check {level}">
                  <span>{level.upper()}</span>
                  <strong>{html.escape(str(check.get("label", "")))}</strong>
                  <p>{html.escape(str(check.get("message", "")))}</p>
                  {action_html}
                </article>
                """
            )
        health_html = "".join(health_cards)
    else:
        health_error = html.escape(str(health.get("error", "Health check not available.")))
        health_html = f"""
        <article class="check warning">
          <span>WARNING</span>
          <strong>System checks unavailable</strong>
          <p>{health_error}</p>
        </article>
        """

    blocking_checks = [
        check
        for check in checks_by_key.values()
        if str(check.get("level", "ok")) != "ok"
    ]
    if blocking_checks:
        alert_html = "".join(
            f"""
            <article class="alert {html.escape(str(check.get("level", "warning")))}">
              <strong>{html.escape(str(check.get("label", "")))}</strong>
              <p>{html.escape(str(check.get("message", "")))}</p>
            </article>
            """
            for check in blocking_checks
        )
    else:
        alert_html = """
        <article class="alert ok">
          <strong>Ready</strong>
          <p>All required checks are passing.</p>
        </article>
        """

    return f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>RASPIAUDIO CamillaDSP Box</title>
  <style>
    :root {{
      color-scheme: light dark;
      --bg: #f5f7f9;
      --panel: #ffffff;
      --text: #16202a;
      --muted: #5d6975;
      --accent: #008b9a;
      --line: #d7dde3;
      --danger: #a33b2f;
      --ok: #16713d;
      --warn: #8a6200;
    }}
    body {{
      margin: 0;
      font-family: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      background: var(--bg);
      color: var(--text);
    }}
    header {{
      padding: 26px clamp(18px, 4vw, 48px) 20px;
      background: #0f2733;
      color: white;
    }}
    .header-inner {{
      max-width: 1120px;
      margin: 0 auto;
      display: flex;
      align-items: flex-start;
      justify-content: space-between;
      gap: 18px;
    }}
    h1 {{
      margin: 0 0 8px;
      font-size: clamp(28px, 4vw, 44px);
      letter-spacing: 0;
    }}
    header p {{ margin: 0; color: #d6edf1; }}
    .version {{
      border: 1px solid rgba(255,255,255,.35);
      border-radius: 999px;
      padding: 7px 10px;
      color: #e8f7f9;
      white-space: nowrap;
      font-weight: 650;
    }}
    main {{
      max-width: 1120px;
      margin: 0 auto;
      padding: 24px clamp(16px, 4vw, 32px) 40px;
    }}
    .wizard {{
      display: grid;
      grid-template-columns: repeat(3, minmax(0, 1fr));
      gap: 14px;
      margin-bottom: 18px;
    }}
    .step, .card, .panel, .alert {{
      background: var(--panel);
      border: 1px solid var(--line);
      border-radius: 8px;
      box-shadow: 0 1px 2px rgba(0,0,0,.04);
    }}
    .step {{
      display: grid;
      grid-template-columns: 42px 1fr;
      gap: 12px;
      padding: 16px;
      min-height: 160px;
    }}
    .step.ok {{ border-color: color-mix(in srgb, var(--ok) 50%, var(--line)); }}
    .step.warning {{ border-color: color-mix(in srgb, var(--warn) 55%, var(--line)); }}
    .step-index {{
      width: 34px;
      height: 34px;
      border-radius: 50%;
      display: grid;
      place-items: center;
      background: #e8f0f2;
      color: #16323a;
      font-weight: 800;
    }}
    .step span {{
      display: inline-block;
      font-size: 12px;
      font-weight: 800;
      color: var(--muted);
      margin-bottom: 8px;
    }}
    .step h2 {{ margin: 0 0 7px; font-size: 20px; }}
    .step p {{ margin: 0 0 12px; color: var(--muted); line-height: 1.35; }}
    h2 {{ margin: 24px 0 12px; font-size: 22px; }}
    .actions, .outputs {{
      display: flex;
      flex-wrap: wrap;
      gap: 10px;
    }}
    .modes {{
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(240px, 1fr));
      gap: 14px;
    }}
    .recommended {{
      display: grid;
      grid-template-columns: 1fr auto;
      align-items: center;
      gap: 16px;
    }}
    .recommended h2 {{ margin: 0 0 8px; }}
    .recommended p {{ margin: 0; color: var(--muted); line-height: 1.4; }}
    .recommended small {{
      display: block;
      margin-top: 8px;
      color: #7a4b00;
      font-weight: 650;
    }}
    .card {{ padding: 18px; }}
    .card h3 {{ margin: 0 0 8px; font-size: 18px; }}
    .card p {{ min-height: 58px; color: var(--muted); line-height: 1.4; }}
    .card small {{
      display: block;
      color: #7a4b00;
      font-weight: 650;
      min-height: 22px;
      margin: 0 0 10px;
    }}
    .card.disabled {{
      opacity: .55;
      background: color-mix(in srgb, var(--panel) 78%, var(--line));
    }}
    .selected {{ outline: 3px solid rgba(0,139,154,.22); border-color: var(--accent); }}
    button, .button {{
      appearance: none;
      border: 1px solid var(--accent);
      background: var(--accent);
      color: white;
      border-radius: 6px;
      padding: 9px 12px;
      font-weight: 650;
      cursor: pointer;
      text-decoration: none;
      display: inline-flex;
      align-items: center;
      justify-content: center;
      min-height: 38px;
    }}
    button:disabled {{
      cursor: not-allowed;
      border-color: var(--line);
      background: #a8b2bc;
      color: #edf2f6;
    }}
    button.secondary, .button.secondary {{
      background: transparent;
      color: var(--accent);
    }}
    .pill {{
      background: var(--panel);
      color: var(--text);
      border-color: var(--line);
    }}
    .pill.selected {{
      background: #e2f5f7;
      color: #06424a;
      border-color: var(--accent);
    }}
    .panel {{
      padding: 18px;
      margin-top: 18px;
    }}
    details.panel summary {{
      cursor: pointer;
      font-size: 22px;
      font-weight: 700;
      margin: 0;
    }}
    details.panel[open] summary {{ margin-bottom: 14px; }}
    .alerts {{
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(240px, 1fr));
      gap: 10px;
      margin-top: 14px;
    }}
    .alert {{ padding: 12px; }}
    .alert strong {{ display: block; }}
    .alert p {{ margin: 6px 0 0; color: var(--muted); }}
    .alert.ok {{ border-color: color-mix(in srgb, var(--ok) 45%, var(--line)); }}
    .alert.warning {{ border-color: color-mix(in srgb, var(--warn) 55%, var(--line)); }}
    .alert.error {{ border-color: color-mix(in srgb, var(--danger) 55%, var(--line)); }}
    .checks {{
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(230px, 1fr));
      gap: 10px;
      margin-top: 12px;
    }}
    .check {{
      border: 1px solid var(--line);
      border-radius: 8px;
      background: var(--panel);
      padding: 12px;
    }}
    .check span {{
      display: inline-block;
      font-size: 12px;
      font-weight: 750;
      margin-bottom: 8px;
      padding: 3px 6px;
      border-radius: 4px;
      background: #e4eaef;
      color: #22313c;
    }}
    .check.ok span {{ background: #d9f1df; color: #165a27; }}
    .check.warning span {{ background: #fff1c7; color: #725400; }}
    .check.error span {{ background: #f9d8d3; color: #8d2c23; }}
    .check strong {{ display: block; }}
    .check p {{ margin: 6px 0 0; color: var(--muted); }}
    .check small {{ display: block; margin-top: 8px; color: var(--text); }}
    pre {{
      white-space: pre-wrap;
      background: #101820;
      color: #e6edf3;
      border-radius: 8px;
      padding: 12px;
      max-height: 260px;
      overflow: auto;
    }}
    @media (prefers-color-scheme: dark) {{
      :root {{
        --bg: #11171d;
        --panel: #18222b;
        --text: #eef3f6;
        --muted: #a7b2bc;
        --line: #2d3a45;
      }}
      .pill.selected {{ background: #123940; color: #d9f7fb; }}
      .step-index {{ background: #22313a; color: #d9f7fb; }}
    }}
    @media (max-width: 760px) {{
      .header-inner, .recommended {{
        display: block;
      }}
      .version {{
        display: inline-block;
        margin-top: 12px;
      }}
      .wizard {{
        grid-template-columns: 1fr;
      }}
    }}
  </style>
</head>
<body>
  <header>
    <div class="header-inner">
      <div>
        <h1>RASPIAUDIO CamillaDSP Box</h1>
        <p>Flash image, boot, choose mode, test audio.</p>
      </div>
      <div class="version">Version {html.escape(version)}</div>
    </div>
  </header>
  <main>
    <section class="wizard">
      {step_card(1, "Hardware detected", hardware_message, hardware_ok)}
      {step_card(2, "USB audio", usb_message, usb_ok, restart_usb_button)}
      {step_card(3, "Audio test", audio_message, audio_test_ok, f'<div class="outputs">{output_buttons}</div>')}
    </section>

    <section class="panel recommended">
      <div>
        <h2>Recommended mode</h2>
        <p><strong>{html.escape(recommended["title"])}</strong></p>
        <p>{html.escape(recommended["body"])}</p>
        {recommended_reason_html}
      </div>
      <div class="actions">{recommended_button}</div>
    </section>

    <section class="alerts">{alert_html}</section>

    <details class="panel">
      <summary>More modes</summary>
      <section class="modes">{"".join(advanced_cards)}</section>
      <div class="actions" style="margin-top: 12px">
        <button data-action="test-toslink">Test TOSLINK</button>
        <button data-action="test-inputs" class="secondary">Record 8 inputs test</button>
      </div>
    </details>

    <section class="panel">
      <h2>Support</h2>
      <div class="actions">
        <button data-action="fix-audio">Fix audio</button>
        <button data-action="update-system" class="secondary">Update system</button>
        <button data-action="factory-reset" class="secondary">Factory reset audio</button>
        <button data-action="validate-release" class="secondary">Run release checks</button>
        {lab_button}
        <a class="button secondary" href="/api/diagnostics">Download diagnostics zip</a>
      </div>
      <pre id="log">Ready.</pre>
    </section>

    <details class="panel">
      <summary>System checks</summary>
      <div class="checks">{health_html}</div>
      <p style="color: var(--muted)">Current mode: {html.escape(str(status.get("active_mode_label", active)))}. System check: {html.escape(str(health_status))}.</p>
    </details>
  </main>
  <script>
    const log = document.getElementById('log');
    function bind(selector, callback) {{
      const node = document.querySelector(selector);
      if (node) node.addEventListener('click', callback);
    }}
    async function post(path, data) {{
      log.textContent = 'Working...';
      const res = await fetch(path, {{
        method: 'POST',
        headers: {{'Content-Type': 'application/json'}},
        body: JSON.stringify(data || {{}})
      }});
      const text = await res.text();
      let body = text;
      try {{
        const json = JSON.parse(text);
        body = json.output || JSON.stringify(json, null, 2);
      }} catch (e) {{}}
      log.textContent = body || 'Done.';
      if (res.ok && (path.includes('/mode') || path.includes('/factory-reset') || path.includes('/fix-audio'))) {{
        setTimeout(() => window.location.reload(), 900);
      }}
    }}
    document.querySelectorAll('[data-mode]').forEach(btn => {{
      btn.addEventListener('click', () => post('/api/mode', {{mode: btn.dataset.mode}}));
    }});
    document.querySelectorAll('[data-output]').forEach(btn => {{
      btn.addEventListener('click', () => post('/api/test-output', {{channel: btn.dataset.output}}));
    }});
    bind('[data-action="test-toslink"]', () => post('/api/test-toslink', {{}}));
    bind('[data-action="test-inputs"]', () => post('/api/test-inputs', {{}}));
    bind('[data-action="restart-usb"]', () => post('/api/restart-usb-gadget', {{}}));
    bind('[data-action="fix-audio"]', () => post('/api/fix-audio', {{}}));
    bind('[data-action="update-system"]', () => post('/api/update-system', {{}}));
    bind('[data-action="factory-reset"]', () => post('/api/factory-reset', {{}}));
    bind('[data-action="validate-release"]', () => post('/api/validate-release', {{}}));
    const labUpdate = document.querySelector('[data-action="lab-update"]');
    if (labUpdate) {{
      labUpdate.addEventListener('click', () => post('/api/lab-update', {{}}));
    }}
  </script>
</body>
</html>
"""


class Handler(BaseHTTPRequestHandler):
    server_version = "RASPIAUDIOWeb/0.1"

    def send_text(self, status, text, content_type="text/plain; charset=utf-8"):
        data = text.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def send_json(self, status, payload):
        self.send_text(status, json.dumps(payload), "application/json; charset=utf-8")

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path == "/":
            self.send_text(HTTPStatus.OK, render_page(), "text/html; charset=utf-8")
            return
        if parsed.path == "/api/status":
            self.send_json(HTTPStatus.OK, load_status())
            return
        if parsed.path == "/api/health":
            self.send_json(HTTPStatus.OK, load_health())
            return
        if parsed.path == "/api/diagnostics":
            with tempfile.NamedTemporaryFile(prefix="raspiaudio-diagnostics-", suffix=".zip", delete=False) as tmp:
                out_path = tmp.name
            result = run_command(["/usr/local/sbin/raspiaudio-diagnostics", "--output", out_path], timeout=45)
            if not result["ok"] or not pathlib.Path(out_path).exists():
                self.send_json(HTTPStatus.INTERNAL_SERVER_ERROR, result)
                return
            data = pathlib.Path(out_path).read_bytes()
            pathlib.Path(out_path).unlink(missing_ok=True)
            self.send_response(HTTPStatus.OK)
            self.send_header("Content-Type", "application/zip")
            self.send_header("Content-Disposition", "attachment; filename=raspiaudio-diagnostics.zip")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            return
        self.send_text(HTTPStatus.NOT_FOUND, "Not found")

    def do_POST(self):
        parsed = urllib.parse.urlparse(self.path)
        try:
            body = read_body(self)
        except Exception as exc:
            self.send_json(HTTPStatus.BAD_REQUEST, {"ok": False, "output": str(exc)})
            return

        if parsed.path == "/api/mode":
            mode = str(body.get("mode", ""))
            result = run_command(["/usr/local/sbin/raspiaudio-mode", "set", mode], timeout=30)
            self.send_json(HTTPStatus.OK if result["ok"] else HTTPStatus.BAD_REQUEST, result)
            return
        if parsed.path == "/api/hardware":
            hardware = str(body.get("hardware", ""))
            result = run_command(["/usr/local/sbin/raspiaudio-mode", "set-hardware", hardware], timeout=30)
            self.send_json(HTTPStatus.OK if result["ok"] else HTTPStatus.BAD_REQUEST, result)
            return
        if parsed.path == "/api/restart-audio":
            result = run_command(["systemctl", "restart", "camilladsp.service"], timeout=30)
            self.send_json(HTTPStatus.OK if result["ok"] else HTTPStatus.BAD_REQUEST, result)
            return
        if parsed.path == "/api/restart-usb-gadget":
            result = run_command(["/usr/local/sbin/raspiaudio-restart-usb-gadget"], timeout=30)
            self.send_json(HTTPStatus.OK if result["ok"] else HTTPStatus.BAD_REQUEST, result)
            return
        if parsed.path == "/api/fix-audio":
            result = run_command(["/usr/local/sbin/raspiaudio-fix-audio"], timeout=120)
            self.send_json(HTTPStatus.OK if result["ok"] else HTTPStatus.BAD_REQUEST, result)
            return
        if parsed.path == "/api/update-system":
            result = run_command(["/usr/local/sbin/raspiaudio-update-system"], timeout=60)
            self.send_json(HTTPStatus.OK if result["ok"] else HTTPStatus.BAD_REQUEST, result)
            return
        if parsed.path == "/api/factory-reset":
            result = run_command(["/usr/local/sbin/raspiaudio-mode", "reset"], timeout=30)
            self.send_json(HTTPStatus.OK if result["ok"] else HTTPStatus.BAD_REQUEST, result)
            return
        if parsed.path == "/api/validate-release":
            result = run_command(["/usr/local/sbin/raspiaudio-validate-release"], timeout=60)
            self.send_json(HTTPStatus.OK if result["ok"] else HTTPStatus.BAD_REQUEST, result)
            return
        if parsed.path == "/api/lab-update":
            if not LAB_MODE_FILE.exists():
                self.send_json(
                    HTTPStatus.FORBIDDEN,
                    {
                        "ok": False,
                        "output": "Lab update is disabled. Create /etc/raspiaudio/lab-mode only on test images.",
                    },
                )
                return
            result = start_lab_update()
            self.send_json(HTTPStatus.OK if result["ok"] else HTTPStatus.BAD_REQUEST, result)
            return
        if parsed.path == "/api/test-output":
            channel = str(body.get("channel", ""))
            result = run_command(["/usr/local/sbin/raspiaudio-test-audio", "output", channel], timeout=30)
            self.send_json(HTTPStatus.OK if result["ok"] else HTTPStatus.BAD_REQUEST, result)
            return
        if parsed.path == "/api/test-toslink":
            result = run_command(["/usr/local/sbin/raspiaudio-test-audio", "toslink"], timeout=600)
            self.send_json(HTTPStatus.OK if result["ok"] else HTTPStatus.BAD_REQUEST, result)
            return
        if parsed.path == "/api/test-inputs":
            result = run_command(["/usr/local/sbin/raspiaudio-test-audio", "inputs"], timeout=20)
            self.send_json(HTTPStatus.OK if result["ok"] else HTTPStatus.BAD_REQUEST, result)
            return

        self.send_text(HTTPStatus.NOT_FOUND, "Not found")

    def log_message(self, fmt, *args):
        print("%s - %s" % (self.address_string(), fmt % args))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default=os.environ.get("RASPIAUDIO_WEB_HOST", "127.0.0.1"))
    parser.add_argument("--port", type=int, default=int(os.environ.get("RASPIAUDIO_WEB_PORT", "8080")))
    args = parser.parse_args()
    server = ThreadingHTTPServer((args.host, args.port), Handler)
    print(f"RASPIAUDIO web UI listening on {args.host}:{args.port}")
    server.serve_forever()


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Remember opening modes by app ID AND title, including late title changes."""
import argparse
import fcntl
import json
import os
from pathlib import Path
import re
import selectors
import socket
import subprocess
import sys
import tempfile


def state_dir():
    return Path(os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config"))) / "niri-window-memory"


def request(message):
    with socket.socket(socket.AF_UNIX) as connection:
        connection.settimeout(5)
        connection.connect(os.environ["NIRI_SOCKET"])
        connection.sendall((json.dumps(message) + "\n").encode())
        with connection.makefile("r") as stream:
            reply = json.loads(stream.readline())
    if "Err" in reply:
        raise RuntimeError(str(reply["Err"]))
    return reply["Ok"]


def windows():
    return request("Windows")["Windows"]


def action(name, **arguments):
    request({"Action": {name: arguments}})


def load_rules():
    path = state_dir() / "rules.json"
    if not path.exists():
        return []
    rules = json.loads(path.read_text())
    if not isinstance(rules, list):
        raise ValueError("Saved rules must be a list")
    for rule in rules:
        if not rule.get("app_id") or not rule.get("title"):
            raise ValueError("Every rule must match both an app ID and a nonempty title")
        if rule["mode"] not in ("floating", "maximized"):
            raise ValueError("Unknown saved mode")
        re.compile(rule["title"])
    return rules


def save_rules(rules):
    folder = state_dir()
    folder.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile("w", dir=folder, delete=False) as stream:
        temporary = Path(stream.name)
        json.dump(rules, stream, ensure_ascii=False, indent=2)
        stream.write("\n")
    os.replace(temporary, folder / "rules.json")


def matching_rule(window, rules):
    # Later rules override earlier rules, but never match an entire application.
    for rule in reversed(rules):
        if window.get("app_id") == rule["app_id"] and re.search(rule["title"], window.get("title") or ""):
            return rule
    return None


def notify(message):
    try:
        subprocess.run(["notify-send", "Window memory", message], check=False)
    except FileNotFoundError:
        print(message, file=sys.stderr)


def menu(prompt, entries):
    result = subprocess.run(
        ["fuzzel", "--dmenu", "--index", "--no-sort", "--width=70", "--prompt", prompt],
        input="\n".join(entries), text=True, capture_output=True,
    )
    if result.returncode or not result.stdout.strip().isdigit():
        return None
    index = int(result.stdout.strip())
    return index if index < len(entries) else None


def pattern_prompt(title):
    # Shell wildcards are easier to edit than regex; all other characters are literal.
    result = subprocess.run(
        ["fuzzel", "--dmenu", "--lines=0", "--width=70", "--prompt", "Title (* = any text): ", "--search", title],
        input="", text=True, capture_output=True,
    )
    if result.returncode:
        return None
    pattern = result.stdout.rstrip("\n")
    if not pattern.strip("*? \t"):
        raise ValueError("A title pattern must contain identifying text")
    return "^" + "".join(".*" if c == "*" else "." if c == "?" else re.escape(c) for c in pattern) + "$"


def remember(mode):
    # Capture before Fuzzel takes focus. Use the ID afterward, never the picker focus.
    window = request("FocusedWindow")["FocusedWindow"]
    if not window or not window.get("app_id") or not window.get("title"):
        raise ValueError("Focus a window with an app ID and a nonempty title first")
    folder = state_dir()
    folder.mkdir(parents=True, exist_ok=True)
    with (folder / "picker.lock").open("w") as picker_lock:
        try:
            fcntl.flock(picker_lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return
        rules = load_rules()
        matches = [r for r in rules if matching_rule(window, [r])]
        title = window["title"].replace("\n", " ")
        choices = [f"Remember exact title: {title}", "Remember a title pattern (* and ? wildcards)"]
        choices += [f"Remove {r['mode']} rule: {r['title']}" for r in matches]
        choice = menu(f"{mode} · {window['app_id']}: ", choices)
        if choice is None:
            return
        if choice >= 2:
            selected = matches[choice - 2]
            if menu("Remove saved preference? ", ["Remove: " + selected["title"], "Cancel"]) != 0:
                return
            with (folder / "rules.lock").open("w") as lock:
                fcntl.flock(lock, fcntl.LOCK_EX)
                save_rules([r for r in load_rules() if r != selected])
            notify("Preference removed. Existing windows keep their current mode.")
            return
        pattern = "^" + re.escape(window["title"]) + "$" if choice == 0 else pattern_prompt(window["title"])
        if pattern is None:
            return
        if not re.search(pattern, window["title"]):
            raise ValueError("The pattern does not match the selected window")
        rule = {"app_id": window["app_id"], "title": pattern, "mode": mode}
        count = sum(1 for w in windows() if matching_rule(w, [rule]))
        confirmation = ["Save preference", "Cancel", f"App ID: {rule['app_id']}", f"Title: {pattern}", f"Currently matches {count} window(s)"]
        if menu(f"Always open {mode}? ", confirmation) != 0:
            return
        with (folder / "rules.lock").open("w") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            updated = [r for r in load_rules() if (r["app_id"], r["title"]) != (rule["app_id"], pattern)]
            save_rules(updated + [rule])
        # The watcher applies the confirmed rule, including to this window.
        notify(f"Remembered {mode} for {title}")


class Watcher:
    def __init__(self):
        self.rules = []
        self.applied = {}
        self.known = {}
        self.signature = None

    def reload(self):
        path = state_dir() / "rules.json"
        signature = path.stat().st_mtime_ns if path.exists() else None
        if signature != self.signature:
            self.rules = load_rules()
            self.signature = signature
            identities = {(r["app_id"], r["title"], r["mode"]) for r in self.rules}
            self.applied = {key: value for key, value in self.applied.items() if value in identities}
            self.scan()

    def apply(self, window):
        rule = matching_rule(window, self.rules)
        if not rule:
            return
        identity = (rule["app_id"], rule["title"], rule["mode"])
        if self.applied.get(window["id"]) == identity:
            return
        # Record before sending actions: their own events must not reapply the rule.
        self.applied[window["id"]] = identity
        try:
            if rule["mode"] == "floating":
                action("MoveWindowToFloating", id=window["id"])
            else:
                action("MoveWindowToTiling", id=window["id"])
                # Full-width like Super+F, without stealing focus or toggling an
                # already maximized column back to a narrow width.
                action("SetWindowWidth", id=window["id"], change={"SetProportion": 100.0})
        except (OSError, ValueError, RuntimeError):
            self.applied.pop(window["id"], None)
            raise

    def scan(self):
        for window in list(self.known.values()):
            self.apply(window)

    def event(self, event):
        if "WindowsChanged" in event:
            self.known = {w["id"]: w for w in event["WindowsChanged"]["windows"]}
            self.applied = {key: value for key, value in self.applied.items() if key in self.known}
            self.scan()
        elif "WindowOpenedOrChanged" in event:
            window = event["WindowOpenedOrChanged"]["window"]
            self.known[window["id"]] = window
            self.apply(window)
        elif "WindowClosed" in event:
            key = event["WindowClosed"]["id"]
            self.known.pop(key, None)
            self.applied.pop(key, None)


def watch():
    folder = state_dir()
    folder.mkdir(parents=True, exist_ok=True)
    # Separate locks per compositor; both login sessions share saved rules.
    lock_path = folder / ("watch-" + Path(os.environ["NIRI_SOCKET"]).name + ".lock")
    with lock_path.open("w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return
        watcher = Watcher()
        with socket.socket(socket.AF_UNIX) as connection, selectors.DefaultSelector() as selector:
            connection.connect(os.environ["NIRI_SOCKET"])
            connection.sendall(b'"EventStream"\n')
            selector.register(connection, selectors.EVENT_READ)
            buffer = b""
            while True:
                try:
                    watcher.reload()
                except (OSError, ValueError, RuntimeError) as error:
                    print(f"Window memory: {error}", file=sys.stderr, flush=True)
                for key, _ in selector.select(timeout=1):
                    data = key.fileobj.recv(65536)
                    if not data:
                        return
                    buffer += data
                    while b"\n" in buffer:
                        line, buffer = buffer.split(b"\n", 1)
                        try:
                            watcher.event(json.loads(line))
                        except (OSError, ValueError, RuntimeError) as error:
                            print(f"Window memory: {error}", file=sys.stderr, flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["watch", "floating", "maximized"])
    args = parser.parse_args()
    try:
        watch() if args.command == "watch" else remember(args.command)
    except (OSError, ValueError, RuntimeError, KeyError) as error:
        if args.command != "watch":
            notify(str(error))
        print(f"Window memory: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())

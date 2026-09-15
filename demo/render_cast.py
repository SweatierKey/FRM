#!/usr/bin/env python3
"""Small deterministic fallback renderer for the README demo.

This is not part of FRM runtime. When agg is installed, render-demo.sh uses agg.
"""
import json
import pathlib
import re
import sys

from PIL import Image, ImageDraw, ImageFont

ANSI_RE = re.compile(r"\x1b\[[0-9;?]*[ -/]*[@-~]")
CLEAR_RE = re.compile(r"\x1b\[2J\x1b\[H")

BG = (11, 16, 32)
PANEL = (17, 24, 39)
FG = (218, 224, 234)
DIM = (113, 128, 150)
GREEN = (74, 222, 128)
RED = (248, 113, 113)
YELLOW = (250, 204, 21)
CYAN = (34, 211, 238)
PURPLE = (167, 139, 250)


def font(size=18):
    candidates = [
        "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
        "/usr/share/fonts/truetype/liberation2/LiberationMono-Regular.ttf",
    ]
    for p in candidates:
        if pathlib.Path(p).exists():
            return ImageFont.truetype(p, size)
    return ImageFont.load_default()


def line_color(line):
    if "RUNNING" in line or "is RUNNING" in line:
        return GREEN
    if " DOWN " in f" {line} " or "not running" in line:
        return RED
    if "WARNING" in line or "UNKNOWN" in line:
        return YELLOW
    if line.startswith("$"):
        return CYAN
    if line.startswith("FRM "):
        return PURPLE
    if "DRY-RUN" in line:
        return CYAN
    if line.startswith("Summary:"):
        return PURPLE
    return FG


def render(lines, width=1100, height=650):
    img = Image.new("RGB", (width, height), BG)
    draw = ImageDraw.Draw(img)
    draw.rounded_rectangle((18, 18, width - 18, height - 18), radius=22, fill=PANEL)
    # Window chrome.
    draw.ellipse((38, 37, 52, 51), fill=(248, 113, 113))
    draw.ellipse((61, 37, 75, 51), fill=(250, 204, 21))
    draw.ellipse((84, 37, 98, 51), fill=(74, 222, 128))
    title_font = font(15)
    draw.text((width // 2 - 125, 35), "FRM · terminal demo", fill=DIM, font=title_font)

    fnt = font(18)
    line_h = 24
    x = 40
    y = 72
    max_lines = (height - y - 28) // line_h
    visible = lines[-max_lines:]
    for ln in visible:
        draw.text((x, y), ln[:105], fill=line_color(ln), font=fnt)
        y += line_h
    return img


def main(cast_path, gif_path):
    raw = pathlib.Path(cast_path).read_text().splitlines()
    if not raw:
        raise SystemExit("empty cast")
    header = json.loads(raw[0])
    events = [json.loads(x) for x in raw[1:]]

    screen = ""
    frames = []
    durations = []
    last_t = 0.0

    for idx, event in enumerate(events):
        t, kind, payload = event
        if kind != "o":
            continue
        if CLEAR_RE.search(payload):
            screen = ""
            payload = CLEAR_RE.sub("", payload)
        payload = ANSI_RE.sub("", payload)
        screen += payload.replace("\r", "")
        lines = screen.split("\n")
        if lines and lines[-1] == "":
            lines = lines[:-1]
        frames.append(render(lines))
        next_t = events[idx + 1][0] if idx + 1 < len(events) else t + 1.8
        delay = max(250, min(1800, int((next_t - t) * 1000)))
        durations.append(delay)
        last_t = t

    if not frames:
        raise SystemExit("no output events")

    frames[0].save(
        gif_path,
        save_all=True,
        append_images=frames[1:],
        duration=durations,
        loop=0,
        optimize=True,
        disposal=2,
    )


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit(f"usage: {sys.argv[0]} INPUT.cast OUTPUT.gif")
    main(sys.argv[1], sys.argv[2])

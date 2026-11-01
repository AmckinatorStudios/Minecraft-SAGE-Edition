#!/usr/bin/env python3
"""Рисует лист интерфейса SAGE Craft (assets/ui/gui.png) и его описание
(gui.png.sagesheet) — свой пиксель-арт: панели со скошенной рамкой, ячейки,
кнопки, рамка выбора, стрелка, полоса опыта.

Запуск: python3 tools/make_gui.py  (нужен Pillow)
"""
import json
import os

from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
OUT = os.path.join(ROOT, "assets", "ui", "gui.png")

# Палитра: тёплый камень.
OUTLINE = (22, 20, 18, 255)
LIGHT = (238, 234, 226, 255)
FACE = (184, 179, 170, 255)
SHADE = (104, 99, 92, 255)
SLOT_DARK = (62, 59, 55, 255)
SLOT_FILL = (136, 131, 124, 255)
SLOT_LIGHT = (244, 241, 234, 255)

img = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
px = img.load()
sprites = []


def rect(x, y, w, h, c):
    for yy in range(y, y + h):
        for xx in range(x, x + w):
            px[xx, yy] = c


def raised(x, y, w, h, face, light, shade, outline=OUTLINE, round_=True):
    """Выпуклая плашка: контур, светлый верх-лево, тёмный низ-право."""
    rect(x, y, w, h, outline)
    rect(x + 1, y + 1, w - 2, h - 2, face)
    rect(x + 1, y + 1, w - 2, 2, light)
    rect(x + 1, y + 1, 2, h - 2, light)
    rect(x + 1, y + h - 3, w - 2, 2, shade)
    rect(x + w - 3, y + 1, 2, h - 2, shade)
    if round_:
        for cx, cy in ((x, y), (x + w - 1, y), (x, y + h - 1), (x + w - 1, y + h - 1)):
            px[cx, cy] = (0, 0, 0, 0)


def add(name, x, y, w, h, slice_=None):
    e = {"name": name, "rect": [x, y, w, h]}
    if slice_:
        e["slice"] = slice_
    sprites.append(e)


# Панель окна — 16×16, девятина 4.
raised(0, 0, 16, 16, FACE, LIGHT, SHADE)
add("panel", 0, 0, 16, 16, [4, 4, 4, 4])

# Ячейка — вдавленная, 18×18.
x, y = 16, 0
rect(x, y, 18, 18, SLOT_FILL)
rect(x, y, 18, 1, SLOT_DARK); rect(x, y, 1, 18, SLOT_DARK)
rect(x, y + 17, 18, 1, SLOT_LIGHT); rect(x + 17, y, 1, 18, SLOT_LIGHT)
add("slot", x, y, 18, 18, [1, 1, 1, 1])

# Ячейка панели быстрого доступа — тёмная полупрозрачная, 22×22.
x = 34
rect(x, y, 22, 22, (40, 38, 36, 230))
rect(x + 1, y + 1, 20, 20, (20, 20, 20, 140))
add("hotbar_slot", x, y, 22, 22, [1, 1, 1, 1])

# Рамка выбранной ячейки — 24×24, без середины.
x = 56
rect(x, y, 24, 24, OUTLINE)
rect(x + 1, y + 1, 22, 22, (250, 250, 246, 255))
rect(x + 3, y + 3, 18, 18, OUTLINE)
rect(x + 4, y + 4, 16, 16, (0, 0, 0, 0))
add("hotbar_select", x, y, 24, 24, [4, 4, 4, 4])

# Кнопки: обычная, наведённая, выключенная — 16×16, девятина 3.
raised(0, 24, 16, 16, (152, 148, 140, 255), (220, 216, 208, 255), (84, 80, 74, 255))
add("button", 0, 24, 16, 16, [3, 3, 3, 3])
raised(16, 24, 16, 16, (132, 150, 196, 255), (200, 214, 246, 255), (66, 80, 120, 255))
add("button_hover", 16, 24, 16, 16, [3, 3, 3, 3])
raised(32, 24, 16, 16, (70, 68, 64, 255), (96, 93, 88, 255), (44, 42, 40, 255))
add("button_disabled", 32, 24, 16, 16, [3, 3, 3, 3])

# Подсказка — тёмная с цветной каймой.
x, y = 48, 24
rect(x, y, 16, 16, (14, 10, 22, 240))
rect(x + 1, y + 1, 14, 14, (60, 30, 110, 255))
rect(x + 2, y + 2, 12, 12, (14, 10, 22, 240))
add("tooltip", x, y, 16, 16, [3, 3, 3, 3])

# Стрелка крафта — 22×15.
x, y = 64, 24
ARROW = [
    "..............#.......",
    "..............##......",
    "..............###.....",
    "..............####....",
    "..............#####...",
    "######################",
    "#######################"[:22],
    "######################",
    "######################",
    "..............#####...",
    "..............####....",
    "..............###.....",
    "..............##......",
    "..............#.......",
    "......................",
]
for j, row in enumerate(ARROW):
    for i, ch in enumerate(row):
        if ch == "#":
            px[x + i, y + j] = (120, 115, 108, 255)
add("arrow", x, y, 22, 15)

# Полоса опыта: подложка и заливка, 32×5, девятина 1.
x, y = 0, 44
rect(x, y, 32, 5, OUTLINE); rect(x + 1, y + 1, 30, 3, (40, 46, 36, 255))
add("bar_back", x, y, 32, 5, [1, 1, 1, 1])
y = 50
rect(x, y, 32, 5, (0, 0, 0, 0)); rect(x, y + 1, 32, 3, (120, 220, 70, 255)); rect(x, y + 1, 32, 1, (190, 250, 140, 255))
add("bar_fill", x, y, 32, 5, [1, 1, 1, 1])

# Превью персонажа — чёрное окно в рамке.
x, y = 80, 0
rect(x, y, 16, 16, SLOT_LIGHT); rect(x, y, 15, 15, SLOT_DARK); rect(x + 1, y + 1, 14, 14, (8, 8, 10, 255))
add("well", x, y, 16, 16, [2, 2, 2, 2])

os.makedirs(os.path.dirname(OUT), exist_ok=True)
img.save(OUT)
with open(OUT + ".sagesheet", "w", encoding="utf-8") as f:
    json.dump({"sprites": sprites}, f, ensure_ascii=False, indent=2)
print("лист:", OUT, "кусков:", len(sprites))

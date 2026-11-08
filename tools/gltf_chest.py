#!/usr/bin/env python3
"""Модели сундука из Blockbench (art/chest/*.gltf) -> assets/scripts/chestmesh.lua.

Каждая модель — один меш на двух костях: body (корпус) и lid_pivot (крышка с
защёлкой). Скрипт делит меш на три части по кости и по геометрии:
  base — вершины кости body;
  lid  — вершины кости lid_pivot, кроме защёлки;
  knob — грани кости lid_pivot перед крышкой (z < −7/16): защёлка.
Берутся только грани, на которые ссылаются индексы (у половин двойного
сундука внутренних граней шва нет). Крышка и защёлка — относительно точки
вращения lid_pivot. UV — в долях текстуры игры (v снизу): одиночный —
normal.png 64×64 (у модели та же картинка встроена), половины двойного —
normal_double.png 128×64 (UV модели — в пикселях / 16).

Запуск: python3 tools/gltf_chest.py   (проверка: --check)
"""
import base64, json, struct, sys, os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODELS = [  # имя, файл, во сколько пикселей единица UV, ширина и высота текстуры
    ("single", "art/chest/Chest.gltf", 64, 64, 64),
    ("left", "art/chest/Double_Chest_Left.gltf", 16, 128, 64),
    ("right", "art/chest/Double_Chest_Right.gltf", 16, 128, 64),
]
OUT = os.path.join(ROOT, "assets/scripts/chestmesh.lua")


def load(path):
    g = json.load(open(os.path.join(ROOT, path)))
    buf = base64.b64decode(g["buffers"][0]["uri"].split(",", 1)[1])

    def acc(i):
        a = g["accessors"][i]
        bv = g["bufferViews"][a["bufferView"]]
        n = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}[a["type"]]
        fmt = {5126: "f", 5123: "H", 5125: "I"}[a["componentType"]]
        size = struct.calcsize(fmt)
        stride = bv.get("byteStride", size * n)
        return [struct.unpack_from("<" + fmt * n, buf, bv.get("byteOffset", 0) + a.get("byteOffset", 0) + k * stride)
                for k in range(a["count"])]

    prim0 = g["meshes"][0]["primitives"][0]["attributes"]
    pos, nrm, uv = acc(prim0["POSITION"]), acc(prim0["NORMAL"]), acc(prim0["TEXCOORD_0"])
    joints, weights = acc(prim0["JOINTS_0"]), acc(prim0["WEIGHTS_0"])
    skin = g["skins"][0]["joints"]
    names = [g["nodes"][j]["name"] for j in skin]
    tris = []
    for p in g["meshes"][0]["primitives"]:
        idx = [i[0] for i in acc(p["indices"])]
        tris += [idx[k:k + 3] for k in range(0, len(idx), 3)]
    pivot = next(n for n in g["nodes"] if n["name"] == "lid_pivot")["translation"]

    def bone(v):
        w = weights[v]
        k = max(range(4), key=lambda i: w[i])
        return names[joints[v][k]]
    return pos, nrm, uv, tris, bone, pivot


def build(name, path, unit, tw, th):
    pos, nrm, uv, tris, bone, pivot = load(path)
    parts = {"base": [], "lid": [], "knob": []}
    # Коробка защёлки — по вершинам кости крышки, вынесенным перед крышку
    # (z < −7/16): все грани, лежащие в ней целиком, — защёлка.
    front = [pos[v] for t in tris for v in t if bone(v) == "lid_pivot" and pos[v][2] < -7 / 16 - 1e-6]
    e = 1e-6
    box = [min(p[a] for p in front) - e for a in range(3)] + [max(p[a] for p in front) + e for a in range(3)]
    box[5] = -7 / 16 + e

    def inKnob(t):
        return all(box[a] <= pos[v][a] <= box[a + 3] for v in t for a in range(3))
    for t in tris:
        if bone(t[0]) == "body":
            parts["base"].append(t)
        elif inKnob(t):
            parts["knob"].append(t)
        else:
            parts["lid"].append(t)
    out = {}
    for part, ts in parts.items():
        remap, P, N, U, I = {}, [], [], [], []
        org = (0, 0, 0) if part == "base" else pivot
        for t in ts:
            for v in t:
                if v not in remap:
                    remap[v] = len(remap) + 1
                    P += [pos[v][a] - org[a] for a in range(3)]
                    N += list(nrm[v])
                    U += [uv[v][0] * unit / tw, 1 - uv[v][1] * unit / th]
                I.append(remap[v])
        out[part] = (P, N, U, I)
    return out, pivot


def fmt(vals):
    return ", ".join(("%.6f" % v).rstrip("0").rstrip(".") if isinstance(v, float) else str(v) for v in vals)


def main():
    lines = ["-- chestmesh.lua — СОЗДАН tools/gltf_chest.py из art/chest/*.gltf, руками не править.",
             "-- Части сундука: base (корпус), lid (крышка, от точки вращения), knob (защёлка,",
             "-- от точки вращения крышки). Координаты — блоки, центр модели (0, 0, 0) — середина",
             "-- низа клетки, перед — к −Z. UV — доли текстуры игры, v снизу.", "return {"]
    for name, path, unit, tw, th in MODELS:
        parts, pivot = build(name, path, unit, tw, th)
        lines.append("    %s = {" % name)
        lines.append("        pivot = {%s}," % fmt([float(v) for v in pivot]))
        for part in ("base", "lid", "knob"):
            P, N, U, I = parts[part]
            lines.append("        %s = {" % part)
            lines.append("            position = {%s}," % fmt([float(v) for v in P]))
            lines.append("            normal = {%s}," % fmt([float(v) for v in N]))
            lines.append("            uv = {%s}," % fmt([float(v) for v in U]))
            lines.append("            index = {%s}," % fmt(I))
            lines.append("        },")
        lines.append("    },")
    lines.append("}")
    text = "\n".join(lines) + "\n"
    if "--check" in sys.argv:
        cur = open(OUT).read() if os.path.exists(OUT) else ""
        if cur != text:
            print("chestmesh.lua устарел: запустите python3 tools/gltf_chest.py")
            sys.exit(1)
        print("chestmesh.lua: OK")
        return
    open(OUT, "w").write(text)
    for name, path, *_ in MODELS:
        parts, _ = build(name, path, *_)
        print(name, {k: len(v[3]) // 3 for k, v in parts.items()})


if __name__ == "__main__":
    main()

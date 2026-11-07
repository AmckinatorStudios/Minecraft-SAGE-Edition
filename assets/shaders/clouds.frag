#version 330 core
// Клетка текстуры clouds.png — облако, если пиксель непрозрачный (порог
// альфы 0.1, как glAlphaFunc оригинала). Оттенки граней — как у
// renderCloudsFancy: низ 0.7, верх 1, стенки по X 0.9, по Z 0.8; альфа 0.8.
// Туман — setupFog(0): от четверти дальности до дальности, по расстоянию.
//
// Оригинал рисует облака дважды (сначала только глубину), чтобы внутренние
// стенки между соседними клетками не просвечивали. Здесь стенка, за которой
// облако продолжается, просто не рисуется.
layout (location = 0) out vec4 FragColor;
in vec3 vNormal;
in vec3 vWorld;
in vec2 vUV;
uniform sampler2D uTex;    // Облака
uniform vec3 uViewPos;
uniform vec3 uCloudColor;  // color 1 1 1 Цвет облаков
uniform vec3 uFogColor;    // color 0.7 0.82 1 Цвет тумана
uniform float uFogStart;   // 32 [0, 400] Начало тумана
uniform float uFogEnd;     // 128 [0, 500] Конец тумана
uniform float uShowTop;    // 1 [0, 1] Верх виден
uniform float uShowBottom; // 1 [0, 1] Низ виден

// Цвета Minecraft — значения sRGB, а движок считает вывод шейдера
// линейным и сам кодирует его в sRGB: смешиваем как оригинал (в sRGB) и
// переводим в линейный только на выходе.
vec3 toLinear(vec3 c) {
    return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}

bool cloudAt(vec2 uv) {
    // v оригинала идёт сверху картинки, у текстур движка — снизу. Пиксель —
    // точно в центре клетки и без мип-уровней: края облаков — ступеньки
    // клеток, как у GL_NEAREST оригинала, при любой фильтрации материала.
    vec2 c = (floor(vec2(uv.x, 1.0 - uv.y) * 256.0) + 0.5) / 256.0;
    return textureLod(uTex, c, 0.0).a > 0.1;
}

void main() {
    vec3 n = normalize(vNormal);
    // Грань, повёрнутая от глаза, не рисуется (отсечение задних граней,
    // не зависящее от порядка обхода вершин).
    if (dot(n, uViewPos - vWorld) < 0.0) discard;
    if (!cloudAt(vUV)) discard;
    float shade;
    if (n.y > 0.5) { if (uShowTop < 0.5) discard; shade = 1.0; }
    else if (n.y < -0.5) { if (uShowBottom < 0.5) discard; shade = 0.7; }
    else {
        if (cloudAt(vUV + n.xz / 256.0)) discard;
        shade = abs(n.x) > 0.5 ? 0.9 : 0.8;
    }
    vec3 c = uCloudColor * shade;
    float dist = length(vWorld - uViewPos);
    float f = clamp((uFogEnd - dist) / max(uFogEnd - uFogStart, 1.0), 0.0, 1.0);
    FragColor = vec4(toLinear(mix(uFogColor, c, f)), 0.8);
}

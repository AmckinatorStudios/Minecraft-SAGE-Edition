#version 330 core
// Светила — сложением, как у оригинала (GL_SRC_ALPHA, GL_ONE; материал
// "blend": "additive" — src + dst): к небу прибавляется цвет картинки ×
// её альфа × видимость. Чёрный фон картинки не прибавляет ничего, жёлтое
// солнце на голубом небе становится белым — как в 1.7.10.
// uAlpha — 1 − сила дождя; у звёзд без текстуры — яркость звёзд в квадрате.
layout (location = 0) out vec4 FragColor;
in vec2 vUV;
// linear: картинка без перевода из sRGB — оригинал складывает в гамма-
// пространстве, и слабый ореол солнца (0.15) обязан прибавиться заметно, а
// не стать 0.02 после декодирования.
uniform sampler2D uTex;    // linear Картинка
uniform float uAlpha;      // 1 [0, 1] Видимость
uniform float uTextured;   // 1 [0, 1] Есть картинка
// Картинка светила — пиксельный диск и мягкий ореол, запечённый в те же
// 64×64 клетки. Резкая выборка оставляла ореол лесенкой крупных квадратов,
// плавная — мылила диск. Поэтому раздельно: тексель диска (яркий) — как
// есть, ореол — билинейно по соседям, где яркие тексели диска прижаты к
// уровню ореола (иначе вокруг диска встала бы светлая мыльная кайма).
const float DISC = 0.2;     // ярче — тексель диска
const float GLOW = 0.16;    // самый яркий тексель ореола (у края диска)
vec3 texel(ivec2 p, ivec2 size) {
    vec4 c = texelFetch(uTex, clamp(p, ivec2(0), size - 1), 0);
    return c.rgb * c.a;
}
vec3 halo(vec3 c) {
    float m = max(c.r, max(c.g, c.b));
    return m > GLOW ? c * (GLOW / m) : c;
}
vec3 sampleCelestial(vec2 uv) {
    ivec2 size = textureSize(uTex, 0);
    vec2 p = uv * vec2(size);
    vec3 near = texel(ivec2(floor(p)), size);
    if (max(near.r, max(near.g, near.b)) > DISC) return near;
    // Ореол нарисован парами пикселей (шаг 2): билинейно по сетке с тем же
    // шагом — иначе между парами оставались ровные ступени.
    vec2 q = p / 2.0 - 0.5;
    ivec2 i = ivec2(floor(q));
    vec2 f = smoothstep(0.0, 1.0, q - vec2(i));
    vec3 a = halo(texel(i * 2, size)), b = halo(texel((i + ivec2(1, 0)) * 2, size));
    vec3 c = halo(texel((i + ivec2(0, 1)) * 2, size)), d = halo(texel((i + ivec2(1, 1)) * 2, size));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void main() {
    if (uTextured > 0.5) {
        vec4 c = vec4(sampleCelestial(vUV), 1.0);
        FragColor = vec4(c.rgb * c.a * uAlpha, 1.0);
    } else {
        // Звёзды: яркость оригинала — в sRGB; к тёмному небу — в линейный.
        float a = uAlpha;
        float lin = a <= 0.04045 ? a / 12.92 : pow((a + 0.055) / 1.055, 2.4);
        FragColor = vec4(vec3(lin), 1.0);
    }
}

#version 330 core
// Трещины ломаемого блока (RenderGlobal.drawBlockDamageTexture 1.7.10):
// плитка стадии ложится на блок смешением GL_DST_COLOR, GL_SRC_COLOR —
// фон × удвоенный цвет плитки (материал: "blend": "modulate2x"). Серое
// 128 блок не меняет, тёмные штрихи затемняют, светлые чуть осветляют.
// Прозрачное отсекается альфа-тестом (> 0.1), как у оригинала.
//
// Оригинал умножает в sRGB: блок' = 2·s·блок. Кадр движка линейный, и то же
// умножение в нём — блок' = (2·s)^2.2 · блок; смешение даёт 2·цвет·фон,
// значит цвет = (2·s)^2.2 / 2.
layout (location = 0) out vec4 FragColor;
in vec2 vUV;
in vec2 vLight;
in vec3 vNormal;
in vec3 vWorld;
in vec3 vTint;
in float vAlpha;
uniform sampler2D uAtlas;   // Атлас граней
uniform float uOpacity;
vec3 toSrgb(vec3 c) {
    return mix(c * 12.92, 1.055 * pow(max(c, vec3(0.0)), vec3(1.0 / 2.4)) - 0.055, step(0.0031308, c));
}
void main() {
    vec4 tex = texture(uAtlas, vUV);
    if (tex.a <= 0.1) discard;
    vec3 s = toSrgb(tex.rgb);
    FragColor = vec4(0.5 * pow(2.0 * s, vec3(2.2)), 1.0);
}

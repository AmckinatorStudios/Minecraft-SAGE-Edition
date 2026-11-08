#version 330 core
// Осколок блока (EntityDiggingFX 1.7.10): кусочек текстуры стороны блока из
// атласа, серый 0.6 × свет клетки осколка. Свет — уровни неба и блоков в
// цвете объекта (lightmap.applyLevels), как у предметов на шейдере участка.
// Прозрачное отсекается (альфа-тест 0.1 оригинала); смешение — обычное
// SRC_ALPHA, ONE_MINUS_SRC_ALPHA, глубина не пишется (прозрачный материал).
layout (location = 0) out vec4 FragColor;
in vec2 vUV;
in vec3 vTint;
uniform sampler2D uAtlas;      // Атлас граней
uniform sampler2D uLightCells; // Световая карта
vec3 toLinear(vec3 c) {
    return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}
vec3 toSrgb(vec3 c) {
    return mix(c * 12.92, 1.055 * pow(max(c, vec3(0.0)), vec3(1.0 / 2.4)) - 0.055, step(0.0031308, c));
}
void main() {
    vec4 tex = texture(uAtlas, vUV);
    if (tex.a < 0.1) discard;
    vec2 level = toSrgb(vTint).xy * 15.0;
    vec3 lm = textureLod(uLightCells, (vec2(level.y, level.x) + 0.5) / 16.0, 0.0).rgb;
    FragColor = vec4(tex.rgb * toLinear(vec3(0.6)) * lm, tex.a);
}

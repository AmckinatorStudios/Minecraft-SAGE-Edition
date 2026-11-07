#version 330 core
// Освещение Minecraft 1.7.10 без теней движка: цвет поверхности =
// текстура × оттенок вершины × световая карта (lightmap.lua) по уровням
// неба и блоков. Оттенок вершины — сторона грани (верх 1, низ 0.5, X 0.6,
// Z 0.8) × затенение угла (длина нормали, mesher.lua). День и ночь, мерцание
// факелов, погода — только в световой карте: меш не пересобирается.
layout (location = 0) out vec4 FragColor;

in vec2 vUV;
in vec2 vLight;
in vec3 vNormal;
in vec3 vWorld;
in vec3 vTint;
in float vAlpha;

uniform sampler2D uAtlas;    // Атлас граней
uniform sampler2D uLightCells; // Световая карта
uniform vec3 uViewPos;
uniform float uOpacity;

// @header Свет
uniform float uEntityLight;  // 0 [0, 1] Свет из цвета объекта
uniform float uDaylight;     // 1 [0, 1] Дневной свет
uniform vec3 uTint;          // color 1 1 1 Оттенок материала

// @header Туман
uniform vec3 uFogColor;      // color 0.7 0.82 1 Цвет тумана
uniform float uFogStart;     // 60 [0, 400] Начало тумана
uniform float uFogEnd;       // 110 [0, 500] Конец тумана
uniform float uUnderwater;   // 0 [0, 1] Камера в воде

// Числа оригинала — в sRGB (он умножает цвета в этом пространстве), движок
// же считает в линейном: множители переводятся туда.
vec3 toLinear(vec3 c) {
    return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}
vec3 toSrgb(vec3 c) {
    return mix(c * 12.92, 1.055 * pow(max(c, vec3(0.0)), vec3(1.0 / 2.4)) - 0.055, step(0.0031308, c));
}

void main() {
    vec4 tex = texture(uAtlas, vUV);
    if (tex.a < 0.5 && uOpacity >= 0.999) discard;

    vec3 n = normalize(vNormal);
    float side;
    if (n.y > 0.5) side = 1.0;
    else if (n.y < -0.5) side = 0.5;
    else if (abs(n.z) > 0.5) side = 0.8;
    else side = 0.6;
    float ao = clamp(length(vNormal), 0.0, 1.0);

    // Уровни света: у участка — из вершины; у предмета, руки, стрелы — из
    // цвета объекта (уровни клетки, где он стоит: небо/15, блоки/15).
    vec2 level = vLight;
    vec3 tint = vTint;
    if (uEntityLight > 0.5) {
        level = toSrgb(vTint).xy * 15.0;
        tint = vec3(1.0);
    }
    // Ячейка карты: X — блоки, Y — небо; центры ячеек — (уровень + 0.5)/16.
    vec3 lm = textureLod(uLightCells, (vec2(level.y, level.x) + 0.5) / 16.0, 0.0).rgb;
    vec3 color = tex.rgb * uTint * tint * lm * toLinear(vec3(side * ao));

    float dist = length(vWorld - uViewPos);
    float fogStart = mix(uFogStart, 0.0, uUnderwater);
    float fogEnd = mix(uFogEnd, 14.0, uUnderwater);
    vec3 fogColor = mix(uFogColor, vec3(0.05, 0.12, 0.35) * max(uDaylight, 0.15), uUnderwater);
    float fog = clamp((dist - fogStart) / max(fogEnd - fogStart, 0.001), 0.0, 1.0);
    color = mix(color, fogColor, fog);

    float alpha = uOpacity < 0.999 ? tex.a * uOpacity * vAlpha : 1.0;
    FragColor = vec4(color, alpha);
}

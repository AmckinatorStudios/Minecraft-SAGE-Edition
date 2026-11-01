#version 330 core
// Свет по вокселям без теней: яркость = max(небо × день, блоки) по кривой
// уровней, сторона грани — постоянный множитель (верх ярче боков), туман —
// к цвету неба у горизонта. Ни одного источника света движка: так мир
// выглядит одинаково при любой их настройке.
layout (location = 0) out vec4 FragColor;

in vec2 vUV;
in vec2 vLight;
in vec3 vNormal;
in vec3 vWorld;
in vec3 vTint;
in float vAlpha;

uniform sampler2D uAtlas;   // Атлас граней
uniform vec3 uViewPos;
uniform float uOpacity;

// @header Свет
uniform float uDaylight;    // 1 [0, 1] Дневной свет
uniform vec3 uSkyTint;      // color 1 1 1 Оттенок неба
uniform vec3 uBlockTint;    // color 1 0.86 0.66 Оттенок огня
uniform float uMinLight;    // 0.05 [0, 0.3] Темнота пещер
uniform float uGamma;       // 0.75 [0.3, 1.5] Кривая уровней
uniform vec3 uTint;         // color 1 1 1 Оттенок материала

// @header Туман
uniform vec3 uFogColor;     // color 0.7 0.82 1 Цвет тумана
uniform float uFogStart;    // 60 [0, 400] Начало тумана
uniform float uFogEnd;      // 110 [0, 500] Конец тумана
uniform float uUnderwater;  // 0 [0, 1] Камера в воде

float curve(float level) {
    // Каждый уровень ниже 15 темнее предыдущего в одно и то же число раз:
    // так свет факела убывает «ступенями», а не линейно.
    float l = clamp(level / 15.0, 0.0, 1.0);
    return pow(l, 1.0 + 2.2 * uGamma) ;
}

void main() {
    vec4 tex = texture(uAtlas, vUV);
    if (tex.a < 0.5 && uOpacity >= 0.999) discard;

    vec3 n = normalize(vNormal);
    float side = 1.0;
    if (n.y > 0.5) side = 1.0;
    else if (n.y < -0.5) side = 0.5;
    else if (abs(n.z) > 0.5) side = 0.8;
    else side = 0.6;

    float sky = curve(vLight.x) * uDaylight;
    float blk = curve(vLight.y);
    vec3 light = max(uSkyTint * sky, uBlockTint * blk);
    light = max(light, vec3(uMinLight));

    vec3 color = tex.rgb * uTint * vTint * light * side;

    float dist = length(vWorld - uViewPos);
    float fogStart = mix(uFogStart, 0.0, uUnderwater);
    float fogEnd = mix(uFogEnd, 14.0, uUnderwater);
    vec3 fogColor = mix(uFogColor, vec3(0.05, 0.12, 0.35) * max(uDaylight, 0.15), uUnderwater);
    float fog = clamp((dist - fogStart) / max(fogEnd - fogStart, 0.001), 0.0, 1.0);
    color = mix(color, fogColor, fog);

    float alpha = uOpacity < 0.999 ? tex.a * uOpacity * vAlpha : 1.0;
    FragColor = vec4(color, alpha);
}

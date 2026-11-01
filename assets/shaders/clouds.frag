#version 330 core
// Белые полупрозрачные коробки: стороны темнее верха, к краю видимости —
// растворяются в тумане, а не обрываются.
layout (location = 0) out vec4 FragColor;
in vec3 vNormal;
in vec3 vWorld;
uniform vec3 uViewPos;
uniform float uOpacity;
uniform float uDaylight;   // 1 [0, 1] Дневной свет
uniform vec3 uFogColor;    // color 0.7 0.82 1 Цвет тумана
uniform float uFogStart;   // 60 [0, 400] Начало тумана
uniform float uFogEnd;     // 110 [0, 500] Конец тумана
uniform vec3 uCloudColor;  // color 1 1 1 Цвет облаков
void main() {
    vec3 n = normalize(vNormal);
    float side = n.y > 0.5 ? 1.0 : (n.y < -0.5 ? 0.7 : (abs(n.z) > 0.5 ? 0.9 : 0.8));
    vec3 c = uCloudColor * side * mix(0.12, 1.0, uDaylight);
    float dist = length(vWorld.xz - uViewPos.xz);
    float far = uFogEnd * 1.6;
    float fade = 1.0 - clamp((dist - uFogStart * 1.4) / max(far - uFogStart * 1.4, 1.0), 0.0, 1.0);
    c = mix(uFogColor, c, fade * 0.85 + 0.15);
    FragColor = vec4(c, uOpacity * fade);
}

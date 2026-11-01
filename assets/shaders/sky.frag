#version 330 core
// Небо: градиент от горизонта к зениту, зарево у солнца на закате и
// восходе, звёзды ночью (по хэшу направления — без текстуры).
layout (location = 0) out vec4 FragColor;
in vec3 vDir;
uniform vec3 uZenith;    // color 0.45 0.62 1 Зенит
uniform vec3 uHorizon;   // color 0.72 0.83 1 Горизонт
uniform vec3 uGlow;      // color 1 0.5 0.2 Зарево
uniform vec3 uSunDir;    // 0 1 0 Направление на солнце
uniform float uGlowAmount; // 0 [0, 1] Сила зарева
uniform float uStars;    // 0 [0, 1] Звёзды
uniform float uTime;

float hash(vec3 p) {
    p = fract(p * 0.3183099 + 0.1);
    p *= 17.0;
    return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

void main() {
    vec3 d = normalize(vDir);
    float h = clamp(d.y, -1.0, 1.0);
    float t = pow(clamp(h, 0.0, 1.0), 0.55);
    vec3 col = mix(uHorizon, uZenith, t);
    // Ниже горизонта — темнее (под миром «пустота», но не чёрная дыра).
    col = mix(col, uHorizon * 0.55, clamp(-h * 3.0, 0.0, 1.0));
    float toSun = max(dot(d, normalize(uSunDir)), 0.0);
    float band = 1.0 - clamp(abs(h) * 2.5, 0.0, 1.0);
    col = mix(col, uGlow, uGlowAmount * band * pow(toSun, 3.0));
    if (uStars > 0.0 && h > 0.0) {
        vec3 cell = floor(d * 140.0);
        float s = hash(cell);
        float tw = 0.75 + 0.25 * sin(uTime * 3.0 + s * 40.0);
        if (s > 0.9965) col += vec3(0.9) * uStars * tw * clamp(h * 4.0, 0.0, 1.0);
    }
    FragColor = vec4(col, 1.0);
}

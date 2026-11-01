#version 330 core
// Трещины ломаемого блока: плитка стадии из атласа ложится НА блок
// смешиванием — тёмные штрихи затемняют его текстуру, прозрачное не трогает.
// Яркость — та же, что у участка (день и свет клетки), иначе ночью трещины
// светились бы поверх тёмного блока.
layout (location = 0) out vec4 FragColor;
in vec2 vUV;
in vec2 vLight;
in vec3 vNormal;
in vec3 vWorld;
in vec3 vTint;
in float vAlpha;
uniform sampler2D uAtlas;   // Атлас граней
uniform float uOpacity;
uniform float uDaylight;    // 1 [0, 1] Дневной свет
uniform float uStrength;    // 0.75 [0, 1] Сила трещин
void main() {
    vec4 tex = texture(uAtlas, vUV);
    if (tex.a < 0.02) discard;
    float sky = pow(clamp(vLight.x / 15.0, 0.0, 1.0), 2.65) * uDaylight;
    float blk = pow(clamp(vLight.y / 15.0, 0.0, 1.0), 2.65);
    float light = max(max(sky, blk), 0.05);
    FragColor = vec4(tex.rgb * light, tex.a * uStrength);
}

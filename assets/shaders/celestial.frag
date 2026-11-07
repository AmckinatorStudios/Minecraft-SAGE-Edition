#version 330 core
// Оригинал рисует светила сложением (GL_SRC_ALPHA, GL_ONE): чёрный фон
// картинки не виден, светлое прибавляется к небу. Здесь — то же через
// обычное смешение: яркость пикселя становится его прозрачностью.
// uAlpha — 1 − сила дождя; у звёзд без текстуры — яркость звёзд.
layout (location = 0) out vec4 FragColor;
in vec2 vUV;
uniform sampler2D uTex;    // Картинка
uniform float uAlpha;      // 1 [0, 1] Видимость
uniform float uTextured;   // 1 [0, 1] Есть картинка
void main() {
    vec4 c = uTextured > 0.5 ? texture(uTex, vUV) : vec4(1.0);
    float a = max(c.r, max(c.g, c.b)) * c.a;
    FragColor = vec4(c.rgb / max(a, 0.001), a * uAlpha);
}

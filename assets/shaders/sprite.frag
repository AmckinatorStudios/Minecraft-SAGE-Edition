#version 330 core
// Яркость картинки — её прозрачность: чёрный фон солнца и луны исчезает,
// и светило ложится на небо сложением, а не квадратом.
layout (location = 0) out vec4 FragColor;
in vec2 vUV;
in vec3 vTint;
uniform sampler2D uTex;  // Картинка
uniform float uOpacity;
void main() {
    vec4 c = texture(uTex, vUV);
    float a = max(c.r, max(c.g, c.b)) * c.a;
    FragColor = vec4(c.rgb * vTint / max(a, 0.001), a * uOpacity);
}

#version 330 core
// shadow.png — чёрное пятно с мягким краем: цвет картинки, прозрачность —
// её альфа × прозрачность квадрата (setColorRGBA_F(1, 1, 1, d6) оригинала).
layout (location = 0) out vec4 FragColor;
in vec2 vUV;
in float vAlpha;
uniform sampler2D uTex;    // Пятно тени
void main() {
    vec4 c = texture(uTex, clamp(vUV, 0.0, 1.0));
    FragColor = vec4(c.rgb, c.a * vAlpha);
}

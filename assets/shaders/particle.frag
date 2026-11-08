#version 330 core
// Частица из листа particles.png (EntityFX): картинка с вырезом по альфе,
// оттенок — цвет объекта (дым серый, огонь как есть).
layout (location = 0) out vec4 FragColor;
in vec2 vUV;
in vec3 vTint;
uniform sampler2D uTex;    // Лист частиц
void main() {
    vec4 c = texture(uTex, vUV);
    if (c.a < 0.1) discard;
    FragColor = vec4(c.rgb * vTint, c.a);
}

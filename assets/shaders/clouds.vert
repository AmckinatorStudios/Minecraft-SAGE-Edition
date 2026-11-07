#version 330 core
// Облака 1.7.10 (renderCloudsFancy): меш построен один раз в клетках
// текстуры вокруг клетки глаза; объект стоит в мировых блоках (×12 по X и Z),
// а какая клетка текстуры под какой гранью — сдвиг uOffset (целые клетки
// глаза с ветром, ÷256).
layout (location = 0) in vec3 aPos;
layout (location = 1) in vec3 aNormal;
layout (location = 2) in vec2 aUV;
layout (location = 4) in vec4 iM0;
layout (location = 5) in vec4 iM1;
layout (location = 6) in vec4 iM2;
layout (location = 7) in vec4 iM3;
uniform mat4 uView;
uniform mat4 uProjection;
uniform vec2 uOffset;
out vec3 vNormal;
out vec3 vWorld;
out vec2 vUV;
void main() {
    mat4 model = mat4(iM0, iM1, iM2, iM3);
    vec4 w = model * vec4(aPos, 1.0);
    vNormal = aNormal;
    vWorld = w.xyz;
    vUV = aUV + uOffset;
    gl_Position = uProjection * uView * w;
}

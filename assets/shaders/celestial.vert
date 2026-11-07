#version 330 core
// Солнце, луна, звёзды: обычные квадраты на небесной сфере радиуса 100 —
// поворачивает их объект (угол небесной сферы), а не камера.
layout (location = 0) in vec3 aPos;
layout (location = 2) in vec2 aUV;
layout (location = 4) in vec4 iM0;
layout (location = 5) in vec4 iM1;
layout (location = 6) in vec4 iM2;
layout (location = 7) in vec4 iM3;
uniform mat4 uView;
uniform mat4 uProjection;
out vec2 vUV;
void main() {
    mat4 model = mat4(iM0, iM1, iM2, iM3);
    vUV = aUV;
    gl_Position = uProjection * uView * (model * vec4(aPos, 1.0));
}

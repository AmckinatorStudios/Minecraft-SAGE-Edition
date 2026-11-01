#version 330 core
// Облака — объёмные коробки. Сдвиг ветром — в шейдере (uOffset), меш
// пересобирается, только когда облачное поле уезжает на целую клетку.
layout (location = 0) in vec3 aPos;
layout (location = 1) in vec3 aNormal;
layout (location = 4) in vec4 iM0;
layout (location = 5) in vec4 iM1;
layout (location = 6) in vec4 iM2;
layout (location = 7) in vec4 iM3;
uniform mat4 uView;
uniform mat4 uProjection;
out vec3 vNormal;
out vec3 vWorld;
void main() {
    mat4 model = mat4(iM0, iM1, iM2, iM3);
    vec4 w = model * vec4(aPos, 1.0);
    vNormal = aNormal;
    vWorld = w.xyz;
    gl_Position = uProjection * uView * w;
}

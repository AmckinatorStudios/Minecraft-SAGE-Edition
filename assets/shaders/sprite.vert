#version 330 core
// Плоская картинка в мире (солнце, луна): своя текстура, без освещения.
layout (location = 0) in vec3 aPos;
layout (location = 2) in vec2 aUV;
layout (location = 4) in vec4 iM0;
layout (location = 5) in vec4 iM1;
layout (location = 6) in vec4 iM2;
layout (location = 7) in vec4 iM3;
layout (location = 8) in vec3 iColor;
uniform mat4 uView;
uniform mat4 uProjection;
out vec2 vUV;
out vec3 vTint;
// Квадрат — билборд: углы откладываются в пространстве КАМЕРЫ от центра
// объекта, поэтому светило всегда смотрит на зрителя ровным квадратом. Поворот
// объекта не участвует: подбирать его скриптом под наклонную орбиту значило
// получать перекошенный параллелограмм, стоило орбите отойти от плоскости XY.
void main() {
    mat4 model = mat4(iM0, iM1, iM2, iM3);
    vUV = aUV;
    vTint = iColor;
    vec4 center = uView * (model * vec4(0.0, 0.0, 0.0, 1.0));
    float size = length(model[0].xyz);
    vec4 corner = center + vec4(aPos.x * size, aPos.z * size, 0.0, 0.0);
    gl_Position = uProjection * corner;
}

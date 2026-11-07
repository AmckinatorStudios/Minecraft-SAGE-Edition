#version 330 core
// Тень под существом: квадраты на верхних гранях блоков, прозрачность
// квадрата — второй UV (у каждого блока своя: высота над ним и его свет).
layout (location = 0) in vec3 aPos;
layout (location = 2) in vec2 aUV;
layout (location = 11) in vec2 aUV2;
layout (location = 4) in vec4 iM0;
layout (location = 5) in vec4 iM1;
layout (location = 6) in vec4 iM2;
layout (location = 7) in vec4 iM3;
uniform mat4 uView;
uniform mat4 uProjection;
out vec2 vUV;
out float vAlpha;
void main() {
    mat4 model = mat4(iM0, iM1, iM2, iM3);
    vUV = aUV;
    vAlpha = aUV2.x;
    gl_Position = uProjection * uView * (model * vec4(aPos, 1.0));
}

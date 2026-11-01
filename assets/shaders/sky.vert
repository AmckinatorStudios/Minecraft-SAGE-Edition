#version 330 core
// Купол неба вокруг камеры: направление взгляда — это просто позиция вершины
// сферы относительно её центра.
layout (location = 0) in vec3 aPos;
layout (location = 4) in vec4 iM0;
layout (location = 5) in vec4 iM1;
layout (location = 6) in vec4 iM2;
layout (location = 7) in vec4 iM3;
uniform mat4 uView;
uniform mat4 uProjection;
out vec3 vDir;
void main() {
    mat4 model = mat4(iM0, iM1, iM2, iM3);
    vDir = aPos;
    gl_Position = uProjection * uView * (model * vec4(aPos, 1.0));
}

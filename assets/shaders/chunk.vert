#version 330 core
// Участок мира. Свет запечён в вершины: uv2 = (уровень неба, уровень блоков)
// 0..15, уже с затенением углов. День/ночь — множитель uDaylight, поэтому
// закат не пересобирает ни одного меша.
layout (location = 0) in vec3 aPos;
layout (location = 1) in vec3 aNormal;
layout (location = 2) in vec2 aUV;
layout (location = 11) in vec2 aUV2;
layout (location = 4) in vec4 iM0;
layout (location = 5) in vec4 iM1;
layout (location = 6) in vec4 iM2;
layout (location = 7) in vec4 iM3;
layout (location = 8) in vec3 iColor;
layout (location = 12) in float iAlpha;

uniform mat4 uView;
uniform mat4 uProjection;
uniform float uTime;
uniform float uWave; // 0 [0, 1] Колыхание (жидкость)

out vec2 vUV;
out vec2 vLight;
out vec3 vNormal;
out vec3 vWorld;
out vec3 vTint;
out float vAlpha;

void main() {
    mat4 model = mat4(iM0, iM1, iM2, iM3);
    vec4 world = model * vec4(aPos, 1.0);
    if (uWave > 0.0 && aNormal.y > 0.5)
        world.y += (sin(world.x * 1.7 + uTime * 1.6) + cos(world.z * 1.3 + uTime * 1.2)) * 0.025 * uWave - 0.03;
    vUV = aUV;
    vLight = aUV2;
    vNormal = aNormal;
    vWorld = world.xyz;
    vTint = iColor;
    vAlpha = iAlpha;
    gl_Position = uProjection * uView * world;
}

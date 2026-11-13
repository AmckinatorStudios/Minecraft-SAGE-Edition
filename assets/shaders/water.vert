#version 330 core
// Вода: тот же вход, что у участка (chunk.vert), плюс лёгкое колыхание глади.
// Волна — функция мировой точки: у соседних граней вершины на стыке
// смещаются одинаково, и гладь не рвётся по блокам. Мелкая рябь — не здесь,
// а в нормалях фрагментного шейдера (water.frag): у грани 1×1 блок всего
// четыре вершины.
layout (location = 0) in vec3 aPos;
layout (location = 1) in vec3 aNormal;
layout (location = 2) in vec2 aUV;
layout (location = 11) in vec2 aUV2;
layout (location = 4) in vec4 iM0;
layout (location = 5) in vec4 iM1;
layout (location = 6) in vec4 iM2;
layout (location = 7) in vec4 iM3;
layout (location = 8) in vec3 iColor;

uniform mat4 uView;
uniform mat4 uProjection;
uniform float uTime;
uniform float uSwell; // 0.035 [0, 0.2] Высота зыби, блоков

out vec2 vLight;
out vec3 vNormal;
out vec3 vWorld;
out vec3 vTint;

void main() {
    vec4 world = mat4(iM0, iM1, iM2, iM3) * vec4(aPos, 1.0);
    if (aNormal.y > 0.5) {
        float t = uTime;
        world.y += (sin(dot(world.xz, vec2(0.37, 0.21)) + t * 1.10) * 0.6
                  + sin(dot(world.xz, vec2(-0.19, 0.43)) + t * 0.83) * 0.4) * uSwell - uSwell;
    }
    vLight = aUV2;
    vNormal = aNormal;
    vWorld = world.xyz;
    vTint = iColor;
    gl_Position = uProjection * uView * world;
}

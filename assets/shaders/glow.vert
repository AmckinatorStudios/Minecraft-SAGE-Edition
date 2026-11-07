#version 330 core
// Веер зари (calcSunriseSunsetColors): центр — над горизонтом у солнца, край —
// кольцо радиуса 120; край сдвинут на −cos·40·альфа — второй UV хранит −cos·40,
// альфа меняется каждый кадр, меш — нет.
layout (location = 0) in vec3 aPos;
layout (location = 2) in vec2 aUV;
layout (location = 11) in vec2 aUV2;
layout (location = 4) in vec4 iM0;
layout (location = 5) in vec4 iM1;
layout (location = 6) in vec4 iM2;
layout (location = 7) in vec4 iM3;
uniform mat4 uView;
uniform mat4 uProjection;
uniform vec4 uGlow;
out float vCenter;
void main() {
    mat4 model = mat4(iM0, iM1, iM2, iM3);
    vCenter = aUV.x;
    vec3 p = aPos + vec3(0.0, 0.0, aUV2.y * uGlow.a);
    gl_Position = uProjection * uView * (model * vec4(p, 1.0));
}

#version 330 core
// Цвет зари; прозрачность — от альфы в центре до нуля на краю (плавная
// заливка веера треугольников, как у оригинала).
layout (location = 0) out vec4 FragColor;
in float vCenter;
uniform vec4 uGlow;        // color 1 0.6 0.2 Заря (альфа — сила)
// Цвета Minecraft — значения sRGB, а движок считает вывод шейдера
// линейным и сам кодирует его в sRGB: смешиваем как оригинал (в sRGB) и
// переводим в линейный только на выходе.
vec3 toLinear(vec3 c) {
    return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}

void main() {
    FragColor = vec4(toLinear(uGlow.rgb), uGlow.a * vCenter);
}

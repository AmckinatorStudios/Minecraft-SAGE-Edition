#version 330 core
// Светила — сложением, как у оригинала (GL_SRC_ALPHA, GL_ONE; материал
// "blend": "additive" — src + dst): к небу прибавляется цвет картинки ×
// её альфа × видимость. Чёрный фон картинки не прибавляет ничего, жёлтое
// солнце на голубом небе становится белым — как в 1.7.10.
// uAlpha — 1 − сила дождя; у звёзд без текстуры — яркость звёзд в квадрате.
layout (location = 0) out vec4 FragColor;
in vec2 vUV;
// linear: картинка без перевода из sRGB — оригинал складывает в гамма-
// пространстве, и слабый ореол солнца (0.15) обязан прибавиться заметно, а
// не стать 0.02 после декодирования.
uniform sampler2D uTex;    // linear Картинка
uniform float uAlpha;      // 1 [0, 1] Видимость
uniform float uTextured;   // 1 [0, 1] Есть картинка
void main() {
    if (uTextured > 0.5) {
        vec4 c = texture(uTex, vUV);
        FragColor = vec4(c.rgb * c.a * uAlpha, 1.0);
    } else {
        // Звёзды: яркость оригинала — в sRGB; к тёмному небу — в линейный.
        float a = uAlpha;
        float lin = a <= 0.04045 ? a / 12.92 : pow((a + 0.055) / 1.055, 2.4);
        FragColor = vec4(vec3(lin), 1.0);
    }
}

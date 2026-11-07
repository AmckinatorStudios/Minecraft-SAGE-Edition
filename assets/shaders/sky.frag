#version 330 core
// Небо Minecraft 1.7.10 (RenderGlobal.renderSky) без купола-градиента:
// над глазом — плоскость на высоте 16 цвета getSkyColor, под линейным
// туманом от 0 до 0.8 дальности (setupFog(-1)); туман по расстоянию до
// точки плоскости и даёт горизонт цвета тумана. Ниже горизонта — плоскость
// «пустоты» на высоте горизонта мира (63) цвета неба ×0.2; глаз ниже неё —
// чёрная коробка. Где плоскостей нет — цвет очистки кадра = цвет тумана.
layout (location = 0) out vec4 FragColor;
in vec3 vDir;
uniform vec3 uSkyColor;    // color 0.47 0.65 1 Цвет неба
uniform vec3 uFogColor;    // color 0.75 0.85 1 Цвет тумана
uniform vec3 uVoidColor;   // color 0.13 0.17 0.7 Цвет пустоты
uniform float uFogEnd;     // 204.8 [1, 1000] Конец тумана неба
uniform float uEyeHeight;  // 1 [-256, 256] Глаз над горизонтом мира

// Цвета Minecraft — значения sRGB, а движок считает вывод шейдера
// линейным и сам кодирует его в sRGB: смешиваем как оригинал (в sRGB) и
// переводим в линейный только на выходе.
vec3 toLinear(vec3 c) {
    return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}

float fogged(float t) { return clamp(1.0 - t / uFogEnd, 0.0, 1.0); }

void main() {
    vec3 d = normalize(vDir);
    vec3 col = uFogColor;
    if (d.y > 0.0) {
        float t = 16.0 / d.y;
        vec3 p = d * t;
        if (max(abs(p.x), abs(p.z)) <= 384.0) col = mix(uFogColor, uSkyColor, fogged(t));
    } else if (d.y < 0.0) {
        if (uEyeHeight >= 0.0) {
            float t = uEyeHeight / -d.y;
            vec3 p = d * t;
            if (max(abs(p.x), abs(p.z)) <= 384.0) col = mix(uFogColor, uVoidColor, fogged(t));
        } else {
            // Чёрная коробка радиуса 1 ниже глаза и чёрная плоскость под ней.
            float h = length(d.xz);
            if (-d.y > h) col = vec3(0.0);
            else col = mix(uFogColor, vec3(0.0), fogged(4.0 / -d.y));
        }
    }
    FragColor = vec4(toLinear(col), 1.0);
}

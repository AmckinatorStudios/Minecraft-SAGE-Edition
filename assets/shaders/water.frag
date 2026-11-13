#version 330 core
// ---------------------------------------------------------------------------
// Вода. Свет и цвет считаются так, как их видит глаз, а не «синяя плёнка с
// прозрачностью»:
//   • ПРЕЛОМЛЕНИЕ — дно берётся из кадра ЗА водой (uSceneColor движка) со
//     сдвигом по нормали ряби; ближе к камере и на мели сдвиг меньше, а то,
//     что стоит ПЕРЕД водой, в преломление не попадает (проверка глубины);
//   • ПОГЛОЩЕНИЕ — закон Бугера–Ламберта по толщине воды вдоль взгляда
//     (uSceneDepth): красный гаснет первым, поэтому мель — прозрачная, с
//     бирюзой, а глубина — тёмно-сине-зелёная; свет, рассеянный толщей, —
//     цвет глубины, освещённый так же, как сама гладь (карта света);
//   • КАУСТИКА — световая сетка на дне: проекция ряби, гаснущая с глубиной и
//     только там, куда достаёт небо (днём, не в пещере);
//   • ОТРАЖЕНИЕ — небо по Френелю (Шлик, F0 = 0.02): сверху вода прозрачна,
//     к горизонту зеркальна; блик солнца по рассчитанной нормали;
//   • ПЕНА — тонкая кромка у берега, там, где воды почти нет.
// Цвета — в линейном пространстве (кадр движка HDR-линейный), туман — как у
// участков (chunk.frag). Из-под воды гладь не отражает, а пропускает.
// ---------------------------------------------------------------------------
layout (location = 0) out vec4 FragColor;

in vec2 vLight;
in vec3 vNormal;
in vec3 vWorld;
in vec3 vTint;

uniform sampler2D uLightCells;  // Световая карта
uniform sampler2D uSceneColor;  // кадр за водой (движок)
uniform sampler2D uSceneDepth;  // его глубина (движок)
uniform vec2 uViewportPos;
uniform vec2 uViewportSize;
uniform mat4 uProjection;
uniform vec3 uViewPos;
uniform float uTime;

// @header Вода
uniform vec3 uShallowColor;    // color 0.04 0.30 0.30 Рассеяние на мели
uniform vec3 uDeepColor;       // color 0.005 0.045 0.075 Рассеяние в глубине
uniform vec3 uAbsorption;      // 0.42 0.11 0.075 Поглощение R G B за блок
uniform float uRefraction;     // 0.35 [0, 2] Преломление
uniform float uRipple;         // 1 [0, 3] Сила ряби
uniform float uCaustics;       // 1.8 [0, 4] Каустика на дне
uniform float uFoam;           // 0.45 [0, 2] Пена у берега

// @header Небо и свет
uniform vec3 uSkyColor;        // color 0.45 0.62 1 Небо в зените (линейное)
uniform vec3 uSunDir;          // 0.3 0.9 0 Направление на солнце
uniform float uSunStrength;    // 1 [0, 4] Солнце: блик и каустика
uniform float uDaylight;       // 1 [0, 1] Дневной свет

// @header Туман
uniform vec3 uFogColor;        // color 0.7 0.82 1 Цвет тумана
uniform float uFogStart;       // 60 [0, 400] Начало тумана
uniform float uFogEnd;         // 110 [0, 500] Конец тумана
uniform float uUnderwater;     // 0 [0, 1] Камера в воде

// --- Рябь: сумма направленных волн + шум; нормаль — по производным ----------
const int WAVES = 6;
const vec3 W[WAVES] = vec3[WAVES](   // направление (xz), длина волны в блоках
    vec3(0.80, 0.60, 3.1), vec3(-0.55, 0.83, 1.9), vec3(0.20, -0.98, 1.3),
    vec3(-0.93, -0.36, 0.87), vec3(0.62, -0.78, 0.61), vec3(0.98, 0.17, 0.43));

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

// Наклон глади (dh/dx, dh/dz) в точке p.
vec2 slope(vec2 p, float t, float fade) {
    vec2 d = vec2(0.0);
    for (int i = 0; i < WAVES; ++i) {
        float k = 6.2831853 / W[i].z;          // волновое число
        float a = 0.011 * W[i].z;              // амплитуда ∝ длине (крутизна постоянна)
        float c = sqrt(9.8 * k) * 0.35;        // дисперсия глубокой воды, замедленная
        float ph = dot(W[i].xy, p) * k + t * c;
        d += W[i].xy * (a * k * cos(ph));
    }
    // Мелкая «шершавость» шумом (конечная разность), гаснет вдали.
    vec2 q = p * 2.3 + vec2(t * 0.35, -t * 0.27);
    float e = 0.07;
    float n0 = vnoise(q), nx = vnoise(q + vec2(e, 0.0)), nz = vnoise(q + vec2(0.0, e));
    d += vec2(nx - n0, nz - n0) / e * 0.018 * fade;
    return d * uRipple;
}

// Каустика: световая сетка (схема Dave_Hoskins, «Tileable Water Caustic»).
float caustic(vec2 uv, float t) {
    vec2 p = mod(uv * 6.2831853, 6.2831853) - 250.0;
    vec2 i = p;
    float c = 1.0;
    const float inten = 0.005;
    for (int n = 0; n < 5; ++n) {
        float tt = t * (1.0 - 3.5 / float(n + 1));
        i = p + vec2(cos(tt - i.x) + sin(tt + i.y), sin(tt - i.y) + cos(tt + i.x));
        c += 1.0 / length(vec2(p.x / (sin(i.x + tt) / inten), p.y / (cos(i.y + tt) / inten)));
    }
    c /= 5.0;
    c = 1.17 - pow(c, 1.4);
    return pow(abs(c), 8.0);
}

// Расстояние вдоль оси взгляда по значению буфера глубины 0..1.
float linearDepth(float d) {
    float z = d * 2.0 - 1.0;
    return uProjection[3][2] / (z + uProjection[2][2]);
}

void main() {
    vec3 toEye = uViewPos - vWorld;
    float dist = length(toEye);
    vec3 V = toEye / max(dist, 1e-4);
    bool fromBelow = !gl_FrontFacing || uUnderwater > 0.5;

    // Нормаль глади: у верхней грани — рябь, у боковых — как есть.
    vec3 n = normalize(vNormal);
    bool top = n.y > 0.5;
    if (top) {
        float fade = clamp(1.0 - dist / 48.0, 0.0, 1.0);
        vec2 s = slope(vWorld.xz, uTime, fade) * mix(0.35, 1.0, fade);
        n = normalize(vec3(-s.x, 1.0, -s.y));
    }
    if (fromBelow) n = -n;

    // Свет места: та же карта света, что у участков (ночь, пещера, факел).
    vec3 lm = textureLod(uLightCells, (vec2(vLight.y, vLight.x) + 0.5) / 16.0, 0.0).rgb;
    float skyOpen = clamp(vLight.x / 15.0, 0.0, 1.0);

    // --- Кадр за водой и толщина воды -------------------------------------
    vec2 uv = (gl_FragCoord.xy - uViewportPos) / uViewportSize;
    float surface = linearDepth(gl_FragCoord.z);
    float behindRaw = linearDepth(texture(uSceneDepth, uv).r);
    float thick0 = max(behindRaw - surface, 0.0) * dist / max(surface, 1e-3);   // вдоль взгляда
    // Сдвиг преломления: по наклону ряби, меньше вдали и на мели.
    vec2 offs = n.xz * uRefraction * 0.06 * clamp(thick0 * 0.6, 0.0, 1.0) * (6.0 / (6.0 + surface));
    vec2 ruv = clamp(uv + offs, vec2(0.001), vec2(0.999));
    float behind = linearDepth(texture(uSceneDepth, ruv).r);
    // То, что стоит перед водой, в преломление не берём: сдвиг — назад.
    if (behind < surface) { ruv = uv; behind = behindRaw; }
    float thick = max(behind - surface, 0.0) * dist / max(surface, 1e-3);
    // Боковая грань — ступенька глади у края или стенка у воздуха: вода за
    // ней по горизонтали тонкая (до соседнего блока), а не «стена моря».
    if (!top) thick = min(thick, 1.0);
    vec3 under = texture(uSceneColor, ruv).rgb;

    // Точка дна под пикселем — на том же луче, на глубине behind.
    vec3 bottom = uViewPos - V * (behind / max(surface, 1e-3)) * dist;
    float vdepth = max(vWorld.y - bottom.y, 0.0);   // глубина по вертикали

    // --- Каустика на дне ---------------------------------------------------
    if (!fromBelow && uCaustics > 0.0) {
        // Сетка смещается с наклоном солнца и дрожит с рябью.
        vec2 cp = bottom.xz * 0.23 + uSunDir.xz * vdepth * 0.08;
        float c = caustic(cp, uTime * 0.55) + caustic(cp * 1.7 + 3.1, uTime * 0.4) * 0.5;
        float reach = exp(-vdepth * 0.28) * smoothstep(0.0, 0.35, vdepth);
        float sun = uSunStrength * uDaylight * skyOpen * skyOpen;
        under += under * c * reach * sun * uCaustics;
    }

    // --- Поглощение и рассеяние в толще ------------------------------------
    vec3 T = exp(-uAbsorption * thick);
    vec3 scatter = mix(uShallowColor, uDeepColor, 1.0 - exp(-thick * 0.18)) * lm * vTint;
    vec3 refracted = under * T + scatter * (1.0 - T);

    // --- Отражение неба и блик солнца ---------------------------------------
    float cosV = clamp(dot(n, V), 0.0, 1.0);
    float fresnel = fromBelow ? 0.0 : 0.02 + 0.98 * pow(1.0 - cosV, 5.0);
    vec3 R = reflect(-V, n);
    float up = clamp(R.y, 0.0, 1.0);
    vec3 sky = mix(uFogColor, uSkyColor, pow(up, 0.45)) * skyOpen + uDeepColor * (1.0 - skyOpen);
    vec3 reflection = sky * max(uDaylight, 0.08);
    vec3 L = normalize(uSunDir);
    vec3 H = normalize(L + V);
    float spec = pow(max(dot(n, H), 0.0), 720.0) * 9.0 + pow(max(dot(n, H), 0.0), 90.0) * 0.18;
    spec *= uSunStrength * skyOpen * step(0.0, L.y) * (fromBelow ? 0.0 : 1.0);

    vec3 color = mix(refracted, reflection, fresnel) + vec3(1.0, 0.96, 0.88) * spec;

    // --- Пена у берега -------------------------------------------------------
    if (top && !fromBelow && uFoam > 0.0) {
        float edge = 1.0 - smoothstep(0.0, 0.2, vdepth);
        float pattern = vnoise(vWorld.xz * 3.1 + vec2(uTime * 0.21, uTime * 0.17));
        pattern *= vnoise(vWorld.xz * 7.3 - vec2(uTime * 0.31, 0.0));
        // Пена — клочьями: шум решает, где она есть, кромка — только где мелко.
        float foam = edge * smoothstep(0.18, 0.42, pattern + edge * 0.12) * uFoam;
        color = mix(color, vec3(0.92, 0.97, 1.0) * lm, clamp(foam, 0.0, 0.8));
    }

    // --- Туман — как у участков --------------------------------------------
    float fogStart = mix(uFogStart, 0.0, uUnderwater);
    float fogEnd = mix(uFogEnd, 14.0, uUnderwater);
    vec3 fogColor = mix(uFogColor, vec3(0.05, 0.12, 0.35) * max(uDaylight, 0.15), uUnderwater);
    float fog = clamp((dist - fogStart) / max(fogEnd - fogStart, 0.001), 0.0, 1.0);
    color = mix(color, fogColor, fog);

    // Кадр за водой уже вошёл в цвет — смешивать ещё раз нечего.
    FragColor = vec4(color, 1.0);
}

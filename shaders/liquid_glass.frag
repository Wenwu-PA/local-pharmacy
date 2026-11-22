#version 460 core
#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uLensCenter;
uniform sampler2D uBackdrop;
out vec4 fragColor;

void main() {
    vec2 uv = FlutterFragCoord().xy / uSize;
    vec2 center = vec2(uLensCenter, 0.5);
    vec2 lensPosition = (uv - center) / vec2(0.14, 0.56);
    float lens = 1.0 - smoothstep(0.48, 1.08, length(lensPosition));
    vec2 refracted = mix(uv, center, lens * 0.24);
    vec2 glassEdge = abs(uv - 0.5) * 2.0;
    refracted += (vec2(0.5) - uv) * 0.043 * smoothstep(0.68, 1.0, max(glassEdge.x, glassEdge.y));
    #ifdef IMPELLER_TARGET_OPENGLES
      refracted.y = 1.0 - refracted.y;
    #endif
    vec2 spread = vec2(8.5) / uSize;
    vec4 soft = texture(uBackdrop, refracted) * 0.28;
    soft += texture(uBackdrop, refracted + vec2(spread.x, spread.y)) * 0.18;
    soft += texture(uBackdrop, refracted - vec2(spread.x, spread.y)) * 0.18;
    soft += texture(uBackdrop, refracted + vec2(-spread.x, spread.y)) * 0.18;
    soft += texture(uBackdrop, refracted + vec2(spread.x, -spread.y)) * 0.18;
    fragColor = soft;
}

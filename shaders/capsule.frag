#version 460 core
#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform vec3 uAxisX;
uniform vec3 uAxisY;
uniform vec3 uAxisZ;
uniform float uDark;
out vec4 fragColor;

const float halfLength = 0.48;
const float radius = 0.43;
const float miss = 100.0;

// Transform the camera ray and lights into the capsule's local coordinates.
vec3 toLocal(vec3 p) {
    return vec3(dot(uAxisX, p), dot(uAxisY, p), dot(uAxisZ, p));
}

float sphereHit(vec3 origin, vec3 ray, float x) {
    vec3 relative = origin - vec3(x, 0, 0);
    float b = dot(relative, ray);
    float h = b * b - dot(relative, relative) + radius * radius;
    return h >= 0.0 ? -b - sqrt(max(0.0, h)) : miss;
}

float capsuleHit(vec3 origin, vec3 ray) {
    vec2 radial = origin.yz;
    vec2 direction = ray.yz;
    float a = dot(direction, direction);
    float b = dot(radial, direction);
    float h = b * b - a * (dot(radial, radial) - radius * radius);
    float t = miss;
    if (a > 0.0001 && h >= 0.0) {
        float body = (-b - sqrt(h)) / a;
        if (abs(origin.x + body * ray.x) <= halfLength) t = body;
    }
    return min(t, min(sphereHit(origin, ray, -halfLength),
                      sphereHit(origin, ray, halfLength)));
}

float roundedStroke(vec2 p, vec2 halfSize) {
    return 1.0 - smoothstep(0.012, 0.023, length(max(abs(p) - halfSize, vec2(0))));
}

void main() {
    vec2 xy = (FlutterFragCoord().xy - uSize * 0.5) * (2.32 / uSize.x);
    vec3 origin = toLocal(vec3(0, 0, 3.6));
    vec3 ray = toLocal(normalize(vec3(xy.x, -xy.y, -3.6)));
    float t = capsuleHit(origin, ray);
    if (t >= miss) {
        fragColor = vec4(0);
        return;
    }

    vec3 p = origin + t * ray;
    vec3 axis = vec3(clamp(p.x, -halfLength, halfLength), 0, 0);
    vec3 normal = normalize(p - axis);
    vec3 key = toLocal(normalize(vec3(-0.45, 0.75, 0.65)));
    vec3 rimLight = toLocal(normalize(vec3(0.55, -0.23, -0.75)));
    float diffuse = max(0.0, dot(normal, key));
    float facing = max(0.0, dot(normal, -ray));
    float sheen = pow(max(0.0, dot(normal, normalize(key - ray))), 15.0);
    float rim = max(0.0, dot(normal, rimLight)) * pow(1.0 - facing, 2.0);
    float green = smoothstep(-0.004, 0.004, p.x);

    // The ivory face, sage shell, join and medical cross match the supplied artwork.
    vec3 ivory = vec3(0.97, 0.97, 0.91);
    vec3 sage = mix(vec3(0.41, 0.55, 0.44), vec3(0.50, 0.66, 0.53), uDark);
    vec3 color = mix(ivory, sage, green);
    float seam = 1.0 - smoothstep(0.004, 0.013, abs(p.x));
    color *= 1.0 - 0.34 * seam;
    float edge = 1.0 - smoothstep(0.002, 0.013, abs(p.x - 0.019));
    color += vec3(0.10, 0.13, 0.10) * edge;
    vec2 mark = vec2(p.x - 0.42, radius * (atan(p.y, p.z) - 0.28));
    float cross = max(roundedStroke(mark, vec2(0.05, 0.001)),
                      roundedStroke(mark, vec2(0.001, 0.05)));
    color = mix(color, vec3(0.94, 0.99, 0.91), cross * 0.94);
    color *= 0.51 + 0.48 * diffuse;
    color += vec3(0.32, 0.38, 0.31) * sheen + vec3(0.20, 0.31, 0.25) * rim;
    float opacity = smoothstep(0.0, 0.095, facing);
    fragColor = vec4(clamp(color, 0.0, 1.0) * opacity, opacity);
}

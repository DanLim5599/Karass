#version 460 core

#include <flutter/runtime_effect.glsl>

uniform vec2 uResolution;
uniform float uTime;

out vec4 fragColor;

// HSV to RGB conversion
vec3 hsv2rgb(vec3 c) {
    vec4 K = vec4(1.0, 2.0/3.0, 1.0/3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

void main() {
    vec2 fragCoord = FlutterFragCoord().xy;
    vec2 uv = fragCoord / uResolution;
    float aspect = uResolution.x / uResolution.y;

    float t = uTime;

    // Start with transparent - only add colorful effects
    vec3 col = vec3(0.0);
    float alpha = 0.0;

    // === GLOWING ORB ===
    vec2 orbCenter = vec2(
        0.5 + cos(t * 0.3) * 0.25,
        0.5 + sin(t * 0.2) * 0.3
    );

    vec2 scaledUV = vec2((uv.x - 0.5) * aspect, uv.y - 0.5);
    vec2 scaledCenter = vec2((orbCenter.x - 0.5) * aspect, orbCenter.y - 0.5);
    float orbDist = length(scaledUV - scaledCenter);

    // Main glow
    float glow = exp(-orbDist * 4.0);
    glow *= 0.85 + 0.25 * sin(t * 1.5);

    // Orb iridescence - rainbow colors shifting through the orb
    float orbAngle = atan(scaledUV.y - scaledCenter.y, scaledUV.x - scaledCenter.x);
    vec3 orbIri = hsv2rgb(vec3(
        fract(orbAngle / 6.28318 + orbDist * 3.0 - t * 0.3),
        0.6 + 0.3 * sin(orbDist * 15.0 - t * 2.0),
        1.0
    ));

    // Soft base color for orb
    vec3 orbBase = mix(
        vec3(0.9, 0.95, 1.0),
        vec3(1.0, 0.9, 0.95),
        0.5 + 0.5 * sin(t * 0.5)
    );

    vec3 orbColor = mix(orbBase, orbIri, 0.6);

    // Add orb glow
    col += orbColor * glow * 1.2;
    alpha += glow * 0.6;

    // Inner bright core
    float core = exp(-orbDist * 15.0);
    col += vec3(1.0, 0.98, 0.95) * core * 0.7;
    alpha += core * 0.5;

    // Outer halo rings with iridescence
    for(float i = 1.0; i <= 4.0; i += 1.0) {
        float ringDist = abs(orbDist - i * 0.1);
        float ring = exp(-ringDist * 30.0) * (0.5 + 0.5 * sin(t * 2.0 + i));
        vec3 ringColor = hsv2rgb(vec3(fract(i * 0.25 + t * 0.2), 0.5, 1.0));
        col += ringColor * ring * 0.25;
        alpha += ring * 0.15;
    }

    // === Shimmer particles ===
    for(float i = 0.0; i < 12.0; i += 1.0) {
        vec2 particlePos = vec2(
            fract(sin(i * 127.1 + 1.0) * 43758.5453),
            fract(cos(i * 269.5 + 2.0) * 43758.5453)
        );
        particlePos.x += sin(t * (0.4 + i * 0.08) + i) * 0.15;
        particlePos.y += cos(t * (0.25 + i * 0.1) + i * 2.0) * 0.15;

        float pDist = length(vec2((uv.x - particlePos.x) * aspect, uv.y - particlePos.y));
        float pGlow = exp(-pDist * 15.0) * (0.5 + 0.4 * sin(t * 2.5 + i * 1.3));
        vec3 pColor = hsv2rgb(vec3(fract(i * 0.15 + t * 0.08), 0.45, 1.0));
        col += pColor * pGlow * 0.3;
        alpha += pGlow * 0.2;
    }

    // Clamp values
    col = clamp(col, 0.0, 1.0);
    alpha = clamp(alpha, 0.0, 0.85);

    fragColor = vec4(col, alpha);
}

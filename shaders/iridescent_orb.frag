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

    // Start with very light base that will show colors
    vec3 col = vec3(0.96);

    // === STRONG IRIDESCENT GRADIENT covering entire screen ===
    // Use smooth gradients instead of just waves for base coverage
    float yGrad = uv.y;  // 0 at top, 1 at bottom
    float xGrad = uv.x;

    // Iridescent colors that smoothly vary across the ENTIRE screen
    vec3 topColor = hsv2rgb(vec3(fract(0.55 + t * 0.05), 0.35, 1.0));  // Cyan-ish at top
    vec3 bottomColor = hsv2rgb(vec3(fract(0.95 + t * 0.05), 0.4, 1.0));  // Pink at bottom
    vec3 leftColor = hsv2rgb(vec3(fract(0.15 + t * 0.03), 0.3, 1.0));  // Yellow-green
    vec3 rightColor = hsv2rgb(vec3(fract(0.75 + t * 0.03), 0.35, 1.0));  // Purple

    // Mix base gradient across whole screen
    vec3 vertGrad = mix(topColor, bottomColor, yGrad);
    vec3 horzGrad = mix(leftColor, rightColor, xGrad);
    col = mix(col, vertGrad, 0.25);  // 25% vertical gradient
    col = mix(col, horzGrad, 0.15);  // 15% horizontal gradient

    // === Add wave modulation on top of gradient ===
    float wave1 = sin(uv.x * 5.0 + uv.y * 3.0 + t * 0.5);
    float wave2 = sin(uv.x * 3.0 - uv.y * 5.0 + t * 0.7);
    float wave3 = sin((uv.x + uv.y) * 6.0 + t * 0.3);
    float wave4 = sin(length(uv - 0.5) * 8.0 - t * 0.8);

    // Additional iridescence layers with waves
    vec3 iri1 = hsv2rgb(vec3(fract(uv.x + uv.y * 0.5 + t * 0.1), 0.45, 1.0));
    vec3 iri2 = hsv2rgb(vec3(fract(uv.y * 1.5 - uv.x * 0.3 - t * 0.12), 0.4, 1.0));

    col = mix(col, iri1, abs(wave1) * 0.12 + 0.05);
    col = mix(col, iri2, abs(wave2) * 0.10 + 0.05);

    // Add oil-slick style iridescence - covers whole screen
    float oilAngle = atan(uv.y - 0.5, (uv.x - 0.5) * aspect);
    float oilDist = length(vec2((uv.x - 0.5) * aspect, uv.y - 0.5));
    vec3 oilColor = hsv2rgb(vec3(
        fract(oilAngle / 6.28318 + oilDist * 1.5 + t * 0.15),
        0.5,
        1.0
    ));
    col = mix(col, oilColor, 0.12 * (0.7 + 0.3 * wave4));

    // === GLOWING ORB - moves around more of the screen ===
    vec2 orbCenter = vec2(
        0.5 + cos(t * 0.3) * 0.25,
        0.5 + sin(t * 0.2) * 0.3
    );

    vec2 scaledUV = vec2((uv.x - 0.5) * aspect, uv.y - 0.5);
    vec2 scaledCenter = vec2((orbCenter.x - 0.5) * aspect, orbCenter.y - 0.5);
    float orbDist = length(scaledUV - scaledCenter);

    // Main glow - larger radius
    float glow = exp(-orbDist * 4.0);

    // Pulsation
    glow *= 0.85 + 0.25 * sin(t * 1.5);

    // Orb iridescence - rainbow colors shifting through the orb
    float orbAngle = atan(scaledUV.y - scaledCenter.y, scaledUV.x - scaledCenter.x);
    vec3 orbIri = hsv2rgb(vec3(
        fract(orbAngle / 6.28318 + orbDist * 3.0 - t * 0.3),
        0.6 + 0.3 * sin(orbDist * 15.0 - t * 2.0),
        1.0
    ));

    // Soft base color
    vec3 orbBase = mix(
        vec3(0.9, 0.95, 1.0),  // soft blue
        vec3(1.0, 0.9, 0.95),  // soft pink
        0.5 + 0.5 * sin(t * 0.5)
    );

    // Combine orb base with strong iridescence
    vec3 orbColor = mix(orbBase, orbIri, 0.6);

    // Apply glow to scene
    col += orbColor * glow * 1.2;

    // Inner bright core
    float core = exp(-orbDist * 15.0);
    col += vec3(1.0, 0.98, 0.95) * core * 0.7;

    // Outer halo rings with iridescence - larger
    for(float i = 1.0; i <= 4.0; i += 1.0) {
        float ringDist = abs(orbDist - i * 0.1);
        float ring = exp(-ringDist * 30.0) * (0.5 + 0.5 * sin(t * 2.0 + i));
        vec3 ringColor = hsv2rgb(vec3(fract(i * 0.25 + t * 0.2), 0.5, 1.0));
        col += ringColor * ring * 0.25;
    }

    // === Shimmer particles distributed across FULL screen ===
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
    }

    col = clamp(col, 0.0, 1.0);

    fragColor = vec4(col, 1.0);
}

#version 460 core

#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uDpr;
uniform float uProgress;
uniform vec4 uLock;
uniform vec4 uBeam;
uniform vec2 uBeamShape;
uniform vec3 uInk;
uniform vec3 uBase;

out vec4 fragColor;

const vec2 kLight = vec2(0.857, -0.514);

float hash(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

float roundRect(vec2 p, vec2 c, vec2 h, float r) {
  vec2 q = abs(p - c) - h + r;
  return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

float lockShape(vec2 p) {
  float body = roundRect(p, vec2(0.5, 0.76), vec2(0.31, 0.23), 0.05);
  float arc = p.y <= 0.48
      ? abs(length(p - vec2(0.5, 0.48)) - 0.19) - 0.045
      : max(min(abs(p.x - 0.31), abs(p.x - 0.69)) - 0.045, p.y - 0.56);
  float hole = min(length(p - vec2(0.5, 0.71)) - 0.045, roundRect(p, vec2(0.5, 0.79), vec2(0.016, 0.06), 0.01));
  return max(min(body, arc), -hole);
}

float beam(vec2 pos) {
  vec2 a = uBeam.xy;
  vec2 ab = uBeam.zw - a;
  float len2 = dot(ab, ab);
  float t = dot(pos - a, ab) / len2;
  float dist = abs((pos.x - a.x) * ab.y - (pos.y - a.y) * ab.x) / sqrt(len2);
  float w = uBeamShape.x * (0.35 + 0.65 * clamp(t, 0.0, 1.0));
  return uBeamShape.y * exp(-(dist / w) * (dist / w)) * clamp(1.0 - t * 0.6, 0.0, 1.0) * step(-0.05, t);
}

void main() {
  vec2 pos = FlutterFragCoord().xy;
  float light = 0.0;
  float solid = 0.0;

  if (uLock.w > 0.5) {
    float side = uLock.z;
    vec2 p = (pos - uLock.xy) / side;
    float d = lockShape(p);
    const float e = 0.02;
    vec2 g = vec2(lockShape(p + vec2(e, 0.0)) - lockShape(p - vec2(e, 0.0)),
                  lockShape(p + vec2(0.0, e)) - lockShape(p - vec2(0.0, e)));
    float facing = clamp(dot(g / (length(g) + 1e-5), kLight), 0.0, 1.0);
    float t = clamp((p.y - 0.245) / 0.745, 0.0, 1.0);
    float fade = clamp(1.15 - 1.05 * t, 0.05, 1.0);
    if (d < 0.0) {
      float body = 0.16 + 0.34 * (1.0 - t) + 0.2 * (p.x - 0.2);
      float rim = exp(d / 0.018) * (0.35 + 0.65 * facing);
      light = 1.25 * (body + 0.6 * rim) * fade;
    } else {
      light = (0.6 * exp(-d / 0.034) * (0.4 + 0.6 * facing) + 0.12 * exp(-d / 0.28)) * (0.15 + 0.85 * fade)
          * smoothstep(0.58, 0.35, d);
    }
    solid = smoothstep(0.004, -0.004, d) * fade * fade;
  }

  if (uBeamShape.y > 0.0) light += beam(pos);

  vec2 px = floor(pos * uDpr);
  float reach = dot(pos / max(uSize.x, uSize.y), -kLight);
  float ramp = uProgress >= 1.0 ? 1.0 : clamp(uProgress * 2.3 - 0.6 * (reach + 0.8), 0.0, 1.0);
  float lit = clamp((ramp * 1.15 - hash(px + 71.3)) * 6.0, 0.0, 1.0);
  light *= lit;
  solid *= ramp;

  float level = clamp(light, 0.0, 1.2);
  float r = hash(px);
  float dots = smoothstep(r - 0.08, r + 0.08, pow(level, 1.15));
  float v = clamp(0.85 * dots * min(1.0, level * 1.6 + 0.25) + 0.15 * level, 0.0, 1.0);

  float alpha = mix(v, 1.0, solid);
  fragColor = vec4(uInk * v + uBase * (alpha - v), alpha);
}

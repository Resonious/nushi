#version 460 core
// Caustics: the light a rippling surface throws on a pond's floor, drifting
// under the transcript's live end while the agent works. Two layers of
// moving cells; light gathers along their edges, brightest where the two
// layers' edges cross. Strongest at the bottom, gone toward the top.
#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uTime;
uniform float uStrength;   // 0 off, 1 calm working, more while words come
uniform vec4 uColor;       // the light's rgb, and its most alpha

out vec4 fragColor;

vec2 hash2(vec2 p) {
  p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
  return fract(sin(p) * 43758.5453);
}

// The distance from [p] to the edge between its two nearest moving
// points: small along cell edges, where the light gathers.
float edge(vec2 p, float t) {
  vec2 cell = floor(p);
  vec2 f = fract(p);
  float d1 = 8.0;
  float d2 = 8.0;
  for (int j = -1; j <= 1; j++) {
    for (int i = -1; i <= 1; i++) {
      vec2 g = vec2(float(i), float(j));
      vec2 h = hash2(cell + g);
      vec2 o = 0.5 + 0.42 * sin(t * (0.6 + 0.5 * h) + 6.2831 * h);
      float d = length(g + o - f);
      if (d < d1) {
        d2 = d1;
        d1 = d;
      } else if (d < d2) {
        d2 = d;
      }
    }
  }
  return d2 - d1;
}

// Light along an edge: a bright core in a soft glow.
float light(float e) {
  float core = clamp(1.0 - e / 0.14, 0.0, 1.0);
  float halo = clamp(1.0 - e / 0.5, 0.0, 1.0);
  return core * core * core * core + 0.22 * halo * halo;
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float t = uTime;
  vec2 p = frag / 190.0;
  // The surface's sway bends the cells' edges into curves: two scales of
  // slow warp, so no edge stays straight.
  p += 0.30 * vec2(sin(p.y * 2.1 + t * 0.7), cos(p.x * 1.7 - t * 0.55));
  p += 0.09 * vec2(sin(p.y * 5.3 - t * 1.1), cos(p.x * 4.7 + t * 0.9));

  float a = light(edge(p, t * 0.9));
  float b = light(edge(p * 1.45 + vec2(3.7, 1.3) + 0.05 * t, t * 1.2));
  float c = a * 0.5 + b * 0.3 + a * b * 1.8;
  c = 1.0 - exp(-c * 1.5);

  // Under the live end: strongest at the bottom, fading out up the pane,
  // and soft at the sides.
  float y = frag.y / uSize.y;
  float x = frag.x / uSize.x;
  float mask = smoothstep(0.2, 0.95, y) * smoothstep(0.0, 0.12, x)
      * smoothstep(1.0, 0.88, x);

  float alpha = clamp(c * mask * uStrength, 0.0, 1.0) * uColor.a;
  fragColor = vec4(uColor.rgb * alpha, alpha);
}

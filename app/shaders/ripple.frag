#version 460 core
// The pond's ripple: the transcript, snapshotted, bent outward from where
// a message dropped in. Up to three ripples at once. Each is a packet of
// rings that travels out and spreads as it slows, its height falling with
// age and distance. Crests catch the light and troughs darken a little.
// Kind 0 is a drop (a message sent); kind 1 is a glint (the daemon
// confirmed it): a quicker, flatter ring whose crest flashes amber.
#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform vec4 uR0;      // x, y, age (s), kind; age < 0 means off. Kind 2
                       // (an edge splash) carries its strength in its
                       // fraction: 2 + 0.9 * strength.
uniform vec4 uR1;
uniform vec4 uR2;
uniform vec4 uCrest;   // drop crest light, rgb + strength
uniform vec4 uGlint;   // glint light, rgb + strength
uniform float uDark;   // 1 on a dark theme
uniform sampler2D uTexture;

out vec4 fragColor;

const float PI = 3.14159265;

// A splash along the bottom edge (the list landing at its end): a wave
// running up from the edge, uneven along it, and a chop right at the edge.
void edgeSplash(vec4 r, vec2 p, inout vec2 shift, inout float crest,
                inout float trough) {
  float age = r.z;
  float strength = (r.w - 2.0) / 0.9;
  float life = 1.1;
  float t = age / life;
  if (t >= 1.0) return;
  // A gentle arc, as from a point far below the edge's middle, fading
  // toward the sides: a landing in the middle of the water, not a band.
  vec2 src = vec2(r.x, r.y + 520.0);
  float d = distance(p, src) - 520.0; // height above the edge, curved
  if (p.y > r.y || d < 0.0) return;
  float side = (p.x - r.x) / (uSize.x * 0.42);
  float across = exp(-side * side);
  vec2 up = normalize(p - src);
  float front = 340.0 * (1.0 - exp(-age * 3.2));
  float lambda = 24.0 + 22.0 * t;
  float sigma = 20.0 + 40.0 * t;
  float x = d - front;
  float env = exp(-x * x / (2.0 * sigma * sigma));
  env *= smoothstep(sigma * 0.9, -sigma * 0.2, x) * 0.6 + 0.4;
  float phase = x / lambda * 2.0 * PI;
  float fade = pow(1.0 - t, 1.5);
  float near = 1.0 / (1.0 + d / 220.0);
  float uneven = 0.7 + 0.3 * sin(p.x / 53.0 + age * 4.0)
      * cos(p.x / 131.0 - age * 2.0);
  float amp = 4.0 * strength * fade * near * uneven * across;
  float chop = exp(-d / 18.0) * exp(-age * 7.0)
      * sin(p.x / 9.0 + age * 40.0) * 1.2 * strength * across;
  float h = sin(phase) * env;
  float slope = cos(phase) * env;
  shift += up * (h * amp + chop);
  float s = slope * fade * near * strength * across * 0.45;
  crest += max(s, 0.0);
  trough += max(-s, 0.0);
}

// Accumulates one ripple's displacement and light at [p].
void ripple(vec4 r, vec2 p, inout vec2 shift, inout float crest,
            inout float trough, inout float glint) {
  float age = r.z;
  if (age < 0.0) return;
  if (r.w >= 2.0) {
    edgeSplash(r, p, shift, crest, trough);
    return;
  }
  bool isGlint = r.w > 0.5;
  float life = isGlint ? 0.9 : 1.6;
  float t = age / life;
  if (t >= 1.0) return;

  vec2 d = p - r.xy;
  float dist = length(d);
  vec2 dir = dist > 0.001 ? d / dist : vec2(0.0);

  // The front races out, then slows: fast enough to cross the transcript.
  float reach = isGlint ? 520.0 : 900.0;
  float front = reach * (1.0 - exp(-age * (isGlint ? 2.6 : 1.7)));
  // Rings trail behind the front; wavelength grows as it spreads.
  float lambda = (isGlint ? 26.0 : 34.0) + 30.0 * t;
  float sigma = (isGlint ? 12.0 : 24.0) + (isGlint ? 20.0 : 36.0) * t;
  float x = dist - front;
  float env = exp(-x * x / (2.0 * sigma * sigma));
  // Only rings behind the front (and a little ahead).
  env *= smoothstep(sigma * 0.9, -sigma * 0.2, x) * 0.6 + 0.4;
  float phase = x / lambda * 2.0 * PI;
  float fade = pow(1.0 - t, 1.6);
  float near = 1.0 / (1.0 + dist / 300.0);
  float amp = (isGlint ? 1.2 : 3.6) * fade * near;

  // A splash at the point of impact, early on.
  float splash = isGlint ? 0.0
      : exp(-dist * dist / (2.0 * 70.0 * 70.0)) * exp(-age * 7.0);

  float h = sin(phase) * env;            // surface height
  float slope = cos(phase) * env;        // its slope: light catches it
  shift += dir * (h * amp - splash * 2.0 * sin(dist / 14.0 - age * 30.0));

  float s = slope * fade * near;
  if (isGlint) {
    // One bright crest, not rings: a bump riding the front.
    glint += env * fade * near * (1.0 - t);
  } else {
    crest += max(s, 0.0) + splash * 0.15;
    trough += max(-s, 0.0);
  }
}

void main() {
  vec2 p = FlutterFragCoord().xy;
  vec2 shift = vec2(0.0);
  float crest = 0.0;
  float trough = 0.0;
  float glint = 0.0;
  ripple(uR0, p, shift, crest, trough, glint);
  ripple(uR1, p, shift, crest, trough, glint);
  ripple(uR2, p, shift, crest, trough, glint);

  vec2 uv = clamp((p - shift) / uSize, vec2(0.0), vec2(1.0));
  vec4 c = texture(uTexture, uv);

  // Light: add on dark, tint on light, so the text keeps its contrast.
  vec3 light = uCrest.rgb * crest * uCrest.a + uGlint.rgb * glint * uGlint.a;
  float shade = trough * (uDark > 0.5 ? 0.10 : 0.06);
  vec3 rgb = c.rgb * (1.0 - shade);
  if (uDark > 0.5) {
    rgb += light * c.a;
  } else {
    // On a light page, light can't brighten white: crests take the
    // tint of the light instead.
    rgb = mix(rgb, uCrest.rgb, clamp(crest * uCrest.a, 0.0, 0.45) * c.a);
    rgb = mix(rgb, uGlint.rgb, clamp(glint * uGlint.a, 0.0, 0.6) * c.a);
  }
  fragColor = vec4(rgb, c.a);
}

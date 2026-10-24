// Curtain of drifting shadow in a doorway that leads out of the player's sight line.
// Chunky pixels and stepped alpha to match the low-res look; cheap enough for WebGL 2.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

uniform float strength : hint_range(0.0, 1.0) = 1.0;
uniform float seed = 0.0;
uniform vec3 dark_color : source_color = vec3(0.015, 0.008, 0.03);
uniform vec3 wisp_color : source_color = vec3(0.11, 0.08, 0.14);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	// 24 x 26 texels per doorway, like the 32px wall textures seen at this size.
	vec2 uv = floor(UV * vec2(24.0, 26.0)) / vec2(24.0, 26.0);
	float t = TIME * 0.35 + seed * 13.0;
	vec2 p = uv * vec2(3.0, 3.4) + vec2(seed * 7.0, 0.0);
	float n = noise(p + vec2(t, -t * 0.6)) * 0.55
			+ noise(p * 2.1 + vec2(-t * 1.3, t * 0.4)) * 0.3
			+ noise(p * 4.3 + vec2(t * 0.8, t)) * 0.15;

	// A light haze, a bit denser mid-doorway and fading toward the frame. Two layers stack to roughly 50%.
	float edge = min(min(uv.x, 1.0 - uv.x) * 4.0, 1.0) * min(min(uv.y, 1.0 - uv.y) * 5.0, 1.0);
	float a = clamp(0.12 + edge * 0.18 + (n - 0.5) * 0.16, 0.0, 1.0);
	a = floor(a * 16.0 + 0.5) / 16.0;

	float wisp = smoothstep(0.5, 0.9, n);
	ALBEDO = mix(dark_color, wisp_color, wisp);
	ALPHA = a * strength;
}

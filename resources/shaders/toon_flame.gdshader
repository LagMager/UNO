shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;
// A dark campfire: the flame is a column of heat torn up by rising noise. Deep reds at
// the edges (almost soot), orange in the body and only a small, dim yellow heart.
// Soft color blends on purpose: the screen's Bayer dither breaks them into dirty pixels.
// The quad always turns to the camera around its vertical axis.

uniform vec4 soot : source_color = vec4(0.13, 0.025, 0.015, 1.0);
uniform vec4 ember : source_color = vec4(0.48, 0.07, 0.02, 1.0);
uniform vec4 body : source_color = vec4(0.85, 0.27, 0.05, 1.0);
uniform vec4 heart : source_color = vec4(1.0, 0.62, 0.22, 1.0);
uniform float intensity = 1.0;     // driven by the script: the fire breathes and flares
uniform float speed = 0.75;        // how fast the heat rises (calm fire)
uniform float push = 0.0;          // meters toward the camera (the front layer wraps the logs)
uniform float phase = 0.0;         // time and noise offset, so two layers never match

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		vec4(normalize(cross(vec3(0.0, 1.0, 0.0), INV_VIEW_MATRIX[2].xyz)) * length(MODEL_MATRIX[0].xyz), 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(normalize(cross(INV_VIEW_MATRIX[0].xyz, vec3(0.0, 1.0, 0.0))), 0.0),
		MODEL_MATRIX[3]);
	MODELVIEW_MATRIX[3].z += push;     // view space: +z is toward the camera
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

float hash(vec2 p) {
	p = fract(p * vec2(233.34, 851.73));
	p += dot(p, p + 23.45);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x),
		mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p = p * 2.07 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

void fragment() {
	float t = (TIME + phase * 13.0) * speed;
	vec2 p = vec2(UV.x - 0.5, 1.0 - UV.y);     // p.y: 0 at the bottom, 1 at the top
	// the heat sways and is torn sideways more the higher it goes
	float sway = (fbm(vec2(p.y * 1.5 - t * 0.6, phase * 5.0)) - 0.5) * 0.35 * p.y;
	vec2 q = vec2(p.x - sway, p.y);
	// a wide base narrowing to a ragged top
	float width = 0.36 * pow(max(1.0 - p.y * 0.95, 0.0), 0.7) + 0.02;
	float shape = 1.0 - abs(q.x) / width;
	// rising turbulence eats the shape from the edges and breaks it into licks at the top
	float n = fbm(vec2(q.x * 3.2 + phase * 7.0, q.y * 2.4 - t * 1.6));
	float n2 = fbm(vec2(q.x * 7.0 - phase * 3.0, q.y * 5.0 - t * 2.6));
	float heat = shape * (1.05 - p.y * 0.75) + (n - 0.5) * 0.9 + (n2 - 0.5) * 0.35;
	heat *= 0.8 + 0.25 * intensity;
	heat -= smoothstep(0.55, 1.0, p.y) * 0.5;   // nothing reaches the very top of the quad
	if (heat < 0.18) {
		discard;
	}
	vec3 c = mix(soot.rgb, ember.rgb, smoothstep(0.18, 0.32, heat));
	c = mix(c, body.rgb, smoothstep(0.34, 0.55, heat));
	c = mix(c, heart.rgb, smoothstep(0.62, 0.9, heat) * (1.0 - p.y * 0.6));
	ALBEDO = c * (0.85 + 0.2 * intensity);
}

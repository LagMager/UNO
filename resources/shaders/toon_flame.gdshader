shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;
// A drawn campfire: a few flame tongues filled with flat colors (red-orange, orange,
// yellow core) and a thick ink outline, animated "on twos" like stop-motion.
// The quad always turns to the camera around its vertical axis.

uniform vec4 ink : source_color = vec4(0.16, 0.05, 0.03, 1.0);
uniform vec4 outer : source_color = vec4(0.93, 0.3, 0.07, 1.0);
uniform vec4 middle : source_color = vec4(1.0, 0.6, 0.14, 1.0);
uniform vec4 core : source_color = vec4(1.0, 0.92, 0.6, 1.0);
uniform float outline = 0.022;     // ink width, in UV (thicker read as a sticker)
uniform float intensity = 1.0;     // driven by the script: the fire breathes and flares
uniform float fps = 6.0;           // stop-motion steps per second
uniform float pace = 0.55;         // how fast the tongues sway (calm fire)
uniform float pixels = 0.0;        // > 0: its own chunky grid (flame pixels across the quad)
uniform float messy = 0.03;        // how ragged the edges are
uniform float push = 0.0;          // meters toward the camera (the front layer wraps the logs)
uniform float phase = 0.0;         // time offset, so two layers never move together

void vertex() {
	// billboard around Y, keeping the node's scale
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		vec4(normalize(cross(vec3(0.0, 1.0, 0.0), INV_VIEW_MATRIX[2].xyz)) * length(MODEL_MATRIX[0].xyz), 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(normalize(cross(INV_VIEW_MATRIX[0].xyz, vec3(0.0, 1.0, 0.0))), 0.0),
		MODEL_MATRIX[3]);
	MODELVIEW_MATRIX[3].z += push;     // view space: +z is toward the camera
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

float wob(float t, float k) {
	return sin(t * 1.9 + k * 3.1) * 0.6 + sin(t * 3.3 + k * 1.7) * 0.3 + sin(t * 5.7 + k * 4.9) * 0.1;
}

// Signed "inside" amount of the whole flame (positive inside), scaled by s for the inner layers.
float flame(vec2 p, float t, float s) {
	float d = -1.0;
	// four tongues: x offset, width, height
	for (int i = 0; i < 4; i++) {
		float k = float(i);
		float xo = (k - 1.5) * 0.11 + wob(t, k + 10.0) * 0.02;
		float w = (0.13 - abs(k - 1.5) * 0.02) * s;
		float h = (0.62 - abs(k - 1.5) * 0.13 + wob(t, k) * 0.1) * s * intensity;
		float y = p.y / max(h, 0.05);
		if (y > 1.0) continue;
		float sway = sin(p.y * 9.0 - t * 4.0 + k * 2.0) * 0.05 * p.y + wob(t, k + 5.0) * 0.03 * p.y;
		float width = w * pow(max(1.0 - y, 0.0), 0.75) * (1.0 + 0.6 * smoothstep(0.0, 0.35, y) * (1.0 - y));
		d = max(d, width - abs(p.x - xo * s - sway));
	}
	// the round bed where the tongues start
	vec2 b = vec2(p.x / 0.28, (p.y - 0.06) / 0.13) / s;
	d = max(d, (1.0 - length(b)) * 0.12 * s);
	return d;
}

float cell_hash(vec2 p) {
	p = fract(p * vec2(233.34, 851.73));
	p += dot(p, p + 23.45);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(cell_hash(i), cell_hash(i + vec2(1, 0)), f.x),
		mix(cell_hash(i + vec2(0, 1)), cell_hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	float t = floor((TIME + phase) * fps) / fps * pace;
	vec2 uv = UV;
	if (pixels > 0.0) {
		// optional chunky grid of its own (off by default: the screen's dither does the pixels)
		vec2 cells = vec2(pixels, pixels * 1.4);
		uv = (floor(UV * cells) + 0.5) / cells;
	}
	vec2 p = vec2(uv.x - 0.5, (1.0 - uv.y) * 1.4);   // p.y: 0 at the bottom
	// ragged edges, re-rolled every step (boiling)
	float step_id = floor((TIME + phase) * fps);
	float j = (vnoise(p * 40.0 + step_id * 3.7) - 0.5) * messy;
	float d0 = flame(p, t, 1.0) + j;
	if (d0 < -outline) {
		discard;
	}
	vec3 c = ink.rgb;
	if (d0 > 0.0) {
		// soft blends between the layers (not hard steps): the screen's Bayer dither turns
		// them into the same dirty, speckled pixels as the rest of the scene
		float m1 = smoothstep(-0.03, 0.03, flame(p - vec2(0.0, 0.015), t + 0.37, 0.68) + j);
		float m2 = smoothstep(-0.03, 0.03, flame(p - vec2(0.0, 0.02), t + 0.71, 0.38) + j);
		c = mix(outer.rgb, middle.rgb, m1);
		c = mix(c, core.rgb, m2);
		// darker toward the tips and the edges, with blotchy grime inside
		float tip = smoothstep(0.1, 0.75, p.y);
		float edge = smoothstep(0.0, 0.06, d0);
		float grime = vnoise(p * vec2(9.0, 6.0) + vec2(0.0, -step_id * 0.6));
		c *= mix(0.55, 1.05, edge) * (1.0 - tip * 0.35) * (0.78 + grime * 0.4);
		c *= 0.9 + 0.25 * intensity;
	}
	ALBEDO = c;
}

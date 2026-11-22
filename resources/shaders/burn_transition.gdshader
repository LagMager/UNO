shader_type canvas_item;
// Screen change: a still of the old screen burns away like paper held to a flame. Holes open
// from a few points, their edges glowing ember with a charred rim, and show the new screen.

uniform sampler2D old_screen : filter_nearest;
uniform float progress = 0.0;       // 0 = old screen whole, 1 = burnt away
uniform vec2 seed = vec2(0.0);
uniform float aspect = 1.777;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
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
	for (int i = 0; i < 5; i++) {
		v += a * vnoise(p);
		p = p * 2.07 + 1.3;
		a *= 0.5;
	}
	return v;
}

void fragment() {
	// chunky like the rest: the burn front moves on a 3-px grid
	vec2 px = floor(FRAGCOORD.xy / 3.0) * 3.0 / (1.0 / SCREEN_PIXEL_SIZE);
	vec2 p = vec2(px.x * aspect, px.y);
	// three places catch fire first; the noise makes the fronts ragged
	float d = 9.0;
	for (int i = 0; i < 3; i++) {
		vec2 c = vec2(hash(seed + float(i) * 3.7) * aspect, hash(seed + float(i) * 9.1 + 2.0));
		d = min(d, length(p - c));
	}
	float burn = d / (aspect * 0.9) + (fbm(p * 4.0 + seed) - 0.5) * 0.35;
	float front = progress * 1.25 - 0.1;
	if (burn < front) {
		discard;
	}
	vec4 old = texture(old_screen, UV);
	float edge = burn - front;
	vec3 c = old.rgb;
	c *= smoothstep(0.0, 0.09, edge) * 0.8 + 0.2;                     // charring ahead of the flame
	vec3 glow = mix(vec3(1.0, 0.75, 0.35), vec3(0.6, 0.12, 0.03), smoothstep(0.0, 0.025, edge));
	c = mix(glow, c, smoothstep(0.0, 0.035, edge));
	COLOR = vec4(c, 1.0);
}

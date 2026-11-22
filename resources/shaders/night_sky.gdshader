shader_type sky;
// Night sky of the rest point: always night, no moon. Lots of faint stars clumped
// unevenly, a dim band of the Milky Way, and only a few bright stars with four short
// points. The sky gets a little lighter toward the horizon so distant hills read as
// silhouettes (there is no hard line between ground and sky).

uniform vec3 zenith : source_color = vec3(0.012, 0.016, 0.035);
uniform vec3 horizon : source_color = vec3(0.15, 0.15, 0.2);
uniform vec3 band_color : source_color = vec3(0.11, 0.115, 0.15);
uniform vec3 band_axis = vec3(0.35, 0.55, 0.76);   // normal of the Milky Way's great circle
uniform float brightness = 1.0;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise3(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x),
			mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x),
			mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise3(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

// One layer of stars on an (azimuth, elevation) grid. Returns brightness in .x,
// warmth in .y. cross > 0 lets the brightest ones grow four short points.
vec2 stars(vec3 d, float cells, float chance, float size, float cross) {
	float up = d.y;
	vec2 sp = vec2(atan(d.x, -d.z) / 6.2831853 + 0.5, asin(up) / 1.5707963);
	vec2 g = vec2(sp.x * cells * 4.0, sp.y * cells);
	vec2 cell = floor(g);
	float total = 0.0;
	float warm = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 c = cell + vec2(float(x), float(y));
			c.x = mod(c.x, cells * 4.0);
			if (hash(c) > chance) continue;
			vec2 q = g - (c + 0.1 + 0.8 * vec2(hash(c + 1.7), hash(c + 8.3)));
			q.x -= cells * 4.0 * round(q.x / (cells * 4.0));
			q.x *= cos(asin(up)) * 4.0 * 1.5707963 / 6.2831853;   // keep them round
			float mag = pow(hash(c + 3.1), 3.0);                    // most are faint
			float s = exp(-dot(q, q) / (size * size)) * (0.15 + mag);
			if (cross > 0.0 && mag > 0.6) {
				float r = size * cross;
				s += (exp(-abs(q.x) / (size * 0.25)) * exp(-abs(q.y) / r)
					+ exp(-abs(q.y) / (size * 0.25)) * exp(-abs(q.x) / r)) * 0.5 * mag;
			}
			s *= 0.85 + 0.15 * sin(TIME * (0.8 + 2.5 * hash(c + 4.4)) + hash(c) * 50.0);
			total += s;
			warm += s * hash(c + 6.6);
		}
	}
	return vec2(total, total > 0.0 ? warm / total : 0.5);
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float up = d.y;
	vec3 col = mix(horizon, zenith, pow(smoothstep(-0.03, 0.4, up), 0.55));
	// the Milky Way: a soft, broken band of light across the sky
	float off = dot(d, normalize(band_axis));
	float haze = fbm(d * 5.0) * 0.7 + fbm(d * 13.0) * 0.3;
	float band = exp(-off * off / 0.035) * smoothstep(0.35, 0.75, haze);
	float dark_lane = smoothstep(0.55, 0.7, fbm(d * 9.0 + 3.0)) * exp(-off * off / 0.006);
	band *= 1.0 - dark_lane * 0.7;
	col += band_color * band * 1.4;
	// where stars clump: more of them along the band and in random patches
	float clump = smoothstep(0.35, 0.8, fbm(d * 3.0 + 7.0)) * 0.6 + band * 0.8;
	float above = smoothstep(-0.01, 0.03, up);
	vec2 dust = stars(d, 110.0, 0.05 + 0.25 * clump, 0.11, 0.0);
	vec2 field = stars(d, 40.0, 0.14 + 0.12 * clump, 0.07, 0.0);
	vec2 bright = stars(d, 14.0, 0.16, 0.045, 2.6);
	vec3 cool = vec3(0.78, 0.84, 1.0);
	vec3 warmc = vec3(1.0, 0.88, 0.72);
	col += mix(cool, warmc, dust.y) * dust.x * 0.35 * brightness * above;
	col += mix(cool, warmc, field.y) * field.x * 0.7 * brightness * above;
	col += mix(cool, warmc, bright.y) * bright.x * 1.1 * brightness * above;
	COLOR = col;
}

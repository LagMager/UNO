shader_type canvas_item;
// Dirty, dark finish for the 2D interface, so buttons and text match the dithered 3D:
// a few color steps with ordered (Bayer) dithering on a 2-px grid, grain, and worn
// specks where the ink didn't take. Pattern is fixed to the screen (it doesn't crawl).

uniform float pixel = 2.0;        // screen px per dither cell
uniform float levels = 24.0;      // color steps per channel
uniform float grain = 0.05;
uniform float wear = 0.0;        // share of specks that lose most of their ink
uniform float darken = 0.92;

const float BAYER[16] = float[16](
	0.0, 8.0, 2.0, 10.0,
	12.0, 4.0, 14.0, 6.0,
	3.0, 11.0, 1.0, 9.0,
	15.0, 7.0, 13.0, 5.0);

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	ivec2 cell = ivec2(floor(FRAGCOORD.xy / pixel));
	vec2 fc = vec2(cell);
	float th = (BAYER[(cell.y % 4) * 4 + (cell.x % 4)] + 0.5) / 16.0 - 0.5;
	vec3 rgb = c.rgb * darken;
	rgb *= 1.0 + (hash(fc) - 0.5) * grain * 2.0;
	rgb = floor(rgb * levels + 0.5 + th) / levels;
	// worn ink: blotches of a few cells
	float blot = hash(floor(fc / 3.0) + 17.0);
	if (blot < wear && hash(fc + 5.0) < 0.7) {
		c.a *= 0.35;
	}
	COLOR = vec4(clamp(rgb, 0.0, 1.0), c.a);
}

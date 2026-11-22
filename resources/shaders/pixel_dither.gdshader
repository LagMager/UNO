shader_type canvas_item;
// Buckshot Roulette-like finish for the low-resolution 3D render:
// ordered (Bayer) dithering into a reduced palette, crushed blacks and a bit more contrast.
// The viewport is rendered at a fraction of the screen size and shown with nearest filtering,
// so every dithered pixel is visible.
// "Things went bad" effects, driven from the duel: chromatic split, desaturation,
// a hot flash, a blackout and a wobble of the image.

uniform float levels = 9.0;      // color steps per channel
uniform float contrast = 1.22;
uniform float black_crush = 0.06;
uniform float dither_amount = 1.0;
uniform float aberration = 0.0;   // 0..~0.02, in UV
uniform float desaturate = 0.0;   // 0..1
uniform float flash = 0.0;        // 0..1, hot white-red flash
uniform float blackout = 0.0;     // 0..1
uniform float wobble = 0.0;       // 0..1, wavy distortion

const float BAYER[16] = float[16](
	0.0, 8.0, 2.0, 10.0,
	12.0, 4.0, 14.0, 6.0,
	3.0, 11.0, 1.0, 9.0,
	15.0, 7.0, 13.0, 5.0);

void fragment() {
	vec2 uv = UV;
	uv.x += sin(uv.y * 40.0 + TIME * 9.0) * 0.004 * wobble;
	vec2 dir = (uv - 0.5) * aberration * 2.0;
	vec4 src = texture(TEXTURE, uv);
	vec3 c = vec3(texture(TEXTURE, uv + dir).r, src.g, texture(TEXTURE, uv - dir).b);
	float grey = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(c, vec3(grey), desaturate);
	c = mix(c, vec3(1.0, 0.86, 0.8), flash);
	c *= 1.0 - blackout;
	c = max(c - black_crush, 0.0) / (1.0 - black_crush);
	c = (c - 0.5) * contrast + 0.5;
	ivec2 px = ivec2(floor(uv / TEXTURE_PIXEL_SIZE));
	float threshold = (BAYER[(px.y % 4) * 4 + (px.x % 4)] + 0.5) / 16.0 - 0.5;
	c = floor(c * levels + 0.5 + threshold * dither_amount) / levels;
	COLOR = vec4(clamp(c, 0.0, 1.0), src.a);
}

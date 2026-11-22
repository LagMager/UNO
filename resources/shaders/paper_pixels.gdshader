// The notebook scrap, rendered small and shown big: a few of its pixels grimy, a few flecked,
// colours in coarse steps. Dirty but still readable.
shader_type canvas_item;

uniform float grime = 0.14;       // how much the dirty pixels darken
uniform float levels = 18.0;      // colour steps

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 cell = floor(UV / TEXTURE_PIXEL_SIZE);
	vec4 c = texture(TEXTURE, UV);
	float n = hash(cell);
	c.rgb *= 1.0 - grime * n * n;                     // uneven, grimy paper
	if (hash(cell + 7.13) > 0.985) {
		c.rgb *= 0.55;                                // flecks of dirt
	}
	c.rgb = floor(c.rgb * levels + 0.5) / levels;
	COLOR = c * COLOR;
}

shader_type canvas_item;
// Film look over the duel: dark vignette and a little moving grain (Buckshot Roulette-like mood).

uniform float vignette = 0.7;
uniform float grain = 0.09;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	float v = smoothstep(0.3, 0.85, distance(SCREEN_UV, vec2(0.5))) * vignette;
	float n = hash(floor(SCREEN_UV * 900.0) + floor(TIME * 24.0)) - 0.5;
	float g = abs(n) * grain;
	float a = clamp(v + g, 0.0, 1.0);
	// grain lightens or darkens a speck; the vignette is pure black
	vec3 speck = vec3(n > 0.0 ? 1.0 : 0.0);
	COLOR = vec4(mix(speck, vec3(0.0), v / max(a, 0.001)), a);
}

shader_type spatial;
// Contorno de dibujo: el mismo modelo, un poco inflado, con las caras de adelante ocultas.
render_mode unshaded, cull_front, depth_draw_opaque;

uniform vec4 color : source_color = vec4(0.078, 0.063, 0.063, 1.0);
uniform float grow = 0.006;

void vertex() {
	VERTEX += NORMAL * grow;
}

void fragment() {
	ALBEDO = color.rgb;
}

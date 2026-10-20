shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque;

// Dark floor with glowing grid lines. Lines are anti-aliased with fwidth(),
// with a brighter line every `major_every` cells, fading out toward the horizon.

uniform vec3 base_color : source_color = vec3(0.03, 0.02, 0.08);
uniform vec3 line_color : source_color = vec3(0.35, 0.85, 1.0);
uniform vec3 major_color : source_color = vec3(1.0, 0.5, 0.9);
uniform float cell_size = 0.5;
uniform int major_every = 4;
uniform float line_width = 0.025;
uniform float fade_distance = 40.0;
uniform vec3 fog_color : source_color = vec3(0.12, 0.06, 0.25);

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = world_pos.xz / cell_size;
	vec2 deriv = fwidth(uv);

	// Minor lines: distance to nearest integer line, in pixels-ish units.
	vec2 minor_d = abs(fract(uv - 0.5) - 0.5) / max(deriv, vec2(0.0001));
	float minor = 1.0 - clamp(min(minor_d.x, minor_d.y) - line_width / max(max(deriv.x, deriv.y), 0.0001), 0.0, 1.0);
	// Kill moiré when lines get denser than a pixel.
	minor *= 1.0 - clamp(max(deriv.x, deriv.y) * 1.5 - 0.3, 0.0, 1.0);

	vec2 muv = uv / float(major_every);
	vec2 mderiv = fwidth(muv);
	vec2 major_d = abs(fract(muv - 0.5) - 0.5) / max(mderiv, vec2(0.0001));
	float major = 1.0 - clamp(min(major_d.x, major_d.y) - 1.5 * line_width / max(max(mderiv.x, mderiv.y), 0.0001), 0.0, 1.0);
	major *= 1.0 - clamp(max(mderiv.x, mderiv.y) * 1.5 - 0.3, 0.0, 1.0);

	vec3 col = base_color;
	col = mix(col, line_color, minor * 0.8);
	col = mix(col, major_color, major);

	float dist = length(world_pos.xz - CAMERA_POSITION_WORLD.xz);
	float fade = clamp(dist / fade_distance, 0.0, 1.0);
	col = mix(col, fog_color, fade * fade);

	ALBEDO = col;
}

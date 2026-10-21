shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque;

// Dark floor with glowing grid lines. Lines are anti-aliased from the pixel footprint,
// with a brighter line every `major_every` cells. Far away the floor fades into the
// sky's own color for that view angle (the same gradient sky.gdshader draws below
// the horizon), so the plane's far edge and the horizon leave no visible, aliased line.

uniform vec3 base_color : source_color = vec3(0.03, 0.02, 0.08);
uniform vec3 line_color : source_color = vec3(0.35, 0.85, 1.0);
uniform vec3 major_color : source_color = vec3(1.0, 0.5, 0.9);
uniform float cell_size = 0.5;
uniform int major_every = 4;
uniform float line_width = 0.025;
uniform float fade_start = 30.0;
uniform float fade_end = 90.0;
// Keep these in sync with horizon_color and ground_color in sky.gdshader.
uniform vec3 horizon_color : source_color = vec3(1.00, 0.45, 0.50);
uniform vec3 ground_color : source_color = vec3(0.05, 0.03, 0.12);

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// Coverage (0..1) of grid lines at integer positions of `p`. `d` is the size of a
// pixel in grid units, `hw` the line's half width. A line thinner than a pixel is
// drawn one pixel wide but dimmed by how thin it really is, so it fades smoothly
// into the average floor brightness instead of shimmering between pixels. When a
// pixel spans a whole cell the lines settle on their average coverage.
float grid_lines(vec2 p, vec2 d, float hw) {
	vec2 dist = abs(fract(p - 0.5) - 0.5);
	vec2 draw = clamp(vec2(hw), d * 0.5, vec2(0.5));
	vec2 aa = d * 0.75;
	vec2 cov = 1.0 - smoothstep(draw - aa, draw + aa, dist);
	cov *= clamp(hw / draw, 0.0, 1.0);
	cov = mix(cov, vec2(2.0 * hw), smoothstep(0.4, 1.0, d));
	return 1.0 - (1.0 - cov.x) * (1.0 - cov.y);
}

void fragment() {
	vec2 uv = world_pos.xz / cell_size;
	// Screen-space footprint of a pixel in grid cells. Not fwidth(): that sums the x
	// and y derivatives, which grows when the view is rolled (tilting your head).
	vec2 deriv = sqrt(dFdx(uv) * dFdx(uv) + dFdy(uv) * dFdy(uv));

	float minor = grid_lines(uv, deriv, line_width);
	float major = grid_lines(uv / float(major_every), deriv / float(major_every), 1.5 * line_width);

	vec3 col = base_color;
	col = mix(col, line_color, minor * 0.8);
	col = mix(col, major_color, major);

	vec3 to_floor = world_pos - CAMERA_POSITION_WORLD;
	float dist = length(to_floor.xz);
	float h = normalize(to_floor).y;
	vec3 sky_color = mix(horizon_color, ground_color, smoothstep(0.0, 0.06, -h));
	col = mix(col, sky_color, smoothstep(fade_start, fade_end, dist));

	ALBEDO = col;
}

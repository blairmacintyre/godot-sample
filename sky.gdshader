shader_type sky;

// Fantasy sky: violet-to-teal gradient with a glowing horizon, drifting
// clouds, shimmering aurora ribbons, twinkling stars and two moons.

uniform vec3 zenith_color : source_color = vec3(0.04, 0.02, 0.20);
uniform vec3 mid_color : source_color = vec3(0.35, 0.10, 0.55);
uniform vec3 horizon_color : source_color = vec3(1.00, 0.45, 0.50);
uniform vec3 ground_color : source_color = vec3(0.05, 0.03, 0.12);
uniform vec3 aurora_a : source_color = vec3(0.10, 1.00, 0.60);
uniform vec3 aurora_b : source_color = vec3(0.60, 0.30, 1.00);
uniform vec3 moon_a_dir = vec3(0.55, 0.45, -0.70);
uniform vec3 moon_b_dir = vec3(-0.70, 0.30, -0.65);

// Noise is built on an integer hash, not fract(sin()) style float math, and every
// value is highp. The float hash lost precision on the Quest's GPU and left
// angular, straight-edged facets in the clouds and aurora.
uint pcg(uint v) {
	uint state = v * 747796405u + 2891336453u;
	uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
	return (word >> 22u) ^ word;
}

highp float hash21(highp vec2 p) {
	ivec2 i = ivec2(floor(p));
	uint h = pcg(uint(i.x) + pcg(uint(i.y) + 2654435769u));
	return float(h >> 8u) * (1.0 / 16777216.0);
}

highp float hash31(highp vec3 p) {
	ivec3 i = ivec3(floor(p));
	uint h = pcg(uint(i.x) + pcg(uint(i.y) + pcg(uint(i.z) + 2654435769u)));
	return float(h >> 8u) * (1.0 / 16777216.0);
}

highp float vnoise(highp vec2 p) {
	highp vec2 i = floor(p);
	highp vec2 f = fract(p);
	// Quintic fade: smoother than the cubic one, so the lattice shows less.
	f = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
			mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

highp float fbm(highp vec2 p) {
	highp float v = 0.0;
	highp float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p = p * 2.03 + vec2(17.1, 9.2);
		a *= 0.5;
	}
	return v;
}

vec3 moon(vec3 dir, vec3 moon_dir, float radius, vec3 tint) {
	vec3 m = normalize(moon_dir);
	float d = acos(clamp(dot(dir, m), -1.0, 1.0));
	float disc = smoothstep(radius, radius * 0.92, d);
	float glow = exp(-d * 9.0) * 0.45;
	// Cheap crater shading from noise on the disc.
	vec3 t = normalize(cross(m, vec3(0.0, 1.0, 0.0)));
	vec3 b = cross(m, t);
	highp vec2 local = vec2(dot(dir, t), dot(dir, b)) / radius;
	float crater = fbm(local * 3.0 + 3.0);
	return tint * (disc * (0.65 + 0.5 * crater) + glow);
}

void sky() {
	highp vec3 dir = normalize(EYEDIR);
	highp float h = dir.y;

	// Base gradient.
	vec3 col;
	if (h >= 0.0) {
		float t = pow(h, 0.55);
		col = mix(horizon_color, mid_color, smoothstep(0.0, 0.35, t));
		col = mix(col, zenith_color, smoothstep(0.3, 1.0, t));
	} else {
		// Starts at exactly horizon_color so it meets the sky above without a step.
		col = mix(horizon_color, ground_color, smoothstep(0.0, 0.25, -h));
	}

	if (h > 0.0) {
		// Stars: cells on the direction sphere, only in the darker upper sky.
		highp vec3 sp = dir * 90.0;
		highp vec3 cell = floor(sp);
		float star = hash31(cell);
		highp vec3 local = fract(sp) - 0.5;
		float star_mask = step(0.985, star) * smoothstep(0.35, 0.0, length(local));
		float twinkle = 0.7 + 0.3 * sin(TIME * 2.0 + star * 60.0);
		col += vec3(0.9, 0.95, 1.0) * star_mask * twinkle * smoothstep(0.15, 0.6, h);

		// Aurora ribbons: two noisy bands sweeping across the sky.
		highp vec2 uv = dir.xz / (dir.y + 0.35);
		highp float wave = sin(uv.x * 1.5 + TIME * 0.15) * 0.5 + fbm(uv * 1.3 + TIME * 0.05);
		float band1 = smoothstep(0.25, 0.0, abs(h - 0.40 - 0.10 * wave));
		float band2 = smoothstep(0.20, 0.0, abs(h - 0.62 - 0.08 * sin(uv.y * 1.2 - TIME * 0.1)));
		// Sample noise from the direction itself, not atan(z, x): the angle jumps
		// from +pi to -pi behind the viewer and leaves a visible seam.
		highp float curtain = 0.5 + 0.5 * fbm(dir.xz * 3.0 + vec2(TIME * 0.1, 0.0));
		col += aurora_a * band1 * curtain * 0.55;
		col += aurora_b * band2 * (1.0 - curtain * 0.5) * 0.40;

		// Clouds: lit from the horizon glow, fading toward the zenith.
		highp vec2 cuv = dir.xz / (h + 0.25) * 0.9 + vec2(TIME * 0.01, 0.0);
		highp float c = fbm(cuv * 1.6);
		c = smoothstep(0.52, 0.85, c);
		vec3 cloud_col = mix(horizon_color * 1.1, mid_color * 1.5, smoothstep(0.0, 0.5, h));
		col = mix(col, cloud_col, c * smoothstep(0.0, 0.12, h) * (1.0 - smoothstep(0.5, 0.9, h)) * 0.7);

		// Two moons.
		col += moon(dir, moon_a_dir, 0.11, vec3(1.00, 0.90, 0.75));
		col += moon(dir, moon_b_dir, 0.06, vec3(0.55, 0.80, 1.00));
	}

	COLOR = col;
}

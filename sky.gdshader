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

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float hash31(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
			mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
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
	vec2 local = vec2(dot(dir, t), dot(dir, b)) / radius;
	float crater = fbm(local * 3.0 + 3.0);
	return tint * (disc * (0.65 + 0.5 * crater) + glow);
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	float h = dir.y;

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
		vec3 sp = dir * 90.0;
		vec3 cell = floor(sp);
		float star = hash31(cell);
		vec3 local = fract(sp) - 0.5;
		float star_mask = step(0.985, star) * smoothstep(0.35, 0.0, length(local));
		float twinkle = 0.7 + 0.3 * sin(TIME * 2.0 + star * 60.0);
		col += vec3(0.9, 0.95, 1.0) * star_mask * twinkle * smoothstep(0.15, 0.6, h);

		// Aurora ribbons: two noisy bands sweeping across the sky.
		vec2 uv = dir.xz / (dir.y + 0.35);
		float wave = sin(uv.x * 1.5 + TIME * 0.15) * 0.5 + fbm(uv * 1.3 + TIME * 0.05);
		float band1 = smoothstep(0.25, 0.0, abs(h - 0.40 - 0.10 * wave));
		float band2 = smoothstep(0.20, 0.0, abs(h - 0.62 - 0.08 * sin(uv.y * 1.2 - TIME * 0.1)));
		// Sample noise from the direction itself, not atan(z, x): the angle jumps
		// from +pi to -pi behind the viewer and leaves a visible seam.
		float curtain = 0.5 + 0.5 * fbm(dir.xz * 3.0 + vec2(TIME * 0.1, 0.0));
		col += aurora_a * band1 * curtain * 0.55;
		col += aurora_b * band2 * (1.0 - curtain * 0.5) * 0.40;

		// Clouds: lit from the horizon glow, fading toward the zenith.
		vec2 cuv = dir.xz / (h + 0.25) * 0.9 + vec2(TIME * 0.01, 0.0);
		float c = fbm(cuv * 1.6);
		c = smoothstep(0.52, 0.85, c);
		vec3 cloud_col = mix(horizon_color * 1.1, mid_color * 1.5, smoothstep(0.0, 0.5, h));
		col = mix(col, cloud_col, c * smoothstep(0.0, 0.12, h) * (1.0 - smoothstep(0.5, 0.9, h)) * 0.7);

		// Two moons.
		col += moon(dir, moon_a_dir, 0.11, vec3(1.00, 0.90, 0.75));
		col += moon(dir, moon_b_dir, 0.06, vec3(0.55, 0.80, 1.00));
	}

	COLOR = col;
}

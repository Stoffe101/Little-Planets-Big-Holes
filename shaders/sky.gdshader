shader_type sky;

// Candy-space sky: a pastel gradient that follows the player's local "up", stars at the zenith,
// a soft sun and a couple of neighbouring toy planets.

uniform vec3 top_color : source_color = vec3(0.11, 0.1, 0.33);
uniform vec3 mid_color : source_color = vec3(0.36, 0.29, 0.77);
uniform vec3 horizon_color : source_color = vec3(1.0, 0.62, 0.69);
uniform vec3 glow_color : source_color = vec3(1.0, 0.84, 0.6);
uniform vec3 sun_color : source_color = vec3(1.0, 0.95, 0.79);
uniform vec3 up_dir = vec3(0.0, 1.0, 0.0);
uniform vec3 sun_dir = vec3(0.3, 0.8, 0.5);
uniform vec3 planet_a_dir = vec3(-0.6, 0.35, 0.7);
uniform vec3 planet_a_color : source_color = vec3(0.37, 0.88, 0.82);
uniform vec3 planet_b_dir = vec3(0.75, 0.15, -0.6);
uniform vec3 planet_b_color : source_color = vec3(1.0, 0.6, 0.45);
uniform float star_amount = 1.0;
uniform float underground = 0.0;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

vec3 toy_planet(vec3 dir, vec3 pdir, vec3 pcol, float size, vec3 light) {
	float d = dot(dir, normalize(pdir));
	float edge = cos(size);
	if (d < edge) { return vec3(-1.0); }
	// fake sphere normal from the angular offset
	vec3 c = normalize(pdir);
	vec3 off = (dir - c * d) / sin(size);
	float z = sqrt(max(0.0, 1.0 - dot(off, off)));
	vec3 n = normalize(off + c * -z);
	float l = dot(n, normalize(light)) * 0.5 + 0.5;
	float band = smoothstep(0.45, 0.55, l) * 0.5 + smoothstep(0.7, 0.8, l) * 0.3 + 0.35;
	float stripes = 0.92 + 0.08 * sin(dot(off, vec3(3.0, 9.0, 5.0)) * 4.0);
	return pcol * band * stripes;
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	float h = dot(dir, normalize(up_dir));
	vec3 col = mix(horizon_color, mid_color, smoothstep(-0.05, 0.38, h));
	col = mix(col, top_color, smoothstep(0.3, 0.95, h));
	col = mix(col, mid_color * 0.55, smoothstep(0.0, -0.6, h));
	// horizon glow
	col += glow_color * pow(1.0 - abs(h), 9.0) * 0.35;

	// stars: jittered cells on the direction sphere
	vec3 sp = dir * 70.0;
	vec3 cell = floor(sp);
	float rnd = hash13(cell);
	vec3 jitter = vec3(hash13(cell + 7.1), hash13(cell + 13.7), hash13(cell + 29.3));
	float sd = length(fract(sp) - 0.25 - jitter * 0.5);
	float star = smoothstep(0.09, 0.0, sd) * step(0.86, rnd);
	float twinkle = 0.7 + 0.3 * sin(TIME * (1.0 + rnd * 3.0) + rnd * 40.0);
	col += vec3(1.0, 0.97, 0.9) * star * twinkle * star_amount * smoothstep(-0.1, 0.5, h);

	// Keep the gradient itself below the glow threshold so only the sun blooms; otherwise the
	// bright horizon bleeds a haze over everything in front of it.
	col = min(col, vec3(0.98));

	// sun: disc + two soft halos
	float sdot = dot(dir, normalize(sun_dir));
	col += sun_color * smoothstep(0.9965, 0.9975, sdot) * 2.5;
	col += sun_color * pow(max(sdot, 0.0), 180.0) * 0.6;
	col += glow_color * pow(max(sdot, 0.0), 12.0) * 0.22;

	vec3 pa = toy_planet(dir, planet_a_dir, planet_a_color, 0.085, sun_dir);
	if (pa.x >= 0.0) { col = pa; }
	vec3 pb = toy_planet(dir, planet_b_dir, planet_b_color, 0.045, sun_dir);
	if (pb.x >= 0.0) { col = pb; }

	COLOR = mix(col, col * 0.25, underground);
}

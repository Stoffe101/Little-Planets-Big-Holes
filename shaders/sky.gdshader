shader_type sky;

// Small-planet sky: a thin, clean atmosphere over open space. A restrained three-stop gradient
// follows the player's local "up", stars show through towards the zenith, the sun is a small
// crisp disc and one neighbouring world hangs in the distance. Nothing here should compete
// with the ground for attention (docs/ART_DIRECTION.md, "Sky and atmosphere").

uniform vec3 top_color : source_color = vec3(0.02, 0.04, 0.1);
uniform vec3 mid_color : source_color = vec3(0.12, 0.3, 0.52);
uniform vec3 horizon_color : source_color = vec3(0.55, 0.68, 0.74);
uniform vec3 glow_color : source_color = vec3(0.9, 0.8, 0.6);      // warm haze around the sun
uniform vec3 ground_color : source_color = vec3(0.12, 0.14, 0.12); // below the horizon (drives bounce light)
uniform vec3 sun_color : source_color = vec3(1.0, 0.95, 0.85);
uniform vec3 up_dir = vec3(0.0, 1.0, 0.0);
uniform vec3 sun_dir = vec3(0.3, 0.8, 0.5);
uniform vec3 planet_a_dir = vec3(-0.6, 0.35, 0.7);
uniform vec3 planet_a_color : source_color = vec3(0.45, 0.55, 0.6);
uniform vec3 planet_a_color2 : source_color = vec3(0.3, 0.38, 0.33);
uniform float planet_a_size = 0.05;                                 // angular radius in radians
uniform vec3 moon_dir = vec3(0.75, 0.2, -0.6);
uniform vec3 moon_color : source_color = vec3(0.55, 0.55, 0.58);
uniform float moon_size = 0.022;
uniform float star_amount = 1.0;
uniform float atmosphere = 1.0;      // 1 = soft daytime air, 0 = airless (stars everywhere)
uniform float nebula_amount = 0.0;
uniform vec3 nebula_color : source_color = vec3(0.1, 0.16, 0.32);
uniform float underground = 0.0;
uniform float horizon_dip = 0.0;    // sine of the angle the planet's limb sits below eye level (tiny planets: a lot)

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = p - i;
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash13(i), hash13(i + vec3(1, 0, 0)), f.x), mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), f.x), mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

// A lit sphere seen from far away: returns rgb, a = coverage (antialiased edge).
vec4 body(vec3 dir, vec3 bdir, float size, vec3 col_a, vec3 col_b, vec3 light, float banding) {
	vec3 c = normalize(bdir);
	float d = dot(dir, c);
	float ang = acos(clamp(d, -1.0, 1.0));
	float cover = 1.0 - smoothstep(size * 0.97, size, ang);
	if (cover <= 0.0) { return vec4(0.0); }
	vec3 off = (dir - c * d) / sin(size);
	float z = sqrt(max(0.0, 1.0 - dot(off, off)));
	vec3 n = normalize(off - c * z);
	// A distant world is always shown at a pleasant gibbous phase, leaning towards the real sun.
	vec3 l_dir = normalize(normalize(light) - c * 0.55);
	float l = smoothstep(-0.1, 0.5, dot(n, l_dir));
	float bands = vnoise(vec3(off.y * 4.0 + vnoise(off * 2.5) * 1.5, off.x * 1.0, 3.7));
	vec3 albedo = mix(col_a, col_b, smoothstep(0.3, 0.7, bands) * banding);
	vec3 col = albedo * (0.1 + 0.9 * l);
	col += albedo * pow(1.0 - z, 2.5) * 0.3 * l;       // thin limb haze
	return vec4(col, cover);
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	vec3 up = normalize(up_dir);
	float h = dot(dir, up);

	// gradient measured from the planet's actual limb, not from eye level: on a 48 m world the
	// horizon drops far below "level", and the haze has to hug it.
	float t = h + horizon_dip;
	vec3 col = mix(horizon_color, mid_color, smoothstep(0.0, 0.3, t));
	col = mix(col, top_color, smoothstep(0.3, 1.15, t));
	if (AT_CUBEMAP_PASS) {
		// what lights the scene from below is the ground, not the sky behind the planet
		col = mix(col, ground_color, smoothstep(0.02, -0.12, t));
	} else {
		// looking past the limb (down a hole, off a cliff): thinning air, then space
		col = mix(col, mix(mid_color, top_color, 0.5), smoothstep(0.0, -0.45, t));
	}

	// faint nebula band for airless moons
	if (nebula_amount > 0.0) {
		float nb = vnoise(dir * 2.2 + 5.0) * 0.6 + vnoise(dir * 5.1) * 0.4;
		float band = 1.0 - smoothstep(0.0, 0.55, abs(dot(dir, normalize(vec3(0.35, 0.8, -0.45)))));
		col += nebula_color * smoothstep(0.42, 0.85, nb) * band * nebula_amount * smoothstep(-0.05, 0.25, t);
	}

	// stars: jittered cells on the direction sphere; the atmosphere hides them near the horizon
	vec3 sp = dir * 90.0;
	vec3 cell = floor(sp);
	float rnd = hash13(cell);
	vec3 jitter = vec3(hash13(cell + 7.1), hash13(cell + 13.7), hash13(cell + 29.3));
	float sd = length(fract(sp) - 0.25 - jitter * 0.5);
	float star = smoothstep(0.07, 0.0, sd) * step(0.9, rnd) * (0.35 + 0.65 * hash13(cell + 3.3));
	float star_vis = mix(smoothstep(-0.02, 0.2, t), smoothstep(0.25, 0.85, t), atmosphere);
	col += vec3(0.95, 0.97, 1.0) * star * star_amount * star_vis;

	// sun: small disc with a tight halo and a gentle warm haze
	float sdot = dot(dir, normalize(sun_dir));
	float above = smoothstep(-0.06, 0.02, t);
	col += glow_color * pow(max(sdot, 0.0), 14.0) * 0.1 * atmosphere * above;
	col += sun_color * pow(max(sdot, 0.0), 1400.0) * 0.6 * above;
	col += sun_color * smoothstep(0.99955, 0.99975, sdot) * 6.0 * above;

	vec4 pa = body(dir, planet_a_dir, planet_a_size, planet_a_color, planet_a_color2, sun_dir, 1.0);
	col = mix(col, mix(pa.rgb, col, 0.38 * atmosphere), pa.a * smoothstep(-0.05, 0.03, t));
	vec4 mo = body(dir, moon_dir, moon_size, moon_color, moon_color * 0.8, sun_dir, 0.6);
	col = mix(col, mix(mo.rgb, col, 0.38 * atmosphere), mo.a * smoothstep(-0.05, 0.03, t));

	COLOR = mix(col, col * 0.12, underground);
}

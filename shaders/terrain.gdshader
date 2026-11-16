shader_type spatial;
render_mode cull_back, depth_draw_opaque, diffuse_lambert, specular_schlick_ggx;

// Planet terrain: colours every fragment from the same deterministic geology function the
// gameplay code uses (see src/planet/geology.gd). Materials are never stored per-voxel.

#include "res://shaders/toon_light.gdshaderinc"

uniform float voxel_size = 0.5;
uniform float planet_radius = 48.0;
uniform sampler2D height_map : filter_linear, repeat_disable;   // octahedral: R = height, G/B = tints
uniform sampler3D noise_a : filter_linear, repeat_enable;
uniform sampler3D noise_b : filter_linear, repeat_enable;
uniform sampler3D noise_c : filter_linear, repeat_enable;
uniform float noise_n = 96.0;
uniform float layer_warp = 1.5;
uniform float edge_fade = 1.5;

uniform int layer_count = 1;
uniform float layer_bottom[8];
uniform int layer_mat[8];

uniform int ore_count = 0;
uniform vec4 ore_a[12];   // min depth, max depth, scale, threshold
uniform vec4 ore_b[12];   // offset xyz, channel
uniform int ore_mat[12];

uniform vec3 mat_color[24] : source_color;
uniform vec3 mat_color2[24] : source_color;
uniform vec4 mat_fx[24];  // emission, sparkle, is_ore, unused

uniform vec3 grass_a : source_color = vec3(0.5, 0.86, 0.35);
uniform vec3 grass_b : source_color = vec3(0.25, 0.81, 0.56);
uniform vec3 grass_c : source_color = vec3(0.79, 0.92, 0.36);
uniform vec3 rim_color : source_color = vec3(0.56, 0.94, 1.0);

uniform vec3 scan_origin = vec3(0.0);       // planet-local metres
uniform float scan_radius = -1.0;           // < 0 = no scan pulse
uniform float scan_strength = 0.0;
uniform float bloom_amount = 0.0;           // 0..1, planet "awakened" glow on the grass
uniform float underground_dim = 0.0;        // 0..1 darkens ambient when the camera is deep

varying vec3 lp;        // planet-local position in metres
varying vec3 lnormal;   // planet-local normal

vec2 oct_encode(vec3 n) {
	vec3 a = n / (abs(n.x) + abs(n.y) + abs(n.z));
	vec2 o = a.xz;
	if (a.y < 0.0) {
		o = vec2((1.0 - abs(a.z)) * (a.x >= 0.0 ? 1.0 : -1.0), (1.0 - abs(a.x)) * (a.z >= 0.0 ? 1.0 : -1.0));
	}
	return o * 0.5 + 0.5;
}

float sample_noise(int channel, vec3 q) {
	vec3 uvw = q / noise_n;
	if (channel == 0) { return texture(noise_a, uvw).r; }
	if (channel == 1) { return texture(noise_b, uvw).r; }
	return texture(noise_c, uvw).r;
}

vec3 hash33(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.xxy + p.yxx) * p.zyx);
}

// Cheap 2x2x2 cellular noise: x = distance to nearest cell centre, y = random id of that cell.
// Gives the ground a crisp, chunky "clods and cobbles" look right up to the camera.
vec2 cells(vec3 p) {
	vec3 ip = floor(p - 0.5);
	vec3 fp = p - ip;
	float best = 8.0;
	float id = 0.0;
	for (int z = 0; z <= 1; z++) {
		for (int y = 0; y <= 1; y++) {
			for (int x = 0; x <= 1; x++) {
				vec3 g = vec3(float(x), float(y), float(z));
				vec3 h = hash33(ip + g);
				vec3 d = g + 0.25 + h * 0.5 - fp;
				float dd = dot(d, d);
				if (dd < best) { best = dd; id = h.x; }
			}
		}
	}
	return vec2(sqrt(best), id);
}

void vertex() {
	// Mesh blocks are separate instances offset from the terrain origin, so go through world space.
	// The planet sits at the world origin (see planet.gd), therefore world metres == planet-local metres.
	lp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	lnormal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	float r = length(lp);
	vec3 dir = lp / max(r, 0.001);
	vec3 hm = texture(height_map, oct_encode(dir)).rgb;
	float depth = planet_radius + hm.r - r;
	float warp = (sin(lp.x * 0.21 + 1.3) + sin(lp.y * 0.17 + 4.1) + sin(lp.z * 0.19 + 2.2)) * (layer_warp / 3.0);
	float dl = depth + warp * smoothstep(1.0, 5.0, depth);

	// --- base layer
	int mat = layer_mat[0];
	float layer_edge = 10.0;   // distance (m) to the nearest strata boundary, for a soft seam line
	for (int i = 0; i < layer_count; i++) {
		if (dl < layer_bottom[i]) { mat = layer_mat[i]; break; }
		mat = layer_mat[i];
	}
	for (int i = 0; i < layer_count; i++) {
		layer_edge = min(layer_edge, abs(dl - layer_bottom[i]));
	}

	// --- ores (first match wins; same order as Geology.material_for)
	float ore_rim = 0.0;
	bool is_ore = false;
	for (int i = 0; i < ore_count; i++) {
		vec4 a = ore_a[i];
		if (dl > a.x && dl < a.y) {
			float edge = clamp(max(1.0 - (dl - a.x) / edge_fade, 1.0 - (a.y - dl) / edge_fade), 0.0, 1.0);
			float thr = mix(a.w, 1.01, edge);
			float n = sample_noise(int(ore_b[i].w), lp * a.z + ore_b[i].xyz);
			if (n > thr) {
				mat = ore_mat[i];
				is_ore = true;
				ore_rim = 1.0 - smoothstep(0.0, 0.03, n - thr);
				break;
			}
		}
	}

	vec3 c1 = mat_color[mat];
	vec3 c2 = mat_color2[mat];
	vec4 fx = mat_fx[mat];

	// --- stylised detail: chunky clods/cobbles + sediment stripes
	float n_big = texture(noise_b, lp * 0.045).r;
	float n_small = texture(noise_c, lp * 0.21 + 0.37).r;
	bool rocky = mat_fx[mat].w > 0.5;
	vec2 cell = cells(lp * (rocky ? 1.5 : 2.6));
	float mottle = smoothstep(0.42, 0.58, n_small);
	vec3 col = mix(c1, c2, mottle * 0.6);
	if (!is_ore) {
		col = mix(col, c2, step(0.72, cell.y) * 0.5);
		col *= 0.93 + 0.12 * cell.y;
		col *= mix(0.84, 1.0, smoothstep(0.50, 0.42, cell.x) );                 // dark gaps between clods
		float stripe = smoothstep(0.35, 0.5, abs(fract(dl * 0.55 + n_big * 1.2) - 0.5));
		col *= mix(0.92, 1.03, stripe);
		col *= mix(1.0, 0.8, 1.0 - smoothstep(0.0, 0.12, layer_edge));   // dark seam between strata
	} else {
		// facets: each cell is a flat gem face, with a dark outline where ore meets rock
		vec2 facet = cells(lp * 3.2 + 7.7);
		col = mix(c1, c2, facet.y);
		col *= mix(0.8, 1.0, smoothstep(0.52, 0.4, facet.x));
		col *= mix(1.0, 0.45, ore_rim);
	}

	// --- grass skin on the original surface
	vec3 world_n = normalize(lnormal);
	float up_facing = dot(world_n, dir);
	// The turf edge is jittered by noise so cut holes get a crisp, hand-torn rim instead of a blur.
	float turf = 0.34 + (n_small - 0.5) * 0.22;
	float grass = (1.0 - smoothstep(turf - 0.02, turf + 0.02, depth)) * smoothstep(0.42, 0.5, up_facing);
	vec3 gcol = mix(grass_a, grass_b, smoothstep(0.5, 0.62, hm.g));
	gcol = mix(gcol, grass_c, smoothstep(0.6, 0.7, hm.b));
	vec2 gcell = cells(lp * 3.4 + 3.1);
	gcol *= 0.93 + 0.11 * gcell.y;
	gcol = mix(gcol, gcol * vec3(1.12, 1.1, 0.85), step(0.86, gcell.y));     // sunlit tufts
	gcol *= mix(0.95, 1.0, smoothstep(0.4, 0.6, n_big));
	// darker root band just under the turf
	float lip = (1.0 - smoothstep(turf + 0.02, turf + 0.3, depth)) * (1.0 - grass) * step(0.0, depth);
	col = mix(col, gcol, grass);
	col *= mix(1.0, 0.7, lip);

	ALBEDO = col;
	ROUGHNESS = is_ore ? 0.35 : 0.95;
	SPECULAR = 0.0;
	METALLIC = 0.0;

	// --- glow & sparkle
	vec3 emission = c2 * fx.x * (0.6 + 0.4 * n_big);
	if (fx.y > 0.0) {
		vec3 vdir = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
		float glint = texture(noise_a, lp * 1.7 + vdir * 2.5).r;
		glint = smoothstep(0.80, 0.86, glint) * fx.y;
		emission += c2 * glint * (is_ore ? 2.2 : 0.5);
	}
	emission += gcol * grass * bloom_amount * 0.35;

	// --- scanner pulse ring (travels through rock; ores light up as the ring passes)
	if (scan_radius >= 0.0) {
		float sd = distance(lp, scan_origin);
		float ring = 1.0 - smoothstep(0.0, 1.4, abs(sd - scan_radius));
		float wake = smoothstep(scan_radius - 14.0, scan_radius, sd) * step(sd, scan_radius);
		emission += rim_color * ring * 1.6 * scan_strength;
		if (is_ore) { emission += c2 * wake * 2.5 * scan_strength; }
	}
	EMISSION = emission;
	AO = 1.0;
}

void light() {
	DIFFUSE_LIGHT += toon_diffuse(NORMAL, LIGHT, LIGHT_COLOR, ATTENUATION, vec3(1.0));
	// small, soft highlight for shiny ore (ROUGHNESS-driven)
	vec3 h = normalize(LIGHT + VIEW);
	float spec = pow(max(dot(NORMAL, h), 0.0), mix(64.0, 6.0, ROUGHNESS)) * (1.0 - ROUGHNESS);
	SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * spec * 0.6;
}

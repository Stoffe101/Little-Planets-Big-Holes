shader_type spatial;
render_mode cull_back, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

// Planet terrain: colours every fragment from the same deterministic geology function the
// gameplay code uses (see src/planet/geology.gd). Materials are never stored per-voxel.
//
// The shader has two halves:
//   1. WHAT is here  - depth, strata and ore lookup. Must stay identical to Geology.material_for.
//   2. HOW it looks  - restrained natural colour, fine procedural surface relief (a detail
//      normal instead of colour patches), sediment banding on cut faces, and occlusion that
//      deepens with depth so excavations read as real holes. See docs/ART_DIRECTION.md.

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
uniform vec4 ore_c[12];   // region index (-1 = none), threshold inside that region
uniform int ore_mat[12];

uniform vec3 mat_color[24] : source_color;
uniform vec3 mat_color2[24] : source_color;
uniform vec4 mat_fx[24];   // emission, sparkle, is_ore, kind (0 soil, 1 rock, 2 crystalline)
uniform vec4 mat_pbr[24];  // roughness, metallic, strata strength, relief strength

// Regions: soft areas that lift the strata, thin the ground cover and recolour it.
uniform int region_count = 0;
uniform vec4 region_a[8];   // direction xyz, cos(inner radius)
uniform vec4 region_b[8];   // cos(outer radius), strata lift (m), ground cover (0..1), unused
uniform vec4 region_grass_a[8] : source_color;   // a = 0 means "use the planet's colours"
uniform vec4 region_grass_b[8] : source_color;

// Transvoxel LOD stitching (set by VoxelLodTerrain per mesh block).
uniform int u_transition_mask;

uniform vec3 grass_a : source_color = vec3(0.21, 0.32, 0.11);
uniform vec3 grass_b : source_color = vec3(0.15, 0.27, 0.13);
uniform vec3 grass_c : source_color = vec3(0.37, 0.39, 0.14);
uniform vec3 rim_color : source_color = vec3(0.1, 0.68, 0.57);
uniform float turf_depth = 0.34;            // thickness of the surface skin in metres
uniform float cover_relief = 0.55;          // strength of the fine relief on the surface skin
uniform float cover_roughness = 0.92;

uniform vec3 scan_origin = vec3(0.0);       // planet-local metres
uniform float scan_radius = -1.0;           // < 0 = no scan pulse
uniform float scan_strength = 0.0;
uniform float bloom_amount = 0.0;           // 0..1, planet "awakened": the ground cover grows lusher
uniform float underground_dim = 0.0;        // reserved

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

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

// Value noise with analytic gradient: x = value (0..1), yzw = d/dp.
vec4 vnoise_d(vec3 p) {
	vec3 i = floor(p);
	vec3 f = p - i;
	vec3 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	vec3 du = 30.0 * f * f * (f * (f - 2.0) + 1.0);
	float a = hash13(i);
	float b = hash13(i + vec3(1.0, 0.0, 0.0));
	float c = hash13(i + vec3(0.0, 1.0, 0.0));
	float d = hash13(i + vec3(1.0, 1.0, 0.0));
	float e = hash13(i + vec3(0.0, 0.0, 1.0));
	float f1 = hash13(i + vec3(1.0, 0.0, 1.0));
	float g = hash13(i + vec3(0.0, 1.0, 1.0));
	float h = hash13(i + vec3(1.0, 1.0, 1.0));
	float k0 = a;
	float k1 = b - a;
	float k2 = c - a;
	float k3 = e - a;
	float k4 = a - b - c + d;
	float k5 = a - c - e + g;
	float k6 = a - b - e + f1;
	float k7 = -a + b + c - d + e - f1 - g + h;
	float v = k0 + k1 * u.x + k2 * u.y + k3 * u.z + k4 * u.x * u.y + k5 * u.y * u.z + k6 * u.z * u.x + k7 * u.x * u.y * u.z;
	vec3 dv = du * vec3(
		k1 + k4 * u.y + k6 * u.z + k7 * u.y * u.z,
		k2 + k5 * u.z + k4 * u.x + k7 * u.z * u.x,
		k3 + k6 * u.x + k5 * u.y + k7 * u.x * u.y);
	return vec4(v, dv);
}

// VoxelMesherTransvoxel packs, per vertex, a secondary position (CUSTOM0.xyz) and bit flags
// (CUSTOM0.a): bits 0-5 = cell borders, bits 8-13 = vertex borders, bits 16-21 = which
// transition side the vertex belongs to (0 = regular cell). Verified against meshes produced
// by Voxel Tools 1.7 (tools/dev/lodproto.gd).
vec3 transvoxel_position(vec3 vertex_pos, vec4 fdata) {
	int idata = floatBitsToInt(fdata.a);
	int cell_border_mask = idata & 63;
	int vertex_border_mask = (idata >> 8) & 63;
	// near a side with a lower-resolution neighbour: move to the secondary position...
	float t = float((u_transition_mask & cell_border_mask) != 0);
	// ...unless the vertex sits on a side whose neighbour is NOT lower resolution
	t *= float((vertex_border_mask & ~u_transition_mask) == 0);
	vec3 pos = mix(vertex_pos, fdata.xyz, t);
	// transition-cell triangles are only shown on the sides that need them
	int transition_side = (idata >> 16) & 63;
	if (transition_side != 0 && (transition_side & u_transition_mask) == 0) {
		pos = vec3(0.0);
	}
	return pos;
}

float region_weight(int i, vec3 dir) {
	return smoothstep(region_b[i].x, region_a[i].w, dot(dir, region_a[i].xyz));
}

void vertex() {
	VERTEX = transvoxel_position(VERTEX, CUSTOM0);
	// Mesh blocks are separate instances offset from the terrain origin, so go through world space.
	// The planet sits at the world origin (see planet.gd), therefore world metres == planet-local metres.
	lp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	lnormal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	// ================= 1. WHAT is here (mirror of Geology.material_for) =================
	float r = length(lp);
	vec3 dir = lp / max(r, 0.001);
	vec3 hm = texture(height_map, oct_encode(dir)).rgb;
	float depth = planet_radius + hm.r - r;
	float warp = (sin(lp.x * 0.21 + 1.3) + sin(lp.y * 0.17 + 4.1) + sin(lp.z * 0.19 + 2.2)) * (layer_warp / 3.0);
	float lift = 0.0;
	float cover_amount = 1.0;
	vec3 rgrass_a = vec3(0.0);
	vec3 rgrass_b = vec3(0.0);
	float rgrass_w = 0.0;
	for (int i = 0; i < region_count; i++) {
		float w = region_weight(i, dir);
		lift += region_b[i].y * w;
		cover_amount = mix(cover_amount, region_b[i].z, w);
		if (region_grass_a[i].a > 0.5 && w > 0.0) {
			rgrass_a = mix(rgrass_a, region_grass_a[i].rgb, w / max(rgrass_w + w, 0.0001));
			rgrass_b = mix(rgrass_b, region_grass_b[i].rgb, w / max(rgrass_w + w, 0.0001));
			rgrass_w = max(rgrass_w, w);
		}
	}
	float dl = depth + warp * smoothstep(1.0, 5.0, depth) + lift * smoothstep(0.0, 1.5, depth);

	int mat = layer_mat[0];
	float layer_edge = 10.0;   // distance (m) to the nearest strata boundary
	for (int i = 0; i < layer_count; i++) {
		if (dl < layer_bottom[i]) { mat = layer_mat[i]; break; }
		mat = layer_mat[i];
	}
	for (int i = 0; i < layer_count; i++) {
		layer_edge = min(layer_edge, abs(dl - layer_bottom[i]));
	}

	float ore_in = 0.0;        // how far past the ore threshold (0 at the vein's edge)
	bool is_ore = false;
	for (int i = 0; i < ore_count; i++) {
		vec4 a = ore_a[i];
		if (dl > a.x && dl < a.y) {
			float edge = clamp(max(1.0 - (dl - a.x) / edge_fade, 1.0 - (a.y - dl) / edge_fade), 0.0, 1.0);
			float base_thr = a.w;
			int ri = int(ore_c[i].x);
			if (ri >= 0) { base_thr = mix(a.w, ore_c[i].y, region_weight(ri, dir)); }
			float thr = mix(base_thr, 1.01, edge);
			float n = sample_noise(int(ore_b[i].w), lp * a.z + ore_b[i].xyz);
			if (n > thr) {
				mat = ore_mat[i];
				is_ore = true;
				ore_in = n - thr;
				break;
			}
		}
	}

	// ================= 2. HOW it looks =================
	vec3 c1 = mat_color[mat];
	vec3 c2 = mat_color2[mat];
	vec4 fx = mat_fx[mat];
	vec4 pbr = mat_pbr[mat];
	vec3 world_n = normalize(lnormal);
	float up_facing = dot(world_n, dir);
	float view_dist = length(VERTEX);
	float near_fade = 1.0 - smoothstep(16.0, 46.0, view_dist);   // fine detail fades with distance (no shimmer)

	float n_big = texture(noise_b, lp * 0.045).r;                // ~20 m patches
	float n_mid = texture(noise_c, lp * 0.21 + 0.37).r;          // ~1 m mottling
	vec4 d1 = vnoise_d(lp * 5.5);                                // ~18 cm grain
	vec4 d2 = vnoise_d(lp * 17.0 + 11.3);                        // ~6 cm grit
	float grain = d1.x * 0.65 + d2.x * 0.35;
	vec3 relief = d1.yzw * 5.5 * 0.65 + d2.yzw * 17.0 * 0.35;    // gradient of `grain`

	vec3 col;
	vec3 facet_tilt = vec3(0.0);
	float rough = pbr.x;
	float metallic = 0.0;
	float relief_k = pbr.w;
	if (!is_ore) {
		// Sediment: broad alternating tones plus thin darker bedding lines, both following the
		// (warped) depth so every cut face shows the layering.
		// Layering belongs on cut walls. Floors and ceilings run along a stratum, where depth
		// bands would smear into contour swirls, so there the tone settles to its average.
		float wall = 1.0 - smoothstep(0.45, 0.85, abs(up_facing));
		float tone = smoothstep(0.3, 0.7, texture(noise_a, vec3(dl * 0.09, 0.37, 0.61)).r);
		tone = mix(0.45, tone, wall);
		col = mix(c1, c2, clamp(tone * 0.7 + (n_mid - 0.5) * 0.25, 0.0, 1.0));
		float bed = fract(dl * 0.83 + n_big * 0.5);
		float bed_line = 1.0 - smoothstep(0.0, 0.035, bed) * (1.0 - smoothstep(0.955, 1.0, bed));
		col *= 1.0 - bed_line * 0.16 * pbr.z * wall;
		col *= 0.94 + 0.12 * grain;
		// a soft dark seam where one stratum meets the next
		col *= mix(0.82, 1.0, smoothstep(0.0, 0.16, layer_edge));
	} else {
		// Ore: a crisp-edged body in the host rock, flecked with its brighter second colour.
		float fleck = smoothstep(0.52, 0.66, d1.x * 0.5 + d2.x * 0.5 + (n_mid - 0.5) * 0.3);
		col = mix(c1, c2, fleck);
		col *= mix(0.55, 1.0, smoothstep(0.0, 0.022, ore_in));   // dark contact line
		metallic = pbr.y;
		rough = mix(pbr.x, pbr.x * 0.6, fleck);
		relief_k *= 1.4;
		if (fx.w > 1.5) {
			// crystalline bodies: small facets that each catch the light at their own angle
			vec3 q = vec3(dot(lp, vec3(0.80, 0.36, -0.48)), dot(lp, vec3(-0.6, 0.48, -0.64)), dot(lp, vec3(0.0, 0.8, 0.6))) * 7.0;
			vec3 cellp = floor(q);
			vec3 tilt = vec3(hash13(cellp), hash13(cellp + 17.3), hash13(cellp + 41.7)) - 0.5;
			facet_tilt = tilt * near_fade;
			col *= 0.9 + 0.25 * hash13(cellp + 5.1);
			relief_k *= 0.3;
		}
	}

	// --- surface skin (grass / moss / dust) on the ORIGINAL surface only
	float turf = turf_depth + (n_mid - 0.5) * 0.2;
	float slope_ok = smoothstep(0.3, 0.5, up_facing);
	// regions with thin cover show bare ground in patches (the cover follows the mottling)
	float patchy = smoothstep(cover_amount - 0.2, cover_amount + 0.2, 1.0 - (n_big * 0.6 + n_mid * 0.4));
	float soil_here = float(fx.w < 0.5 && fx.z < 0.5);     // cover grows on soil, not on rock or ore
	float cover = (1.0 - smoothstep(turf - 0.025, turf + 0.025, depth)) * slope_ok * patchy * mix(0.25, 1.0, soil_here);
	vec3 gcol = mix(grass_a, grass_b, smoothstep(0.38, 0.66, hm.g));
	gcol = mix(gcol, grass_c, smoothstep(0.55, 0.8, hm.b) * 0.8);
	vec3 rg = mix(rgrass_a, rgrass_b, smoothstep(0.38, 0.66, hm.g));
	gcol = mix(gcol, rg, rgrass_w);
	gcol *= 0.9 + 0.2 * n_big;
	gcol *= 0.93 + 0.14 * grain;
	gcol = mix(gcol, gcol * vec3(1.06, 1.14, 0.98) + vec3(0.004, 0.012, 0.0), bloom_amount);
	// darker, damp band just under the skin so a fresh cut has a clean readable rim
	float lip = (1.0 - smoothstep(turf + 0.02, turf + 0.34, depth)) * (1.0 - cover) * step(0.0, depth);
	col *= mix(1.0, 0.66, lip);
	col = mix(col, gcol, cover);
	rough = mix(rough, cover_roughness, cover);
	metallic *= 1.0 - cover;
	relief_k = mix(relief_k, cover_relief, cover);

	// --- fine relief: perturb the normal with the gradient of the grain noise
	vec3 tangent_grad = relief - world_n * dot(relief, world_n);
	vec3 n2 = normalize(world_n - tangent_grad * 0.028 * relief_k * near_fade + facet_tilt * 0.9 * (1.0 - cover));
	NORMAL = normalize((VIEW_MATRIX * vec4(n2, 0.0)).xyz);

	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metallic;
	SPECULAR = 0.4;

	// --- occlusion: excavations and caves get darker with depth (ambient only), so holes read
	// as holes; a touch of that also affects direct light to ground the rim.
	float pit = smoothstep(0.15, 5.5, depth);
	AO = mix(1.0, 0.55, pit) * (0.9 + 0.1 * grain);
	AO_LIGHT_AFFECT = 0.08;

	// --- restrained glow: only materials that are authored to emit, plus tight glints on ore
	vec3 emission = c2 * fx.x * (0.55 + 0.45 * n_big);
	if (fx.y > 0.0 && is_ore) {
		vec3 vdir = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
		float glint = texture(noise_a, lp * 2.3 + vdir * 2.0).r;
		glint = smoothstep(0.84, 0.9, glint) * fx.y * near_fade;
		emission += c2 * glint * 0.55;
	}

	// --- scanner pulse: a thin ring travels through the rock; ore answers as it passes
	if (scan_radius >= 0.0) {
		float sd = distance(lp, scan_origin);
		float ring = 1.0 - smoothstep(0.0, 0.5, abs(sd - scan_radius));
		float wake = smoothstep(scan_radius - 12.0, scan_radius, sd) * step(sd, scan_radius);
		emission += rim_color * ring * 0.9 * scan_strength;
		if (is_ore) { emission += mix(c2, rim_color, 0.25) * wake * 1.6 * scan_strength; }
	}
	EMISSION = emission;
}

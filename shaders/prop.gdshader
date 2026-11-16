shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Vertex-coloured props, tools, machines and structures. Built by MeshKit:
//   COLOR.rgb = albedo (sRGB, as authored in Pal)
//   UV.x  = emission amount      UV.y  = sway weight (0 = rigid)
//   UV2.x = roughness            UV2.y = metallic
// Lighting is plain physically based shading - no ramps, no outlines, no rim glow - so machines
// read as clean painted metal and the scene's sun/sky do the work (docs/ART_DIRECTION.md).

uniform float sway_amount = 0.0;
uniform float emission_scale = 1.0;
uniform vec3 tint : source_color = vec3(1.0);
uniform bool viewmodel = false;       // first-person tools: squash depth so they never clip into terrain
uniform float viewmodel_fov = 0.0;    // > 0: draw with this fixed vertical FOV (degrees) regardless of camera FOV
uniform float flash = 0.0;            // 0..1 brief highlight (purchase / hit feedback)
uniform float fade = 1.0;             // < 1 dithers the mesh out (used for spawn/despawn)

varying float v_emis;
varying vec2 v_pbr;
varying vec3 v_albedo;

vec3 srgb_to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void vertex() {
	v_emis = UV.x;
	v_pbr = UV2;
	v_albedo = srgb_to_linear(COLOR.rgb);
	if (sway_amount > 0.0) {
		vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		float ph = wp.x * 0.7 + wp.y * 0.9 + wp.z * 0.8;
		vec3 off = vec3(sin(TIME * 1.1 + ph), 0.0, cos(TIME * 0.9 + ph * 1.3)) * UV.y * sway_amount;
		VERTEX += off;
	}
	// POSITION must be written on every path: once a shader touches it, Godot stops doing the
	// default projection.
	POSITION = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	if (viewmodel) {
		if (viewmodel_fov > 0.0) {
			// Re-project with a fixed field of view so the tool looks the same at any FOV setting.
			float k = 1.0 / (abs(PROJECTION_MATRIX[1][1]) * tan(radians(viewmodel_fov) * 0.5));
			POSITION.xy *= k;
		}
		POSITION.z = mix(POSITION.z, POSITION.w, 0.92);   // reversed-Z: pull towards the near plane
	}
}

void fragment() {
	if (fade < 1.0) {
		// ordered dither, stable in screen space
		float d = fract(dot(floor(FRAGCOORD.xy), vec2(0.7548776662, 0.5698402910)));
		if (d > fade) { discard; }
	}
	vec3 col = v_albedo * tint;
	col = mix(col, vec3(1.0), flash * 0.55);
	ALBEDO = col;
	ROUGHNESS = clamp(v_pbr.x, 0.04, 1.0);
	METALLIC = clamp(v_pbr.y, 0.0, 1.0);
	SPECULAR = 0.5;
	EMISSION = col * v_emis * emission_scale + vec3(flash * 0.25);
}

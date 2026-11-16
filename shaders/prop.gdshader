shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_schlick_ggx;

// Vertex-coloured chunky props, tools and machines. Built by MeshKit:
//   COLOR.rgb = albedo, UV.x = emission amount, UV.y = sway weight (0 = rigid).

#include "res://shaders/toon_light.gdshaderinc"

uniform float sway_amount = 0.0;
uniform float emission_scale = 1.0;
uniform float roughness = 0.75;
uniform float rim_strength = 0.1;
uniform vec3 tint : source_color = vec3(1.0);
uniform bool viewmodel = false;      // first-person tools: squash depth so they never clip into terrain
uniform float flash = 0.0;           // 0..1 white flash (purchase / hit feedback)

varying float v_emis;

void vertex() {
	v_emis = UV.x;
	if (sway_amount > 0.0) {
		vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		float ph = wp.x * 0.7 + wp.y * 0.9 + wp.z * 0.8;
		vec3 off = vec3(sin(TIME * 1.6 + ph), 0.0, cos(TIME * 1.3 + ph * 1.3)) * UV.y * sway_amount;
		VERTEX += off;
	}
	// POSITION must be written on every path: once a shader touches it, Godot stops doing the
	// default projection.
	POSITION = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	if (viewmodel) {
		POSITION.z = mix(POSITION.z, POSITION.w, 0.92);   // reversed-Z: pull towards the near plane
	}
}

void fragment() {
	vec3 col = COLOR.rgb * tint;
	col = mix(col, vec3(1.0), flash);
	ALBEDO = col;
	ROUGHNESS = roughness;
	SPECULAR = 0.0;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = col * v_emis * emission_scale + col * rim * rim_strength + vec3(flash * 0.6);
}

void light() {
	DIFFUSE_LIGHT += toon_diffuse(NORMAL, LIGHT, LIGHT_COLOR, ATTENUATION, vec3(1.0));
	vec3 h = normalize(LIGHT + VIEW);
	float spec = smoothstep(0.55, 0.62, pow(max(dot(NORMAL, h), 0.0), mix(48.0, 8.0, ROUGHNESS)));
	SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * spec * (1.0 - ROUGHNESS) * 0.5;
}

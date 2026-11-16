// Shared soft-banded lighting so terrain, props and tools all read as one chunky toy world.
// Usage: #include "res://shaders/toon_light.gdshaderinc" then call toon_diffuse() from light().

float toon_ramp(float ndl) {
	// Half-lambert pushed through two soft steps: lit, mid, shade.
	float h = ndl * 0.5 + 0.5;
	float a = smoothstep(0.30, 0.42, h);
	float b = smoothstep(0.62, 0.74, h);
	return 0.18 + 0.47 * a + 0.35 * b;
}

vec3 toon_diffuse(vec3 n, vec3 l, vec3 light_color, float attenuation, vec3 albedo) {
	float ramp = toon_ramp(dot(n, l));
	// Shadows are softened so shaded sides stay colourful instead of going black.
	float att = mix(0.25, 1.0, attenuation);
	return albedo * light_color * ramp * att / PI;
}

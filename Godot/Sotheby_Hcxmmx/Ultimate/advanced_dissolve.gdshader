shader_type canvas_item;
// blend_add is replaced by the original material's alpha mode where needed.
render_mode blend_add, unshaded;

uniform sampler2D main_map : repeat_enable, filter_linear;
uniform sampler2D noise_map : repeat_enable, filter_linear;
uniform sampler2D mask_map : repeat_enable, filter_linear;
uniform bool has_noise = false;
uniform bool has_mask = false;
uniform vec4 main_st = vec4(1.0,1.0,0.0,0.0);
uniform vec4 noise_st = vec4(1.0,1.0,0.0,0.0);
uniform vec4 mask_st = vec4(1.0,1.0,0.0,0.0);
uniform vec4 material_tint = vec4(1.0);
uniform vec4 uv_speed = vec4(0.0);
uniform float smoothness = 1.0;
uniform float effect_time = 0.0;
uniform float gain = 0.8;
uniform bool preview_tonemap = false;
// Reconstruct source UV from the previous seekable bake's transformed UV.
uniform vec2 baked_scroll = vec2(0.0);
uniform bool alpha_from_luminance = false;
varying vec4 particle_tint;
varying vec4 particle_custom;

vec2 image_uv(vec2 unity_uv) { return vec2(unity_uv.x,1.0-unity_uv.y); }

void vertex() {
    particle_tint = COLOR;
    particle_custom = CUSTOM0;
}

void fragment() {
    vec2 base_image = (UV - main_st.zw - baked_scroll) / main_st.xy;
    vec2 base_unity = image_uv(base_image);
    vec2 uv_main = base_unity * main_st.xy + main_st.zw + particle_custom.xy * 0.1;
    vec2 uv_noise = base_unity * noise_st.xy + noise_st.zw + uv_speed.xy * effect_time;
    vec2 uv_mask = base_unity * mask_st.xy + mask_st.zw + uv_speed.zw * effect_time;
    vec4 main_value = texture(main_map,image_uv(uv_main));
    if (alpha_from_luminance) {
        main_value.a *= dot(main_value.rgb,vec3(0.212673,0.715152,0.072175));
    }
    main_value *= material_tint;
    vec4 noise_value = has_noise ? texture(noise_map,image_uv(uv_noise)) : vec4(1.0);
    vec2 noise_ra = (noise_value.ra - vec2(0.5)) * smoothness + vec2(0.5);
    // Direct translation of original dissolve_particle fragment blob 50/51.
    float cut = clamp(noise_ra.x * noise_ra.y + main_value.a - particle_custom.w,0.0,1.0);
    main_value.a = min(main_value.a,cut);
    vec4 mask_value = has_mask ? texture(mask_map,image_uv(uv_mask)) : vec4(1.0);
    vec4 output_value = main_value * particle_tint * mask_value.r * mask_value.a;
    vec3 light = output_value.rgb * gain;
    if (preview_tonemap) {
        // Hue-preserving adaptation for the LDR preview; not official grading.
        light /= 1.0 + max(light.r,max(light.g,light.b));
    }
    COLOR = vec4(light,clamp(output_value.a,0.0,1.0));
}

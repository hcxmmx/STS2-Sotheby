shader_type canvas_item;
render_mode blend_add, unshaded;
uniform sampler2D mask_map : repeat_enable, filter_linear;
uniform vec4 main_st = vec4(1.0,1.0,0.0,0.0);
uniform vec2 baked_scroll = vec2(0.0);
uniform float factor = 1.0;
varying float particle_alpha;
void vertex() { particle_alpha = COLOR.a; }
void fragment() {
    // Source postprocess/mask keyword _USEDISTORT_ON, fragment blob 33:
    // Z=W=texture.r * texture.a * factor^2 * particle_alpha^2.
    // Store only the additive contribution in RG; the compositor adds neutral .5.
    vec4 t = texture(mask_map,UV - baked_scroll);
    float contribution = t.r * t.a * factor * factor * particle_alpha * particle_alpha;
    COLOR = vec4(contribution,contribution,0.0,1.0);
}

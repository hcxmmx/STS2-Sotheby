shader_type canvas_item;
render_mode blend_disabled, unshaded;
uniform sampler2D screen_map : hint_screen_texture, repeat_disable, filter_linear;
uniform sampler2D distortion_field : repeat_disable, filter_linear;
uniform float strength_pixels = 7.0;
uniform vec4 stage_rect = vec4(0.0,0.0,1.0,1.0);
void fragment() {
    vec2 field = vec2(0.5) + texture(distortion_field,SCREEN_UV).rg;
    // Original uberpre 83 / uberpost 415 uses this neutral dead band and unpack.
    vec2 active = step(vec2(0.501),field) + step(field,vec2(0.498));
    vec2 offset = (field * 2.0 - vec2(1.0)) * active;
    vec2 border_distance = min(SCREEN_UV-stage_rect.xy,stage_rect.zw-SCREEN_UV) / SCREEN_PIXEL_SIZE;
    float border_fade = smoothstep(1.0,18.0,min(border_distance.x,border_distance.y));
    vec2 sample_uv = clamp(SCREEN_UV + offset * strength_pixels * SCREEN_PIXEL_SIZE * border_fade,
                           stage_rect.xy + SCREEN_PIXEL_SIZE,stage_rect.zw - SCREEN_PIXEL_SIZE);
    COLOR = texture(screen_map,sample_uv);
}

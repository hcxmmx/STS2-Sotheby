shader_type canvas_item;
render_mode blend_add, unshaded;
varying float opacity;
void vertex() { opacity = COLOR.a; }
float liquid_at(sampler2D source_map, vec2 uv) {
    vec4 c = texture(source_map, uv);
    return smoothstep(0.045,0.24,c.g-c.b)
         * smoothstep(-0.02,0.16,c.g-c.r)
         * smoothstep(0.39,0.44,uv.y) * c.a;
}
void fragment() {
    vec2 d = TEXTURE_PIXEL_SIZE * 2.0;
    float mask = liquid_at(TEXTURE,UV) * 0.30;
    mask += (liquid_at(TEXTURE,UV+vec2(d.x,0.0))+liquid_at(TEXTURE,UV-vec2(d.x,0.0))
           +liquid_at(TEXTURE,UV+vec2(0.0,d.y))+liquid_at(TEXTURE,UV-vec2(0.0,d.y))) * 0.12;
    mask += (liquid_at(TEXTURE,UV+d)+liquid_at(TEXTURE,UV-d)
           +liquid_at(TEXTURE,UV+vec2(d.x,-d.y))+liquid_at(TEXTURE,UV+vec2(-d.x,d.y))) * 0.055;
    COLOR = vec4(0.72,1.0,0.12,mask * opacity * 0.32);
}

shader_type canvas_item;
render_mode blend_add, unshaded;
varying float opacity;
void vertex() { opacity = COLOR.a; }
void fragment() {
    vec4 noise = texture(TEXTURE,vec2(UV.x,UV.y));
    float cross_section = max(0.0,1.0-abs(UV.y*2.0-1.0));
    float core = pow(cross_section,3.0);
    float ribbon = max(noise.r*noise.a*cross_section,core*0.92) + cross_section*0.10;
    vec3 color = mix(vec3(0.25,0.94,0.08),vec3(0.92,1.0,0.43),core);
    COLOR = vec4(color,ribbon*opacity*0.88);
}

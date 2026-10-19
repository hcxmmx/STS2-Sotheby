shader_type canvas_item;
render_mode blend_add, unshaded;
uniform float emission_cutoff=10000.0;
uniform float glow_strength=0.85;
varying float born;
varying float opacity;

vec4 potion_light(sampler2D source_map,vec2 uv,vec2 low,vec2 high){
    vec4 t=texture(source_map,clamp(uv,low,high));
    float hi=max(t.r,max(t.g,t.b));
    float lo=min(t.r,min(t.g,t.b));
    float colored=smoothstep(0.055,0.27,hi-lo);
    float mask=colored*smoothstep(0.12,0.45,hi)*t.a;
    return vec4(t.rgb/max(hi,0.001),mask);
}

void vertex(){born=CUSTOM1.x;opacity=COLOR.a;}
void fragment(){
    if(born>emission_cutoff+0.0001)discard;
    vec2 low=floor(UV*3.0)/3.0+TEXTURE_PIXEL_SIZE;
    vec2 high=low+vec2(1.0/3.0)-TEXTURE_PIXEL_SIZE*2.0;
    vec4 core=potion_light(TEXTURE,UV,low,high);
    vec3 light=core.rgb*core.a*0.22;
    for(int ring=1;ring<=2;ring++){
        vec2 d=TEXTURE_PIXEL_SIZE*float(ring)*4.0;
        vec4 a=potion_light(TEXTURE,UV+vec2(d.x,0.0),low,high);
        vec4 b=potion_light(TEXTURE,UV-vec2(d.x,0.0),low,high);
        vec4 c=potion_light(TEXTURE,UV+vec2(0.0,d.y),low,high);
        vec4 e=potion_light(TEXTURE,UV-vec2(0.0,d.y),low,high);
        light+=(a.rgb*a.a+b.rgb*b.a+c.rgb*c.a+e.rgb*e.a)*(ring==1?0.11:0.045);
    }
    COLOR=vec4(light*glow_strength,opacity);
}

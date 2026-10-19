shader_type canvas_item;
render_mode blend_disabled, unshaded;
uniform sampler2D screen_map : hint_screen_texture, repeat_disable, filter_linear;
uniform sampler2D distortion_field : repeat_disable, filter_linear;
uniform vec4 stage_rect=vec4(0.0,0.0,1.0,1.0);
uniform vec2 burst_center=vec2(0.62,0.55);
uniform float radial_blur=0.0;
uniform float split_pixels=0.0;
uniform float flash=0.0;
uniform float distort_pixels=7.0;
uniform float dissolve_flash=0.0;

void fragment(){
    vec2 border=min(SCREEN_UV-stage_rect.xy,stage_rect.zw-SCREEN_UV)/SCREEN_PIXEL_SIZE;
    float edge=smoothstep(1.0,20.0,min(border.x,border.y));
    vec2 field=vec2(0.5)+texture(distortion_field,SCREEN_UV).rg;
    vec2 active=step(vec2(0.501),field)+step(field,vec2(0.498));
    vec2 offset=(field*2.0-vec2(1.0))*active*distort_pixels*SCREEN_PIXEL_SIZE*edge;
    vec2 uv=clamp(SCREEN_UV+offset,stage_rect.xy+SCREEN_PIXEL_SIZE,stage_rect.zw-SCREEN_PIXEL_SIZE);
    vec2 radial=(uv-burst_center)*radial_blur*0.015*edge;
    vec3 sum=vec3(0.0);
    for(int i=0;i<7;i++){
        vec2 tap=clamp(uv-radial*float(i)/6.0,stage_rect.xy+SCREEN_PIXEL_SIZE,stage_rect.zw-SCREEN_PIXEL_SIZE);
        vec2 split=vec2(split_pixels*SCREEN_PIXEL_SIZE.x*edge,0.0);
        sum+=vec3(texture(screen_map,tap+split).r,texture(screen_map,tap).g,texture(screen_map,tap-split).b);
    }
    vec3 light=sum/7.0;
    float luma=dot(light,vec3(0.2126,0.7152,0.0722));
    float cut=smoothstep(0.12,0.8,luma)*dissolve_flash;
    light=mix(light,vec3(0.88,1.0,0.62),cut*0.22*edge);
    light=mix(light,vec3(0.94,1.0,0.79),flash*edge);
    COLOR=vec4(light,1.0);
}

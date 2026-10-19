shader_type canvas_item;
// The source is a grayscale mask, rather than an opaque background picture.
void fragment() {
	float coverage = texture(TEXTURE, UV).r;
	COLOR = vec4(COLOR.rgb, COLOR.a * coverage);
}

export default `

uniform sampler2D map;
uniform sampler2D matcap;
uniform float fresnelBias;
uniform float fresnelScale;
uniform float fresnelPower;
uniform float uFresnelIntensity;
uniform vec3 uFresnelColor;
uniform vec2 uFresnelPosRange;
uniform float uSpecularIntensity;

varying vec3 vViewPosition;
varying vec2 vUv;
varying vec3 vNormal;
varying vec3 vLocalPosition;

//http://gamedev.stackexchange.com/questions/59797/glsl-shader-change-hue-saturation-brightness
vec3 rgb2hsv(vec3 c)
{
    vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
    vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));

    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c)
{
    vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}


void main() {
	vec4 diffuseColor = vec4(1.0);
	vec4 sampledDiffuseColor = texture2D( map, vUv );
	diffuseColor *= sampledDiffuseColor;

	vec3 normal = normalize( vNormal );
	float light = dot(normal, vec3(1, 1, -1)) * 0.5 + 0.5;
	float specular_1 = dot(normal, normalize(vec3(0.5, 1, 1))) * 0.5 + 0.5;
	specular_1 = smoothstep(0.95, 1.0, specular_1);

	float specular_2 = dot(normal, normalize(vec3(-0.5, -1, 1))) * 0.5 + 0.5;
	specular_2 = smoothstep(0.95, 1.0, specular_1);

	float specular = max(specular_1, specular_2) * uSpecularIntensity;




	vec3 viewDir = normalize( vViewPosition );
	vec3 x = normalize( vec3( viewDir.z, 0.0, - viewDir.x ) );
	vec3 y = cross( viewDir, x );
	vec2 uv = vec2( dot( x, normal ), dot( y, normal ) ) * 0.495 + 0.5;

	vec4 matcapColor = texture2D( matcap, uv );
	matcapColor = linearToOutputTexel(matcapColor);

	vec3 outgoingLight = diffuseColor.rgb;

	float fp = fresnelPower;

	float fresnel = fresnelBias + fresnelScale * pow(1.0 - dot(normalize(vNormal), vec3(0.0, 0.0, 1.0)), fp);

	// #if GLASS == 1
	//   fresnel = dot(normal, normalize(vec3(0.0, 2, 1))) * 0.5 + 0.5;
	// 	fresnel = smoothstep(0.6, 0.85, fresnel);
	// #endif
	float gradientPos = smoothstep(uFresnelPosRange.x, uFresnelPosRange.y, vLocalPosition.y); // Gradient based on y-position
	vec4 fresnelColor = vec4(uFresnelColor, 1.0);

	gl_FragColor = vec4( outgoingLight, diffuseColor.a );
	gl_FragColor = linearToOutputTexel( gl_FragColor );
	gl_FragColor = mix(gl_FragColor, fresnelColor, uFresnelIntensity * fresnel * gradientPos);


	float glowIntensity = length(vec3(0.0, -1.0, 0.0) - vLocalPosition);
	glowIntensity = smoothstep(0.5, 0.0, glowIntensity);

	vec3 hsv = rgb2hsv(gl_FragColor.rgb);
	hsv.r -= glowIntensity * 0.05;
	hsv.g += 0.1 - specular * 0.2;
	hsv.b += mix(-0.2, 0.1, matcapColor.g) + specular * 0.1;
	hsv.b = clamp(hsv.b, 0.0, 1.0);
	gl_FragColor.rgb = hsv2rgb(hsv);
	gl_FragColor.rgb += glowIntensity * 0.2 + light * 0.1 * uFresnelIntensity;



	gl_FragColor.rgb = pow(gl_FragColor.rgb, vec3(0.9));

	// debug
	// gl_FragColor.rgb = matcapColor.ggg;
}
`

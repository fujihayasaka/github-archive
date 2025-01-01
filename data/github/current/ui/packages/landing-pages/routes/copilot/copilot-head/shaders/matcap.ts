export default `
#define MATCAP
uniform vec3 diffuse;
uniform float opacity;
uniform sampler2D matcap;
uniform float fresnelBias;
uniform float fresnelScale;
uniform float fresnelPower;
uniform float uFresnelIntensity;

varying vec3 vViewPosition;
#include <common>
#include <dithering_pars_fragment>
#include <color_pars_fragment>
#include <uv_pars_fragment>
#include <map_pars_fragment>
#include <alphamap_pars_fragment>
#include <alphatest_pars_fragment>
#include <fog_pars_fragment>
#include <normal_pars_fragment>
#include <bumpmap_pars_fragment>
#include <normalmap_pars_fragment>
#include <logdepthbuf_pars_fragment>
#include <clipping_planes_pars_fragment>
void main() {
	#include <clipping_planes_fragment>
	vec4 diffuseColor = vec4( diffuse, opacity );
	#include <logdepthbuf_fragment>
	#include <map_fragment>
	#include <color_fragment>
	#include <alphamap_fragment>
	#include <alphatest_fragment>
	#include <normal_fragment_begin>
	#include <normal_fragment_maps>
	vec3 viewDir = normalize( vViewPosition );
	vec3 x = normalize( vec3( viewDir.z, 0.0, - viewDir.x ) );
	vec3 y = cross( viewDir, x );
	vec2 uv = vec2( dot( x, normal ), dot( y, normal ) ) * 0.495 + 0.5;
	#ifdef USE_MATCAP
		vec4 matcapColor = texture2D( matcap, uv );
	#else
		vec4 matcapColor = vec4( vec3( mix( 0.2, 0.8, uv.y ) ), 1.0 );
	#endif
	vec3 outgoingLight = diffuseColor.rgb * matcapColor.rgb;
    float fresnel = fresnelBias + fresnelScale * pow(1.0 - dot(normalize(vNormal), vec3(0.0, 0.0, 1.0)), fresnelPower);
    float gradient = smoothstep(-0.0, 0.5, vNormal.y);
    float gradientPos = smoothstep(0.5, -1.0, vViewPosition.y); // Gradient based on y-position
    vec4 accentGreen = vec4(0.0, 0.4, 0.015, 1.0); // #00FF46
    vec4 fresnelColor = vec4(vec3(0.0, fresnel * gradient, fresnel * gradient * 0.275), fresnel*gradient);
    fresnelColor *= gradientPos;
	#include <output_fragment>
    gl_FragColor = mix(gl_FragColor, accentGreen, fresnelColor.a * uFresnelIntensity);

	#include <tonemapping_fragment>
	#include <encodings_fragment>
	#include <fog_fragment>
	#include <premultiplied_alpha_fragment>
	#include <dithering_fragment>
}
`

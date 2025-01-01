export default `
uniform sampler2D uMatcapTex;
uniform sampler2D uAo;
uniform sampler2D uDiffuse;

varying vec3 vWorldPosition;
varying vec3 vMVPosition;
varying vec2 vUv;
varying vec3 vNormal;

vec3 blendSoftLight(vec3 base, vec3 blend) {
    return mix(
        sqrt(base) * (2.0 * blend - 1.0) + 2.0 * base * (1.0 - blend),
        2.0 * base * blend + base * base * (1.0 - 2.0 * blend),
        step(base, vec3(0.5))
    );
}

float fresnelEffect(vec3 Normal, vec3 ViewDir, float Power)
{
    return pow((1.0 - clamp(dot(normalize(Normal), normalize(ViewDir)), 0.0, 1.0)), Power);
}

void main(){
  vec3 matcap = texture2D(uMatcapTex, vUv).rgb;
  vec3 ao = texture2D(uAo, vUv).rgb;
  vec3 diffuse = texture2D(uDiffuse, vUv).rgb;

  vec3 color = diffuse * ao;

  float noise = snoise3D(vWorldPosition * 3.0 + 1.0) * 0.5 + 0.5;

  float fresnel = fresnelEffect(vNormal, vec3(0.0, 0.0, 1.0), 0.3);

  vec3 hsv = rgb2hsv(color);
  hsv.r += mix(-0.12, 0.0, smoothstep(0.0, 0.6, noise));
  color = hsv2rgb(hsv);

  color = mix(color, color + 0.5, fresnel);

  gl_FragColor = vec4(color, 1.0);
}
`

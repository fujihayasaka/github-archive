export default `
uniform sampler2D u_ao;
uniform sampler2D u_colorTex;
uniform sampler2D u_matcapTex;
uniform vec3 uScrollProgress;
uniform float uSpecularFactor;

uniform vec3 u_color;
uniform float u_time;
uniform vec2 u_noiseRange;
uniform vec2 u_fogRangeZ;
uniform vec2 u_resolution;
uniform vec3 u_lightPos;
uniform vec4 uProgress;
uniform vec3 uBgColor;

varying vec3 vWorldPosition;
varying vec3 vMVPosition;

varying vec2 vUv;
varying vec3 vNormal;

#define PI 3.1415926535897932384626433832795

mat2 rotate2D (float r){
  float s = sin(r);
  float c = cos(r);
  return mat2(c, s, -s, c);
}

vec3 blendSoftLight(vec3 base, vec3 blend) {
    return mix(
        sqrt(base) * (2.0 * blend - 1.0) + 2.0 * base * (1.0 - blend),
        2.0 * base * blend + base * base * (1.0 - 2.0 * blend),
        step(base, vec3(0.5))
    );
}

void main(){
  vec2 screenST = gl_FragCoord.xy / u_resolution.xy;

  vec2 matcapUv = (vNormal.xy + 1.0) / 2.0;

  matcapUv -= 0.5;
  matcapUv = rotate2D(0.8) * matcapUv + 0.5;
  vec3 matcap = texture2D(u_matcapTex, matcapUv).rgb;

  vec3 hsv = rgb2hsv(matcap);
  hsv.g -= 0.2;
  matcap = hsv2rgb(hsv);

  vec3 color = mix(uBgColor, matcap, uProgress.x);
  gl_FragColor = vec4(color, 1.0);
}
`

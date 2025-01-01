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
uniform vec3 uBgColor;
uniform vec4 uProgress;

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

  vec3 r = vNormal;
  float m = 2.8284271247461903 * sqrt( r.z+1.0 );
  vec2 matcapUv = r.xy / m + .5;

  matcapUv -= 0.5;
  matcapUv = rotate2D(0.0) * matcapUv + 0.5;

  vec2 matcapUv2 = r.xy / m + .5;
  matcapUv2 -= 0.5;
  matcapUv2 = rotate2D(PI) * matcapUv2 + 0.5;

  vec3 matcap = texture2D(u_matcapTex, matcapUv).rgb;
  vec3 matcap2 = texture2D(u_matcapTex, matcapUv2).rgb;
  float matcap_highlight = smoothstep(0.2, 1.0, matcap2.g) * 0.7;

  vec3 ao3 = texture2D(u_ao, vUv).rgb;
  float ao = ao3.r;

  vec3 normal = normalize(vNormal);

  float lightIntensity = max(0.0, dot(normalize(normal), normalize(u_lightPos)));
  float specular = pow(lightIntensity, 12.0) * uSpecularFactor;

  // ao = ao * lightIntensity;

  vec3 color = u_color;

  float gray = (color.r + color.g + color.b) * 0.333;


  #ifdef USE_COLORTEX
    color = texture2D(u_colorTex, vUv).rgb;
  #endif


  color = blendSoftLight(color, ao3 * ao3 );

  vec3 color_ao = rgb2hsv(color);

  #if MASCOT_TYPE == 0
    float noise = snoise3D(vWorldPosition * 1.0 + vec3(0, 0, 2.85)) * 0.5 + 0.5;
  //   matcap_highlight *= 0.8;

    color_ao.r += mix(-0.15, 0.15, noise) + mix(-0.15, 0.0, ao3.g);
    color_ao.g += mix(0.0, -0.3, matcap.g);
    color_ao.b += mix(-0.2, 0.7, matcap.g);
  #endif

  #if MASCOT_TYPE == 1
    float noise = snoise3D(vWorldPosition * 1.5 + vec3(0.0, -0.15, 0.0)) * 0.5 + 0.5;
    noise = smoothstep(0.1, 0.6, noise);
    noise = mix(noise, lightIntensity * noise, noise);
    color_ao.r += mix(-0.01, 0.07, noise) + mix(-0.05, 0.05, ao3.g);
    color_ao.g += mix(0.0, -0.3, matcap.g) + mix(0.0, 0.1, noise);
    color_ao.b += mix(-0.4, 0.7, matcap.g) + mix(-0.1, 0.2, ao3.g);
  #endif

  #if MASCOT_TYPE == 2
    float noise = snoise3D(vWorldPosition * 1.7 + vec3(0.0, 0.0, 1.7)) * 0.5 + 0.5;
    color_ao.r += mix(-0.1, 0.02, noise);
    color_ao.g += mix(0.0, 0.3, matcap.g) + mix(-0.1, 0.15, noise);
    color_ao.b += mix(0.1, 0.8, matcap.g);
  #endif

  color_ao = hsv2rgb(color_ao);

  color_ao = clamp(color_ao, vec3(0.0), vec3(1.0));
  color_ao = mix(pow(color_ao, vec3(1.4)), color_ao, smoothstep(0.0, 0.1, gray));
  color = color_ao + matcap_highlight + specular;

  color = clamp(vec3(0.0), vec3(1.0), color);

  color = mix(uBgColor, color, uProgress.x);
  gl_FragColor = vec4(color, 1.0);
}
`

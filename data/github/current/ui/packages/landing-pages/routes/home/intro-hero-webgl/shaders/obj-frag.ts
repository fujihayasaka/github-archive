export default `
uniform sampler2D uAo;
uniform sampler2D uColorTex;
uniform sampler2D uMatcapTex;

uniform vec3 uLightColor1;
uniform vec3 uLightColor2;

uniform vec3 uColor;
uniform float uTime;
uniform vec2 uResolution;
uniform vec3 uLightPos;
uniform vec3 uLightPos2;
uniform vec3 uProgress;

uniform sampler2D uDiffuse_star;
uniform sampler2D uDiffuse_blue;
uniform sampler2D uDiffuse_bg;

varying vec3 vWorldPosition;
varying vec3 vMVPosition;

varying vec2 vUv;
varying vec3 vNormal;
varying vec2 vN;

// vec3 LIGHTPOS = vec3(1.0, 1.0, -0.4);
// vec3 LIGHTPOS2 = vec3(-1.0, -1.0, -3.0);
// vec3 LIGHTPOS3 = vec3(-1.0, -1.0, -0.2);


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

  vec2 screenST = gl_FragCoord.xy / uResolution.xy;

  vec3 bg = texture2D(uDiffuse_star, screenST).rgb;

  float matcapAngle = 1.5;

  #if MASCOT_TYPE == 0
  matcapAngle = 1.0;
  #endif


  vec2 matcapUv = vN - 0.5;
  matcapUv = rotate2D(matcapAngle) * matcapUv + 0.5;

  vec3 matcap = texture2D(uMatcapTex, matcapUv).rgb;
  float matcap_highlight = smoothstep(0.3, 0.9, matcap.g);

  vec3 ao3 = texture2D(uAo, vUv).rgb;
  float ao = ao3.r;

  vec3 normal = normalize(vNormal + ao3 * 0.8);


  float lightIntensity = dot(normalize(normal), normalize(uLightPos)) * 0.5 + 0.5;

  lightIntensity = pow(lightIntensity, 12.0) * 0.5;

  vec3 color = uColor;


  #ifdef USE_COLORTEX
    color = texture2D(uColorTex, vUv).rgb;
  #endif

  vec3 lightColor = mix(uLightColor1, uLightColor2, lightIntensity);

  color = blendSoftLight(color, ao3);


  vec3 color_ao = rgb2hsv(color);

  #if MASCOT_TYPE == 0
    float noise = snoise3D(vWorldPosition * 0.8 + vec3(0.0, 0.0, 1.2)) * 0.5 + 0.5;
    matcap_highlight *= 0.8;

    color_ao.r += mix(-0.2, 0.1, noise);
    color_ao.g += mix(0.0, 0.3, matcap.g) + 0.1;
    color_ao.b += mix(-0.5, 0.7, matcap.g) + mix(0.0, 0.5, noise);
  #endif

  #if MASCOT_TYPE == 1
    float noise = snoise3D(vWorldPosition * 1.6 + 0.5) * 0.5 + 0.5;

    color_ao.r += mix(-0.1, 0.05, noise);
    color_ao.g += mix(0.0, 0.3, matcap.g) + 0.05;
    color_ao.b += mix(-0.5, 0.6, matcap.g) + mix(-0.3, 0.5, noise) + 0.1;
  #endif

  #if MASCOT_TYPE == 2
    matcap_highlight *= 0.0;
    float noise = snoise3D(vWorldPosition * 1.6 + 0.5) * 0.5 + 0.5;

    color_ao.r += mix(-0.1, 0.05, noise);
    color_ao.g += mix(0.0, 0.3, matcap.g) + 0.05;
    color_ao.b += mix(-0.2, 0.6, matcap.g) + mix(-0.2, 0.5, noise) + 0.1;
  #endif

  color_ao = hsv2rgb(color_ao);

  color = color_ao + lightIntensity + matcap_highlight * 0.7;

  color = clamp(vec3(0.0), vec3(1.0), color);

  float alpha = 1.0;

  color = pow(color, vec3(max(0.8, alpha)));

  gl_FragColor = vec4(color, alpha);
}
`

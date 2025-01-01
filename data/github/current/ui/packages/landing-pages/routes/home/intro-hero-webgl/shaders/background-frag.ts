export default `
uniform vec3 uColor1;
uniform vec3 uColor2;
uniform float uTime;

uniform vec2 uResolution;
uniform vec4 uProgress;
uniform float uIsFullWidth;
uniform float uCtaAnimTime;
uniform float uCtaProgress;

varying vec2 vUv;

const float PI = 3.14159265359;

float pointToLineDistance(float a, float b, float x1, float y1) {
    return abs(a * x1 - y1 + b) / sqrt(a * a + 1.0);
}

float fbm(float x, float y, float t) {
  float amplitude = 1.;
  float frequency = 1.;
  y = sin(x * frequency);
  y += sin(x*frequency*2.1 + t) * 4.5;
  y += sin(x*frequency*1.72 + t * 1.121) * 4.0;
  y += sin(x*frequency*2.221 + t * 0.437) * 5.0;
  y += sin(x*frequency*3.1122+ t * 4.269) * 2.5;
  y *= amplitude* 0.06;
  return y;
}

void main(){
  vec2 st = gl_FragCoord.xy / uResolution;
  st -= 0.5;
  st *= uResolution / uResolution.y;
  st *= 0.8;
  // st += 0.5;
  st.y += 0.47;

  float centerRadiantRadius = length((st + vec2(0.0, 0.0)));
  float bottomLightRadius = length(st + vec2(0.0, 4.0));

  float angle = atan(st.y, st.x);
  float radius = length(st);

  float f1 = fbm(angle * 4.0, angle * 2.0,  uProgress.z * 4.0 + uCtaAnimTime * 0.5) * 0.5 + 0.5;
  radius *= mix(1.1, 1.15, f1);

  float f2 = fbm(angle * 2.0, angle * 2.0, uProgress.z * 4.0 + uCtaAnimTime * 0.5) * 0.5 + 0.5;
  float maxRadius = mix(1.0, 1.4, f2) - (1.0 - uProgress.y);

  float f3 = fbm(angle * 2.0, angle * 2.0, uCtaAnimTime * 0.5) * 0.5 + 0.5;


  float a = mix(1.0, mix(0.8, 1.1, f3), uCtaProgress);
  float b = 0.2;
  float blurRange = 0.2;

  float d_right = pointToLineDistance(a, b, st.x, st.y);
  float light_right = smoothstep(blurRange, 0.0, d_right);
  light_right = mix(1.0, light_right, step(st.y, st.x * a + b));
  float d_left = pointToLineDistance(-a, b, st.x, st.y);
  float light_left = smoothstep(blurRange, 0.0, d_left);
  light_left = mix(1.0, light_left, step(st.y, -st.x * a + b));

  float light = light_right * light_left;
  light = mix(light, 0.0, smoothstep(0.0, maxRadius, radius));

  float gradientFactor = mix(0.0, 0.4, 1.0 - vUv.y);

  vec3 color = mix(uColor1, uColor2, light * light * 1.3);
  color *= mix(1.7, 1.0, smoothstep(0.1, 0.4, radius));
  color += mix(0.2, 0.0, smoothstep(0.1, 0.4, radius));

  color += mix(0.0, 0.07, uCtaProgress);

  float alpha = min(1.0, light * uProgress.x * 1.3 * smoothstep(0.8, 0.3, radius));

  gl_FragColor = vec4(color, alpha);
}
`

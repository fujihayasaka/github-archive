export default `
uniform sampler2D uAlpha;
uniform vec3 uColor1;
uniform vec3 uColor2;
uniform vec3 uProgress;
varying vec2 vUv;

const float PI = 3.14159265359;

mat2 rotate2d(float _angle){
  return mat2(cos(_angle),-sin(_angle),
              sin(_angle),cos(_angle));
}

void main(){
  vec2 st = vUv - 0.5;
  st = rotate2d(uProgress.x) * st;
  float radian = atan(st.y, st.x);
  float alpha = texture2D(uAlpha, vUv).r;
  float alphaFactor1 = smoothstep(0.0, PI * 0.5, radian);
  alphaFactor1 *= smoothstep(PI * 0.7, PI * 0.5, radian);

  float alphaFactor2 = smoothstep(- PI, -PI * 0.5, radian);
  alphaFactor2 *= smoothstep(- PI * 0.3, -PI * 0.5, radian);

  float alphaFactor = min(1.0, alphaFactor1 + alphaFactor2);

  alpha *= mix(mix(0.6, 1.0, uProgress.y), 1.0, alphaFactor);




  alpha *= mix(1.5, 1.6, uProgress.y);
  alpha *= mix(1.0, 0.0, uProgress.z);

  vec3 color = mix(uColor1, uColor2, alpha);

  gl_FragColor = vec4(color, alpha);
}

`

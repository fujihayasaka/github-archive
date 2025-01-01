export default `
uniform sampler2D uMask;
uniform vec4 uProgress;
uniform vec3 uScrollProgress;

varying vec2 vUv;

void main(){
  float mask = texture2D(uMask, vUv).r;
  float alpha = 1.0 - mask;
  alpha *= uProgress.x;
  alpha = mix(alpha, alpha * 0.8, uScrollProgress.x);
  gl_FragColor = vec4(vec3(1.0), alpha);
}
`

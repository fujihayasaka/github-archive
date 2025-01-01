export default `
uniform vec3 uColor;
uniform vec4 uProgress;
varying vec2 vUv;
 float parabola(float x){
  return 4.0 * x * (1.0 - x);
 }

void main(){
  float p = parabola(uProgress.z);

  float l = length(vUv - 0.5);
  float alpha = smoothstep(0.5 * uProgress.x + p * 0.13, 0.0 * uProgress.x + p * 0.13, l);


  vec3 color = uColor;
  vec3 hsv = rgb2hsv(color);
  hsv.r += mix(0.05, 0.0, smoothstep(0.0, 0.2, alpha));
  hsv.g += p * 0.1;
  hsv.b += p * 0.6;
  color = hsv2rgb(hsv);

  alpha *= uProgress.y;

  gl_FragColor = vec4(color, alpha);
}
`

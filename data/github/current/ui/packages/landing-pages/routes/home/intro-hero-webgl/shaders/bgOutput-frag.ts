export default `
uniform sampler2D uDiffuse_star;
uniform sampler2D uDiffuse_blue;
uniform vec3 uScrollProgress;
uniform vec3 uBgColor1;
uniform vec3 uBgColor2;

varying vec2 vUv;


void main(){
vec4 star = texture2D(uDiffuse_star, vUv);
  vec4 blue = texture2D(uDiffuse_blue, vUv);
  // vec4 bg = texture2D(uDiffuse_bg, vUv);
  float gradientFactor = mix(
    mix(0.0, 0.4, 1.0 - vUv.y),
    mix(0.8, 1.17, 1.0 - vUv.y),
    uScrollProgress.y
  );
  vec3 bg = mix(uBgColor1, uBgColor2, gradientFactor);
  vec3 color = mix(blue.rgb + star.rgb, star.rgb, star.a);

  float alpha = min(1.0, star.a + blue.a);
  // color = mix(bg + color, color, alpha);
  gl_FragColor = vec4(color, alpha);
}
`

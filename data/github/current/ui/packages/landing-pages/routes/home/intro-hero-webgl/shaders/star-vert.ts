export default `
uniform float uRadius;
uniform float uTime;
uniform float uOffsetY;
uniform vec4 uProgress;
uniform vec3 uScrollProgress;
uniform float uCtaAnimTime;

attribute vec3 atranslate;
attribute vec3 arandom;

varying vec2 vUv;

const float PI = 3.14159265359;

void main(){
  vUv = uv;
  float scale = mix(0.3, 1.0, arandom.x);
  float speed = mix(0.03, 0.01, arandom.y);

  float angle = atranslate.x + cos(uProgress.y * 5.0 * speed * 3.0 + PI * arandom.z) * 0.1;
  float life = fract(atranslate.y + uProgress.y * 5.0 * speed + uCtaAnimTime * speed);
  float radius = life * uRadius;
  scale *= 1.0 - pow(life * 2.0 - 1.0, 2.0);
  vec3 translate = vec3(cos(angle) * radius, sin(angle) * radius - uOffsetY, 0.0);
  translate *= 1.0 - uScrollProgress.x * 0.08;
  vec3 pos = position * scale + translate;
  gl_Position = projectionMatrix * viewMatrix * modelMatrix * vec4( pos, 1.0 );
}
`

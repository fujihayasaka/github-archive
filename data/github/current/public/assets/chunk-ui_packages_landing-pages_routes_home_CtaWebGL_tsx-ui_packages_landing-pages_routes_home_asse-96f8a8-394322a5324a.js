"use strict";(globalThis.webpackChunk=globalThis.webpackChunk||[]).push([["ui_packages_landing-pages_routes_home_CtaWebGL_tsx-ui_packages_landing-pages_routes_home_asse-96f8a8"],{94729:(e,t,o)=>{o.r(t),o.d(t,{default:()=>es});var a=o(74848),s=o(96540),i=o(8526),r=o(42979),n=o(39437);function c(e,t,o){return t in e?Object.defineProperty(e,t,{value:o,enumerable:!0,configurable:!0,writable:!0}):e[t]=o,e}let l=class Common{init({$wrapper:e,$canvas:t}){this.pixelRatio=Math.min(1.5,window.devicePixelRatio),this.renderer=new n.S3G({antialias:!0,alpha:!0,canvas:t}),this.renderer.outputEncoding=n.tgE,this.$canvas=this.renderer.domElement,e.appendChild(this.$canvas),this.$wrapper=e,this.scene.add(this.camera),this.renderer.setClearColor(this.bgColor,1),this.renderer.setPixelRatio(this.pixelRatio),this.clock=new n.zD7,this.clock.start(),this.resize()}resize(){let e=this.$wrapper?.clientWidth||0,t=this.$wrapper?.clientHeight||0;this.screenSize_old.copy(this.screenSize),this.screenSize.set(e,t),this.fbo_screenSize.set(e*this.pixelRatio,t*this.pixelRatio),this.aspect=e/t,this.camera.aspect=this.aspect,this.camera.updateProjectionMatrix(),this.renderer?.setSize(this.screenSize.x,this.screenSize.y)}getEase(e){return Math.min(1,e*this.delta)}update(){let e=this.clock?.getDelta();e&&(this.delta=e),this.time+=this.delta}constructor(){c(this,"$wrapper",void 0),c(this,"$canvas",void 0),c(this,"screenSize",new n.I9Y),c(this,"screenSize_old",new n.I9Y),c(this,"aspect",1),c(this,"isMobile",!1),c(this,"pixelRatio",1),c(this,"camera",new n.ubm(30,1,.01,50)),c(this,"scene",new n.Z58),c(this,"fbo_screenSize",new n.I9Y),c(this,"time",0),c(this,"delta",0),c(this,"bgColor",new n.Q1f(856343)),c(this,"renderer",void 0),c(this,"clock",void 0),c(this,"controls",void 0)}},u={light_data:{position:new n.Pq0(1,1,1.5)},group_data:{position:new n.Pq0(0,-.05,.1),scale:new n.Pq0(3,3,3),rotation:new n.O9p(0,0,0),order:"ZYX"},textures:{nose:{ao:"cat_nose_ao",color:null,colorVec:new n.Q1f(0),matcap:"matcap_metal",noiseRange:new n.I9Y(-.03,.03),fogRangeZ:new n.I9Y(-1,-.3),specularFactor:.6,blackObj:!0},eye:{ao:"cat_eye_ao",color:null,colorVec:new n.Q1f(0),matcap:"matcap_metal",noiseRange:new n.I9Y(-.03,.03),fogRangeZ:new n.I9Y(-1,-.3),specularFactor:.6,blackObj:!0},face:{ao:"cat_face_ao",color:null,colorVec:new n.Q1f(0xff69c8),matcap:"matcap_mascot",noiseRange:new n.I9Y(-.1,.1),fogRangeZ:new n.I9Y(-1,-.5),specularFactor:.05,blackObj:!1},head:{ao:"cat_head_ao",color:null,colorVec:new n.Q1f(0xf046b2),matcap:"matcap_mascot",noiseRange:new n.I9Y(-.1,.1),fogRangeZ:new n.I9Y(-1,-.5),specularFactor:.3,blackObj:!1},eyeball:{ao:"cat_eyeball_ao",color:null,colorVec:new n.Q1f(0xffa3dd),matcap:"matcap_mascot",noiseRange:new n.I9Y(-.03,.03),fogRangeZ:new n.I9Y(-1,-.3),specularFactor:.3,blackObj:!1}}},m={light_data:{position:new n.Pq0(1,1,1)},group_data:{position:new n.Pq0(.8,-.2,.6),scale:new n.Pq0(4,4,4),rotation:new n.O9p(-.2,-.15,0),order:"XZY"},textures:{body:{ao:"duck_body_ao",color:null,colorVec:new n.Q1f(0xf6b545),matcap:"matcap_mascot",noiseRange:new n.I9Y(-.03,.03),fogRangeZ:new n.I9Y(-1,-.3),specularFactor:.2,blackObj:!1},beak:{ao:"duck_beak_ao",color:null,colorVec:new n.Q1f(0xf6b545),matcap:"matcap_mascot",noiseRange:new n.I9Y(-.03,.03),fogRangeZ:new n.I9Y(-1,-.3),specularFactor:.2,blackObj:!1},eyes:{ao:"duck_eyes_ao",color:null,colorVec:new n.Q1f(0),matcap:"matcap_metal",noiseRange:new n.I9Y(-.03,.03),fogRangeZ:new n.I9Y(-1,-.3),specularFactor:.6,blackObj:!0},eyeballs:{ao:"duck_eyeballs_ao",color:null,colorVec:new n.Q1f(0),matcap:"matcap_metal",noiseRange:new n.I9Y(-.03,.03),fogRangeZ:new n.I9Y(-1,-.3),specularFactor:.6,blackObj:!0}}},p={position:new n.Pq0(1,1,1)},h={position:new n.Pq0(-.8,0,-.3),scale:new n.Pq0(2.8,2.8,2.8),rotation:new n.O9p(-.1,-.3,0),order:"XZY"},v=new n.Q1f(6374374),d={light_data:p,group_data:h,textures:{eyes:{ao:"copilot_eyes_ao",color:null,colorVec:new n.Q1f(1656532),matcap:"matcap_mascot",noiseRange:new n.I9Y(-.03,.03),fogRangeZ:new n.I9Y(-1,-.3),specularFactor:.2,blackObj:!1},face:{ao:"copilot_face_ao",color:null,colorVec:new n.Q1f(163),matcap:"matcap_mascot",noiseRange:new n.I9Y(-.03,.03),fogRangeZ:new n.I9Y(-1,-.3),specularFactor:.3,blackObj:!1},glasses:{ao:"copilot_glasses_ao",color:null,colorVec:new n.Q1f(2034324),matcap:"matcap_mascot",noiseRange:new n.I9Y(-.03,.03),fogRangeZ:new n.I9Y(-1,-.3),specularFactor:.3,blackObj:!1},goggle:{ao:"copilot_goggle_ao",color:null,colorVec:v,matcap:"matcap_mascot",noiseRange:new n.I9Y(-.03,.03),fogRangeZ:new n.I9Y(-1,-.3),specularFactor:.2,blackObj:!1},head:{ao:"copilot_head_ao",color:null,colorVec:v,matcap:"matcap_mascot",noiseRange:new n.I9Y(-.03,.03),fogRangeZ:new n.I9Y(-1,-.3),specularFactor:.4,blackObj:!1},neck:{ao:"copilot_neck_ao",color:null,colorVec:v,matcap:"matcap_mascot",noiseRange:new n.I9Y(-.03,.03),fogRangeZ:new n.I9Y(-1,-.3),specularFactor:0,blackObj:!1},ears:{ao:"copilot_ears_ao",color:null,colorVec:v,matcap:"matcap_mascot",noiseRange:new n.I9Y(-.03,.03),fogRangeZ:new n.I9Y(-1,-.3),specularFactor:.4,blackObj:!1}}},g=`
uniform vec3 u_translate;
varying vec2 vUv;
varying vec3 vNormal;
varying vec3 vWorldPosition;
varying vec3 vMVPosition;

vec3 getPositionFromModelMatrix(mat4 modelMatrix) {
    return vec3(modelMatrix[3][0], modelMatrix[3][1], modelMatrix[3][2]);
}

void main(){
  vUv = uv;
  vNormal = normalize( normalMatrix * normal );

  vec4 worldPosition = modelMatrix * vec4(position, 1.0);

  vWorldPosition = position + u_translate;

  vec4 mvPosition = viewMatrix * worldPosition;
  vMVPosition = mvPosition.xyz;

  vec3 e = normalize( mvPosition.xyz );
  vec3 n = vNormal;

  gl_Position = projectionMatrix * mvPosition;
}
`,f=`
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
`,x=`
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
`,_=`
vec3 hsv2rgb(vec3 c)
{
    vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

vec3 rgb2hsv(vec3 c)
{
    vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
    vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));

    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

// Simplex 2D noise
//
vec3 permute(vec3 x) { return mod(((x*34.0)+1.0)*x, 289.0); }

float snoise2D(vec2 v){
  const vec4 C = vec4(0.211324865405187, 0.366025403784439,
           -0.577350269189626, 0.024390243902439);
  vec2 i  = floor(v + dot(v, C.yy) );
  vec2 x0 = v -   i + dot(i, C.xx);
  vec2 i1;
  i1 = (x0.x > x0.y) ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
  vec4 x12 = x0.xyxy + C.xxzz;
  x12.xy -= i1;
  i = mod(i, 289.0);
  vec3 p = permute( permute( i.y + vec3(0.0, i1.y, 1.0 ))
  + i.x + vec3(0.0, i1.x, 1.0 ));
  vec3 m = max(0.5 - vec3(dot(x0,x0), dot(x12.xy,x12.xy),
    dot(x12.zw,x12.zw)), 0.0);
  m = m*m ;
  m = m*m ;
  vec3 x = 2.0 * fract(p * C.www) - 1.0;
  vec3 h = abs(x) - 0.5;
  vec3 ox = floor(x + 0.5);
  vec3 a0 = x - ox;
  m *= 1.79284291400159 - 0.85373472095314 * ( a0*a0 + h*h );
  vec3 g;
  g.x  = a0.x  * x0.x  + h.x  * x0.y;
  g.yz = a0.yz * x12.xz + h.yz * x12.yw;
  return 130.0 * dot(m, g);
}

//	Simplex 3D Noise
//	by Ian McEwan, Ashima Arts
//
vec4 permute(vec4 x){return mod(((x*34.0)+1.0)*x, 289.0);}
vec4 taylorInvSqrt(vec4 r){return 1.79284291400159 - 0.85373472095314 * r;}

float snoise3D(vec3 v){
  const vec2  C = vec2(1.0/6.0, 1.0/3.0) ;
  const vec4  D = vec4(0.0, 0.5, 1.0, 2.0);

// First corner
  vec3 i  = floor(v + dot(v, C.yyy) );
  vec3 x0 =   v - i + dot(i, C.xxx) ;

// Other corners
  vec3 g = step(x0.yzx, x0.xyz);
  vec3 l = 1.0 - g;
  vec3 i1 = min( g.xyz, l.zxy );
  vec3 i2 = max( g.xyz, l.zxy );

  //  x0 = x0 - 0. + 0.0 * C
  vec3 x1 = x0 - i1 + 1.0 * C.xxx;
  vec3 x2 = x0 - i2 + 2.0 * C.xxx;
  vec3 x3 = x0 - 1. + 3.0 * C.xxx;

// Permutations
  i = mod(i, 289.0 );
  vec4 p = permute( permute( permute(
             i.z + vec4(0.0, i1.z, i2.z, 1.0 ))
           + i.y + vec4(0.0, i1.y, i2.y, 1.0 ))
           + i.x + vec4(0.0, i1.x, i2.x, 1.0 ));

// Gradients
// ( N*N points uniformly over a square, mapped onto an octahedron.)
  float n_ = 1.0/7.0; // N=7
  vec3  ns = n_ * D.wyz - D.xzx;

  vec4 j = p - 49.0 * floor(p * ns.z *ns.z);  //  mod(p,N*N)

  vec4 x_ = floor(j * ns.z);
  vec4 y_ = floor(j - 7.0 * x_ );    // mod(j,N)

  vec4 x = x_ *ns.x + ns.yyyy;
  vec4 y = y_ *ns.x + ns.yyyy;
  vec4 h = 1.0 - abs(x) - abs(y);

  vec4 b0 = vec4( x.xy, y.xy );
  vec4 b1 = vec4( x.zw, y.zw );

  vec4 s0 = floor(b0)*2.0 + 1.0;
  vec4 s1 = floor(b1)*2.0 + 1.0;
  vec4 sh = -step(h, vec4(0.0));

  vec4 a0 = b0.xzyw + s0.xzyw*sh.xxyy ;
  vec4 a1 = b1.xzyw + s1.xzyw*sh.zzww ;

  vec3 p0 = vec3(a0.xy,h.x);
  vec3 p1 = vec3(a0.zw,h.y);
  vec3 p2 = vec3(a1.xy,h.z);
  vec3 p3 = vec3(a1.zw,h.w);

//Normalise gradients
  vec4 norm = taylorInvSqrt(vec4(dot(p0,p0), dot(p1,p1), dot(p2, p2), dot(p3,p3)));
  p0 *= norm.x;
  p1 *= norm.y;
  p2 *= norm.z;
  p3 *= norm.w;

// Mix final noise value
  vec4 m = max(0.6 - vec4(dot(x0,x0), dot(x1,x1), dot(x2,x2), dot(x3,x3)), 0.0);
  m = m * m;
  return 42.0 * dot( m*m, vec4( dot(p0,x0), dot(p1,x1),
                                dot(p2,x2), dot(p3,x3) ) );
}
`,b={linear:e=>e,easeInSine:e=>-1*Math.cos(Math.PI/2*e)+1,easeOutSine:e=>Math.sin(Math.PI/2*e),easeInOutSine:e=>-.5*(Math.cos(Math.PI*e)-1),easeInQuad:e=>e*e,easeOutQuad:e=>e*(2-e),easeInOutQuad:e=>e<.5?2*e*e:-1+(4-2*e)*e,easeInCubic:e=>e*e*e,easeOutCubic(e){let t=e-1;return t*t*t+1},easeInOutCubic:e=>e<.5?4*e*e*e:(e-1)*(2*e-2)*(2*e-2)+1,easeInQuart:e=>e*e*e*e,easeOutQuart(e){let t=e-1;return 1-t*t*t*t},easeInOutQuart(e){let t=e-1;return e<.5?8*e*e*e*e:1-8*t*t*t*t},easeInQuint:e=>e*e*e*e*e,easeOutQuint(e){let t=e-1;return 1+t*t*t*t*t},easeInOutQuint(e){let t=e-1;return e<.5?16*e*e*e*e*e:1+16*t*t*t*t*t},easeInExpo:e=>0===e?0:Math.pow(2,10*(e-1)),easeOutExpo:e=>1===e?1:-Math.pow(2,-10*e)+1,easeInOutExpo(e){if(0===e||1===e)return e;let t=2*e,o=t-1;return t<1?.5*Math.pow(2,10*o):.5*(-Math.pow(2,-10*o)+2)},easeInCirc:e=>-1*(Math.sqrt(1-e/1*e)-1),easeOutCirc(e){let t=e-1;return Math.sqrt(1-t*t)},easeInOutCirc(e){let t=2*e,o=t-2;return t<1?-.5*(Math.sqrt(1-t*t)-1):.5*(Math.sqrt(1-o*o)+1)},easeInBack:(e,t=1.70158)=>e*e*((t+1)*e-t),easeOutBack(e,t=1.70158){let o=e/1-1;return o*o*((t+1)*o+t)+1},easeInOutBack(e,t=1.70158){let o=2*e,a=o-2,s=1.525*t;return o<1?.5*o*o*((s+1)*o-s):.5*(a*a*((s+1)*a+s)+2)},easeInElastic(e,t=.7){if(0===e||1===e)return e;let o=e/1-1,a=1-t;return-(Math.pow(2,10*o)*Math.sin(2*Math.PI*(o-a/(2*Math.PI)*Math.asin(1))/a))},easeOutElastic(e,t=.7){if(0===e||1===e)return e;let o=1-t,a=2*e;return Math.pow(2,-10*a)*Math.sin(2*Math.PI*(a-o/(2*Math.PI)*Math.asin(1))/o)+1},easeInOutElastic(e,t=.65){if(0===e||1===e)return e;let o=1-t,a=2*e,s=a-1,i=o/(2*Math.PI)*Math.asin(1);return a<1?-(Math.pow(2,10*s)*Math.sin(2*Math.PI*(s-i)/o)*.5):Math.pow(2,-10*s)*Math.sin(2*Math.PI*(s-i)/o)*.5+1},easeOutBounce(e){let t=e/1;if(t<1/2.75)return 7.5625*t*t;if(t<2/2.75){let e=t-1.5/2.75;return 7.5625*e*e+.75}if(t<2.5/2.75){let e=t-2.25/2.75;return 7.5625*e*e+.9375}{let e=t-2.625/2.75;return 7.5625*e*e+.984375}},easeInBounce(e){return 1-this.easeOutBounce(1-e)},easeInOutBounce(e){return e<.5?.5*this.easeInBounce(2*e):.5*this.easeOutBounce(2*e-1)+.5}};function w(e,t,o){return t in e?Object.defineProperty(e,t,{value:o,enumerable:!0,configurable:!0,writable:!0}):e[t]=o,e}let y=class Timeline{to(e,t,o,a){return this._to(e,t,o,a),this}_to(e,t,o,a){let s=0;if(void 0===a||isNaN(a)){if(this.animations.length>0){let e=this.animations[this.animations.length-1];e&&(s=e.duration+e.delay)}}else s=a;s+=this.delay;let i={datas:Array.isArray(e)?e:[e],duration:t,easing:o.easing||this.easing,onComplete:o.onComplete,onUpdate:o.onUpdate,values:[],delay:s,properties:o};this.animations.push(i),this.arrangeDatas(i);let r=0;for(let e=0;e<this.animations.length;e++){let t=this.animations[e];if(!t)continue;let o=t.duration+t.delay;r<o&&(r=o,this.lastIndex=e),t.isLast=!1}return this.getProgress(),i}getProgress(){let e=0;for(let t of this.animations)t.duration+t.delay>e&&(e=t.duration+t.delay);e+=this.delay,this.totalDuration=e}setProgress(e){for(let t of this.animations){let{datas:o,values:a,delay:s,duration:i}=t,r=s+i,n=this.calcProgress(0,this.totalDuration,s),c=this.calcProgress(0,this.totalDuration,r),l=this.calcProgress(n,c,e);for(let e=0;e<o.length;e++){let t=o[e];if(t){let o=a[e],s=o?.start[e],i=o?.end[e];o&&(o.current[e]=this.calcLerp(s,i,l),t[o.key]=o.current[e])}}t.onUpdate&&t.onUpdate()}}start(){if(-1===this.lastIndex)return;this.startTime=new Date,this.oldTime=new Date;let e=this.animations[this.lastIndex];e&&(e.isLast=!0),window.addEventListener("visibilitychange",this.onVisiblitychange),this.animate()}arrangeDatas(e){let{properties:t,datas:o,values:a}=e;for(let e in t){let s=0,i=[],r=[],n=[];switch(e){case"easing":case"onComplete":case"onUpdate":break;default:for(let a of o)null!==a&&"object"==typeof a&&(i[s]=a[e],r[s]=a[e],n[s]=t[e],s++);a.push({key:e,start:i,current:r,end:n})}}}calcProgress(e,t,o){return Math.max(0,Math.min(1,(o-e)/(t-e)))}calcLerp(e,t,o){return e+(t-e)*o}constructor(e={}){w(this,"easing",void 0),w(this,"options",void 0),w(this,"onUpdate",void 0),w(this,"onComplete",void 0),w(this,"delay",void 0),w(this,"isFinished",void 0),w(this,"lastIndex",void 0),w(this,"isWindowFocus",void 0),w(this,"animations",void 0),w(this,"startTime",void 0),w(this,"oldTime",void 0),w(this,"time",void 0),w(this,"totalDuration",0),w(this,"totalProgress",0),w(this,"animate",()=>{let e=new Date;if(this.isWindowFocus||(this.oldTime=e),this.oldTime){let t=e.getTime()-this.oldTime.getTime();this.time+=t}for(let t of(this.oldTime=e,this.animations)){let{datas:e,duration:o,easing:a,values:s,delay:i}=t;if(this.time>i&&!t.isFinished){let r=this.calcProgress(0,o,this.time-i);r=b[a](r);for(let t=0;t<s.length;t++){let o=s[t];if(o)for(let t=0;t<e.length;t++){let a=e[t];o.current[t]=this.calcLerp(o.start[t],o.end[t],r),"object"==typeof a&&null!==a&&(a[o.key]=o.current[t])}}if(t.onUpdate&&t.onUpdate(),1===r&&(t.isFinished=!0,t.onComplete&&t.onComplete(),t.isLast)){this.isFinished=!0;return}}}this.isFinished?(window.removeEventListener("visibilitychange",this.onVisiblitychange),this.onComplete()):(this.onUpdate(),requestAnimationFrame(this.animate))}),w(this,"onVisiblitychange",()=>{"visible"===document.visibilityState?this.isWindowFocus=!0:this.isWindowFocus=!1}),this.easing=e.easing||"linear",this.options=e,this.onUpdate=e.onUpdate||function(){},this.onComplete=e.onComplete||function(){},this.delay=e.delay||0,this.isFinished=!1,this.lastIndex=-1,this.isWindowFocus=!0,this.animations=[],this.time=0}};function P(e,t,o){return t in e?Object.defineProperty(e,t,{value:o,enumerable:!0,configurable:!0,writable:!0}):e[t]=o,e}let I=class MainScene{init(){let e={target:new n.Pq0(0,0,0),position:this.common.camera.position.clone(),progress:new n.Pq0};if(this.scrollTl.to([e.progress],1500,{x:1,easing:"easeOutExpo",onUpdate:()=>{let t=n.cj9.lerp(2,-.5,e.progress.x);this.common.camera.position.y=t,this.common.camera.lookAt(e.target)}},0),this.initTl.to([e.progress],2e3,{y:1,easing:"easeOutExpo",onUpdate:()=>{this.group.visible=!0;let t=n.cj9.lerp(.1*Math.PI,.43*Math.PI,e.progress.y),o=n.cj9.lerp(4,4,e.progress.y),a=Math.sin(t),s=Math.cos(t);this.common.camera.position.x=-a*o,this.common.camera.position.z=+s*o,this.common.camera.lookAt(e.target)}},0),this.assets.gltfs.cat?.scene){let{group5:e,mascotCommonUniforms:t}=this.createNewGroup(this.assets.gltfs.cat.scene,u,"cat");e.position.y=.7,this.initTl.to([t.uProgress.value],500,{x:1},250).to([e.position],1800,{y:0,easing:"easeOutExpo"},250)}if(this.assets.gltfs.copilot?.scene){let{group5:e,mascotCommonUniforms:t}=this.createNewGroup(this.assets.gltfs.copilot.scene,d,"copilot");e.position.y=.7,this.initTl.to([t.uProgress.value],500,{x:1},0).to([e.position],1800,{y:0,easing:"easeOutExpo"},0)}if(this.assets.gltfs.duck?.scene){let{group5:e,mascotCommonUniforms:t}=this.createNewGroup(this.assets.gltfs.duck.scene,m,"duck");e.position.y=.7,this.initTl.to([t.uProgress.value],500,{x:1},500).to([e.position],1800,{y:0,easing:"easeOutExpo"},500)}}initAnimation(){this.initTl.start()}showStatic(){this.initTl.setProgress(1)}scroll(e){this.scrollTl.setProgress(e)}createNewGroup(e,t,o){let a=new n.YJl;a.userData.position=new n.Pq0,a.userData.rotation=new n.Pq0,a.userData.scale=new n.Pq0(1,1,1),a.userData.uScrollProgress=new n.Pq0(0,0,0),a.name="group5",this.groups.push(a),this.group.add(a);let s=new n.YJl;s.position.copy(t.group_data.position),s.name="group4",a.add(s);let i=new n.YJl;i.scale.copy(t.group_data.scale),i.rotation.copy(t.group_data.rotation),i.rotation.order=t.group_data.order,i.userData.random=new n.IUQ(Math.random(),Math.random(),Math.random(),Math.random()),s.add(i),i.name="group3";let r={u_resolution:{value:this.common.fbo_screenSize},u_lightPos:{value:t.light_data.position},uDiffuse_bg:{value:this.assets.images.bg?.texture},uScrollProgress:{value:a.userData.uScrollProgress},uCameraPos:{value:this.common.camera.position},uProgress:{value:new n.IUQ(0,0,0,0)}};return e.traverse(e=>{e instanceof n.eaF&&this.createNewMesh(e,i,t,o,r)}),{group4:s,group5:a,mascotCommonUniforms:r}}createNewMesh(e,t,o,a,s){let i=e.geometry,r=e.material,c=o.textures[e.name];if(!c)return;let l=c.ao,u=c.color,m=c.colorVec?c.colorVec:r.color,p=this.assets.images[l]?.texture,h=u?this.assets.images[u]?.texture:null,v={u_ao:{value:p},u_color:{value:m},u_colorTex:{value:h},u_matcapTex:{value:c.matcap?this.assets.images[c.matcap]?.texture:null},u_noiseRange:{value:c.noiseRange},u_fogRangeZ:{value:c.fogRangeZ},u_translate:{value:e.position},uSpecularFactor:{value:c.specularFactor},...s,...this.commonUniforms},d=new n.BKk({vertexShader:g,fragmentShader:_+(c.blackObj?x:f),uniforms:v,transparent:!0,defines:{USE_COLORTEX:!!h,MASCOT_TYPE:"cat"===a?0:"copilot"===a?1:2}}),b=new n.eaF(i,d);b.renderOrder=1,b.position.copy(e.position),t.add(b)}update(){this.commonUniforms.u_time.value+=this.common.delta}constructor(e,t){P(this,"group",new n.YJl),P(this,"groups",[]),P(this,"commonUniforms",{u_time:{value:0},uBgColor:{value:new n.Q1f(0)}}),P(this,"scrollTl",new y({delay:0})),P(this,"initTl",new y({delay:0})),this.assets=e,this.common=t,this.group.visible=!1,this.group.position.set(0,0,0),this.commonUniforms.uBgColor.value.copy(this.common.bgColor)}},M=`
varying vec2 vUv;

void main(){
  vUv = uv;
  gl_Position = vec4(position.xyz, 1.0);
}
`,z=`
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
`;function O(e,t,o){return t in e?Object.defineProperty(e,t,{value:o,enumerable:!0,configurable:!0,writable:!0}):e[t]=o,e}let Y=class Background{init(){let e=new n.eaF(new n.bdM(2,1),new n.BKk({vertexShader:M,fragmentShader:_+z,uniforms:{uColor:{value:new n.Q1f(6770417)},uProgress:{value:this.progress}},depthTest:!1,depthWrite:!1,transparent:!0}));e.renderOrder=0,this.group.add(e)}showStatic(){this.initTl.setProgress(1)}initAnimation(){this.initTl.to([this.progress],3e3,{x:1,easing:"easeOutExpo"},500).to([this.progress],500,{y:1},500).to([this.progress],4e3,{z:1,easing:"easeOutExpo"},500).start()}constructor(){O(this,"group",new n.YJl),O(this,"initTl",new y({delay:0})),O(this,"progress",new n.IUQ(0,0,0,0)),this.init()}};function k(e,t,o){return t in e?Object.defineProperty(e,t,{value:o,enumerable:!0,configurable:!0,writable:!0}):e[t]=o,e}let C=class Artwork{init(){this.common.init({$wrapper:this.$wrapper,$canvas:this.$canvas}),this.background=new Y,this.common.scene.add(this.background.group),this.mainScene=new I(this.assets,this.common),this.common.scene.position.set(.2,0,0),this.common.camera.position.set(0,2,3),this.common.camera.lookAt(this.common.scene.position),this.common.scene.add(this.mainScene.group)}afterLoad(){this.mainScene?.init(),this.isLoaded=!0}resize(){this.common.resize()}scroll(e){let t=this.common.$wrapper?.getBoundingClientRect();if(t){let o=window.innerHeight,a=-t.height,s=Math.min(1,Math.max(0,n.cj9.mapLinear(t.top,o,a,0,1)));t.bottom-.3*t.height-o<0&&!this.isInitAnimation&&this.isLoaded&&(this.isInitAnimation=!0,this.isReducedMotion||(this.mainScene?.initAnimation(),this.background?.initAnimation())),this.mainScene?.scroll(e?.5:s)}}update(e){e&&(this.mainScene?.showStatic(),this.background?.showStatic()),this.common.update(),this.mainScene?.update(),this.common.renderer?.setRenderTarget(null),this.common.renderer?.render(this.common.scene,this.common.camera)}constructor(e,t,o,a){k(this,"$wrapper",void 0),k(this,"$canvas",void 0),k(this,"mainScene",void 0),k(this,"background",void 0),k(this,"isInitAnimation",!1),k(this,"isLoaded",!1),k(this,"assets",void 0),k(this,"common",new l),k(this,"isReducedMotion",!1),this.assets=a,this.isReducedMotion=o,this.$wrapper=e,this.$canvas=t,this.init()}},j=o.p+"cat-12f7b83d88d9.glb",S=o.p+"duck-317528961eb9.glb",R=o.p+"copilot-4bcfa0360ec4.glb",T=o.p+"mascot-5c5e94e491c2.jpg",F=o.p+"cat_eye-456cb07a65d8.jpg",U=o.p+"metal-ba75af373b6f.jpg",D=o.p+"nose_sss-338f5100f37c.jpg",E=o.p+"head_sss-f7776fc9a7e0.jpg",q=o.p+"face_sss-26a5023624c7.jpg",L=o.p+"eyes_sss-e4f5c1eaee84.jpg",N=o.p+"eyeballs_sss-20198b1d2eb1.jpg",Q=o.p+"eye_color-e32a106912df.jpg",A=o.p+"body_sss-6a70f37fa61d.jpg",V=o.p+"beak_sss-9105c108949e.jpg",Z=o.p+"eyes_sss-84a0ab9ab491.jpg",B=o.p+"eyeballs_sss-6ac78f155b28.jpg",$=o.p+"eyes_sss-8eead3d84dd4.jpg",W=o.p+"face_sss-9492bd35dd57.jpg",G=o.p+"ears_sss-d4b1c349e831.jpg",K=o.p+"glasses_sss-a00d8f4c88af.jpg",J=o.p+"goggle_sss-1d114d19dc79.jpg",X=o.p+"head_sss-0cf8c856aea1.jpg",H=o.p+"neck_sss-6af221b48e7a.jpg";var ee=o(17888);function et(e,t,o){return t in e?Object.defineProperty(e,t,{value:o,enumerable:!0,configurable:!0,writable:!0}):e[t]=o,e}let eo=class Assets{async load(e){let t=[...this.loadImages(),...this.loadGltfs()];try{await Promise.all(t),this.isLoaded=!0,e&&e()}catch(e){console.log("Error loading assets",e)}}loadGltfs(){let e=new ee.B;return Object.values(this.gltfs).map(t=>new Promise((o,a)=>{e.load(t.src,e=>{t.scene=e.scene,o(e.scene)},void 0,e=>a(e))}))}loadImages(){let e=new n.Tap;return Object.values(this.images).map(t=>new Promise((o,a)=>{e.load(t.src,e=>{t.texture=e,e.flipY=t.flipY,o(e)},void 0,e=>a(e))}))}constructor(){et(this,"isLoaded",!1),et(this,"gltfs",{cat:{src:j,scene:null},duck:{src:S,scene:null},copilot:{src:R,scene:null}}),et(this,"images",{matcap_mascot:{src:T,texture:null,flipY:!1},matcap_cateye:{src:F,texture:null,flipY:!1},matcap_metal:{src:U,texture:null,flipY:!1},cat_nose_ao:{src:D,texture:null,flipY:!1},cat_head_ao:{src:E,texture:null,flipY:!1},cat_face_ao:{src:q,texture:null,flipY:!1},cat_eye_ao:{src:L,texture:null,flipY:!1},cat_eyeball_ao:{src:N,texture:null,flipY:!1},cat_eye_color:{src:Q,texture:null,flipY:!1},duck_body_ao:{src:A,texture:null,flipY:!1},duck_beak_ao:{src:V,texture:null,flipY:!1},duck_eyes_ao:{src:Z,texture:null,flipY:!1},duck_eyeballs_ao:{src:B,texture:null,flipY:!1},copilot_eyes_ao:{src:$,texture:null,flipY:!1},copilot_face_ao:{src:W,texture:null,flipY:!1},copilot_ears_ao:{src:G,texture:null,flipY:!1},copilot_glasses_ao:{src:K,texture:null,flipY:!1},copilot_goggle_ao:{src:J,texture:null,flipY:!1},copilot_head_ao:{src:X,texture:null,flipY:!1},copilot_neck_ao:{src:H,texture:null,flipY:!1}})}};var ea=o(28804);function es(){let[e,t]=(0,s.useState)(!1),o=(0,s.useRef)(null),n=(0,s.useRef)(null),c=(0,s.useRef)(0),{isIntersecting:l}=(0,i.A)(o,{threshold:.4,isOnce:!0}),u=(0,s.useCallback)(()=>{t(!0)},[]);return(0,s.useEffect)(()=>{l&&u()},[l,u]),(0,s.useEffect)(()=>{let e;if(!(0,ea.ZN)()||!l)return;let t=!1,a=!1,s=new eo,i=o=>{(t=o.matches)?e&&(a&&e.update(t),c.current&&cancelAnimationFrame(c.current)):a&&h()},r=window.matchMedia("(prefers-reduced-motion: reduce)");r.addEventListener("change",i),t=r.matches;let u=()=>{e&&e.resize(),t&&e&&e.update(t)},m=()=>{e&&e.scroll(t)},p=new IntersectionObserver(o=>{for(let s of o)s.isIntersecting?(a=!0,t?e.update(t):h()):(a=!1,c.current&&cancelAnimationFrame(c.current))},{threshold:.1});o.current&&n.current&&(e=new C(o.current,n.current,t,s),p.observe(n.current),s.load(()=>{e.afterLoad(),u(),m(),t&&e.update(t)})),window.addEventListener("resize",u),window.addEventListener("scroll",m);let h=()=>{a&&(e.update(t),c.current=requestAnimationFrame(h))};t||h();let v=()=>{cancelAnimationFrame(c.current)};return window.addEventListener("beforeunload",v),()=>{window.removeEventListener("resize",u),window.removeEventListener("scroll",m),window.removeEventListener("beforeunload",v),r.removeEventListener("change",i),p.disconnect()}},[l]),(0,a.jsxs)("div",{ref:o,className:`lp-Cta-mascots ${e?"":"lp-Cta-mascots--hidden"}`,children:[(0,a.jsx)("div",{className:"sr-only",children:r.s.visual.alt}),(0,a.jsx)("canvas",{ref:n})]})}try{es.displayName||(es.displayName="CtaWebGL")}catch{}}}]);
//# sourceMappingURL=ui_packages_landing-pages_routes_home_CtaWebGL_tsx-ui_packages_landing-pages_routes_home_asse-96f8a8-b2c8bd04d54d.js.map
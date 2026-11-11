"use strict";(globalThis.rspackChunk_github_ui_github_ui=globalThis.rspackChunk_github_ui_github_ui||[]).push([[35272],{456380(e,t,o){o.r(t),o.d(t,{default:()=>ee});var a=o(474848),s=o(626067),i=o(916522),r=o(296540),n=o(101162),c=o(439437);class l{$wrapper;$canvas;screenSize=new c.I9Y;screenSize_old=new c.I9Y;aspect=1;isMobile=!1;pixelRatio=1;camera=new c.ubm(30,1,.01,50);scene=new c.Z58;fbo_screenSize=new c.I9Y;time=0;delta=0;bgColor=new c.Q1f(0);renderer;clock;controls;init({$wrapper:e,$canvas:t}){this.pixelRatio=Math.min(1.5,window.devicePixelRatio),this.renderer=new c.S3G({antialias:!0,alpha:!0,canvas:t}),this.renderer.outputEncoding=3e3,this.$canvas=this.renderer.domElement,e.appendChild(this.$canvas),this.$wrapper=e,this.scene.add(this.camera),this.renderer.setClearColor(this.bgColor,1),this.renderer.setPixelRatio(this.pixelRatio),this.clock=new c.zD7,this.clock.start(),this.resize()}resize(){let e=this.$wrapper?.clientWidth||0,t=this.$wrapper?.clientHeight||0;this.screenSize_old.copy(this.screenSize),this.screenSize.set(e,t),this.fbo_screenSize.set(e*this.pixelRatio,t*this.pixelRatio),this.aspect=e/t,this.camera.aspect=this.aspect,this.camera.updateProjectionMatrix(),this.renderer?.setSize(this.screenSize.x,this.screenSize.y)}getEase(e){return Math.min(1,e*this.delta)}update(){let e=this.clock?.getDelta();e&&(this.delta=e),this.time+=this.delta}}let u={light_data:{position:new c.Pq0(1,1,1.5)},group_data:{position:new c.Pq0(0,-.05,.1),scale:new c.Pq0(3,3,3),rotation:new c.O9p(0,0,0),order:"ZYX"},textures:{nose:{ao:"cat_nose_ao",color:null,colorVec:new c.Q1f(0),matcap:"matcap_metal",noiseRange:new c.I9Y(-.03,.03),fogRangeZ:new c.I9Y(-1,-.3),specularFactor:.6,blackObj:!0},eye:{ao:"cat_eye_ao",color:null,colorVec:new c.Q1f(0),matcap:"matcap_metal",noiseRange:new c.I9Y(-.03,.03),fogRangeZ:new c.I9Y(-1,-.3),specularFactor:.6,blackObj:!0},face:{ao:"cat_face_ao",color:null,colorVec:new c.Q1f(0xff69c8),matcap:"matcap_mascot",noiseRange:new c.I9Y(-.1,.1),fogRangeZ:new c.I9Y(-1,-.5),specularFactor:.05,blackObj:!1},head:{ao:"cat_head_ao",color:null,colorVec:new c.Q1f(0xf046b2),matcap:"matcap_mascot",noiseRange:new c.I9Y(-.1,.1),fogRangeZ:new c.I9Y(-1,-.5),specularFactor:.3,blackObj:!1},eyeball:{ao:"cat_eyeball_ao",color:null,colorVec:new c.Q1f(0xffa3dd),matcap:"matcap_mascot",noiseRange:new c.I9Y(-.03,.03),fogRangeZ:new c.I9Y(-1,-.3),specularFactor:.3,blackObj:!1}}},m={light_data:{position:new c.Pq0(1,1,1)},group_data:{position:new c.Pq0(.8,-.2,.6),scale:new c.Pq0(4,4,4),rotation:new c.O9p(-.2,-.15,0),order:"XZY"},textures:{body:{ao:"duck_body_ao",color:null,colorVec:new c.Q1f(0xf6b545),matcap:"matcap_mascot",noiseRange:new c.I9Y(-.03,.03),fogRangeZ:new c.I9Y(-1,-.3),specularFactor:.2,blackObj:!1},beak:{ao:"duck_beak_ao",color:null,colorVec:new c.Q1f(0xf6b545),matcap:"matcap_mascot",noiseRange:new c.I9Y(-.03,.03),fogRangeZ:new c.I9Y(-1,-.3),specularFactor:.2,blackObj:!1},eyes:{ao:"duck_eyes_ao",color:null,colorVec:new c.Q1f(0),matcap:"matcap_metal",noiseRange:new c.I9Y(-.03,.03),fogRangeZ:new c.I9Y(-1,-.3),specularFactor:.6,blackObj:!0},eyeballs:{ao:"duck_eyeballs_ao",color:null,colorVec:new c.Q1f(0),matcap:"matcap_metal",noiseRange:new c.I9Y(-.03,.03),fogRangeZ:new c.I9Y(-1,-.3),specularFactor:.6,blackObj:!0}}},p={position:new c.Pq0(1,1,1)},h={position:new c.Pq0(-.8,0,-.3),scale:new c.Pq0(2.8,2.8,2.8),rotation:new c.O9p(-.1,-.3,0),order:"XZY"},d=new c.Q1f(6374374),v={light_data:p,group_data:h,textures:{eyes:{ao:"copilot_eyes_ao",color:null,colorVec:new c.Q1f(1656532),matcap:"matcap_mascot",noiseRange:new c.I9Y(-.03,.03),fogRangeZ:new c.I9Y(-1,-.3),specularFactor:.2,blackObj:!1},face:{ao:"copilot_face_ao",color:null,colorVec:new c.Q1f(163),matcap:"matcap_mascot",noiseRange:new c.I9Y(-.03,.03),fogRangeZ:new c.I9Y(-1,-.3),specularFactor:.3,blackObj:!1},glasses:{ao:"copilot_glasses_ao",color:null,colorVec:new c.Q1f(2034324),matcap:"matcap_mascot",noiseRange:new c.I9Y(-.03,.03),fogRangeZ:new c.I9Y(-1,-.3),specularFactor:.3,blackObj:!1},goggle:{ao:"copilot_goggle_ao",color:null,colorVec:d,matcap:"matcap_mascot",noiseRange:new c.I9Y(-.03,.03),fogRangeZ:new c.I9Y(-1,-.3),specularFactor:.2,blackObj:!1},head:{ao:"copilot_head_ao",color:null,colorVec:d,matcap:"matcap_mascot",noiseRange:new c.I9Y(-.03,.03),fogRangeZ:new c.I9Y(-1,-.3),specularFactor:.4,blackObj:!1},neck:{ao:"copilot_neck_ao",color:null,colorVec:d,matcap:"matcap_mascot",noiseRange:new c.I9Y(-.03,.03),fogRangeZ:new c.I9Y(-1,-.3),specularFactor:0,blackObj:!1},ears:{ao:"copilot_ears_ao",color:null,colorVec:d,matcap:"matcap_mascot",noiseRange:new c.I9Y(-.03,.03),fogRangeZ:new c.I9Y(-1,-.3),specularFactor:.4,blackObj:!1}}},g=`
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
`,w={linear:e=>e,easeInSine:e=>-1*Math.cos(Math.PI/2*e)+1,easeOutSine:e=>Math.sin(Math.PI/2*e),easeInOutSine:e=>-.5*(Math.cos(Math.PI*e)-1),easeInQuad:e=>e*e,easeOutQuad:e=>e*(2-e),easeInOutQuad:e=>e<.5?2*e*e:-1+(4-2*e)*e,easeInCubic:e=>e*e*e,easeOutCubic(e){let t=e-1;return t*t*t+1},easeInOutCubic:e=>e<.5?4*e*e*e:(e-1)*(2*e-2)*(2*e-2)+1,easeInQuart:e=>e*e*e*e,easeOutQuart(e){let t=e-1;return 1-t*t*t*t},easeInOutQuart(e){let t=e-1;return e<.5?8*e*e*e*e:1-8*t*t*t*t},easeInQuint:e=>e*e*e*e*e,easeOutQuint(e){let t=e-1;return 1+t*t*t*t*t},easeInOutQuint(e){let t=e-1;return e<.5?16*e*e*e*e*e:1+16*t*t*t*t*t},easeInExpo:e=>0===e?0:Math.pow(2,10*(e-1)),easeOutExpo:e=>1===e?1:-Math.pow(2,-10*e)+1,easeInOutExpo(e){if(0===e||1===e)return e;let t=2*e,o=t-1;return t<1?.5*Math.pow(2,10*o):.5*(-Math.pow(2,-10*o)+2)},easeInCirc:e=>-1*(Math.sqrt(1-e/1*e)-1),easeOutCirc(e){let t=e-1;return Math.sqrt(1-t*t)},easeInOutCirc(e){let t=2*e,o=t-2;return t<1?-.5*(Math.sqrt(1-t*t)-1):.5*(Math.sqrt(1-o*o)+1)},easeInBack:(e,t=1.70158)=>e*e*((t+1)*e-t),easeOutBack(e,t=1.70158){let o=e/1-1;return o*o*((t+1)*o+t)+1},easeInOutBack(e,t=1.70158){let o=2*e,a=o-2,s=1.525*t;return o<1?.5*o*o*((s+1)*o-s):.5*(a*a*((s+1)*a+s)+2)},easeInElastic(e,t=.7){if(0===e||1===e)return e;let o=e/1-1,a=1-t;return-(Math.pow(2,10*o)*Math.sin(2*Math.PI*(o-a/(2*Math.PI)*Math.asin(1))/a))},easeOutElastic(e,t=.7){if(0===e||1===e)return e;let o=1-t,a=2*e;return Math.pow(2,-10*a)*Math.sin(2*Math.PI*(a-o/(2*Math.PI)*Math.asin(1))/o)+1},easeInOutElastic(e,t=.65){if(0===e||1===e)return e;let o=1-t,a=2*e,s=a-1,i=o/(2*Math.PI)*Math.asin(1);return a<1?-(Math.pow(2,10*s)*Math.sin(2*Math.PI*(s-i)/o)*.5):Math.pow(2,-10*s)*Math.sin(2*Math.PI*(s-i)/o)*.5+1},easeOutBounce(e){let t=e/1;if(t<1/2.75)return 7.5625*t*t;if(t<2/2.75){let e=t-1.5/2.75;return 7.5625*e*e+.75}if(t<2.5/2.75){let e=t-2.25/2.75;return 7.5625*e*e+.9375}{let e=t-2.625/2.75;return 7.5625*e*e+.984375}},easeInBounce(e){return 1-this.easeOutBounce(1-e)},easeInOutBounce(e){return e<.5?.5*this.easeInBounce(2*e):.5*this.easeOutBounce(2*e-1)+.5}};class b{easing;options;onUpdate;onComplete;delay;isFinished;lastIndex;isWindowFocus;animations;startTime;oldTime;time;totalDuration=0;totalProgress=0;constructor(e={}){this.easing=e.easing||"linear",this.options=e,this.onUpdate=e.onUpdate||function(){},this.onComplete=e.onComplete||function(){},this.delay=e.delay||0,this.isFinished=!1,this.lastIndex=-1,this.isWindowFocus=!0,this.animations=[],this.time=0}to(e,t,o,a){return this.#e(e,t,o,a),this}#e(e,t,o,a){let s=0;if(void 0===a||isNaN(a)){if(this.animations.length>0){let e=this.animations[this.animations.length-1];e&&(s=e.duration+e.delay)}}else s=a;s+=this.delay;let i={datas:Array.isArray(e)?e:[e],duration:t,easing:o.easing||this.easing,onComplete:o.onComplete,onUpdate:o.onUpdate,values:[],delay:s,properties:o};this.animations.push(i),this.arrangeDatas(i);let r=0;for(let e=0;e<this.animations.length;e++){let t=this.animations[e];if(!t)continue;let o=t.duration+t.delay;r<o&&(r=o,this.lastIndex=e),t.isLast=!1}return this.getProgress(),i}getProgress(){let e=0;for(let t of this.animations)t.duration+t.delay>e&&(e=t.duration+t.delay);e+=this.delay,this.totalDuration=e}setProgress(e){for(let t of this.animations){let{datas:o,values:a,delay:s,duration:i}=t,r=s+i,n=this.calcProgress(0,this.totalDuration,s),c=this.calcProgress(0,this.totalDuration,r),l=this.calcProgress(n,c,e);for(let e=0;e<o.length;e++){let t=o[e];if(t){let o=a[e],s=o?.start[e],i=o?.end[e];o&&(o.current[e]=this.calcLerp(s,i,l),t[o.key]=o.current[e])}}t.onUpdate&&t.onUpdate()}}start(){if(-1===this.lastIndex)return;this.startTime=new Date,this.oldTime=new Date;let e=this.animations[this.lastIndex];e&&(e.isLast=!0),window.addEventListener("visibilitychange",this.onVisiblitychange),this.animate()}animate=()=>{let e=new Date;if(this.isWindowFocus||(this.oldTime=e),this.oldTime){let t=e.getTime()-this.oldTime.getTime();this.time+=t}for(let t of(this.oldTime=e,this.animations)){let{datas:e,duration:o,easing:a,values:s,delay:i}=t;if(this.time>i&&!t.isFinished){let r=this.calcProgress(0,o,this.time-i);r=w[a](r);for(let t=0;t<s.length;t++){let o=s[t];if(o)for(let t=0;t<e.length;t++){let a=e[t];o.current[t]=this.calcLerp(o.start[t],o.end[t],r),"object"==typeof a&&null!==a&&(a[o.key]=o.current[t])}}if(t.onUpdate&&t.onUpdate(),1===r&&(t.isFinished=!0,t.onComplete&&t.onComplete(),t.isLast)){this.isFinished=!0;return}}}this.isFinished?(window.removeEventListener("visibilitychange",this.onVisiblitychange),this.onComplete()):(this.onUpdate(),requestAnimationFrame(this.animate))};arrangeDatas(e){let{properties:t,datas:o,values:a}=e;for(let e in t){let s=0,i=[],r=[],n=[];switch(e){case"easing":case"onComplete":case"onUpdate":break;default:for(let a of o)null!==a&&"object"==typeof a&&(i[s]=a[e],r[s]=a[e],n[s]=t[e],s++);a.push({key:e,start:i,current:r,end:n})}}}calcProgress(e,t,o){return Math.max(0,Math.min(1,(o-e)/(t-e)))}calcLerp(e,t,o){return e+(t-e)*o}onVisiblitychange=()=>{"visible"===document.visibilityState?this.isWindowFocus=!0:this.isWindowFocus=!1}}class y{group=new c.YJl;groups=[];commonUniforms={u_time:{value:0},uBgColor:{value:new c.Q1f(0)}};scrollTl=new b({delay:0});initTl=new b({delay:0});#t;#o;constructor(e,t){this.#t=e,this.#o=t,this.group.visible=!1,this.group.position.set(0,0,0),this.commonUniforms.uBgColor.value.copy(this.#o.bgColor)}init(){let e={target:new c.Pq0(0,0,0),position:this.#o.camera.position.clone(),progress:new c.Pq0};if(this.scrollTl.to([e.progress],1500,{x:1,easing:"easeOutExpo",onUpdate:()=>{let t=c.cj9.lerp(2,-.5,e.progress.x);this.#o.camera.position.y=t,this.#o.camera.lookAt(e.target)}},0),this.initTl.to([e.progress],2e3,{y:1,easing:"easeOutExpo",onUpdate:()=>{this.group.visible=!0;let t=c.cj9.lerp(.1*Math.PI,.43*Math.PI,e.progress.y),o=c.cj9.lerp(4,4,e.progress.y),a=Math.sin(t),s=Math.cos(t);this.#o.camera.position.x=-a*o,this.#o.camera.position.z=s*o,this.#o.camera.lookAt(e.target)}},0),this.#t.gltfs.cat?.scene){let{group5:e,mascotCommonUniforms:t}=this.createNewGroup(this.#t.gltfs.cat.scene,u,"cat");e.position.y=.7,this.initTl.to([t.uProgress.value],500,{x:1},250).to([e.position],1800,{y:0,easing:"easeOutExpo"},250)}if(this.#t.gltfs.copilot?.scene){let{group5:e,mascotCommonUniforms:t}=this.createNewGroup(this.#t.gltfs.copilot.scene,v,"copilot");e.position.y=.7,this.initTl.to([t.uProgress.value],500,{x:1},0).to([e.position],1800,{y:0,easing:"easeOutExpo"},0)}if(this.#t.gltfs.duck?.scene){let{group5:e,mascotCommonUniforms:t}=this.createNewGroup(this.#t.gltfs.duck.scene,m,"duck");e.position.y=.7,this.initTl.to([t.uProgress.value],500,{x:1},500).to([e.position],1800,{y:0,easing:"easeOutExpo"},500)}}initAnimation(){this.initTl.start()}showStatic(){this.initTl.setProgress(1)}scroll(e){this.scrollTl.setProgress(e)}createNewGroup(e,t,o){let a=new c.YJl;a.userData.position=new c.Pq0,a.userData.rotation=new c.Pq0,a.userData.scale=new c.Pq0(1,1,1),a.userData.uScrollProgress=new c.Pq0(0,0,0),a.name="group5",this.groups.push(a),this.group.add(a);let s=new c.YJl;s.position.copy(t.group_data.position),s.name="group4",a.add(s);let i=new c.YJl;i.scale.copy(t.group_data.scale),i.rotation.copy(t.group_data.rotation),i.rotation.order=t.group_data.order,i.userData.random=new c.IUQ(Math.random(),Math.random(),Math.random(),Math.random()),s.add(i),i.name="group3";let r={u_resolution:{value:this.#o.fbo_screenSize},u_lightPos:{value:t.light_data.position},uDiffuse_bg:{value:this.#t.images.bg?.texture},uScrollProgress:{value:a.userData.uScrollProgress},uCameraPos:{value:this.#o.camera.position},uProgress:{value:new c.IUQ(0,0,0,0)}};return e.traverse(e=>{e instanceof c.eaF&&this.createNewMesh(e,i,t,o,r)}),{group4:s,group5:a,mascotCommonUniforms:r}}createNewMesh(e,t,o,a,s){let i=e.geometry,r=e.material,n=o.textures[e.name];if(!n)return;let l=n.ao,u=n.color,m=n.colorVec?n.colorVec:r.color,p=this.#t.images[l]?.texture,h=u?this.#t.images[u]?.texture:null,d={u_ao:{value:p},u_color:{value:m},u_colorTex:{value:h},u_matcapTex:{value:n.matcap?this.#t.images[n.matcap]?.texture:null},u_noiseRange:{value:n.noiseRange},u_fogRangeZ:{value:n.fogRangeZ},u_translate:{value:e.position},uSpecularFactor:{value:n.specularFactor},...s,...this.commonUniforms},v=new c.BKk({vertexShader:g,fragmentShader:_+(n.blackObj?x:f),uniforms:d,transparent:!0,defines:{USE_COLORTEX:!!h,MASCOT_TYPE:"cat"===a?0:"copilot"===a?1:2}}),w=new c.eaF(i,v);w.renderOrder=1,w.position.copy(e.position),t.add(w)}update(){this.commonUniforms.u_time.value+=this.#o.delta}}let P=`
varying vec2 vUv;

void main(){
  vUv = uv;
  gl_Position = vec4(position.xyz, 1.0);
}
`,I=`
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
`;class M{group=new c.YJl;initTl=new b({delay:0});progress=new c.IUQ(0,0,0,0);constructor(){this.init()}init(){let e=new c.eaF(new c.bdM(2,1),new c.BKk({vertexShader:P,fragmentShader:_+I,uniforms:{uColor:{value:new c.Q1f(6770417)},uProgress:{value:this.progress}},depthTest:!1,depthWrite:!1,transparent:!0}));e.renderOrder=0,this.group.add(e)}showStatic(){this.initTl.setProgress(1)}initAnimation(){this.initTl.to([this.progress],3e3,{x:1,easing:"easeOutExpo"},500).to([this.progress],500,{y:1},500).to([this.progress],4e3,{z:1,easing:"easeOutExpo"},500).start()}}class z{#a;#s;#i;#r;#n=!1;#c=!1;#t;#o=new l;#l=!1;constructor(e,t,o,a){this.#t=a,this.#l=o,this.#a=e,this.#s=t,this.init()}init(){this.#o.init({$wrapper:this.#a,$canvas:this.#s}),this.#r=new M,this.#o.scene.add(this.#r.group),this.#i=new y(this.#t,this.#o),this.#o.scene.position.set(.2,0,0),this.#o.camera.position.set(0,2,3),this.#o.camera.lookAt(this.#o.scene.position),this.#o.scene.add(this.#i.group)}afterLoad(){this.#i?.init(),this.#c=!0}resize(){this.#o.resize()}scroll(e){let t=this.#o.$wrapper?.getBoundingClientRect();if(t){let o=window.innerHeight,a=-t.height,s=Math.min(1,Math.max(0,c.cj9.mapLinear(t.top,o,a,0,1)));t.bottom-.3*t.height-o<0&&!this.#n&&this.#c&&(this.#n=!0,this.#l||(this.#i?.initAnimation(),this.#r?.initAnimation())),this.#i?.scroll(e?.5:s)}}update(e){e&&(this.#i?.showStatic(),this.#r?.showStatic()),this.#o.update(),this.#i?.update(),this.#o.renderer?.setRenderTarget(null),this.#o.renderer?.render(this.#o.scene,this.#o.camera)}}let Y=o.p+"cat-f3f7c174dd40ee38.glb",O=o.p+"duck-fd3edc799900f236.glb",k=o.p+"copilot-637acc5067d6bd48.glb",C=o.p+"mascot-7c495cf9822e0d5c.jpg",R=o.p+"cat_eye-75fdf7af6c5dc157.jpg",S=o.p+"metal-3c8c628f34ff880e.jpg",j=o.p+"nose_sss-6afeebf8847550e0.jpg",F=o.p+"head_sss-d8fae0ae80a4e382.jpg",T=o.p+"face_sss-3e1df8b333b17007.jpg",E=o.p+"eyes_sss-50a88b260278a821.jpg",U=o.p+"eyeballs_sss-7d5e1ff2485a86b4.jpg",D=o.p+"eye_color-bb27e609004c77cc.jpg",L=o.p+"body_sss-81ee34ea4313f489.jpg",q=o.p+"beak_sss-9bedb47fe065d769.jpg",N=o.p+"eyes_sss-1cf5a161036fa333.jpg",A=o.p+"eyeballs_sss-d377e4858a74c681.jpg",Q=o.p+"eyes_sss-d4ec85f4a631f091.jpg",Z=o.p+"face_sss-08fee22135b1ea64.jpg",V=o.p+"ears_sss-0621d17ee690e98e.jpg",B=o.p+"glasses_sss-60c5ab8eb11601ef.jpg",$=o.p+"goggle_sss-e9ec45c9470a5ef8.jpg",W=o.p+"head_sss-20df98de3477bdf9.jpg",K=o.p+"neck_sss-96e4807b0f548768.jpg";var G=o(617888);class J{isLoaded=!1;gltfs={cat:{src:Y,scene:null},duck:{src:O,scene:null},copilot:{src:k,scene:null}};images={matcap_mascot:{src:C,texture:null,flipY:!1},matcap_cateye:{src:R,texture:null,flipY:!1},matcap_metal:{src:S,texture:null,flipY:!1},cat_nose_ao:{src:j,texture:null,flipY:!1},cat_head_ao:{src:F,texture:null,flipY:!1},cat_face_ao:{src:T,texture:null,flipY:!1},cat_eye_ao:{src:E,texture:null,flipY:!1},cat_eyeball_ao:{src:U,texture:null,flipY:!1},cat_eye_color:{src:D,texture:null,flipY:!1},duck_body_ao:{src:L,texture:null,flipY:!1},duck_beak_ao:{src:q,texture:null,flipY:!1},duck_eyes_ao:{src:N,texture:null,flipY:!1},duck_eyeballs_ao:{src:A,texture:null,flipY:!1},copilot_eyes_ao:{src:Q,texture:null,flipY:!1},copilot_face_ao:{src:Z,texture:null,flipY:!1},copilot_ears_ao:{src:V,texture:null,flipY:!1},copilot_glasses_ao:{src:B,texture:null,flipY:!1},copilot_goggle_ao:{src:$,texture:null,flipY:!1},copilot_head_ao:{src:W,texture:null,flipY:!1},copilot_neck_ao:{src:K,texture:null,flipY:!1}};async load(e){let t=[...this.loadImages(),...this.loadGltfs()];try{await Promise.all(t),this.isLoaded=!0,e&&e()}catch(e){console.log("Error loading assets",e)}}loadGltfs(){let e=new G.B;return Object.values(this.gltfs).map(t=>new Promise((o,a)=>{e.load(t.src,e=>{t.scene=e.scene,o(e.scene)},void 0,e=>a(e))}))}loadImages(){let e=new c.Tap;return Object.values(this.images).map(t=>new Promise((o,a)=>{e.load(t.src,e=>{t.texture=e,e.flipY=t.flipY,o(e)},void 0,e=>a(e))}))}}var X=o(502190);let H="A subtle purple glow fades in as Mona the Octocat, Copilot, and Ducky dramatically fall into place next to one another while gazing optimistically into the distance.",ee=(0,s.Re)()?function(){let e,t,o,s,c,l,u,m,p,h=(0,i.c)(12),[d,v]=(0,r.useState)(!1),g=(0,r.useRef)(null),f=(0,r.useRef)(null),x=(0,r.useRef)(0);h[0]===Symbol.for("react.memo_cache_sentinel")?(e={threshold:.4,isOnce:!0},h[0]=e):e=h[0];let{isIntersecting:_}=(0,n.B)(g,e);h[1]===Symbol.for("react.memo_cache_sentinel")?(t=()=>{v(!0)},h[1]=t):t=h[1];let w=t;h[2]!==_?(o=()=>{_&&w()},s=[_,w],h[2]=_,h[3]=o,h[4]=s):(o=h[3],s=h[4]),(0,r.useEffect)(o,s),h[5]!==_?(c=()=>{let e;if(!(0,X.ZN)()||!_)return;let t=!1,o=!1,a=new J,s=a=>{(t=a.matches)?e&&(o&&e.update(t),x.current&&cancelAnimationFrame(x.current)):o&&l()},i=window.matchMedia("(prefers-reduced-motion: reduce)");i.addEventListener("change",s),t=i.matches;let r=()=>{e&&e.resize(),t&&e&&e.update(t)},n=()=>{e&&e.scroll(t)},c=new IntersectionObserver(a=>{for(let s of a)s.isIntersecting?(o=!0,t?e.update(t):l()):(o=!1,x.current&&cancelAnimationFrame(x.current))},{threshold:.1});g.current&&f.current&&(e=new z(g.current,f.current,t,a),c.observe(f.current),a.load(()=>{e.afterLoad(),r(),n(),t&&e.update(t)})),window.addEventListener("resize",r),window.addEventListener("scroll",n);let l=()=>{o&&(e.update(t),x.current=requestAnimationFrame(l))};t||l();let u=()=>{cancelAnimationFrame(x.current)};return window.addEventListener("beforeunload",u),()=>{window.removeEventListener("resize",r),window.removeEventListener("scroll",n),window.removeEventListener("beforeunload",u),i.removeEventListener("change",s),c.disconnect()}},l=[_],h[5]=_,h[6]=c,h[7]=l):(c=h[6],l=h[7]),(0,r.useEffect)(c,l);let b=`lp-Cta-mascots ${!d?"lp-Cta-mascots--hidden":""}`;return h[8]===Symbol.for("react.memo_cache_sentinel")?(u=(0,a.jsx)("div",{className:"sr-only",children:H}),m=(0,a.jsx)("canvas",{ref:f}),h[8]=u,h[9]=m):(u=h[8],m=h[9]),h[10]!==b?(p=(0,a.jsxs)("div",{ref:g,className:b,children:[u,m]}),h[10]=b,h[11]=p):p=h[11],p}:function(){let[e,t]=(0,r.useState)(!1),o=(0,r.useRef)(null),s=(0,r.useRef)(null),i=(0,r.useRef)(0),{isIntersecting:c}=(0,n.B)(o,{threshold:.4,isOnce:!0}),l=(0,r.useCallback)(()=>{t(!0)},[]);return(0,r.useEffect)(()=>{c&&l()},[c,l]),(0,r.useEffect)(()=>{let e;if(!(0,X.ZN)()||!c)return;let t=!1,a=!1,r=new J,n=o=>{(t=o.matches)?e&&(a&&e.update(t),i.current&&cancelAnimationFrame(i.current)):a&&h()},l=window.matchMedia("(prefers-reduced-motion: reduce)");l.addEventListener("change",n),t=l.matches;let u=()=>{e&&e.resize(),t&&e&&e.update(t)},m=()=>{e&&e.scroll(t)},p=new IntersectionObserver(o=>{for(let s of o)s.isIntersecting?(a=!0,t?e.update(t):h()):(a=!1,i.current&&cancelAnimationFrame(i.current))},{threshold:.1});o.current&&s.current&&(e=new z(o.current,s.current,t,r),p.observe(s.current),r.load(()=>{e.afterLoad(),u(),m(),t&&e.update(t)})),window.addEventListener("resize",u),window.addEventListener("scroll",m);let h=()=>{a&&(e.update(t),i.current=requestAnimationFrame(h))};t||h();let d=()=>{cancelAnimationFrame(i.current)};return window.addEventListener("beforeunload",d),()=>{window.removeEventListener("resize",u),window.removeEventListener("scroll",m),window.removeEventListener("beforeunload",d),l.removeEventListener("change",n),p.disconnect()}},[c]),(0,a.jsxs)("div",{ref:o,className:`lp-Cta-mascots ${!e?"lp-Cta-mascots--hidden":""}`,children:[(0,a.jsx)("div",{className:"sr-only",children:H}),(0,a.jsx)("canvas",{ref:s})]})}}}]);
//# sourceMappingURL=chunk-35272-a725a3f33d7b4ed1-86da4d70b9ce98a1.js.map
"use strict";(globalThis.webpackChunk_github_ui_github_ui=globalThis.webpackChunk_github_ui_github_ui||[]).push([["packages_landing-pages_routes_home_CtaWebGL_tsx-packages_landing-pages_routes_home_assets_cta-65313c"],{63640:(e,t,a)=>{a.r(t),a.d(t,{default:()=>ef});var o=a(74848),s=a(96540),i=a(37058),r=a(91690),n=a(35750),c=a(18150),l=a(85242),u=a(39437),p=a(50467);let h=class Common{init({$wrapper:e,$canvas:t}){this.pixelRatio=Math.min(1.5,window.devicePixelRatio),this.renderer=new u.S3G({antialias:!0,alpha:!0,canvas:t}),this.renderer.outputEncoding=u.tgE,this.$canvas=this.renderer.domElement,e.appendChild(this.$canvas),this.$wrapper=e,this.scene.add(this.camera),this.renderer.setClearColor(this.bgColor,1),this.renderer.setPixelRatio(this.pixelRatio),this.clock=new u.zD7,this.clock.start(),this.resize()}resize(){let e=this.$wrapper?.clientWidth||0,t=this.$wrapper?.clientHeight||0;this.screenSize_old.copy(this.screenSize),this.screenSize.set(e,t),this.fbo_screenSize.set(e*this.pixelRatio,t*this.pixelRatio),this.aspect=e/t,this.camera.aspect=this.aspect,this.camera.updateProjectionMatrix(),this.renderer?.setSize(this.screenSize.x,this.screenSize.y)}getEase(e){return Math.min(1,e*this.delta)}update(){let e=this.clock?.getDelta();e&&(this.delta=e),this.time+=this.delta}constructor(){(0,p._)(this,"$wrapper",void 0),(0,p._)(this,"$canvas",void 0),(0,p._)(this,"screenSize",new u.I9Y),(0,p._)(this,"screenSize_old",new u.I9Y),(0,p._)(this,"aspect",1),(0,p._)(this,"isMobile",!1),(0,p._)(this,"pixelRatio",1),(0,p._)(this,"camera",new u.ubm(30,1,.01,50)),(0,p._)(this,"scene",new u.Z58),(0,p._)(this,"fbo_screenSize",new u.I9Y),(0,p._)(this,"time",0),(0,p._)(this,"delta",0),(0,p._)(this,"bgColor",new u.Q1f(856343)),(0,p._)(this,"renderer",void 0),(0,p._)(this,"clock",void 0),(0,p._)(this,"controls",void 0)}},m={position:new u.Pq0(1,1,1.5)},v={light_data:m,group_data:{position:new u.Pq0(0,-.05,.1),scale:new u.Pq0(3,3,3),rotation:new u.O9p(0,0,0),order:"ZYX"},textures:{nose:{ao:"cat_nose_ao",color:null,colorVec:new u.Q1f(0),matcap:"matcap_metal",noiseRange:new u.I9Y(-.03,.03),fogRangeZ:new u.I9Y(-1,-.3),specularFactor:.6,blackObj:!0},eye:{ao:"cat_eye_ao",color:null,colorVec:new u.Q1f(0),matcap:"matcap_metal",noiseRange:new u.I9Y(-.03,.03),fogRangeZ:new u.I9Y(-1,-.3),specularFactor:.6,blackObj:!0},face:{ao:"cat_face_ao",color:null,colorVec:new u.Q1f(0xff69c8),matcap:"matcap_mascot",noiseRange:new u.I9Y(-.1,.1),fogRangeZ:new u.I9Y(-1,-.5),specularFactor:.05,blackObj:!1},head:{ao:"cat_head_ao",color:null,colorVec:new u.Q1f(0xf046b2),matcap:"matcap_mascot",noiseRange:new u.I9Y(-.1,.1),fogRangeZ:new u.I9Y(-1,-.5),specularFactor:.3,blackObj:!1},eyeball:{ao:"cat_eyeball_ao",color:null,colorVec:new u.Q1f(0xffa3dd),matcap:"matcap_mascot",noiseRange:new u.I9Y(-.03,.03),fogRangeZ:new u.I9Y(-1,-.3),specularFactor:.3,blackObj:!1}}},d={position:new u.Pq0(1,1,1)},g={light_data:d,group_data:{position:new u.Pq0(.8,-.2,.6),scale:new u.Pq0(4,4,4),rotation:new u.O9p(-.2,-.15,0),order:"XZY"},textures:{body:{ao:"duck_body_ao",color:null,colorVec:new u.Q1f(0xf6b545),matcap:"matcap_mascot",noiseRange:new u.I9Y(-.03,.03),fogRangeZ:new u.I9Y(-1,-.3),specularFactor:.2,blackObj:!1},beak:{ao:"duck_beak_ao",color:null,colorVec:new u.Q1f(0xf6b545),matcap:"matcap_mascot",noiseRange:new u.I9Y(-.03,.03),fogRangeZ:new u.I9Y(-1,-.3),specularFactor:.2,blackObj:!1},eyes:{ao:"duck_eyes_ao",color:null,colorVec:new u.Q1f(0),matcap:"matcap_metal",noiseRange:new u.I9Y(-.03,.03),fogRangeZ:new u.I9Y(-1,-.3),specularFactor:.6,blackObj:!0},eyeballs:{ao:"duck_eyeballs_ao",color:null,colorVec:new u.Q1f(0),matcap:"matcap_metal",noiseRange:new u.I9Y(-.03,.03),fogRangeZ:new u.I9Y(-1,-.3),specularFactor:.6,blackObj:!0}}},_={position:new u.Pq0(1,1,1)},x={position:new u.Pq0(-.8,0,-.3),scale:new u.Pq0(2.8,2.8,2.8),rotation:new u.O9p(-.1,-.3,0),order:"XZY"},f=new u.Q1f(6374374),w={light_data:_,group_data:x,textures:{eyes:{ao:"copilot_eyes_ao",color:null,colorVec:new u.Q1f(1656532),matcap:"matcap_mascot",noiseRange:new u.I9Y(-.03,.03),fogRangeZ:new u.I9Y(-1,-.3),specularFactor:.2,blackObj:!1},face:{ao:"copilot_face_ao",color:null,colorVec:new u.Q1f(163),matcap:"matcap_mascot",noiseRange:new u.I9Y(-.03,.03),fogRangeZ:new u.I9Y(-1,-.3),specularFactor:.3,blackObj:!1},glasses:{ao:"copilot_glasses_ao",color:null,colorVec:new u.Q1f(2034324),matcap:"matcap_mascot",noiseRange:new u.I9Y(-.03,.03),fogRangeZ:new u.I9Y(-1,-.3),specularFactor:.3,blackObj:!1},goggle:{ao:"copilot_goggle_ao",color:null,colorVec:f,matcap:"matcap_mascot",noiseRange:new u.I9Y(-.03,.03),fogRangeZ:new u.I9Y(-1,-.3),specularFactor:.2,blackObj:!1},head:{ao:"copilot_head_ao",color:null,colorVec:f,matcap:"matcap_mascot",noiseRange:new u.I9Y(-.03,.03),fogRangeZ:new u.I9Y(-1,-.3),specularFactor:.4,blackObj:!1},neck:{ao:"copilot_neck_ao",color:null,colorVec:f,matcap:"matcap_mascot",noiseRange:new u.I9Y(-.03,.03),fogRangeZ:new u.I9Y(-1,-.3),specularFactor:0,blackObj:!1},ears:{ao:"copilot_ears_ao",color:null,colorVec:f,matcap:"matcap_mascot",noiseRange:new u.I9Y(-.03,.03),fogRangeZ:new u.I9Y(-1,-.3),specularFactor:.4,blackObj:!1}}},b=`
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
`,y=`
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
`,P=`
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
`,I=`
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
`;var M=a(88243),k=a(16213);let z={linear:e=>e,easeInSine:e=>-1*Math.cos(Math.PI/2*e)+1,easeOutSine:e=>Math.sin(Math.PI/2*e),easeInOutSine:e=>-.5*(Math.cos(Math.PI*e)-1),easeInQuad:e=>e*e,easeOutQuad:e=>e*(2-e),easeInOutQuad:e=>e<.5?2*e*e:-1+(4-2*e)*e,easeInCubic:e=>e*e*e,easeOutCubic(e){let t=e-1;return t*t*t+1},easeInOutCubic:e=>e<.5?4*e*e*e:(e-1)*(2*e-2)*(2*e-2)+1,easeInQuart:e=>e*e*e*e,easeOutQuart(e){let t=e-1;return 1-t*t*t*t},easeInOutQuart(e){let t=e-1;return e<.5?8*e*e*e*e:1-8*t*t*t*t},easeInQuint:e=>e*e*e*e*e,easeOutQuint(e){let t=e-1;return 1+t*t*t*t*t},easeInOutQuint(e){let t=e-1;return e<.5?16*e*e*e*e*e:1+16*t*t*t*t*t},easeInExpo:e=>0===e?0:Math.pow(2,10*(e-1)),easeOutExpo:e=>1===e?1:-Math.pow(2,-10*e)+1,easeInOutExpo(e){if(0===e||1===e)return e;let t=2*e,a=t-1;return t<1?.5*Math.pow(2,10*a):.5*(-Math.pow(2,-10*a)+2)},easeInCirc:e=>-1*(Math.sqrt(1-e/1*e)-1),easeOutCirc(e){let t=e-1;return Math.sqrt(1-t*t)},easeInOutCirc(e){let t=2*e,a=t-2;return t<1?-.5*(Math.sqrt(1-t*t)-1):.5*(Math.sqrt(1-a*a)+1)},easeInBack:(e,t=1.70158)=>e*e*((t+1)*e-t),easeOutBack(e,t=1.70158){let a=e/1-1;return a*a*((t+1)*a+t)+1},easeInOutBack(e,t=1.70158){let a=2*e,o=a-2,s=1.525*t;return a<1?.5*a*a*((s+1)*a-s):.5*(o*o*((s+1)*o+s)+2)},easeInElastic(e,t=.7){if(0===e||1===e)return e;let a=e/1-1,o=1-t;return-(Math.pow(2,10*a)*Math.sin(2*Math.PI*(a-o/(2*Math.PI)*Math.asin(1))/o))},easeOutElastic(e,t=.7){if(0===e||1===e)return e;let a=1-t,o=2*e;return Math.pow(2,-10*o)*Math.sin(2*Math.PI*(o-a/(2*Math.PI)*Math.asin(1))/a)+1},easeInOutElastic(e,t=.65){if(0===e||1===e)return e;let a=1-t,o=2*e,s=o-1,i=a/(2*Math.PI)*Math.asin(1);return o<1?-(Math.pow(2,10*s)*Math.sin(2*Math.PI*(s-i)/a)*.5):Math.pow(2,-10*s)*Math.sin(2*Math.PI*(s-i)/a)*.5+1},easeOutBounce(e){let t=e/1;if(t<1/2.75)return 7.5625*t*t;if(t<2/2.75){let e=t-1.5/2.75;return 7.5625*e*e+.75}if(t<2.5/2.75){let e=t-2.25/2.75;return 7.5625*e*e+.9375}{let e=t-2.625/2.75;return 7.5625*e*e+.984375}},easeInBounce(e){return 1-this.easeOutBounce(1-e)},easeInOutBounce(e){return e<.5?.5*this.easeInBounce(2*e):.5*this.easeOutBounce(2*e-1)+.5}};var Y=new WeakSet;let O=class Timeline{to(e,t,a,o){return(0,M._)(this,Y,C).call(this,e,t,a,o),this}getProgress(){let e=0;for(let t of this.animations)t.duration+t.delay>e&&(e=t.duration+t.delay);e+=this.delay,this.totalDuration=e}setProgress(e){for(let t of this.animations){let{datas:a,values:o,delay:s,duration:i}=t,r=s+i,n=this.calcProgress(0,this.totalDuration,s),c=this.calcProgress(0,this.totalDuration,r),l=this.calcProgress(n,c,e);for(let e=0;e<a.length;e++){let t=a[e];if(t){let a=o[e],s=a?.start[e],i=a?.end[e];a&&(a.current[e]=this.calcLerp(s,i,l),t[a.key]=a.current[e])}}t.onUpdate&&t.onUpdate()}}start(){if(-1===this.lastIndex)return;this.startTime=new Date,this.oldTime=new Date;let e=this.animations[this.lastIndex];e&&(e.isLast=!0),window.addEventListener("visibilitychange",this.onVisiblitychange),this.animate()}arrangeDatas(e){let{properties:t,datas:a,values:o}=e;for(let e in t){let s=0,i=[],r=[],n=[];switch(e){case"easing":case"onComplete":case"onUpdate":break;default:for(let o of a)null!==o&&"object"==typeof o&&(i[s]=o[e],r[s]=o[e],n[s]=t[e],s++);o.push({key:e,start:i,current:r,end:n})}}}calcProgress(e,t,a){return Math.max(0,Math.min(1,(a-e)/(t-e)))}calcLerp(e,t,a){return e+(t-e)*a}constructor(e={}){(0,k._)(this,Y),(0,p._)(this,"easing",void 0),(0,p._)(this,"options",void 0),(0,p._)(this,"onUpdate",void 0),(0,p._)(this,"onComplete",void 0),(0,p._)(this,"delay",void 0),(0,p._)(this,"isFinished",void 0),(0,p._)(this,"lastIndex",void 0),(0,p._)(this,"isWindowFocus",void 0),(0,p._)(this,"animations",void 0),(0,p._)(this,"startTime",void 0),(0,p._)(this,"oldTime",void 0),(0,p._)(this,"time",void 0),(0,p._)(this,"totalDuration",0),(0,p._)(this,"totalProgress",0),(0,p._)(this,"animate",()=>{let e=new Date;if(this.isWindowFocus||(this.oldTime=e),this.oldTime){let t=e.getTime()-this.oldTime.getTime();this.time+=t}for(let t of(this.oldTime=e,this.animations)){let{datas:e,duration:a,easing:o,values:s,delay:i}=t;if(this.time>i&&!t.isFinished){let r=this.calcProgress(0,a,this.time-i);r=z[o](r);for(let t=0;t<s.length;t++){let a=s[t];if(a)for(let t=0;t<e.length;t++){let o=e[t];a.current[t]=this.calcLerp(a.start[t],a.end[t],r),"object"==typeof o&&null!==o&&(o[a.key]=a.current[t])}}if(t.onUpdate&&t.onUpdate(),1===r&&(t.isFinished=!0,t.onComplete&&t.onComplete(),t.isLast)){this.isFinished=!0;return}}}this.isFinished?(window.removeEventListener("visibilitychange",this.onVisiblitychange),this.onComplete()):(this.onUpdate(),requestAnimationFrame(this.animate))}),(0,p._)(this,"onVisiblitychange",()=>{"visible"===document.visibilityState?this.isWindowFocus=!0:this.isWindowFocus=!1}),this.easing=e.easing||"linear",this.options=e,this.onUpdate=e.onUpdate||function(){},this.onComplete=e.onComplete||function(){},this.delay=e.delay||0,this.isFinished=!1,this.lastIndex=-1,this.isWindowFocus=!0,this.animations=[],this.time=0}};function C(e,t,a,o){let s=0;if(void 0===o||isNaN(o)){if(this.animations.length>0){let e=this.animations[this.animations.length-1];e&&(s=e.duration+e.delay)}}else s=o;s+=this.delay;let i={datas:Array.isArray(e)?e:[e],duration:t,easing:a.easing||this.easing,onComplete:a.onComplete,onUpdate:a.onUpdate,values:[],delay:s,properties:a};this.animations.push(i),this.arrangeDatas(i);let r=0;for(let e=0;e<this.animations.length;e++){let t=this.animations[e];if(!t)continue;let a=t.duration+t.delay;r<a&&(r=a,this.lastIndex=e),t.isLast=!1}return this.getProgress(),i}var j=new WeakMap,R=new WeakMap;let S=class MainScene{init(){let e={target:new u.Pq0(0,0,0),position:(0,n._)(this,R).camera.position.clone(),progress:new u.Pq0};if(this.scrollTl.to([e.progress],1500,{x:1,easing:"easeOutExpo",onUpdate:()=>{let t=u.cj9.lerp(2,-.5,e.progress.x);(0,n._)(this,R).camera.position.y=t,(0,n._)(this,R).camera.lookAt(e.target)}},0),this.initTl.to([e.progress],2e3,{y:1,easing:"easeOutExpo",onUpdate:()=>{this.group.visible=!0;let t=u.cj9.lerp(.1*Math.PI,.43*Math.PI,e.progress.y),a=u.cj9.lerp(4,4,e.progress.y),o=Math.sin(t),s=Math.cos(t);(0,n._)(this,R).camera.position.x=-o*a,(0,n._)(this,R).camera.position.z=s*a,(0,n._)(this,R).camera.lookAt(e.target)}},0),(0,n._)(this,j).gltfs.cat?.scene){let{group5:e,mascotCommonUniforms:t}=this.createNewGroup((0,n._)(this,j).gltfs.cat.scene,v,"cat");e.position.y=.7,this.initTl.to([t.uProgress.value],500,{x:1},250).to([e.position],1800,{y:0,easing:"easeOutExpo"},250)}if((0,n._)(this,j).gltfs.copilot?.scene){let{group5:e,mascotCommonUniforms:t}=this.createNewGroup((0,n._)(this,j).gltfs.copilot.scene,w,"copilot");e.position.y=.7,this.initTl.to([t.uProgress.value],500,{x:1},0).to([e.position],1800,{y:0,easing:"easeOutExpo"},0)}if((0,n._)(this,j).gltfs.duck?.scene){let{group5:e,mascotCommonUniforms:t}=this.createNewGroup((0,n._)(this,j).gltfs.duck.scene,g,"duck");e.position.y=.7,this.initTl.to([t.uProgress.value],500,{x:1},500).to([e.position],1800,{y:0,easing:"easeOutExpo"},500)}}initAnimation(){this.initTl.start()}showStatic(){this.initTl.setProgress(1)}scroll(e){this.scrollTl.setProgress(e)}createNewGroup(e,t,a){let o=new u.YJl;o.userData.position=new u.Pq0,o.userData.rotation=new u.Pq0,o.userData.scale=new u.Pq0(1,1,1),o.userData.uScrollProgress=new u.Pq0(0,0,0),o.name="group5",this.groups.push(o),this.group.add(o);let s=new u.YJl;s.position.copy(t.group_data.position),s.name="group4",o.add(s);let i=new u.YJl;i.scale.copy(t.group_data.scale),i.rotation.copy(t.group_data.rotation),i.rotation.order=t.group_data.order,i.userData.random=new u.IUQ(Math.random(),Math.random(),Math.random(),Math.random()),s.add(i),i.name="group3";let r={u_resolution:{value:(0,n._)(this,R).fbo_screenSize},u_lightPos:{value:t.light_data.position},uDiffuse_bg:{value:(0,n._)(this,j).images.bg?.texture},uScrollProgress:{value:o.userData.uScrollProgress},uCameraPos:{value:(0,n._)(this,R).camera.position},uProgress:{value:new u.IUQ(0,0,0,0)}};return e.traverse(e=>{e instanceof u.eaF&&this.createNewMesh(e,i,t,a,r)}),{group4:s,group5:o,mascotCommonUniforms:r}}createNewMesh(e,t,a,o,s){let i=e.geometry,r=e.material,c=a.textures[e.name];if(!c)return;let l=c.ao,p=c.color,h=c.colorVec?c.colorVec:r.color,m=(0,n._)(this,j).images[l]?.texture,v=p?(0,n._)(this,j).images[p]?.texture:null,d={u_ao:{value:m},u_color:{value:h},u_colorTex:{value:v},u_matcapTex:{value:c.matcap?(0,n._)(this,j).images[c.matcap]?.texture:null},u_noiseRange:{value:c.noiseRange},u_fogRangeZ:{value:c.fogRangeZ},u_translate:{value:e.position},uSpecularFactor:{value:c.specularFactor},...s,...this.commonUniforms},g=new u.BKk({vertexShader:b,fragmentShader:I+(c.blackObj?P:y),uniforms:d,transparent:!0,defines:{USE_COLORTEX:!!v,MASCOT_TYPE:"cat"===o?0:"copilot"===o?1:2}}),_=new u.eaF(i,g);_.renderOrder=1,_.position.copy(e.position),t.add(_)}update(){this.commonUniforms.u_time.value+=(0,n._)(this,R).delta}constructor(e,t){(0,p._)(this,"group",new u.YJl),(0,p._)(this,"groups",[]),(0,p._)(this,"commonUniforms",{u_time:{value:0},uBgColor:{value:new u.Q1f(0)}}),(0,p._)(this,"scrollTl",new O({delay:0})),(0,p._)(this,"initTl",new O({delay:0})),(0,c._)(this,j,{writable:!0,value:void 0}),(0,c._)(this,R,{writable:!0,value:void 0}),(0,l._)(this,j,e),(0,l._)(this,R,t),this.group.visible=!1,this.group.position.set(0,0,0),this.commonUniforms.uBgColor.value.copy((0,n._)(this,R).bgColor)}},T=`
varying vec2 vUv;

void main(){
  vUv = uv;
  gl_Position = vec4(position.xyz, 1.0);
}
`,F=`
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
`,U=class Background{init(){let e=new u.eaF(new u.bdM(2,1),new u.BKk({vertexShader:T,fragmentShader:I+F,uniforms:{uColor:{value:new u.Q1f(6770417)},uProgress:{value:this.progress}},depthTest:!1,depthWrite:!1,transparent:!0}));e.renderOrder=0,this.group.add(e)}showStatic(){this.initTl.setProgress(1)}initAnimation(){this.initTl.to([this.progress],3e3,{x:1,easing:"easeOutExpo"},500).to([this.progress],500,{y:1},500).to([this.progress],4e3,{z:1,easing:"easeOutExpo"},500).start()}constructor(){(0,p._)(this,"group",new u.YJl),(0,p._)(this,"initTl",new O({delay:0})),(0,p._)(this,"progress",new u.IUQ(0,0,0,0)),this.init()}};var D=new WeakMap,E=new WeakMap,q=new WeakMap,N=new WeakMap,L=new WeakMap,Q=new WeakMap,W=new WeakMap,V=new WeakMap,Z=new WeakMap;let A=class Artwork{init(){(0,n._)(this,V).init({$wrapper:(0,n._)(this,D),$canvas:(0,n._)(this,E)}),(0,l._)(this,N,new U),(0,n._)(this,V).scene.add((0,n._)(this,N).group),(0,l._)(this,q,new S((0,n._)(this,W),(0,n._)(this,V))),(0,n._)(this,V).scene.position.set(.2,0,0),(0,n._)(this,V).camera.position.set(0,2,3),(0,n._)(this,V).camera.lookAt((0,n._)(this,V).scene.position),(0,n._)(this,V).scene.add((0,n._)(this,q).group)}afterLoad(){(0,n._)(this,q)?.init(),(0,l._)(this,Q,!0)}resize(){(0,n._)(this,V).resize()}scroll(e){let t=(0,n._)(this,V).$wrapper?.getBoundingClientRect();if(t){let a=window.innerHeight,o=-t.height,s=Math.min(1,Math.max(0,u.cj9.mapLinear(t.top,a,o,0,1)));t.bottom-.3*t.height-a<0&&!(0,n._)(this,L)&&(0,n._)(this,Q)&&((0,l._)(this,L,!0),(0,n._)(this,Z)||((0,n._)(this,q)?.initAnimation(),(0,n._)(this,N)?.initAnimation())),(0,n._)(this,q)?.scroll(e?.5:s)}}update(e){e&&((0,n._)(this,q)?.showStatic(),(0,n._)(this,N)?.showStatic()),(0,n._)(this,V).update(),(0,n._)(this,q)?.update(),(0,n._)(this,V).renderer?.setRenderTarget(null),(0,n._)(this,V).renderer?.render((0,n._)(this,V).scene,(0,n._)(this,V).camera)}constructor(e,t,a,o){(0,c._)(this,D,{writable:!0,value:void 0}),(0,c._)(this,E,{writable:!0,value:void 0}),(0,c._)(this,q,{writable:!0,value:void 0}),(0,c._)(this,N,{writable:!0,value:void 0}),(0,c._)(this,L,{writable:!0,value:!1}),(0,c._)(this,Q,{writable:!0,value:!1}),(0,c._)(this,W,{writable:!0,value:void 0}),(0,c._)(this,V,{writable:!0,value:new h}),(0,c._)(this,Z,{writable:!0,value:!1}),(0,l._)(this,W,o),(0,l._)(this,Z,a),(0,l._)(this,D,e),(0,l._)(this,E,t),this.init()}},B=a.p+"cat-12f7b83d88d9.glb",$=a.p+"duck-317528961eb9.glb",G=a.p+"copilot-4bcfa0360ec4.glb",K=a.p+"mascot-5c5e94e491c2.jpg",J=a.p+"cat_eye-456cb07a65d8.jpg",X=a.p+"metal-ba75af373b6f.jpg",H=a.p+"nose_sss-338f5100f37c.jpg",ee=a.p+"head_sss-f7776fc9a7e0.jpg",et=a.p+"face_sss-26a5023624c7.jpg",ea=a.p+"eyes_sss-e4f5c1eaee84.jpg",eo=a.p+"eyeballs_sss-20198b1d2eb1.jpg",es=a.p+"eye_color-e32a106912df.jpg",ei=a.p+"body_sss-6a70f37fa61d.jpg",er=a.p+"beak_sss-9105c108949e.jpg",en=a.p+"eyes_sss-84a0ab9ab491.jpg",ec=a.p+"eyeballs_sss-6ac78f155b28.jpg",el=a.p+"eyes_sss-8eead3d84dd4.jpg",eu=a.p+"face_sss-9492bd35dd57.jpg",ep=a.p+"ears_sss-d4b1c349e831.jpg",eh=a.p+"glasses_sss-a00d8f4c88af.jpg",em=a.p+"goggle_sss-1d114d19dc79.jpg",ev=a.p+"head_sss-0cf8c856aea1.jpg",ed=a.p+"neck_sss-6af221b48e7a.jpg";var eg=a(17888);let e_=class Assets{async load(e){let t=[...this.loadImages(),...this.loadGltfs()];try{await Promise.all(t),this.isLoaded=!0,e&&e()}catch(e){console.log("Error loading assets",e)}}loadGltfs(){let e=new eg.B;return Object.values(this.gltfs).map(t=>new Promise((a,o)=>{e.load(t.src,e=>{t.scene=e.scene,a(e.scene)},void 0,e=>o(e))}))}loadImages(){let e=new u.Tap;return Object.values(this.images).map(t=>new Promise((a,o)=>{e.load(t.src,e=>{t.texture=e,e.flipY=t.flipY,a(e)},void 0,e=>o(e))}))}constructor(){(0,p._)(this,"isLoaded",!1),(0,p._)(this,"gltfs",{cat:{src:B,scene:null},duck:{src:$,scene:null},copilot:{src:G,scene:null}}),(0,p._)(this,"images",{matcap_mascot:{src:K,texture:null,flipY:!1},matcap_cateye:{src:J,texture:null,flipY:!1},matcap_metal:{src:X,texture:null,flipY:!1},cat_nose_ao:{src:H,texture:null,flipY:!1},cat_head_ao:{src:ee,texture:null,flipY:!1},cat_face_ao:{src:et,texture:null,flipY:!1},cat_eye_ao:{src:ea,texture:null,flipY:!1},cat_eyeball_ao:{src:eo,texture:null,flipY:!1},cat_eye_color:{src:es,texture:null,flipY:!1},duck_body_ao:{src:ei,texture:null,flipY:!1},duck_beak_ao:{src:er,texture:null,flipY:!1},duck_eyes_ao:{src:en,texture:null,flipY:!1},duck_eyeballs_ao:{src:ec,texture:null,flipY:!1},copilot_eyes_ao:{src:el,texture:null,flipY:!1},copilot_face_ao:{src:eu,texture:null,flipY:!1},copilot_ears_ao:{src:ep,texture:null,flipY:!1},copilot_glasses_ao:{src:eh,texture:null,flipY:!1},copilot_goggle_ao:{src:em,texture:null,flipY:!1},copilot_head_ao:{src:ev,texture:null,flipY:!1},copilot_neck_ao:{src:ed,texture:null,flipY:!1}})}};var ex=a(14440);function ef(){let[e,t]=(0,s.useState)(!1),a=(0,s.useRef)(null),n=(0,s.useRef)(null),c=(0,s.useRef)(0),{isIntersecting:l}=(0,i.A)(a,{threshold:.4,isOnce:!0}),u=(0,s.useCallback)(()=>{t(!0)},[]);return(0,s.useEffect)(()=>{l&&u()},[l,u]),(0,s.useEffect)(()=>{let e;if(!(0,ex.ZN)()||!l)return;let t=!1,o=!1,s=new e_,i=a=>{(t=a.matches)?e&&(o&&e.update(t),c.current&&cancelAnimationFrame(c.current)):o&&m()},r=window.matchMedia("(prefers-reduced-motion: reduce)");r.addEventListener("change",i),t=r.matches;let u=()=>{e&&e.resize(),t&&e&&e.update(t)},p=()=>{e&&e.scroll(t)},h=new IntersectionObserver(a=>{for(let s of a)s.isIntersecting?(o=!0,t?e.update(t):m()):(o=!1,c.current&&cancelAnimationFrame(c.current))},{threshold:.1});a.current&&n.current&&(e=new A(a.current,n.current,t,s),h.observe(n.current),s.load(()=>{e.afterLoad(),u(),p(),t&&e.update(t)})),window.addEventListener("resize",u),window.addEventListener("scroll",p);let m=()=>{o&&(e.update(t),c.current=requestAnimationFrame(m))};t||m();let v=()=>{cancelAnimationFrame(c.current)};return window.addEventListener("beforeunload",v),()=>{window.removeEventListener("resize",u),window.removeEventListener("scroll",p),window.removeEventListener("beforeunload",v),r.removeEventListener("change",i),h.disconnect()}},[l]),(0,o.jsxs)("div",{ref:a,className:`lp-Cta-mascots ${!e?"lp-Cta-mascots--hidden":""}`,children:[(0,o.jsx)("div",{className:"sr-only",children:r.s.visual.alt}),(0,o.jsx)("canvas",{ref:n})]})}try{ef.displayName||(ef.displayName="CtaWebGL")}catch{}}}]);
//# sourceMappingURL=packages_landing-pages_routes_home_CtaWebGL_tsx-packages_landing-pages_routes_home_assets_cta-65313c-ae30ba3f8dd4.js.map
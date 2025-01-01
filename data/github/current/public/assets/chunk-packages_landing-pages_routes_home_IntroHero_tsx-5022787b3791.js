"use strict";(globalThis.webpackChunk_github_ui_github_ui=globalThis.webpackChunk_github_ui_github_ui||[]).push([["packages_landing-pages_routes_home_IntroHero_tsx"],{70884:(e,t,o)=>{o.r(t),o.d(t,{default:()=>$});var s,i=o(74848),a=o(96540),r=o(35750),n=o(18150),l=o(85242),c=o(50467),u=o(39437);let h={color1:new u.Q1f(9770163),color2:new u.Q1f(0xbf7600),position:new u.Pq0(-1,1,1),position2:new u.Pq0(1,-1,.4)},m={light_data:h,group_data:{position:new u.Pq0(.6,-.6,2),tablet_position:new u.Pq0(.5,-.2,2),scale:new u.Pq0(1.1,1.1,1.1),rotation:new u.O9p(0,-1.1,-.6),order:"ZYX",mascot:{position:new u.Pq0(0,0,0),scale:new u.Pq0(1,1,1),rotation:new u.O9p(-(.4*Math.PI),0,.5*Math.PI)}},textures:{nose:{ao:"cat_head_ao",color:null,colorVec:new u.Q1f(0),matcap:"matcap_mascot"},eye:{ao:"cat_eye_ao",color:"cat_eye_color",colorVec:new u.Q1f(0),matcap:"matcap_cateye"},face:{ao:"cat_head_ao",color:null,colorVec:new u.Q1f(0xff8fd6),matcap:"matcap_mascot"},head:{ao:"cat_head_ao",color:null,colorVec:new u.Q1f(0xf763c1),matcap:"matcap_mascot"},eyeball:{ao:"cat_head_ao",color:null,colorVec:new u.Q1f(0xffffff),matcap:"matcap_mascot"}}},d={color1:new u.Q1f(0xbf7600),color2:new u.Q1f(0xffebad),position:new u.Pq0(1,1,.4),position2:new u.Pq0(-.5,-1,.6)},v={light_data:d,group_data:{position:new u.Pq0(.3,-1.2,0),tablet_position:new u.Pq0(.1,-.7,0),scale:new u.Pq0(1.5,1.5,1.5),rotation:new u.O9p(0,-.9,-.8),order:"ZYX",mascot:{position:new u.Pq0(0,0,0),scale:new u.Pq0(1,1,1),rotation:new u.O9p(-(.4*Math.PI),0,.5*Math.PI)}},textures:{body:{ao:"duck_body_ao",color:null,colorVec:new u.Q1f(0xf6b545),matcap:"matcap_mascot"},beak:{ao:"duck_body_ao",color:null,colorVec:new u.Q1f(0xf6b545),matcap:"matcap_mascot"},eyes:{ao:"duck_body_ao",color:null,colorVec:new u.Q1f(0),matcap:"matcap_mascot"},eyeballs:{ao:"duck_body_ao",color:null,colorVec:new u.Q1f(0),matcap:"matcap_mascot"}}},p={color1:new u.Q1f(8015085),color2:new u.Q1f(0xce5fe8),position:new u.Pq0(-1,0,2),position2:new u.Pq0(1,-1,1)},g={position:new u.Pq0(-.5,-.8,0),tablet_position:new u.Pq0(-.5,-.3,0),scale:new u.Pq0(1.3,1.3,1.3),rotation:new u.O9p(0,.8,.8),order:"ZYX",mascot:{position:new u.Pq0(0,0,0),scale:new u.Pq0(1,1,1),rotation:new u.O9p(-(.4*Math.PI),0,.5*Math.PI)}},f=new u.Q1f(0x9e55f8),x={light_data:p,group_data:g,textures:{eyes:{ao:"copilot_head_ao",color:null,colorVec:new u.Q1f(3761135),matcap:"matcap_mascot"},face:{ao:"copilot_head_ao",color:null,colorVec:new u.Q1f(328013),matcap:"matcap_mascot"},glass:{ao:"copilot_head_ao",color:null,colorVec:new u.Q1f(6497712),matcap:"matcap_mascot"},goggle:{ao:"copilot_head_ao",color:null,colorVec:new u.Q1f(0x995be3),matcap:"matcap_mascot"},head:{ao:"copilot_head_ao",color:null,colorVec:f,matcap:"matcap_mascot"}}},_=`
uniform vec3 uTranslate;
uniform vec3 uViewDir;
varying vec2 vUv;
varying vec3 vNormal;
varying vec2 vN;
varying vec3 vWorldPosition;
varying vec3 vMVPosition;

vec3 getPositionFromModelMatrix(mat4 modelMatrix) {
    return vec3(modelMatrix[3][0], modelMatrix[3][1], modelMatrix[3][2]);
}

void main(){
  vUv = uv;
  vNormal = normalize( normalMatrix * normal );

  vec4 worldPosition = modelMatrix * vec4(position, 1.0);

  vWorldPosition = position + uTranslate;

  vec4 mvPosition = viewMatrix * worldPosition;
  vMVPosition = mvPosition.xyz;

  vec3 e = normalize( mvPosition.xyz);
  vec3 n = vNormal;

  #if MASCOT_TYPE == 0
    vec3 r = normalize(reflect( -normalize(uViewDir), normalize(n) ));
    float m = 2. * sqrt( pow( r.x, 2. ) + pow( r.y, 2. ) + pow( r.z + 1., 2. ) );
    vN = r.xy / m + .5;
  #else
    vec3 r = normalize(reflect( e, normalize(n) ));
    float m = 2. * sqrt( pow( r.x, 2. ) + pow( r.y, 2. ) + pow( r.z + 1., 2. ) );
    vN = r.xy / m + .5;
  #endif



  gl_Position = projectionMatrix * mvPosition;
}
`,w=`
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
`,b=`
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
`;var y=o(88243),P=o(16213);let M={linear:e=>e,easeInSine:e=>-1*Math.cos(Math.PI/2*e)+1,easeOutSine:e=>Math.sin(Math.PI/2*e),easeInOutSine:e=>-.5*(Math.cos(Math.PI*e)-1),easeInQuad:e=>e*e,easeOutQuad:e=>e*(2-e),easeInOutQuad:e=>e<.5?2*e*e:-1+(4-2*e)*e,easeInCubic:e=>e*e*e,easeOutCubic(e){let t=e-1;return t*t*t+1},easeInOutCubic:e=>e<.5?4*e*e*e:(e-1)*(2*e-2)*(2*e-2)+1,easeInQuart:e=>e*e*e*e,easeOutQuart(e){let t=e-1;return 1-t*t*t*t},easeInOutQuart(e){let t=e-1;return e<.5?8*e*e*e*e:1-8*t*t*t*t},easeInQuint:e=>e*e*e*e*e,easeOutQuint(e){let t=e-1;return 1+t*t*t*t*t},easeInOutQuint(e){let t=e-1;return e<.5?16*e*e*e*e*e:1+16*t*t*t*t*t},easeInExpo:e=>0===e?0:Math.pow(2,10*(e-1)),easeOutExpo:e=>1===e?1:-Math.pow(2,-10*e)+1,easeInOutExpo(e){if(0===e||1===e)return e;let t=2*e,o=t-1;return t<1?.5*Math.pow(2,10*o):.5*(-Math.pow(2,-10*o)+2)},easeInCirc:e=>-1*(Math.sqrt(1-e/1*e)-1),easeOutCirc(e){let t=e-1;return Math.sqrt(1-t*t)},easeInOutCirc(e){let t=2*e,o=t-2;return t<1?-.5*(Math.sqrt(1-t*t)-1):.5*(Math.sqrt(1-o*o)+1)},easeInBack:(e,t=1.70158)=>e*e*((t+1)*e-t),easeOutBack(e,t=1.70158){let o=e/1-1;return o*o*((t+1)*o+t)+1},easeInOutBack(e,t=1.70158){let o=2*e,s=o-2,i=1.525*t;return o<1?.5*o*o*((i+1)*o-i):.5*(s*s*((i+1)*s+i)+2)},easeInElastic(e,t=.7){if(0===e||1===e)return e;let o=e/1-1,s=1-t;return-(Math.pow(2,10*o)*Math.sin(2*Math.PI*(o-s/(2*Math.PI)*Math.asin(1))/s))},easeOutElastic(e,t=.7){if(0===e||1===e)return e;let o=1-t,s=2*e;return Math.pow(2,-10*s)*Math.sin(2*Math.PI*(s-o/(2*Math.PI)*Math.asin(1))/o)+1},easeInOutElastic(e,t=.65){if(0===e||1===e)return e;let o=1-t,s=2*e,i=s-1,a=o/(2*Math.PI)*Math.asin(1);return s<1?-(Math.pow(2,10*i)*Math.sin(2*Math.PI*(i-a)/o)*.5):Math.pow(2,-10*i)*Math.sin(2*Math.PI*(i-a)/o)*.5+1},easeOutBounce(e){let t=e/1;if(t<1/2.75)return 7.5625*t*t;if(t<2/2.75){let e=t-1.5/2.75;return 7.5625*e*e+.75}if(t<2.5/2.75){let e=t-2.25/2.75;return 7.5625*e*e+.9375}{let e=t-2.625/2.75;return 7.5625*e*e+.984375}},easeInBounce(e){return 1-this.easeOutBounce(1-e)},easeInOutBounce(e){return e<.5?.5*this.easeInBounce(2*e):.5*this.easeOutBounce(2*e-1)+.5}};var C=new WeakSet;let z=class Timeline{to(e,t,o,s=0){return(0,y._)(this,C,D).call(this,e,t,o,s),this}start(){if(-1===this.lastIndex)return;this.startTime=new Date,this.oldTime=new Date;let e=this.animations[this.lastIndex];e&&(e.isLast=!0),window.addEventListener("visibilitychange",this.onVisiblitychange),this.animate()}arrangeDatas(e){let{properties:t,datas:o,values:s}=e;for(let e in t){let i=0,a=[],r=[],n=[];switch(e){case"easing":case"onComplete":case"onUpdate":break;default:for(let s of o)null!==s&&"object"==typeof s&&(a[i]=s[e],r[i]=s[e],n[i]=t[e],i++);s.push({key:e,start:a,current:r,end:n})}}}calcProgress(e,t,o){return Math.max(0,Math.min(1,(o-e)/(t-e)))}calcLerp(e,t,o){return e+(t-e)*o}constructor(e={}){(0,P._)(this,C),(0,c._)(this,"easing",void 0),(0,c._)(this,"options",void 0),(0,c._)(this,"onUpdate",void 0),(0,c._)(this,"onComplete",void 0),(0,c._)(this,"delay",void 0),(0,c._)(this,"isFinished",void 0),(0,c._)(this,"lastIndex",void 0),(0,c._)(this,"isWindowFocus",void 0),(0,c._)(this,"animations",void 0),(0,c._)(this,"startTime",void 0),(0,c._)(this,"oldTime",void 0),(0,c._)(this,"time",void 0),(0,c._)(this,"animate",()=>{let e=new Date;if(this.isWindowFocus||(this.oldTime=e),this.oldTime){let t=e.getTime()-this.oldTime.getTime();this.time+=t}for(let t of(this.oldTime=e,this.animations)){let{datas:e,duration:o,easing:s,values:i,delay:a}=t;if(this.time>a&&!t.isFinished){t.isStarted||(t.isStarted=!0,this.arrangeDatas(t));let r=this.calcProgress(0,o,this.time-a);r=M[s](r);for(let t=0;t<i.length;t++){let o=i[t];if(o)for(let t=0;t<e.length;t++){let s=e[t];o.current[t]=this.calcLerp(o.start[t],o.end[t],r),"object"==typeof s&&null!==s&&(s[o.key]=o.current[t])}}if(t.onUpdate&&t.onUpdate(),1===r&&(t.isFinished=!0,t.onComplete&&t.onComplete(),t.isLast)){this.isFinished=!0;return}}}this.isFinished?(window.removeEventListener("visibilitychange",this.onVisiblitychange),this.onComplete()):(this.onUpdate(),requestAnimationFrame(this.animate))}),(0,c._)(this,"onVisiblitychange",()=>{"visible"===document.visibilityState?(this.isWindowFocus=!0,this.oldTime=new Date):this.isWindowFocus=!1}),this.easing=e.easing||"linear",this.options=e,this.onUpdate=e.onUpdate||function(){},this.onComplete=e.onComplete||function(){},this.delay=e.delay||0,this.isFinished=!1,this.lastIndex=-1,this.isWindowFocus=!0,this.animations=[],this.time=0}};function D(e,t,o,s){let i=0;if(isNaN(s)){if(this.animations.length>0){let e=this.animations[this.animations.length-1];e&&(i=e.duration+e.delay)}}else i=s;i+=this.delay;let a={datas:Array.isArray(e)?e:[e],duration:t,easing:o.easing||this.easing,onComplete:o.onComplete,onUpdate:o.onUpdate,values:[],delay:i,properties:o,isStarted:!1};this.animations.push(a);let r=0;for(let e=0;e<this.animations.length;e++){let t=this.animations[e];if(!t)continue;let o=t.duration+t.delay;r<o&&(r=o,this.lastIndex=e),t.isLast=!1}return a}let I=class MainScene{init(){let e=new z({delay:0});if(this.assets.gltfs.cat&&this.assets.gltfs.cat.scene){let{group4:t,group5:o,mascotCommonUniforms:s}=this.createNewGroup(this.assets.gltfs.cat.scene,m,"cat");o.userData.offsetFloatingY=.33*Math.PI*2,t.userData.startPos.set(m.group_data.position.x,-2,0),t.rotation.set(0,1.5*Math.PI,1),this.common.isReduceMotion?(t.rotation.set(0,0,0),t.scale.set(1,1,1),t.userData.introPositionProgress.x=1,s.uProgress.value.x=1):e.to([t.rotation],3e3,{y:0,z:0,easing:"easeOutExpo"},0).to([t.scale],300,{x:1,y:1,z:1,easing:"easeOutExpo"},0).to([t.userData.introPositionProgress],4e3,{x:1,easing:"easeOutExpo"},0).to([s.uProgress.value],500,{x:1},0)}if(this.assets.gltfs.copilot&&this.assets.gltfs.copilot.scene){let{group4:t,group5:o,mascotCommonUniforms:s}=this.createNewGroup(this.assets.gltfs.copilot.scene,x,"copilot");t.userData.startPos.set(-1,-2.5,0),o.userData.offsetFloatingY=.66*Math.PI*2,t.rotation.set(0,-(1.5*Math.PI),-1),this.common.isReduceMotion?(t.rotation.y=0,t.rotation.z=0,t.scale.set(1,1,1),t.userData.introPositionProgress.x=1,s.uProgress.value.x=1):e.to([t.rotation],2400,{y:0,z:0,easing:"easeOutExpo"},600).to([t.scale],300,{x:1,y:1,z:1,easing:"easeOutExpo"},600).to([t.userData.introPositionProgress],4400,{x:1,easing:"easeOutExpo"},600).to([s.uProgress.value],500,{x:1},600)}if(this.assets.gltfs.duck&&this.assets.gltfs.duck.scene){let{group4:t,group5:o,mascotCommonUniforms:s}=this.createNewGroup(this.assets.gltfs.duck.scene,v,"duck");t.userData.startPos.set(1,-2.5,0),o.userData.offsetFloatingY=0,t.rotation.set(0,1.5*Math.PI,-1),this.common.isReduceMotion?(t.rotation.y=0,t.rotation.z=0,t.scale.set(1,1,1),t.userData.introPositionProgress.x=1,s.uProgress.value.x=1,this.common.startCopyAnimation&&this.common.startCopyAnimation()):(e.to([t.rotation],2e3,{y:0,z:0,easing:"easeOutExpo"},1e3).to([t.scale],300,{x:1,y:1,z:1,easing:"easeOutExpo"},1e3).to([t.userData.introPositionProgress],3e3,{x:1,easing:"easeOutExpo"},1e3).to([s.uProgress.value],500,{x:1,onComplete:()=>{this.common.startCopyAnimation&&this.common.startCopyAnimation()}},1e3),e.start())}}createNewGroup(e,t,o){let s=new u.YJl;s.userData.position=new u.Pq0,s.userData.rotation=new u.Pq0,s.userData.scale=new u.Pq0(1,1,1),s.userData.scrollDistY=-1,s.name="group5",this.groups.push(s),this.group.add(s);let i=new u.YJl;i.scale.set(0,0,0),i.position.copy(t.group_data.position),i.userData.startPos=new u.Pq0,i.userData.desktopPos=new u.Pq0().copy(t.group_data.position),i.userData.tabletPos=new u.Pq0().copy(t.group_data.tablet_position),i.userData.introPositionProgress=new u.Pq0(0,0,0),i.name="group4",s.add(i);let a=new u.YJl;a.scale.copy(t.group_data.scale),a.rotation.copy(t.group_data.rotation),a.rotation.order=t.group_data.order,a.userData.random=new u.IUQ(Math.random(),Math.random(),Math.random(),Math.random()),i.add(a),a.name="group3";let r=new u.YJl;r.name="group2",a.add(r);let n={uResolution:{value:this.common.fbo_screenSize},uLightColor1:{value:t.light_data.color1},uLightColor2:{value:t.light_data.color2},uLightPos:{value:t.light_data.position},uLightPos2:{value:t.light_data.position2},uProgress:{value:new u.Pq0(0,0,0)},uDiffuse_star:{value:this.bgFbo.texture},uDiffuse_blue:{value:this.bgFbo_blue.texture}};return e.traverse(e=>{e instanceof u.eaF&&this.createNewMesh(e,r,t,o,n)}),{group4:i,group5:s,mascotCommonUniforms:n}}createNewMesh(e,t,o,s,i){let a=e.geometry,r=e.material,n=o.textures[e.name];if(!n)return;let l=n.ao,c=n.color,h=n.colorVec?n.colorVec:r.color,m=n.matcap,d=l&&this.assets.images[l]?this.assets.images[l].texture:null,v=c&&this.assets.images[c]?this.assets.images[c].texture:null,p={uAo:{value:d},uColor:{value:h},uColorTex:{value:v},uMatcapTex:{value:m&&this.assets.images[m]?this.assets.images[m].texture:null},uTranslate:{value:e.position},uViewDir:{value:this.common.camera.position},...i,...this.commonUniforms},g=new u.BKk({vertexShader:_,fragmentShader:b+w,uniforms:p,transparent:!0,defines:{USE_COLORTEX:!!v,MASCOT_TYPE:"cat"===s?0:"copilot"===s?1:2}});"cat"===s&&(g.blending=u.bCz,g.blendSrc=u.ie2,g.blendDst=u.ojh,g.blendEquation=u.gO9);let f=new u.eaF(a,g);f.position.copy(e.position),f.frustumCulled=!1,t.add(f)}scroll(){}update({ctaAnimTime:e}){this.commonUniforms.uTime.value+=this.common.delta;for(let t=0;t<this.groups.length;t++){let o=this.groups[t];if(!o)return;let s=o.getObjectByName("group4"),i=s.userData.desktopPos;this.common.windowW>=768&&this.common.windowW<=1011&&(i=s.userData.tabletPos);let a=s.getObjectByName("group2");o.position.y=.05*Math.sin(e+o.userData.offsetFloatingY),a.rotation.y=.05*Math.sin(e+o.userData.offsetFloatingY),o.visible=!this.common.isMobile&&this.common.windowH>=640,s.position.lerpVectors(s.userData.startPos,i,s.userData.introPositionProgress.x)}}constructor(e,t,o,s){(0,c._)(this,"group",new u.YJl),(0,c._)(this,"bgFbo",void 0),(0,c._)(this,"bgFbo_blue",void 0),(0,c._)(this,"groups",[]),(0,c._)(this,"commonUniforms",{uTime:{value:0}}),(0,c._)(this,"common",void 0),(0,c._)(this,"assets",void 0),this.common=e,this.assets=t,this.bgFbo=o,this.bgFbo_blue=s,this.group.position.set(0,0,0)}},T=`
varying vec2 vUv;

void main(){
  vUv = uv;
  gl_Position = vec4(position, 1.0);
}
`,S=`
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
`,O=`
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
`,q=`
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
`,k=`
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
`,F=class Background{init(){if(this.bluePlane=new u.eaF(new u.bdM(2,2),new u.BKk({vertexShader:T,fragmentShader:b+S,uniforms:{uColor1:{value:new u.Q1f(920226)},uColor2:{value:new u.Q1f(0x9a7cff)},uResolution:{value:this.blueFboResolution},...this.commonUniforms,uProgress:{value:this.uProgressBackground}},depthTest:!1,depthWrite:!1,transparent:!0,blending:u.bCz,blendEquation:u.gO9,blendSrc:u.qad,blendDst:u.OuU})),this.createStars(),this.camera.position.set(0,0,10),this.common.isReduceMotion)this.uProgressStar.x=1,this.uProgressStar.y=1,this.uProgressBackground.x=1,this.uProgressBackground.y=1,this.uProgressBackground.z=1;else{let e=new z;e.to([this.uProgressStar],1e3,{x:1,easing:"easeOutCubic"},100).to([this.uProgressStar],1e4,{y:1,easing:"easeOutExpo"},0),e.to([this.uProgressBackground],1e3,{x:1,easing:"easeOutCubic"},0).to([this.uProgressBackground],3e3,{y:1,easing:"easeOutCubic"},300).to([this.uProgressBackground],5e3,{z:1,easing:"easeOutCubic",onComplete:()=>{this.common.isFinishedIntroAnim=!0}},0),e.start()}this.resize()}createStars(){let e=new u.bdM(.05,.05),t=new u.CmU;if(e.attributes.position){let o=e.attributes.position.clone();t.setAttribute("position",o)}if(e.attributes.normal){let o=e.attributes.normal.clone();t.setAttribute("normals",o)}if(e.attributes.uv){let o=e.attributes.uv.clone();t.setAttribute("uv",o)}let o=e.index?e.index.clone():null;t.setIndex(o),t.instanceCount=100;let s=new u.uWO(new Float32Array(300),3,!1,1),i=new u.uWO(new Float32Array(300),3,!1,1);t.setAttribute("atranslate",s),t.setAttribute("arandom",i);for(let e=0;e<50;e++){let t=u.cj9.lerp(.25*Math.PI,.75*Math.PI,Math.random());s.setXYZ(e,t,Math.random(),0),i.setXYZ(e,Math.random(),Math.random(),Math.random())}let a=new u.BKk({vertexShader:O,fragmentShader:q,uniforms:{uMask:{value:this.assets.images.star?this.assets.images.star.texture:null},uRadius:{value:2.3},uOffsetY:{value:2.2},uProgress:{value:this.uProgressStar},...this.commonUniforms},transparent:!0,depthTest:!1,depthWrite:!1}),r=new u.eaF(t,a);r.frustumCulled=!1,this.scene.add(r)}createOutputPlane(){this.outputPlane=new u.eaF(new u.bdM(2,2),new u.BKk({vertexShader:T,fragmentShader:k,uniforms:{uDiffuse_star:{value:this.fbo.texture},uDiffuse_blue:{value:this.fbo_blue.texture}},depthTest:!1,depthWrite:!1,transparent:!0}))}resize(){this.fbo.setSize(this.common.fbo_screenSize.x,this.common.fbo_screenSize.y),this.blueFboResolution.set(Math.round(this.common.fbo_screenSize.x*this.fbo_blueRatio),Math.round(this.common.fbo_screenSize.y*this.fbo_blueRatio)),this.fbo_blue.setSize(this.blueFboResolution.x,this.blueFboResolution.y),this.camera.left=-this.common.cameraTop*this.common.aspect,this.camera.right=this.common.cameraTop*this.common.aspect,this.camera.top=this.common.cameraTop,this.camera.bottom=-this.common.cameraTop,this.camera.updateProjectionMatrix()}update({ctaAnimTime:e,ctaAnimationProgress:t}){this.commonUniforms.uTime.value+=this.common.delta,this.commonUniforms.uCtaAnimTime.value=e,this.commonUniforms.uCtaProgress.value=t,this.common.renderer?.setRenderTarget(this.fbo_blue),this.common.renderer?.render(this.bluePlane,this.camera),this.common.renderer?.setRenderTarget(this.fbo),this.common.renderer?.render(this.scene,this.camera),this.commonUniforms.uIsFullWidth.value=+(this.common.screenSize.x<=1246)}constructor(e,t){(0,c._)(this,"fbo_blue",new u.nWS(10,10)),(0,c._)(this,"fbo_blueRatio",.1),(0,c._)(this,"blueFboResolution",new u.I9Y(10,10)),(0,c._)(this,"fbo",new u.nWS(10,10)),(0,c._)(this,"outputPlane",new u.eaF),(0,c._)(this,"bluePlane",new u.eaF),(0,c._)(this,"scene",new u.Z58),(0,c._)(this,"camera",new u.qUd(-1,1,1,-1,.01,200)),(0,c._)(this,"uProgressBackground",new u.IUQ(0,0,0,0)),(0,c._)(this,"uProgressStar",new u.IUQ(0,0,0,0)),(0,c._)(this,"commonUniforms",{uTime:{value:0},uCtaAnimTime:{value:0},uCtaProgress:{value:0},uIsFullWidth:{value:0}}),(0,c._)(this,"common",void 0),(0,c._)(this,"assets",void 0),this.common=e,this.assets=t,this.createOutputPlane()}};var A=new WeakMap,R=new WeakMap,U=new WeakMap,E=new WeakMap,L=new WeakMap,W=new WeakMap,N=new WeakMap,Q=new WeakMap,Y=new WeakMap,V=new WeakMap;let B=class Artwork{init(){(0,r._)(this,W).init({$wrapper:(0,r._)(this,A),$canvas:(0,r._)(this,R)}),(0,r._)(this,E)?.init(),(0,r._)(this,U)?.init(),this.resize()}resize(){(0,r._)(this,W).resize(),(0,r._)(this,E)?.resize(),!this.isRendering&&(0,r._)(this,W).isFinishedIntroAnim&&1!==this.copyProgress.target&&this.render()}scroll(){let e=2*(0,r._)(this,W).cameraTop/(0,r._)(this,W).screenSize.y,t=window.scrollY*e,o=u.cj9.smoothstep(t,0,1),s=u.cj9.smoothstep(t,.6,3);this.mascotProgress.target=o,this.copyProgress.target=s}updateProgress(e,t){e.current!==e.target&&(e.current+=(e.target-e.current)*t,.001>Math.abs(e.current-e.target)&&(e.current=e.target))}render(){(0,r._)(this,E)?.update({ctaAnimTime:(0,r._)(this,V),ctaAnimationProgress:(0,r._)(this,Y)}),(0,r._)(this,U)?.update({ctaAnimTime:(0,r._)(this,V)}),(0,r._)(this,W).renderer?.setRenderTarget(null),(0,r._)(this,W).renderer?.render((0,r._)(this,W).scene,(0,r._)(this,W).camera)}startCtaAnim(){(0,l._)(this,N,!0),(0,l._)(this,Q,!0)}stopCtaAnim(){(0,l._)(this,N,!1)}renderOnce(){this.mascotProgress.target=this.mascotProgress.current=0,this.copyProgress.target=this.copyProgress.current=0,this.render()}update(){(0,r._)(this,W).update();let e=(0,r._)(this,W).getEase(3);this.updateProgress(this.mascotProgress,e),this.updateProgress(this.copyProgress,e),(0,r._)(this,N)?(0,l._)(this,Y,(0,r._)(this,Y)+(1-(0,r._)(this,Y))*e):(0,l._)(this,Y,(0,r._)(this,Y)+(0-(0,r._)(this,Y))*e),.001>(0,r._)(this,Y)&&!(0,r._)(this,N)&&(0,r._)(this,Q)&&((0,l._)(this,Y,0),(0,l._)(this,Q,!1)),(0,l._)(this,V,(0,r._)(this,V)+(0,r._)(this,Y)*(0,r._)(this,W).delta),(this.isRendering||!(0,r._)(this,W).isFinishedIntroAnim||(0,r._)(this,Q))&&this.render(),0===this.mascotProgress.current&&0===this.copyProgress.current&&(this.isRendering=!1)}constructor(e,t,o,s){(0,n._)(this,A,{writable:!0,value:void 0}),(0,n._)(this,R,{writable:!0,value:void 0}),(0,n._)(this,U,{writable:!0,value:void 0}),(0,n._)(this,E,{writable:!0,value:void 0}),(0,n._)(this,L,{writable:!0,value:void 0}),(0,n._)(this,W,{writable:!0,value:void 0}),(0,n._)(this,N,{writable:!0,value:!1}),(0,n._)(this,Q,{writable:!0,value:!1}),(0,n._)(this,Y,{writable:!0,value:0}),(0,n._)(this,V,{writable:!0,value:0}),(0,c._)(this,"mascotProgress",{current:0,target:0}),(0,c._)(this,"copyProgress",{current:0,target:0}),(0,c._)(this,"isRendering",!0),(0,l._)(this,A,e),(0,l._)(this,R,t),(0,l._)(this,W,o),(0,l._)(this,L,s),(0,l._)(this,E,new F((0,r._)(this,W),(0,r._)(this,L))),(0,r._)(this,W).scene.add((0,r._)(this,E).outputPlane),(0,l._)(this,U,new I((0,r._)(this,W),(0,r._)(this,L),(0,r._)(this,E).fbo,(0,r._)(this,E).fbo_blue)),(0,r._)(this,W).camera.position.set(0,0,2.2),(0,r._)(this,W).camera.lookAt((0,r._)(this,W).scene.position),(0,r._)(this,W).scene.add((0,r._)(this,U).group)}},j=class Common{init({$wrapper:e,$canvas:t}){this.pixelRatio=Math.min(1.5,window.devicePixelRatio),this.renderer=new u.S3G({antialias:!0,alpha:!0,canvas:t}),this.renderer.outputEncoding=u.tgE,this.$canvas=this.renderer.domElement,e.appendChild(this.$canvas),this.$wrapper=e,this.renderer.setClearColor(0xffffff,0),this.renderer.setPixelRatio(this.pixelRatio),this.clock=new u.zD7,this.clock.start(),this.resize()}resize(){let e=Math.min(1e3,this.$wrapper?.clientWidth||0),t=this.$wrapper?.clientHeight||0;this.windowW=window.innerWidth,this.windowH=window.innerHeight,this.screenSize_old.copy(this.screenSize),this.screenSize.set(e,t),this.fbo_screenSize.set(e*this.pixelRatio,t*this.pixelRatio),this.aspect=e/t,this.camera.left=-this.cameraTop*this.aspect,this.camera.right=this.cameraTop*this.aspect,this.camera.top=this.cameraTop,this.camera.bottom=-this.cameraTop,this.isMobile=this.windowW<=767,this.camera.updateProjectionMatrix(),this.renderer?.setSize(this.screenSize.x,this.screenSize.y)}getEase(e){return Math.min(1,e*this.delta)}update(){let e=this.clock?.getDelta();e&&(this.delta=e),this.time+=this.delta}constructor({isReduceMotion:e}){(0,c._)(this,"$wrapper",void 0),(0,c._)(this,"$canvas",void 0),(0,c._)(this,"screenSize",new u.I9Y),(0,c._)(this,"screenSize_old",new u.I9Y),(0,c._)(this,"aspect",1),(0,c._)(this,"isMobile",!1),(0,c._)(this,"pixelRatio",1),(0,c._)(this,"camera",new u.qUd(-1,1,1,-1,.01,200)),(0,c._)(this,"scene",new u.Z58),(0,c._)(this,"fbo_screenSize",new u.I9Y),(0,c._)(this,"cameraTop",2.3),(0,c._)(this,"time",0),(0,c._)(this,"delta",0),(0,c._)(this,"windowW",0),(0,c._)(this,"windowH",0),(0,c._)(this,"isFinishedIntroAnim",!1),(0,c._)(this,"startCopyAnimation",void 0),(0,c._)(this,"renderer",void 0),(0,c._)(this,"clock",void 0),(0,c._)(this,"isReduceMotion",void 0),this.isReduceMotion=e}};var K=o(14440);let H={webgl:{alt:"Mona the Octocat, Copilot, and Ducky float jubilantly upward from behind the GitHub product demo accompanied by a purple glow and a scattering of stars."}};function $({setCopyScrollOpacity:e,setCopyScrollScale:t,assetsRef:o}){let s=(0,a.useRef)(null),r=(0,a.useRef)(null),n=(0,a.useRef)(0);return(0,a.useEffect)(()=>{if(!(0,K.ZN)())return;let i=!1,a=!1,l=o=>{(a=o.matches)?(t(1),e(1),m&&m.renderOnce()):g()},c=window.matchMedia("(prefers-reduced-motion: reduce)");c.addEventListener("change",l);let u=new j({isReduceMotion:a=c.matches}),h=o.current;if(!h)return;let m=new B(s.current,r.current,u,h),d=()=>{m.resize(),(a||!m.isRendering)&&m.renderOnce()};window.addEventListener("resize",d);let v=()=>{m.scroll()};window.addEventListener("scroll",v);let p=()=>{!i&&(m.init(),a&&m.renderOnce())};h.isLoaded?p():h.addCallback(p);let g=()=>{if(!a&&m){if(m.update(),u.isMobile)t(1),e(1);else{t(1-.1*m.copyProgress.current),e(1-m.copyProgress.current);let o=1-m.mascotProgress.current,s=1-.1*m.mascotProgress.current;r.current&&(r.current.style.opacity=`${o}`,r.current.style.transform=`scale(${s})`)}n.current=requestAnimationFrame(g)}};g();let f=()=>{!a&&m&&m.startCtaAnim()},x=()=>{!a&&m&&m.stopCtaAnim()},_=document.querySelectorAll(".js-hero-action");for(let e of _)e.addEventListener("mouseenter",f),e.addEventListener("mouseleave",x);let w=()=>{cancelAnimationFrame(n.current)};return window.addEventListener("beforeunload",w),()=>{for(let e of _)e.removeEventListener("mouseenter",f),e.removeEventListener("mouseleave",x);n.current&&cancelAnimationFrame(n.current),i=!0,window.removeEventListener("resize",d),window.removeEventListener("scroll",v),window.removeEventListener("beforeunload",w),c.removeEventListener("change",l)}},[]),(0,i.jsxs)("div",{className:"lp-IntroVisuals",children:[(0,i.jsx)("div",{className:"lp-IntroVisuals-canvasWrapper",ref:s,children:(0,i.jsx)("canvas",{className:"lp-IntroVisuals-canvas",ref:r})}),(0,i.jsx)("div",{className:"sr-only",children:H.webgl.alt})]})}try{$.displayName||($.displayName="IntroHero")}catch{}try{(s=CtaActionRefs).displayName||(s.displayName="CtaActionRefs")}catch{}}}]);
//# sourceMappingURL=packages_landing-pages_routes_home_IntroHero_tsx-12334143a656.js.map
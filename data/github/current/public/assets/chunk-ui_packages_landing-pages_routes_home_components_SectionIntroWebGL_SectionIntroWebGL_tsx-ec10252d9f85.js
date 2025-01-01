"use strict";(globalThis.webpackChunk=globalThis.webpackChunk||[]).push([["ui_packages_landing-pages_routes_home_components_SectionIntroWebGL_SectionIntroWebGL_tsx"],{21974:(e,t,o)=>{o.r(t),o.d(t,{default:()=>I});var s=o(9449),i=o(55293),a=o(39437);let r=class Common{init({$wrapper:e,$canvas:t,$mascot:o}){this.pixelRatio=Math.min(1.5,window.devicePixelRatio),this.$canvas=t,this.$wrapper=e,this.$mascot=o,this.clock=new a.zD7,this.clock.start()}initRenderer(){this.renderer=new a.S3G({antialias:!0,alpha:!0,canvas:this.$canvas}),this.renderer.outputEncoding=a.tgE,this.renderer.setClearColor(0,0),this.renderer.setPixelRatio(this.pixelRatio)}resize(){let e=this.$wrapper?.clientWidth||0,t=this.$wrapper?.clientHeight||0;this.screenSize_old.copy(this.screenSize),this.screenSize.set(e,t),this.fbo_screenSize.set(e*this.pixelRatio,t*this.pixelRatio),this.aspect=e/t,this.camera.left=-this.cameraTop*this.aspect,this.camera.right=this.cameraTop*this.aspect,this.camera.top=this.cameraTop,this.camera.bottom=-this.camera.top,this.camera.updateProjectionMatrix(),this.renderer?.setSize(this.screenSize.x,this.screenSize.y)}scroll(){if(this.$wrapper&&this.$mascot){let e=this.$wrapper.getBoundingClientRect(),t=this.$mascot.getBoundingClientRect();this.mascotAreaOffset.set(t.left-e.left+t.width/2-e.width/2,-(t.top-e.top+t.height/2-e.height/2)-(this.screenSize.y-e.height)*.5),this.wrapperOffset.set(e.left,e.top)}}getEase(e){return Math.min(1,e*this.delta)}update(){let e=this.clock?.getDelta();e&&(this.delta=e),this.time+=this.delta}constructor(){this.screenSize=new a.I9Y,this.screenSize_old=new a.I9Y,this.wrapperOffset=new a.I9Y,this.aspect=1,this.isMobile=!1,this.pixelRatio=1,this.camera=new a.qUd(-1,1,1,-1,.01,200),this.scene=new a.Z58,this.fbo_screenSize=new a.I9Y,this.cameraTop=1.7,this.time=0,this.delta=0,this.mascotAreaOffset=new a.I9Y,this.isReducedMotion=!1}},n=`
uniform vec3 uTranslate;
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

  vec3 e = normalize( mvPosition.xyz );
  vec3 n = vNormal;

  vec3 r = reflect( e, normalize(n + position * 0.5) );
  float m = 2. * sqrt( pow( r.x, 2. ) + pow( r.y, 2. ) + pow( r.z + 1., 2. ) );
  vN = r.xy / m + .5;

  gl_Position = projectionMatrix * mvPosition;
}
`,c=`
uniform sampler2D uAo;
uniform sampler2D uColorTex;
uniform sampler2D uMatcapTex;
uniform vec3 uLightPos;

uniform vec3 uColor;
uniform float uTime;
uniform vec2 uResolution;

varying vec3 vWorldPosition;
varying vec3 vMVPosition;

varying vec2 vUv;
varying vec3 vNormal;
varying vec2 vN;

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

  vec3 r = vNormal;
  float m = 2.8284271247461903 * sqrt( r.z+1.0 );
  vec2 matcapUv = r.xy / m + .5;

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
    float noise = snoise3D(vWorldPosition * 0.6 + 0.5) * 0.5 + 0.5;

    color_ao.r += mix(-0.1, 0.05, noise);
    color_ao.g += mix(0.0, 0.3, matcap.g) + 0.05;
    color_ao.b += mix(-0.3, 0.3, matcap.g) + 0.3;
  #endif

  color_ao = hsv2rgb(color_ao);
  color = color_ao + lightIntensity;

  color = clamp(vec3(0.0), vec3(1.0), color);

  gl_FragColor = vec4(color, 1.0);
}
`,l=`
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
`,h={linear:e=>e,easeInSine:e=>-1*Math.cos(Math.PI/2*e)+1,easeOutSine:e=>Math.sin(Math.PI/2*e),easeInOutSine:e=>-.5*(Math.cos(Math.PI*e)-1),easeInQuad:e=>e*e,easeOutQuad:e=>e*(2-e),easeInOutQuad:e=>e<.5?2*e*e:-1+(4-2*e)*e,easeInCubic:e=>e*e*e,easeOutCubic(e){let t=e-1;return t*t*t+1},easeInOutCubic:e=>e<.5?4*e*e*e:(e-1)*(2*e-2)*(2*e-2)+1,easeInQuart:e=>e*e*e*e,easeOutQuart(e){let t=e-1;return 1-t*t*t*t},easeInOutQuart(e){let t=e-1;return e<.5?8*e*e*e*e:1-8*t*t*t*t},easeInQuint:e=>e*e*e*e*e,easeOutQuint(e){let t=e-1;return 1+t*t*t*t*t},easeInOutQuint(e){let t=e-1;return e<.5?16*e*e*e*e*e:1+16*t*t*t*t*t},easeInExpo:e=>0===e?0:Math.pow(2,10*(e-1)),easeOutExpo:e=>1===e?1:-Math.pow(2,-10*e)+1,easeInOutExpo(e){if(0===e||1===e)return e;let t=2*e,o=t-1;return t<1?.5*Math.pow(2,10*o):.5*(-Math.pow(2,-10*o)+2)},easeInCirc:e=>-1*(Math.sqrt(1-e/1*e)-1),easeOutCirc(e){let t=e-1;return Math.sqrt(1-t*t)},easeInOutCirc(e){let t=2*e,o=t-2;return t<1?-.5*(Math.sqrt(1-t*t)-1):.5*(Math.sqrt(1-o*o)+1)},easeInBack:(e,t=1.70158)=>e*e*((t+1)*e-t),easeOutBack(e,t=1.70158){let o=e/1-1;return o*o*((t+1)*o+t)+1},easeInOutBack(e,t=1.70158){let o=2*e,s=o-2,i=1.525*t;return o<1?.5*o*o*((i+1)*o-i):.5*(s*s*((i+1)*s+i)+2)},easeInElastic(e,t=.7){if(0===e||1===e)return e;let o=e/1-1,s=1-t;return-(Math.pow(2,10*o)*Math.sin(2*Math.PI*(o-s/(2*Math.PI)*Math.asin(1))/s))},easeOutElastic(e,t=.7){if(0===e||1===e)return e;let o=1-t,s=2*e;return Math.pow(2,-10*s)*Math.sin(2*Math.PI*(s-o/(2*Math.PI)*Math.asin(1))/o)+1},easeInOutElastic(e,t=.65){if(0===e||1===e)return e;let o=1-t,s=2*e,i=s-1,a=o/(2*Math.PI)*Math.asin(1);return s<1?-(Math.pow(2,10*i)*Math.sin(2*Math.PI*(i-a)/o)*.5):Math.pow(2,-10*i)*Math.sin(2*Math.PI*(i-a)/o)*.5+1},easeOutBounce(e){let t=e/1;if(t<1/2.75)return 7.5625*t*t;if(t<2/2.75){let e=t-1.5/2.75;return 7.5625*e*e+.75}if(t<2.5/2.75){let e=t-2.25/2.75;return 7.5625*e*e+.9375}{let e=t-2.625/2.75;return 7.5625*e*e+.984375}},easeInBounce(e){return 1-this.easeOutBounce(1-e)},easeInOutBounce(e){return e<.5?.5*this.easeInBounce(2*e):.5*this.easeOutBounce(2*e-1)+.5}},m=class Timeline{to(e,t,o,s=0){return this._to(e,t,o,s),this}_to(e,t,o,s){let i=0;if(isNaN(s)){if(this.animations.length>0){let e=this.animations[this.animations.length-1];e&&(i=e.duration+e.delay)}}else i=s;i+=this.delay;let a={datas:Array.isArray(e)?e:[e],duration:t,easing:o.easing||this.easing,onComplete:o.onComplete,onUpdate:o.onUpdate,values:[],delay:i,properties:o,isStarted:!1};this.animations.push(a);let r=0;for(let e=0;e<this.animations.length;e++){let t=this.animations[e];if(!t)continue;let o=t.duration+t.delay;r<o&&(r=o,this.lastIndex=e),t.isLast=!1}return a}start(){if(-1===this.lastIndex)return;this.startTime=new Date,this.oldTime=new Date;let e=this.animations[this.lastIndex];e&&(e.isLast=!0),window.addEventListener("visibilitychange",this.onVisiblitychange),this.animate()}arrangeDatas(e){let{properties:t,datas:o,values:s}=e;for(let e in t){let i=0,a=[],r=[],n=[];switch(e){case"easing":case"onComplete":case"onUpdate":break;default:for(let s of o)null!==s&&"object"==typeof s&&(a[i]=s[e],r[i]=s[e],n[i]=t[e],i++);s.push({key:e,start:a,current:r,end:n})}}}calcProgress(e,t,o){return Math.max(0,Math.min(1,(o-e)/(t-e)))}calcLerp(e,t,o){return e+(t-e)*o}constructor(e={}){this.animate=()=>{let e=new Date;if(this.isWindowFocus||(this.oldTime=e),this.oldTime){let t=e.getTime()-this.oldTime.getTime();this.time+=t}for(let t of(this.oldTime=e,this.animations)){let{datas:e,duration:o,easing:s,values:i,delay:a}=t;if(this.time>a&&!t.isFinished){t.isStarted||(t.isStarted=!0,this.arrangeDatas(t));let r=this.calcProgress(0,o,this.time-a);r=h[s](r);for(let t=0;t<i.length;t++){let o=i[t];if(o)for(let t=0;t<e.length;t++){let s=e[t];o.current[t]=this.calcLerp(o.start[t],o.end[t],r),"object"==typeof s&&null!==s&&(s[o.key]=o.current[t])}}if(t.onUpdate&&t.onUpdate(),1===r&&(t.isFinished=!0,t.onComplete&&t.onComplete(),t.isLast)){this.isFinished=!0;return}}}this.isFinished?(window.removeEventListener("visibilitychange",this.onVisiblitychange),this.onComplete()):(this.onUpdate(),requestAnimationFrame(this.animate))},this.onVisiblitychange=()=>{"visible"===document.visibilityState?this.isWindowFocus=!0:this.isWindowFocus=!1},this.easing=e.easing||"linear",this.options=e,this.onUpdate=e.onUpdate||function(){},this.onComplete=e.onComplete||function(){},this.delay=e.delay||0,this.isFinished=!1,this.lastIndex=-1,this.isWindowFocus=!0,this.animations=[],this.time=0}},u=class MascotObj{init(){let e=this.gltfs[this.name],t=new a.YJl;this.group2.add(t),e&&e.scene&&e.scene.traverse(e=>{e instanceof a.eaF&&this.createNewMesh(e,t)})}createNewMesh(e,t){let o=e.geometry,s=e.material,i=this.mascotData[e.name];if(!i)return;let r=i.ao,h=i.color,m=i.colorVec?i.colorVec:s.color,u=i.matcap,p=r&&this.images[r]?this.images[r].texture:null,v=h&&this.images[h]?this.images[h].texture:null,d={uAo:{value:p},uColor:{value:m},uColorTex:{value:v},uMatcapTex:{value:u&&this.images[u]?this.images[u].texture:null},uTranslate:{value:e.position},uLightPos:{value:new a.Pq0(-1,1,3)},...this.commonUniforms},x=-1;switch(this.name){case"cat":x=0;break;case"copilot":x=1,t.position.y=-.05;break;case"duck":x=2,t.scale.set(1.4,1.4,1.4)}let g=new a.BKk({vertexShader:n,fragmentShader:l+c,uniforms:d,transparent:!0,defines:{USE_COLORTEX:!!v,MASCOT_TYPE:x}}),f=new a.eaF(o,g);f.position.copy(e.position),t.add(f)}resetLookat(){this.lookatTarget.set(0,0,1),this.group.lookAt(this.lookatTarget)}show(e){e||(this.group2.scale.set(0,0,0),new m().to([this.group2.scale],600,{x:1,y:1,z:1,easing:"easeOutCubic"},0).start())}update(e,t,o){let s=e.length();this.mouseIntensity.target=a.cj9.smootherstep(2,1,s),this.mouseIntensity.current+=(this.mouseIntensity.target-this.mouseIntensity.current)*this.common.getEase(3),o?this.lookatTarget.set(0,0,1).add(this.group.position):this.lookatTarget.set(.3*t.x,.3*t.y,1).multiplyScalar(this.mouseIntensity.current).add(this.group.position),this.group.lookAt(this.lookatTarget)}constructor(e,t,o,s){this.group=new a.YJl,this.group2=new a.YJl,this.commonUniforms={uResolution:{value:new a.I9Y}},this.lookatTarget=new a.Pq0(0,0,0),this.mouseIntensity={target:0,current:0},this.group.add(this.group2),this.name=e,this.common=t,this.gltfs=o.gltfs,this.images=o.images,this.mascotData=s,this.commonUniforms.uResolution.value=this.common.fbo_screenSize}},p=`
uniform sampler2D uMatcapTex;
uniform sampler2D uAo;
uniform sampler2D uDiffuse;

varying vec3 vWorldPosition;
varying vec3 vMVPosition;
varying vec2 vUv;
varying vec3 vNormal;

vec3 blendSoftLight(vec3 base, vec3 blend) {
    return mix(
        sqrt(base) * (2.0 * blend - 1.0) + 2.0 * base * (1.0 - blend),
        2.0 * base * blend + base * base * (1.0 - 2.0 * blend),
        step(base, vec3(0.5))
    );
}

float fresnelEffect(vec3 Normal, vec3 ViewDir, float Power)
{
    return pow((1.0 - clamp(dot(normalize(Normal), normalize(ViewDir)), 0.0, 1.0)), Power);
}

void main(){
  vec3 matcap = texture2D(uMatcapTex, vUv).rgb;
  vec3 ao = texture2D(uAo, vUv).rgb;
  vec3 diffuse = texture2D(uDiffuse, vUv).rgb;

  vec3 color = diffuse * ao;

  float noise = snoise3D(vWorldPosition * 3.0 + 1.0) * 0.5 + 0.5;

  float fresnel = fresnelEffect(vNormal, vec3(0.0, 0.0, 1.0), 0.3);

  vec3 hsv = rgb2hsv(color);
  hsv.r += mix(-0.12, 0.0, smoothstep(0.0, 0.6, noise));
  color = hsv2rgb(hsv);

  color = mix(color, color + 0.5, fresnel);

  gl_FragColor = vec4(color, 1.0);
}
`,v=`
varying vec2 vUv;

void main(){
  vUv = uv;
  gl_Position = projectionMatrix * viewMatrix * modelMatrix * vec4(position, 1.0);
}
`,d=`
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

`,x=class ShieldObj{init(){let e=this.images.shield_blur?this.images.shield_blur.texture:null;this.blurMesh=new a.eaF(new a.bdM(.47,.47),new a.BKk({vertexShader:v,fragmentShader:d,uniforms:{uAlpha:{value:e},uColor1:{value:new a.Q1f(1052926)},uColor2:{value:new a.Q1f(9560031)},uProgress:{value:this.progress}},transparent:!0})),this.blurMesh.position.set(0,-.01,-4),this.group2.add(this.blurMesh);let t=this.gltfs[this.name];t&&t.scene&&t.scene.traverse(e=>{if(e instanceof a.eaF){let t=e.geometry,o=this.images.matcap_mascot?this.images.matcap_mascot.texture:null,s=this.images.shield_sss?this.images.shield_sss.texture:null,i=this.images.shield_diffuse?this.images.shield_diffuse.texture:null,r=new a.BKk({vertexShader:n,fragmentShader:l+p,uniforms:{uMatcapTex:{value:o},uAo:{value:s},uDiffuse:{value:i}},transparent:!0}),c=new a.eaF(t,r);c.scale.set(2.5,2.5,2.5),this.group2.add(c)}})}show(e){e?this.blurMesh&&(this.blurMesh.visible=!1):(this.group2.scale.set(0,0,0),new m().to([this.group2.scale],400,{x:1,y:1,z:1,easing:"easeOutCubic"},0).to([this.progress],4e3,{x:5,easing:"easeOutCubic"},0).to([this.progress],1e3,{y:1,easing:"easeOutCubic"},3e3).to([this.progress],4e3,{z:1,easing:"easeOutCubic"},3500).start())}constructor(e,t){this.name="shield",this.group=new a.YJl,this.group2=new a.YJl,this.progress=new a.Pq0(0,0,0),this.common=e,this.gltfs=t.gltfs,this.images=t.images,this.group.add(this.group2)}},g={nose:{ao:"cat_head_ao",color:null,colorVec:new a.Q1f(0),matcap:"matcap_mascot"},eye:{ao:"cat_eye_ao",color:"cat_eye_color",colorVec:new a.Q1f(0),matcap:"matcap_cateye"},face:{ao:"cat_head_ao",color:null,colorVec:new a.Q1f(16748502),matcap:"matcap_mascot"},head:{ao:"cat_head_ao",color:null,colorVec:new a.Q1f(16212929),matcap:"matcap_mascot"},eyeball:{ao:"cat_head_ao",color:null,colorVec:new a.Q1f(16777215),matcap:"matcap_mascot"}},f=new a.Q1f(10376696),y={eyes:{ao:"copilot_head_ao",color:null,colorVec:new a.Q1f(3761135),matcap:"matcap_mascot"},face:{ao:"copilot_head_ao",color:null,colorVec:new a.Q1f(328013),matcap:"matcap_mascot"},glass:{ao:"copilot_head_ao",color:null,colorVec:new a.Q1f(6497712),matcap:"matcap_mascot"},goggle:{ao:"copilot_head_ao",color:null,colorVec:new a.Q1f(10050531),matcap:"matcap_mascot"},head:{ao:"copilot_head_ao",color:null,colorVec:f,matcap:"matcap_mascot"}},w={body:{ao:"duck_body_ao",color:null,colorVec:new a.Q1f(16100915),matcap:"matcap_mascot"},beak:{ao:"duck_body_ao",color:null,colorVec:new a.Q1f(16100915),matcap:"matcap_mascot"},eyes:{ao:"duck_body_ao",color:null,colorVec:new a.Q1f(0),matcap:"matcap_mascot"},eyeballs:{ao:"duck_body_ao",color:null,colorVec:new a.Q1f(0),matcap:"matcap_mascot"}},b=class Mouse{init(){window.addEventListener("mousemove",e=>{if(!this.common)return;let t=(e.clientX-this.common?.wrapperOffset.x+this.common?.mascotAreaOffset.x)/this.common?.screenSize.x;t=(t-.5)*2;let o=(e.clientY-this.common?.wrapperOffset.y+this.common?.mascotAreaOffset.y)/this.common?.screenSize.y;o=(.5-o)*2,t=Math.max(-1,Math.min(1,t)),o=Math.max(-1,Math.min(1,o)),this.updateMousePos(t,o)})}updateMousePos(e,t){this.pos.target.set(e,t)}resize(){}update(){this.common&&(this.pos.current.lerp(this.pos.target,this.common.getEase(2)),this.pos.current2.lerp(this.pos.target,this.common.getEase(1.5)))}constructor(e){this.common=e,this.originalPos=new a.I9Y,this.pos={target:new a.I9Y(0,0),current:new a.I9Y(0,0),current2:new a.I9Y(0,0)}}},_=class Artwork{toggleVisibility(e,t){e&&!this.isFirstShow&&(this.isFirstShow=!0,this.init(),this.resize(),this.mascot?.show(t),this.shield?.show(t),this.common.startCopyAnimation&&this.common.startCopyAnimation())}setStartCopyAnimation(e){this.common.startCopyAnimation=e}load(){this.isLoaded=!0}init(){this.common.initRenderer(),this.common.resize(),this.mascot?.init(),this.shield?.init()}resize(){this.common.resize()}scroll(){this.common.scroll()}resetMouse(){this.mascot?.resetLookat()}update({isReducedMotion:e}){this.common.update(),this.mouse.update(),this.mascot?.update(this.mouse.pos.target,this.mouse.pos.current,e),this.common.renderer?.setRenderTarget(null),this.common.renderer?.render(this.common.scene,this.common.camera)}constructor(e,t,o,s,i,a,n){switch(this.common=new r,this.mouse=new b(this.common),this.isFirstShow=!1,this.isLoaded=!1,this.$wrapper=e,this.$canvas=t,this.$mascot=o,this.name=s,this.isMascotOnly=i,this.common.isReducedMotion=a,!this.isMascotOnly&&this.common.isReducedMotion&&(this.isFirstShow=!0),this.assets=n,this.name){case"mona":this.mascot=new u("cat",this.common,this.assets,g),this.common.scene.add(this.mascot.group);break;case"copilot":this.mascot=new u("copilot",this.common,this.assets,y),this.common.scene.add(this.mascot.group);break;case"ducky":this.mascot=new u("duck",this.common,this.assets,w),this.common.scene.add(this.mascot.group);break;case"shield":this.shield=new x(this.common,this.assets),this.common.scene.add(this.shield.group)}this.isMascotOnly&&(this.mascot&&this.mascot.group.scale.set(9,9,9),this.shield&&this.shield.group.scale.set(9,9,9)),this.common.init({$wrapper:this.$wrapper,$canvas:this.$canvas,$mascot:this.$mascot}),this.mouse.init(),this.common.camera.position.set(0,0,2.2),this.common.camera.lookAt(this.common.scene.position)}};var M=o(49201);let z=({mascotName:e,mascotRef:t,containerRef:o,isMascotOnly:a,startCopyAnimation:r,assetsRef:n})=>{let c=(0,i.useRef)(null),l=(0,i.useRef)(null),h=(0,i.useRef)(0);return(0,i.useEffect)(()=>{if(!(0,M.ZN)())return r();let s=null,i=!1,m=!1,u=!1,p=e=>{(u=e.matches)?s&&s.update({isReducedMotion:!0}):i&&g()},v=window.matchMedia("(prefers-reduced-motion: reduce)");v.addEventListener("change",p),u=v.matches;let d=()=>{if(t.current&&o.current&&l.current){let e=t.current.getBoundingClientRect(),i=o.current.getBoundingClientRect(),a=e.top-i.top,r=e.width,n=e.height;l.current.style.height=`${n+20}px`,l.current.style.width=`${r+20}px`,l.current.style.top=`${a-10}px`,l.current.style.left=`${e.left-i.left-10}px`,s&&s.resize()}};if(l.current&&c.current&&t.current){let o=n.current;if(!o)return;(s=new _(l.current,c.current,t.current,e,a,u,o)).setStartCopyAnimation(r),o.addCallback(()=>{!m&&(s&&i&&s.toggleVisibility(!0,u),u&&s&&(r(),s.update({isReducedMotion:!0})))})}d();let x=()=>{s&&i&&!u&&s.scroll()};window.addEventListener("resize",d),window.addEventListener("scroll",x);let g=()=>{u||(s&&s.update({isReducedMotion:!1}),h.current=requestAnimationFrame(g))},f=new IntersectionObserver(e=>{for(let t of e){let e=n.current;if(u){t.isIntersecting&&s&&e?.isLoaded&&(s.toggleVisibility(t.isIntersecting,!0),s.update({isReducedMotion:!0}));return}t.isIntersecting?(s&&e?.isLoaded&&s.toggleVisibility(t.isIntersecting,!1),h.current||g(),i=!0):(h.current&&(cancelAnimationFrame(h.current),h.current=0),i=!1)}},{threshold:.1});return c.current&&f.observe(c.current),()=>{h.current&&cancelAnimationFrame(h.current),m=!0,window.removeEventListener("resize",d),window.removeEventListener("scroll",x),v.removeEventListener("change",p),f.disconnect()}},[]),(0,s.jsx)("div",{className:"lp-SectionIntroWebGL",ref:l,children:(0,s.jsx)("canvas",{className:"lp-SectionIntroWebGL-canvas",ref:c})})},I=z;try{z.displayName||(z.displayName="SectionIntroWebGL")}catch{}}}]);
//# sourceMappingURL=ui_packages_landing-pages_routes_home_components_SectionIntroWebGL_SectionIntroWebGL_tsx-535b02590965.js.map
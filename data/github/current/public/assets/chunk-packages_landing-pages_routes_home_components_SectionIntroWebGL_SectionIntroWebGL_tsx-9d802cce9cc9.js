"use strict";(globalThis.webpackChunk_github_ui_github_ui=globalThis.webpackChunk_github_ui_github_ui||[]).push([["packages_landing-pages_routes_home_components_SectionIntroWebGL_SectionIntroWebGL_tsx"],{11142:(e,t,i)=>{i.r(t),i.d(t,{default:()=>$});var s=i(74848),o=i(96540),a=i(35750),r=i(18150),n=i(85242),c=i(50467),l=i(39437);let h=class Common{init({$wrapper:e,$canvas:t,$mascot:i}){this.pixelRatio=Math.min(1.5,window.devicePixelRatio),this.$canvas=t,this.$wrapper=e,this.$mascot=i,this.clock=new l.zD7,this.clock.start()}initRenderer(){this.renderer=new l.S3G({antialias:!0,alpha:!0,canvas:this.$canvas}),this.renderer.outputEncoding=l.tgE,this.renderer.setClearColor(0,0),this.renderer.setPixelRatio(this.pixelRatio)}resize(){let e=this.$wrapper?.clientWidth||0,t=this.$wrapper?.clientHeight||0;this.screenSize_old.copy(this.screenSize),this.screenSize.set(e,t),this.fbo_screenSize.set(e*this.pixelRatio,t*this.pixelRatio),this.aspect=e/t,this.camera.left=-this.cameraTop*this.aspect,this.camera.right=this.cameraTop*this.aspect,this.camera.top=this.cameraTop,this.camera.bottom=-this.camera.top,this.camera.updateProjectionMatrix(),this.renderer?.setSize(this.screenSize.x,this.screenSize.y)}scroll(){if(this.$wrapper&&this.$mascot){let e=this.$wrapper.getBoundingClientRect(),t=this.$mascot.getBoundingClientRect();this.mascotAreaOffset.set(t.left-e.left+t.width/2-e.width/2,-(t.top-e.top+t.height/2-e.height/2)-(this.screenSize.y-e.height)*.5),this.wrapperOffset.set(e.left,e.top)}}getEase(e){return Math.min(1,e*this.delta)}update(){let e=this.clock?.getDelta();e&&(this.delta=e),this.time+=this.delta}constructor(){(0,c._)(this,"$wrapper",void 0),(0,c._)(this,"$canvas",void 0),(0,c._)(this,"screenSize",new l.I9Y),(0,c._)(this,"screenSize_old",new l.I9Y),(0,c._)(this,"wrapperOffset",new l.I9Y),(0,c._)(this,"aspect",1),(0,c._)(this,"isMobile",!1),(0,c._)(this,"pixelRatio",1),(0,c._)(this,"camera",new l.qUd(-1,1,1,-1,.01,200)),(0,c._)(this,"scene",new l.Z58),(0,c._)(this,"fbo_screenSize",new l.I9Y),(0,c._)(this,"cameraTop",1.7),(0,c._)(this,"time",0),(0,c._)(this,"delta",0),(0,c._)(this,"mascotAreaOffset",new l.I9Y),(0,c._)(this,"renderer",void 0),(0,c._)(this,"clock",void 0),(0,c._)(this,"isReducedMotion",!1)}},u=`
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
`,m=`
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
`,v=`
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
`;var p=i(88243),d=i(16213);let _={linear:e=>e,easeInSine:e=>-1*Math.cos(Math.PI/2*e)+1,easeOutSine:e=>Math.sin(Math.PI/2*e),easeInOutSine:e=>-.5*(Math.cos(Math.PI*e)-1),easeInQuad:e=>e*e,easeOutQuad:e=>e*(2-e),easeInOutQuad:e=>e<.5?2*e*e:-1+(4-2*e)*e,easeInCubic:e=>e*e*e,easeOutCubic(e){let t=e-1;return t*t*t+1},easeInOutCubic:e=>e<.5?4*e*e*e:(e-1)*(2*e-2)*(2*e-2)+1,easeInQuart:e=>e*e*e*e,easeOutQuart(e){let t=e-1;return 1-t*t*t*t},easeInOutQuart(e){let t=e-1;return e<.5?8*e*e*e*e:1-8*t*t*t*t},easeInQuint:e=>e*e*e*e*e,easeOutQuint(e){let t=e-1;return 1+t*t*t*t*t},easeInOutQuint(e){let t=e-1;return e<.5?16*e*e*e*e*e:1+16*t*t*t*t*t},easeInExpo:e=>0===e?0:Math.pow(2,10*(e-1)),easeOutExpo:e=>1===e?1:-Math.pow(2,-10*e)+1,easeInOutExpo(e){if(0===e||1===e)return e;let t=2*e,i=t-1;return t<1?.5*Math.pow(2,10*i):.5*(-Math.pow(2,-10*i)+2)},easeInCirc:e=>-1*(Math.sqrt(1-e/1*e)-1),easeOutCirc(e){let t=e-1;return Math.sqrt(1-t*t)},easeInOutCirc(e){let t=2*e,i=t-2;return t<1?-.5*(Math.sqrt(1-t*t)-1):.5*(Math.sqrt(1-i*i)+1)},easeInBack:(e,t=1.70158)=>e*e*((t+1)*e-t),easeOutBack(e,t=1.70158){let i=e/1-1;return i*i*((t+1)*i+t)+1},easeInOutBack(e,t=1.70158){let i=2*e,s=i-2,o=1.525*t;return i<1?.5*i*i*((o+1)*i-o):.5*(s*s*((o+1)*s+o)+2)},easeInElastic(e,t=.7){if(0===e||1===e)return e;let i=e/1-1,s=1-t;return-(Math.pow(2,10*i)*Math.sin(2*Math.PI*(i-s/(2*Math.PI)*Math.asin(1))/s))},easeOutElastic(e,t=.7){if(0===e||1===e)return e;let i=1-t,s=2*e;return Math.pow(2,-10*s)*Math.sin(2*Math.PI*(s-i/(2*Math.PI)*Math.asin(1))/i)+1},easeInOutElastic(e,t=.65){if(0===e||1===e)return e;let i=1-t,s=2*e,o=s-1,a=i/(2*Math.PI)*Math.asin(1);return s<1?-(Math.pow(2,10*o)*Math.sin(2*Math.PI*(o-a)/i)*.5):Math.pow(2,-10*o)*Math.sin(2*Math.PI*(o-a)/i)*.5+1},easeOutBounce(e){let t=e/1;if(t<1/2.75)return 7.5625*t*t;if(t<2/2.75){let e=t-1.5/2.75;return 7.5625*e*e+.75}if(t<2.5/2.75){let e=t-2.25/2.75;return 7.5625*e*e+.9375}{let e=t-2.625/2.75;return 7.5625*e*e+.984375}},easeInBounce(e){return 1-this.easeOutBounce(1-e)},easeInOutBounce(e){return e<.5?.5*this.easeInBounce(2*e):.5*this.easeOutBounce(2*e-1)+.5}};var g=new WeakSet;let x=class Timeline{to(e,t,i,s=0){return(0,p._)(this,g,f).call(this,e,t,i,s),this}start(){if(-1===this.lastIndex)return;this.startTime=new Date,this.oldTime=new Date;let e=this.animations[this.lastIndex];e&&(e.isLast=!0),window.addEventListener("visibilitychange",this.onVisiblitychange),this.animate()}arrangeDatas(e){let{properties:t,datas:i,values:s}=e;for(let e in t){let o=0,a=[],r=[],n=[];switch(e){case"easing":case"onComplete":case"onUpdate":break;default:for(let s of i)null!==s&&"object"==typeof s&&(a[o]=s[e],r[o]=s[e],n[o]=t[e],o++);s.push({key:e,start:a,current:r,end:n})}}}calcProgress(e,t,i){return Math.max(0,Math.min(1,(i-e)/(t-e)))}calcLerp(e,t,i){return e+(t-e)*i}constructor(e={}){(0,d._)(this,g),(0,c._)(this,"easing",void 0),(0,c._)(this,"options",void 0),(0,c._)(this,"onUpdate",void 0),(0,c._)(this,"onComplete",void 0),(0,c._)(this,"delay",void 0),(0,c._)(this,"isFinished",void 0),(0,c._)(this,"lastIndex",void 0),(0,c._)(this,"isWindowFocus",void 0),(0,c._)(this,"animations",void 0),(0,c._)(this,"startTime",void 0),(0,c._)(this,"oldTime",void 0),(0,c._)(this,"time",void 0),(0,c._)(this,"animate",()=>{let e=new Date;if(this.isWindowFocus||(this.oldTime=e),this.oldTime){let t=e.getTime()-this.oldTime.getTime();this.time+=t}for(let t of(this.oldTime=e,this.animations)){let{datas:e,duration:i,easing:s,values:o,delay:a}=t;if(this.time>a&&!t.isFinished){t.isStarted||(t.isStarted=!0,this.arrangeDatas(t));let r=this.calcProgress(0,i,this.time-a);r=_[s](r);for(let t=0;t<o.length;t++){let i=o[t];if(i)for(let t=0;t<e.length;t++){let s=e[t];i.current[t]=this.calcLerp(i.start[t],i.end[t],r),"object"==typeof s&&null!==s&&(s[i.key]=i.current[t])}}if(t.onUpdate&&t.onUpdate(),1===r&&(t.isFinished=!0,t.onComplete&&t.onComplete(),t.isLast)){this.isFinished=!0;return}}}this.isFinished?(window.removeEventListener("visibilitychange",this.onVisiblitychange),this.onComplete()):(this.onUpdate(),requestAnimationFrame(this.animate))}),(0,c._)(this,"onVisiblitychange",()=>{"visible"===document.visibilityState?this.isWindowFocus=!0:this.isWindowFocus=!1}),this.easing=e.easing||"linear",this.options=e,this.onUpdate=e.onUpdate||function(){},this.onComplete=e.onComplete||function(){},this.delay=e.delay||0,this.isFinished=!1,this.lastIndex=-1,this.isWindowFocus=!0,this.animations=[],this.time=0}};function f(e,t,i,s){let o=0;if(isNaN(s)){if(this.animations.length>0){let e=this.animations[this.animations.length-1];e&&(o=e.duration+e.delay)}}else o=s;o+=this.delay;let a={datas:Array.isArray(e)?e:[e],duration:t,easing:i.easing||this.easing,onComplete:i.onComplete,onUpdate:i.onUpdate,values:[],delay:o,properties:i,isStarted:!1};this.animations.push(a);let r=0;for(let e=0;e<this.animations.length;e++){let t=this.animations[e];if(!t)continue;let i=t.duration+t.delay;r<i&&(r=i,this.lastIndex=e),t.isLast=!1}return a}let w=class MascotObj{init(){let e=this.gltfs[this.name],t=new l.YJl;this.group2.add(t),e&&e.scene&&e.scene.traverse(e=>{e instanceof l.eaF&&this.createNewMesh(e,t)})}createNewMesh(e,t){let i=e.geometry,s=e.material,o=this.mascotData[e.name];if(!o)return;let a=o.ao,r=o.color,n=o.colorVec?o.colorVec:s.color,c=o.matcap,h=a&&this.images[a]?this.images[a].texture:null,p=r&&this.images[r]?this.images[r].texture:null,d={uAo:{value:h},uColor:{value:n},uColorTex:{value:p},uMatcapTex:{value:c&&this.images[c]?this.images[c].texture:null},uTranslate:{value:e.position},uLightPos:{value:new l.Pq0(-1,1,3)},...this.commonUniforms},_=-1;switch(this.name){case"cat":_=0;break;case"copilot":_=1,t.position.y=-.05;break;case"duck":_=2,t.scale.set(1.4,1.4,1.4)}let g=new l.BKk({vertexShader:u,fragmentShader:v+m,uniforms:d,transparent:!0,defines:{USE_COLORTEX:!!p,MASCOT_TYPE:_}}),x=new l.eaF(i,g);x.position.copy(e.position),t.add(x)}resetLookat(){this.lookatTarget.set(0,0,1),this.group.lookAt(this.lookatTarget)}show(e){e||(this.group2.scale.set(0,0,0),new x().to([this.group2.scale],600,{x:1,y:1,z:1,easing:"easeOutCubic"},0).start())}update(e,t,i){let s=e.length();this.mouseIntensity.target=l.cj9.smootherstep(2,1,s),this.mouseIntensity.current+=(this.mouseIntensity.target-this.mouseIntensity.current)*this.common.getEase(3),i?this.lookatTarget.set(0,0,1).add(this.group.position):this.lookatTarget.set(.3*t.x,.3*t.y,1).multiplyScalar(this.mouseIntensity.current).add(this.group.position),this.group.lookAt(this.lookatTarget)}constructor(e,t,i,s){(0,c._)(this,"name",void 0),(0,c._)(this,"common",void 0),(0,c._)(this,"group",new l.YJl),(0,c._)(this,"group2",new l.YJl),(0,c._)(this,"gltfs",void 0),(0,c._)(this,"images",void 0),(0,c._)(this,"mascotData",void 0),(0,c._)(this,"commonUniforms",{uResolution:{value:new l.I9Y}}),(0,c._)(this,"lookatTarget",new l.Pq0(0,0,0)),(0,c._)(this,"mouseIntensity",{target:0,current:0}),this.group.add(this.group2),this.name=e,this.common=t,this.gltfs=i.gltfs,this.images=i.images,this.mascotData=s,this.commonUniforms.uResolution.value=this.common.fbo_screenSize}},y=`
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
`,b=`
varying vec2 vUv;

void main(){
  vUv = uv;
  gl_Position = projectionMatrix * viewMatrix * modelMatrix * vec4(position, 1.0);
}
`,M=`
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

`,z=class ShieldObj{init(){let e=this.images.shield_blur?this.images.shield_blur.texture:null;this.blurMesh=new l.eaF(new l.bdM(.47,.47),new l.BKk({vertexShader:b,fragmentShader:M,uniforms:{uAlpha:{value:e},uColor1:{value:new l.Q1f(1052926)},uColor2:{value:new l.Q1f(9560031)},uProgress:{value:this.progress}},transparent:!0})),this.blurMesh.position.set(0,-.01,-4),this.group2.add(this.blurMesh);let t=this.gltfs[this.name];t&&t.scene&&t.scene.traverse(e=>{if(e instanceof l.eaF){let t=e.geometry,i=this.images.matcap_mascot?this.images.matcap_mascot.texture:null,s=this.images.shield_sss?this.images.shield_sss.texture:null,o=this.images.shield_diffuse?this.images.shield_diffuse.texture:null,a=new l.BKk({vertexShader:u,fragmentShader:v+y,uniforms:{uMatcapTex:{value:i},uAo:{value:s},uDiffuse:{value:o}},transparent:!0}),r=new l.eaF(t,a);r.scale.set(2.5,2.5,2.5),this.group2.add(r)}})}show(e){e?this.blurMesh&&(this.blurMesh.visible=!1):(this.group2.scale.set(0,0,0),new x().to([this.group2.scale],400,{x:1,y:1,z:1,easing:"easeOutCubic"},0).to([this.progress],4e3,{x:5,easing:"easeOutCubic"},0).to([this.progress],1e3,{y:1,easing:"easeOutCubic"},3e3).to([this.progress],4e3,{z:1,easing:"easeOutCubic"},3500).start())}constructor(e,t){(0,c._)(this,"name","shield"),(0,c._)(this,"common",void 0),(0,c._)(this,"group",new l.YJl),(0,c._)(this,"group2",new l.YJl),(0,c._)(this,"gltfs",void 0),(0,c._)(this,"images",void 0),(0,c._)(this,"progress",new l.Pq0(0,0,0)),this.common=e,this.gltfs=t.gltfs,this.images=t.images,this.group.add(this.group2)}},I={nose:{ao:"cat_head_ao",color:null,colorVec:new l.Q1f(0),matcap:"matcap_mascot"},eye:{ao:"cat_eye_ao",color:"cat_eye_color",colorVec:new l.Q1f(0),matcap:"matcap_cateye"},face:{ao:"cat_head_ao",color:null,colorVec:new l.Q1f(0xff8fd6),matcap:"matcap_mascot"},head:{ao:"cat_head_ao",color:null,colorVec:new l.Q1f(0xf763c1),matcap:"matcap_mascot"},eyeball:{ao:"cat_head_ao",color:null,colorVec:new l.Q1f(0xffffff),matcap:"matcap_mascot"}},C=new l.Q1f(0x9e55f8),P={eyes:{ao:"copilot_head_ao",color:null,colorVec:new l.Q1f(3761135),matcap:"matcap_mascot"},face:{ao:"copilot_head_ao",color:null,colorVec:new l.Q1f(328013),matcap:"matcap_mascot"},glass:{ao:"copilot_head_ao",color:null,colorVec:new l.Q1f(6497712),matcap:"matcap_mascot"},goggle:{ao:"copilot_head_ao",color:null,colorVec:new l.Q1f(0x995be3),matcap:"matcap_mascot"},head:{ao:"copilot_head_ao",color:null,colorVec:C,matcap:"matcap_mascot"}},k={body:{ao:"duck_body_ao",color:null,colorVec:new l.Q1f(0xf5ae33),matcap:"matcap_mascot"},beak:{ao:"duck_body_ao",color:null,colorVec:new l.Q1f(0xf5ae33),matcap:"matcap_mascot"},eyes:{ao:"duck_body_ao",color:null,colorVec:new l.Q1f(0),matcap:"matcap_mascot"},eyeballs:{ao:"duck_body_ao",color:null,colorVec:new l.Q1f(0),matcap:"matcap_mascot"}},S=class Mouse{init(){window.addEventListener("mousemove",e=>{if(!this.common)return;let t=(e.clientX-this.common?.wrapperOffset.x+this.common?.mascotAreaOffset.x)/this.common?.screenSize.x;t=(t-.5)*2;let i=(e.clientY-this.common?.wrapperOffset.y+this.common?.mascotAreaOffset.y)/this.common?.screenSize.y;i=(.5-i)*2,t=Math.max(-1,Math.min(1,t)),i=Math.max(-1,Math.min(1,i)),this.updateMousePos(t,i)})}updateMousePos(e,t){this.pos.target.set(e,t)}resize(){}update(){this.common&&(this.pos.current.lerp(this.pos.target,this.common.getEase(2)),this.pos.current2.lerp(this.pos.target,this.common.getEase(1.5)))}constructor(e){(0,c._)(this,"originalPos",void 0),(0,c._)(this,"pos",void 0),(0,c._)(this,"common",void 0),this.common=e,this.originalPos=new l.I9Y,this.pos={target:new l.I9Y(0,0),current:new l.I9Y(0,0),current2:new l.I9Y(0,0)}}};var T=new WeakMap,O=new WeakMap,D=new WeakMap,A=new WeakMap,F=new WeakMap,E=new WeakMap,W=new WeakMap,L=new WeakMap,U=new WeakMap,N=new WeakMap,R=new WeakMap,V=new WeakMap;let q=class Artwork{toggleVisibility(e,t){e&&!(0,a._)(this,N)&&((0,n._)(this,N,!0),this.init(),this.resize(),(0,a._)(this,W)?.show(t),(0,a._)(this,L)?.show(t),(0,a._)(this,F).startCopyAnimation&&(0,a._)(this,F).startCopyAnimation())}setStartCopyAnimation(e){(0,a._)(this,F).startCopyAnimation=e}load(){(0,n._)(this,V,!0)}init(){(0,a._)(this,F).initRenderer(),(0,a._)(this,F).resize(),(0,a._)(this,W)?.init(),(0,a._)(this,L)?.init()}resize(){(0,a._)(this,F).resize()}scroll(){(0,a._)(this,F).scroll()}resetMouse(){(0,a._)(this,W)?.resetLookat()}update({isReducedMotion:e}){(0,a._)(this,F).update(),(0,a._)(this,U).update(),(0,a._)(this,W)?.update((0,a._)(this,U).pos.target,(0,a._)(this,U).pos.current,e),(0,a._)(this,F).renderer?.setRenderTarget(null),(0,a._)(this,F).renderer?.render((0,a._)(this,F).scene,(0,a._)(this,F).camera)}constructor(e,t,i,s,o,c,l){switch((0,r._)(this,T,{writable:!0,value:void 0}),(0,r._)(this,O,{writable:!0,value:void 0}),(0,r._)(this,D,{writable:!0,value:void 0}),(0,r._)(this,A,{writable:!0,value:void 0}),(0,r._)(this,F,{writable:!0,value:new h}),(0,r._)(this,E,{writable:!0,value:void 0}),(0,r._)(this,W,{writable:!0,value:void 0}),(0,r._)(this,L,{writable:!0,value:void 0}),(0,r._)(this,U,{writable:!0,value:new S((0,a._)(this,F))}),(0,r._)(this,N,{writable:!0,value:!1}),(0,r._)(this,R,{writable:!0,value:void 0}),(0,r._)(this,V,{writable:!0,value:!1}),(0,n._)(this,T,e),(0,n._)(this,O,t),(0,n._)(this,D,i),(0,n._)(this,E,s),(0,n._)(this,R,o),(0,a._)(this,F).isReducedMotion=c,!(0,a._)(this,R)&&(0,a._)(this,F).isReducedMotion&&(0,n._)(this,N,!0),(0,n._)(this,A,l),(0,a._)(this,E)){case"mona":(0,n._)(this,W,new w("cat",(0,a._)(this,F),(0,a._)(this,A),I)),(0,a._)(this,F).scene.add((0,a._)(this,W).group);break;case"copilot":(0,n._)(this,W,new w("copilot",(0,a._)(this,F),(0,a._)(this,A),P)),(0,a._)(this,F).scene.add((0,a._)(this,W).group);break;case"ducky":(0,n._)(this,W,new w("duck",(0,a._)(this,F),(0,a._)(this,A),k)),(0,a._)(this,F).scene.add((0,a._)(this,W).group);break;case"shield":(0,n._)(this,L,new z((0,a._)(this,F),(0,a._)(this,A))),(0,a._)(this,F).scene.add((0,a._)(this,L).group)}(0,a._)(this,R)&&((0,a._)(this,W)&&(0,a._)(this,W).group.scale.set(9,9,9),(0,a._)(this,L)&&(0,a._)(this,L).group.scale.set(9,9,9)),(0,a._)(this,F).init({$wrapper:(0,a._)(this,T),$canvas:(0,a._)(this,O),$mascot:(0,a._)(this,D)}),(0,a._)(this,U).init(),(0,a._)(this,F).camera.position.set(0,0,2.2),(0,a._)(this,F).camera.lookAt((0,a._)(this,F).scene.position)}};var Q=i(14440);let Y=({mascotName:e,mascotRef:t,containerRef:i,isMascotOnly:a,startCopyAnimation:r,assetsRef:n})=>{let c=(0,o.useRef)(null),l=(0,o.useRef)(null),h=(0,o.useRef)(0);return(0,o.useEffect)(()=>{if(!(0,Q.ZN)())return r();let s=null,o=!1,u=!1,m=!1,v=e=>{(m=e.matches)?s&&s.update({isReducedMotion:!0}):o&&g()},p=window.matchMedia("(prefers-reduced-motion: reduce)");p.addEventListener("change",v),m=p.matches;let d=()=>{if(t.current&&i.current&&l.current){let e=t.current.getBoundingClientRect(),o=i.current.getBoundingClientRect(),a=e.top-o.top,r=e.width,n=e.height;l.current.style.height=`${n+20}px`,l.current.style.width=`${r+20}px`,l.current.style.top=`${a-10}px`,l.current.style.left=`${e.left-o.left-10}px`,s&&s.resize()}};if(l.current&&c.current&&t.current){let i=n.current;if(!i)return;(s=new q(l.current,c.current,t.current,e,a,m,i)).setStartCopyAnimation(r),i.addCallback(()=>{!u&&(s&&o&&s.toggleVisibility(!0,m),m&&s&&(r(),s.update({isReducedMotion:!0})))})}d();let _=()=>{s&&o&&!m&&s.scroll()};window.addEventListener("resize",d),window.addEventListener("scroll",_);let g=()=>{m||(s&&s.update({isReducedMotion:!1}),h.current=requestAnimationFrame(g))},x=new IntersectionObserver(e=>{for(let t of e){let e=n.current;if(m){t.isIntersecting&&s&&e?.isLoaded&&(s.toggleVisibility(t.isIntersecting,!0),s.update({isReducedMotion:!0}));return}t.isIntersecting?(s&&e?.isLoaded&&s.toggleVisibility(t.isIntersecting,!1),h.current||g(),o=!0):(h.current&&(cancelAnimationFrame(h.current),h.current=0),o=!1)}},{threshold:.1});return c.current&&x.observe(c.current),()=>{h.current&&cancelAnimationFrame(h.current),u=!0,window.removeEventListener("resize",d),window.removeEventListener("scroll",_),p.removeEventListener("change",v),x.disconnect()}},[]),(0,s.jsx)("div",{className:"lp-SectionIntroWebGL",ref:l,children:(0,s.jsx)("canvas",{className:"lp-SectionIntroWebGL-canvas",ref:c})})},$=Y;try{Y.displayName||(Y.displayName="SectionIntroWebGL")}catch{}}}]);
//# sourceMappingURL=packages_landing-pages_routes_home_components_SectionIntroWebGL_SectionIntroWebGL_tsx-69fc84e0a806.js.map
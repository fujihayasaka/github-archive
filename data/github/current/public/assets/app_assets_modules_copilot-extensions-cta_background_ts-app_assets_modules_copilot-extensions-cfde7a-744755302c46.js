"use strict";(globalThis.webpackChunk=globalThis.webpackChunk||[]).push([["app_assets_modules_copilot-extensions-cta_background_ts-app_assets_modules_copilot-extensions-cfde7a"],{13664:(e,s,i)=>{i.d(s,{A:()=>p});var t=i(39437);let o=`
varying vec2 vUv;

void main(){
  vUv = uv;
  gl_Position = projectionMatrix * viewMatrix * modelMatrix * vec4(position, 1.0);
}
`,r=`
uniform float uBorderRadius;
uniform vec2 uDimensions;
uniform sampler2D uDiffuse;
uniform float uColorProgress;
uniform vec3 uCenterColor;
uniform vec3 uBgColor;

varying vec2 vUv;
void main() {
  // set rounded corners
  vec2 aspect = uDimensions / max(uDimensions.x, uDimensions.y);
  vec2 alphaUv = vUv - 0.5;
  float borderRadius = min(uBorderRadius, min(uDimensions.x, uDimensions.y) * 0.5);
  vec2 offset = vec2(borderRadius) / uDimensions;
  vec2 alphaXY = smoothstep(vec2(0.5 - offset), vec2(0.5 - offset - 0.001), abs(alphaUv));
  float alpha = min(1.0, alphaXY.x + alphaXY.y);
  vec2 alphaUv2 = abs(vUv - 0.5);
  float radius = borderRadius / max(uDimensions.x, uDimensions.y);
  alphaUv2 = (alphaUv2 - 0.5) * aspect + radius;
  float roundAlpha = smoothstep(radius + 0.001, radius, length(alphaUv2));

  alpha = min(1.0, alpha + roundAlpha);

  // set texture
  vec3 color = texture2D(uDiffuse, vUv).rgb;
  vec3 centerColor = uCenterColor;

  #if TYPE == 0

  vec3 hsv_center = rgb2hsv(centerColor);
  // hsv_center.g += 0.1 * uColorProgress;
  hsv_center.b += 0.2 * uColorProgress;
  centerColor = hsv2rgb(hsv_center);

  #endif

  #if TYPE == 1

  vec3 hsv_center = rgb2hsv(centerColor);
  hsv_center.g += 0.2 * uColorProgress;
  hsv_center.b += 0.2 * uColorProgress;
  centerColor = hsv2rgb(hsv_center);

  #endif

  #if TYPE == 0
  float centerFactor = smoothstep(0.1, 0.6, abs(vUv.x - 0.5));
  color = mix(centerColor, color, centerFactor * 0.8 + 0.2);
  #endif

  #if TYPE == 1
  float centerFactor = smoothstep(0.0, 0.5, abs(vUv.x - 0.5));
  color = mix(centerColor, color, centerFactor);
  #endif

  color = mix(color, uBgColor, smoothstep(0.2, 1.0, vUv.y) * 0.9);

  #if TYPE == 0
  color = mix(uBgColor, color, smoothstep(0.0, 0.2, vUv.y));
  #endif

  // #if TYPE == 1
  // vec3 hsv = rgb2hsv(color);
  // hsv.g += 0.05 * uColorProgress;
  // hsv.b += 0.05 * uColorProgress;
  // color = hsv2rgb(hsv);
  // #endif

  gl_FragColor = vec4(color, alpha);

}
`,a=`
vec4 permute(vec4 x){return mod(x*x*34.0+x,289.);}
vec4 taylorInvSqrt(vec4 r){ return 1.79284291400159 - 0.85373472095314 * r; }

float snoise(vec3 v){
  const vec2  C = vec2(0.166666667, 0.33333333333) ;
  const vec4  D = vec4(0.0, 0.5, 1.0, 2.0);
  vec3 i  = floor(v + dot(v, C.yyy) );
  vec3 x0 = v - i + dot(i, C.xxx) ;
  vec3 g = step(x0.yzx, x0.xyz);
  vec3 l = 1.0 - g;
  vec3 i1 = min( g.xyz, l.zxy );
  vec3 i2 = max( g.xyz, l.zxy );
  vec3 x1 = x0 - i1 + C.xxx;
  vec3 x2 = x0 - i2 + C.yyy;
  vec3 x3 = x0 - D.yyy;
  i = mod(i,289.);
  vec4 p = permute( permute( permute(
	  i.z + vec4(0.0, i1.z, i2.z, 1.0 ))
	+ i.y + vec4(0.0, i1.y, i2.y, 1.0 ))
	+ i.x + vec4(0.0, i1.x, i2.x, 1.0 ));
  vec3 ns = 0.142857142857 * D.wyz - D.xzx;
  vec4 j = p - 49.0 * floor(p * ns.z * ns.z);
  vec4 x_ = floor(j * ns.z);
  vec4 x = x_ *ns.x + ns.yyyy;
  vec4 y = floor(j - 7.0 * x_ ) *ns.x + ns.yyyy;
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
  vec4 norm = taylorInvSqrt(vec4(dot(p0,p0), dot(p1,p1), dot(p2, p2), dot(p3,p3)));
  p0 *= norm.x;
  p1 *= norm.y;
  p2 *= norm.z;
  p3 *= norm.w;
  vec4 m = max(0.6 - vec4(dot(x0,x0), dot(x1,x1), dot(x2,x2), dot(x3,x3)), 0.0);
  m = m * m * m;
  return 42.0 * dot( m, vec4( dot(p0,x0), dot(p1,x1),dot(p2,x2), dot(p3,x3) ) );
}

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
`;var n=i(24043);let u=`
uniform float uWidth;
uniform float uRadius;
uniform float uMaxRadius;
uniform float uMinRadius;
uniform float uWindowScale;
uniform vec2 uAlphaRange;

varying vec2 vUv;
varying float vAngle;
varying float vAlpha;

const float PI = 3.14159265359;
void main(){
  vUv = uv;
  vec3 pos = position;

  float angle = uv.y * PI * 2.0;


  float radius = mix(uRadius - uWidth * 0.5, uRadius + uWidth * 0.5, uv.x);
  pos.x = cos(angle) * radius;
  pos.y = sin(angle) * radius;

  vAngle = (1.0 - uv.y) * PI * 2.0;

  vAlpha = smoothstep(uMaxRadius * uAlphaRange.x, uMaxRadius * uAlphaRange.y, length(pos));
  vAlpha *= smoothstep(uMinRadius * 1.0, uMinRadius * 1.1, length(pos));

  pos.xy *= uWindowScale;


  gl_Position = projectionMatrix * viewMatrix * modelMatrix * vec4(pos, 1.0);
}
`,h=`
  uniform vec3 uColor1;
  uniform vec3 uColor2;
  uniform vec3 uShine1;
  uniform vec3 uShine2;
  uniform vec2 uResolution;
  uniform float uAngles[ANGLE_NUM];
  uniform float uColorScale;
  uniform float uIsStar;

  varying vec2 vUv;
  varying float vAngle;
  varying float vAlpha;
  const float PI = 3.14159265359;
  const float PI2 = PI * 2.0;

  void main(){
    vec2 st = gl_FragCoord.xy / uResolution;
    vec3 color = mix(uColor1, uColor2, st.x);

    #if TYPE == 0
    color *= 2.8;
    #endif

    vec3 shineColor;
    float shineFactor;
    float shineFactor2;
    float darkFactor;

    #if IS_STAR == 1

    for(int i = 0; i < ANGLE_NUM; i++){
      float angle = fract(vAngle / PI2 + uAngles[i]);
      shineFactor = smoothstep(1.0, 0.95, angle);
      shineFactor2 = smoothstep(0.995, 0.95, angle);

      shineColor = mix(uShine1, uShine2, shineFactor);

      #if TYPE == 0
      shineColor *= 1.4;
      #endif
      color = mix(shineColor, color, shineFactor2);

      darkFactor = smoothstep(0.0, 0.05, angle);

      color = mix(color * 0.5, color, darkFactor);
    }
    #endif

    float smoothEdge = smoothstep(0.46, 0.38, abs(vUv.x - 0.5));

    gl_FragColor = vec4(color, vAlpha * smoothEdge);
  }
`,l=`
uniform float uMaxRadius;
uniform float uMinRadius;
uniform vec2 uAlphaRange;
uniform float uRadius;
uniform float uWindowScale;

varying vec2 vUv;
varying float vAlpha;

void main(){
  vUv = uv;
  vec4 worldPosition = modelMatrix * vec4(position, 1.0);
  vAlpha = smoothstep(uMaxRadius * uAlphaRange.x, uMaxRadius * uAlphaRange.y, uRadius);
  vAlpha *= smoothstep(uMinRadius * 1.0, uMinRadius * 1.1, uRadius);

  gl_Position = projectionMatrix * viewMatrix * worldPosition;
}
`,c=`
uniform sampler2D uMask;
uniform sampler2D uShadow;
uniform sampler2D uShadowGlow;
uniform vec3 uColor;
uniform vec3 uColor2;
uniform float uTime;
uniform vec3 uRandom;
uniform vec3 uBgColor;

varying vec2 vUv;
varying float vAlpha;

void main(){
  float alpha = smoothstep(0.3, 1.0, texture2D(uMask, vUv).r);
  float glow = texture2D(uShadowGlow, vUv).r;
  alpha += glow;

  float shadow = texture2D(uShadow, vUv).r;

  float noise = snoise(vec3(vUv * 2.0, uTime * 0.4 + uRandom.x)) * 0.5 + 0.5;

  vec3 brightColor = mix(uColor2, vec3(1.0), noise * 0.3);
  vec3 color = mix(uColor, brightColor, (1.0 - shadow) * noise);

  color = mix(color, color + 0.1, sin(uTime * 0.2 + uRandom.y) * 0.5 + 0.5);

  color = mix(uBgColor, color, vAlpha);



  gl_FragColor = vec4(color, alpha);
}
`;function m(e,s,i){return s in e?Object.defineProperty(e,s,{value:i,enumerable:!0,configurable:!0,writable:!0}):e[s]=i,e}let v=class Stars{init(e,s,i,o,r){this.bgColor.copy(r),this.isHero=o,this.common=e,this.assets=s,this.isHero&&(this.max_radius=.65,this.min_radius=.2,this.alphaRange.set(1,.9),this.circleNum=9,this.lineWidth=.01,this.starScale=.9,this.minStarCircleIndex=2),this.starOffsetScaleY=i;for(let e=0;e<this.circleNum;e++){let s=[],i=(e+1)/this.circleNum*(this.max_radius-this.min_radius)+this.min_radius,o={uWidth:{value:this.lineWidth},uRadius:{value:i},uColor1:{value:new t.Q1f(263737)},uColor2:{value:new t.Q1f(273434)},uShine1:{value:new t.Q1f(4690592)},uShine2:{value:new t.Q1f(9324542)},uResolution:{value:this.resolution},uAngles:{value:s},...this.commonUniforms},r={ANGLE_NUM:2,TYPE:this.isHero?0:1,IS_STAR:e<this.minStarCircleIndex?0:1},n=new t.eaF(new t.bdM(1,1,1,100),new t.BKk({vertexShader:u,fragmentShader:h,uniforms:o,defines:r,transparent:!0}));n.userData.uniforms=o,n.userData.angles=s,n.userData.radius=i,n.name="circle",n.userData.speed=25e-5;let m=(e-2)/(this.circleNum-2)+(Math.random()-.5)*.05;if(this.group.add(n),!(e<this.minStarCircleIndex))for(let e=0;e<2;e++){s[e]=m=.5+m;let i=new t.eaF(new t.bdM(.1*this.starScale,.1*this.starScale),new t.BKk({vertexShader:l,fragmentShader:a+c,uniforms:{uMask:{value:this.assets?.images.starShape.texture},uShadow:{value:this.assets?.images.starShapeShadow.texture},uShadowGlow:{value:this.assets?.images.starShapeGlow.texture},uColor:{value:new t.Q1f(8537847)},uColor2:{value:new t.Q1f(5632746)},uRandom:{value:new t.Pq0(Math.random(),Math.random(),Math.random())},uRadius:o.uRadius,...this.commonUniforms},transparent:!0}));i.name="star",n.add(i),i.position.z=1}}this.resize()}resize(){if(this.common){let e=this.common?.wrapperDimentions.x,s=this.common?.wrapperDimentions.y;this.uWindowScale.value=Math.min(1,1800/e),this.resolution.set(e,s),this.camera.left=-e/2,this.camera.right=e/2,this.camera.top=s/2,this.camera.bottom=-s/2,this.camera.updateProjectionMatrix();let i=this.common?.isMobile?2:1;this.group.scale.set(e*i,e*i,1),this.group.position.y=s*this.starOffsetScaleY,this.fbo.setSize(e,s)}}speedUp(){this.speedProgress.target=1}speedDown(){this.speedProgress.target=0}update(){this.commonUniforms.uMaxRadius&&(this.commonUniforms.uMaxRadius.value=this.max_radius),this.commonUniforms.uMinRadius&&(this.commonUniforms.uMinRadius.value=this.min_radius),this.common&&(this.speedProgress.current+=(this.speedProgress.target-this.speedProgress.current)*(0,n.p1)(2,this.common.delta)),this.group.traverse(e=>{if(e instanceof t.eaF&&"circle"==e.name){e.userData.radius-=this.min_radius,e.userData.radius/=this.max_radius-this.min_radius,e.userData.radius=e.userData.radius-Math.floor(e.userData.radius),e.userData.radius*=this.max_radius-this.min_radius,e.userData.radius+=this.min_radius,e.userData.uniforms.uRadius.value=e.userData.radius;let s=e.userData.radius,i=e.userData.angles,o=e.userData.speed;e.children.forEach((e,r)=>{e instanceof t.eaF&&"star"==e.name&&(i[r]-=o*(1+5*this.speedProgress.current),e.position.x=Math.cos(i[r]*Math.PI*2)*s*this.uWindowScale.value,e.position.y=Math.sin(i[r]*Math.PI*2)*s*this.uWindowScale.value,e.rotation.z=i[r]*Math.PI*2)})}}),this.commonUniforms.uTime&&this.common&&(this.uTime.value+=this.common.delta*t.cj9.lerp(1,2,this.speedProgress.current)),this.common?.renderer.setClearColor(this.bgColor),this.common?.renderer.setRenderTarget(this.fbo),this.common?.renderer.render(this.scene,this.camera)}constructor(){m(this,"scene",new t.Z58),m(this,"group",new t.YJl),m(this,"camera",new t.qUd(1,1,1,1,1,1)),m(this,"fbo",new t.nWS(1,1)),m(this,"circles",[]),m(this,"resolution",new t.I9Y),m(this,"min_radius",.22),m(this,"max_radius",.6),m(this,"alphaRange",new t.I9Y(1,.9)),m(this,"uTime",{value:0}),m(this,"circleNum",7),m(this,"bgColor",new t.Q1f(0)),m(this,"uWindowScale",{value:1}),m(this,"minStarCircleIndex",1),m(this,"commonUniforms",{uTime:this.uTime,uMaxRadius:{value:this.max_radius},uMinRadius:{value:this.min_radius},uAlphaRange:{value:this.alphaRange},uBgColor:{value:this.bgColor},uWindowScale:this.uWindowScale}),m(this,"lineWidth",.011),m(this,"starScale",.9),m(this,"speedProgress",{current:0,target:0}),m(this,"starOffsetScaleY",.08),m(this,"common",void 0),m(this,"assets",void 0),m(this,"isHero",!0),this.scene.add(this.group),this.camera.near=.01,this.camera.far=50,this.camera.position.set(0,0,10)}};function d(e,s,i){return s in e?Object.defineProperty(e,s,{value:i,enumerable:!0,configurable:!0,writable:!0}):e[s]=i,e}let p=class Background{init(){this.stars.init(this.common,this.assets,this.starOffsetScaleY,this.isHero,this.bgColor),this.mesh=new t.eaF(new t.bdM(1,1),new t.BKk({vertexShader:o,fragmentShader:a+r,uniforms:this.uniforms,defines:{TYPE:this.isHero?0:1},transparent:!0,depthTest:!1,depthWrite:!1})),this.mesh.renderOrder=-1,this.group.add(this.mesh)}resize(e){if(!this.common?.canvasWrapper)return;let s=parseFloat(getComputedStyle(this.common?.canvasWrapper).borderRadius),i=this.common?.wrapperDimentions.x*e,o=this.common?.wrapperDimentions.y*e;this.uniforms.uDimensions&&this.uniforms.uDimensions.value instanceof t.I9Y&&this.uniforms.uDimensions.value.set(i,o),this.uniforms.uBorderRadius&&(this.uniforms.uBorderRadius.value=s*e),this.group.scale.set(i,o,1),this.group.position.y=-(.5*(this.common?.sizes.y-this.common?.wrapperDimentions.y))*e,this.stars.resize()}speedUp(){this.stars.speedUp()}speedDown(){this.stars.speedDown()}update(){this.stars.update(),this.uniforms.uColorProgress&&(this.uniforms.uColorProgress.value=this.stars.speedProgress.current)}constructor(e,s,i=!0){d(this,"group",new t.YJl),d(this,"mesh",new t.eaF),d(this,"stars",new v),d(this,"starOffsetScaleY",.08),d(this,"isHero",!0),d(this,"common",void 0),d(this,"assets",void 0),d(this,"bgColor",new t.Q1f(0)),d(this,"centerColor",new t.Q1f(923532)),d(this,"uniforms",{uBorderRadius:{value:0},uDimensions:{value:new t.I9Y(0,0)},uDiffuse:{value:this.stars.fbo.texture},uCenterColor:{value:this.centerColor},uColorProgress:{value:0},uBgColor:{value:this.bgColor}}),this.isHero=i,this.common=e,this.assets=s,this.isHero&&(this.starOffsetScaleY=.25,this.bgColor.set(856343),this.centerColor.set(1906068)),this.common.scene.add(this.group)}}},6974:(e,s,i)=>{i.d(s,{A:()=>r});var t=i(39437);function o(e,s,i){return s in e?Object.defineProperty(e,s,{value:i,enumerable:!0,configurable:!0,writable:!0}):e[s]=i,e}let r=class Common{init(e){this.clock=new t.zD7,this.pixelRatio=Math.min(window.devicePixelRatio,e),this.renderer=new t.JeP({canvas:this.canvas,antialias:!0,alpha:!0}),this.renderer.setPixelRatio(this.pixelRatio),this.renderer.outputEncoding=t.S2Q,this.renderer.toneMapping=t.FV,this.renderer.toneMappingExposure=1.5,this.renderer.setClearColor(0xffffff,0),this.resize()}scroll(){let e=this.canvasWrapper.getBoundingClientRect(),s=this.copilotArea.getBoundingClientRect();this.copilotAreaOffset.set(s.left-e.left+s.width/2-e.width/2,-(s.top-e.top+s.height/2-e.height/2)-(this.sizes.y-e.height)*.5),this.wrapperOffset.set(e.left,e.top)}resize(){this.isMobile=window.innerWidth<768;let e=this.canvasWrapper.getBoundingClientRect(),s=e.width,i=e.height;this.wrapperDimentions.set(s,i);let t=this.copilotArea.getBoundingClientRect();i+=e.top-t.top,this.aspect=s/i,this.sizes.set(s,i);let o=i/t.height;this.camera.position.z=60*o,this.cameraDistance=this.camera.position.z,this.camera.aspect=this.aspect,this.camera.updateProjectionMatrix(),this.renderer.setSize(s,i),this.scroll()}update(){let e=this.clock.getDelta();this.delta=e,this.time+=this.delta}constructor(e,s,i,r){o(this,"sizes",new t.I9Y),o(this,"pixelRatio",1.5),o(this,"aspect",0),o(this,"scene",new t.Z58),o(this,"camera",new t.ubm(10,1,.1,200)),o(this,"wrapperOffset",new t.I9Y),o(this,"delta",0),o(this,"time",0),o(this,"canvasWrapper",void 0),o(this,"cameraDistance",60),o(this,"copilotArea",void 0),o(this,"canvas",void 0),o(this,"copilotAreaOffset",new t.I9Y),o(this,"wrapperDimentions",new t.I9Y),o(this,"isMobile",!1),this.aspect=1,this.canvasWrapper=e,this.copilotArea=s,this.canvas=i,this.camera.position.set(0,0,this.cameraDistance),this.scene.add(this.camera),this.delta=0,this.time=0,this.init(r)}}},24043:(e,s,i)=>{function t(e,s,i){return e+(s-e)*i}function o(e,s,i){return Math.max(0,Math.min(1,(i-e)/(s-e)))}function r(e,s){return Math.min(1,s*e)}i.d(s,{Cc:()=>t,p1:()=>r,y4:()=>o})}}]);
//# sourceMappingURL=app_assets_modules_copilot-extensions-cta_background_ts-app_assets_modules_copilot-extensions-cfde7a-0c331626a7cf.js.map
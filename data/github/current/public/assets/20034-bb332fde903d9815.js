performance.mark("js-parse-end:20034-bb332fde903d9815.js");
"use strict";(globalThis.rspackChunk_github_ui_github_ui=globalThis.rspackChunk_github_ui_github_ui||[]).push([[20034],{386940(e,t,o){o.d(t,{Pt:()=>tX,$M:()=>u,Ay:()=>c,zh:()=>tG,mU:()=>l});var i,s=o(474848),r=o(916522),a=o(296540);let n=(0,a.createContext)(null);n.displayName="WebGLContext";let l=()=>(0,a.useContext)(n);function u(e){let t,o,i,n,u=(0,r.c)(12),{className:c,params:f,offsetByWrapperTop:h}=e,{registerBrandedDivider:d,unregisterBrandedDivider:p}=l(),v=(0,a.useRef)(null),m=(0,a.useId)(),[w,b]=(0,a.useState)("1600 / 157");return u[0]!==m||u[1]!==h||u[2]!==f||u[3]!==d||u[4]!==p?(t=()=>{v.current&&d({id:m,element:v.current,params:f,offsetByWrapperTop:h});let e=()=>{window.innerWidth<=768?b("390 / 115"):window.innerWidth<=1011?b("800 / 131"):b("1600 / 157")};return e(),window.addEventListener("resize",e),()=>{p(m),window.removeEventListener("resize",e)}},u[0]=m,u[1]=h,u[2]=f,u[3]=d,u[4]=p,u[5]=t):t=u[5],u[6]===Symbol.for("react.memo_cache_sentinel")?(o=[],u[6]=o):o=u[6],(0,a.useEffect)(t,o),u[7]!==w?(i={width:"100%",maxWidth:"1600px",aspectRatio:w},u[7]=w,u[8]=i):i=u[8],u[9]!==c||u[10]!==i?(n=(0,s.jsx)("div",{ref:v,className:c,style:i}),u[9]=c,u[10]=i,u[11]=n):n=u[11],n}function c(e){let t,o,i,n,u,c,f=(0,r.c)(20),{className:h,params:d,offsetByWrapperTop:p}=e,v=(0,a.useRef)(null),m=(0,a.useRef)(!1),w=(0,a.useRef)(0),{registerDither:b,unregisterDither:g}=l(),P=(0,a.useId)();f[0]!==P?(t=()=>`${P}-${w.current}`,f[0]=P,f[1]=t):t=f[1];let y=t;return f[2]!==y||f[3]!==p||f[4]!==d||f[5]!==b||f[6]!==g?(o=()=>{v.current&&(m.current&&(g(y()),m.current=!1),w.current=w.current+1,b({id:y(),element:v.current,params:d,offsetByWrapperTop:p}),m.current=!0)},f[2]=y,f[3]=p,f[4]=d,f[5]=b,f[6]=g,f[7]=o):o=f[7],f[8]!==p||f[9]!==d.color||f[10]!==d.dotOpacity||f[11]!==d.fadeIn||f[12]!==d.type?(i=[d.color,d.type,d.fadeIn,d.dotOpacity,p],f[8]=p,f[9]=d.color,f[10]=d.dotOpacity,f[11]=d.fadeIn,f[12]=d.type,f[13]=i):i=f[13],(0,a.useEffect)(o,i),f[14]!==y||f[15]!==g?(n=()=>()=>{m.current&&(g(y()),m.current=!1)},f[14]=y,f[15]=g,f[16]=n):n=f[16],f[17]===Symbol.for("react.memo_cache_sentinel")?(u=[],f[17]=u):u=f[17],(0,a.useEffect)(n,u),f[18]!==h?(c=(0,s.jsx)("div",{ref:v,className:h}),f[18]=h,f[19]=c):c=f[19],c}u.displayName="WebGLBrandedDivider",c.displayName="WebGLDither";var f=o(439437);let h=new f.qUd(-1,1,1,-1,.1,3e3);h.position.z=1200,h.lookAt(new f.Pq0(0,0,0)),h.updateProjectionMatrix();let d=null,p=()=>{if(!d)throw Error("Renderer not set");return d},v=new f.Q1f(0),m=new f.I9Y(800,600),w=new f.I9Y(800,600),b=new f.I9Y(800,600);var g=o(710961);let P=()=>"u">typeof window&&!!window.matchMedia&&window.matchMedia("(prefers-reduced-motion: reduce)").matches;function y(e,t=!1){let o=null!==e[0].index,i=new Set(Object.keys(e[0].attributes)),s=new Set(Object.keys(e[0].morphAttributes)),r={},a={},n=e[0].morphTargetsRelative,l=new f.LoY,u=0;for(let c=0;c<e.length;++c){let f=e[c],h=0;if(o!==(null!==f.index))return console.error("THREE.BufferGeometryUtils: .mergeBufferGeometries() failed with geometry at index "+c+". All geometries must have compatible attributes; make sure index attribute exists among all geometries, or in none of them."),null;for(let e in f.attributes){if(!i.has(e))return console.error("THREE.BufferGeometryUtils: .mergeBufferGeometries() failed with geometry at index "+c+'. All geometries must have compatible attributes; make sure "'+e+'" attribute exists among all geometries, or in none of them.'),null;void 0===r[e]&&(r[e]=[]),r[e].push(f.attributes[e]),h++}if(h!==i.size)return console.error("THREE.BufferGeometryUtils: .mergeBufferGeometries() failed with geometry at index "+c+". Make sure all geometries have the same number of attributes."),null;if(n!==f.morphTargetsRelative)return console.error("THREE.BufferGeometryUtils: .mergeBufferGeometries() failed with geometry at index "+c+". .morphTargetsRelative must be consistent throughout all geometries."),null;for(let e in f.morphAttributes){if(!s.has(e))return console.error("THREE.BufferGeometryUtils: .mergeBufferGeometries() failed with geometry at index "+c+".  .morphAttributes must be consistent throughout all geometries."),null;void 0===a[e]&&(a[e]=[]),a[e].push(f.morphAttributes[e])}if(t){let e;if(o)e=f.index.count;else{if(void 0===f.attributes.position)return console.error("THREE.BufferGeometryUtils: .mergeBufferGeometries() failed with geometry at index "+c+". The geometry must have either an index or a position attribute"),null;e=f.attributes.position.count}l.addGroup(u,e,c),u+=e}}if(o){let t=0,o=[];for(let i=0;i<e.length;++i){let s=e[i].index;for(let e=0;e<s.count;++e)o.push(s.getX(e)+t);t+=e[i].attributes.position.count}l.setIndex(o)}for(let e in r){let t=x(r[e]);if(!t)return console.error("THREE.BufferGeometryUtils: .mergeBufferGeometries() failed while trying to merge the "+e+" attribute."),null;l.setAttribute(e,t)}for(let e in a){let t=a[e][0].length;if(0===t)break;l.morphAttributes=l.morphAttributes||{},l.morphAttributes[e]=[];for(let o=0;o<t;++o){let t=[];for(let i=0;i<a[e].length;++i)t.push(a[e][i][o]);let i=x(t);if(!i)return console.error("THREE.BufferGeometryUtils: .mergeBufferGeometries() failed while trying to merge the "+e+" morphAttribute."),null;l.morphAttributes[e].push(i)}}return l}function x(e){let t,o,i,s=0;for(let r=0;r<e.length;++r){let a=e[r];if(a.isInterleavedBufferAttribute)return console.error("THREE.BufferGeometryUtils: .mergeBufferAttributes() failed. InterleavedBufferAttributes are not supported."),null;if(void 0===t&&(t=a.array.constructor),t!==a.array.constructor)return console.error("THREE.BufferGeometryUtils: .mergeBufferAttributes() failed. BufferAttribute.array must be of consistent array types across matching attributes."),null;if(void 0===o&&(o=a.itemSize),o!==a.itemSize)return console.error("THREE.BufferGeometryUtils: .mergeBufferAttributes() failed. BufferAttribute.itemSize must be consistent across matching attributes."),null;if(void 0===i&&(i=a.normalized),i!==a.normalized)return console.error("THREE.BufferGeometryUtils: .mergeBufferAttributes() failed. BufferAttribute.normalized must be consistent across matching attributes."),null;s+=a.array.length}let r=new t(s),a=0;for(let t=0;t<e.length;++t)r.set(e[t].array,a),a+=e[t].array.length;return new f.THS(r,o,i)}class q extends f.LoY{constructor(e=.1,t=4){super();const o=new f.bdM(1,1);o.translate(0,0,.5+e);const i=o.clone(),s=o.clone();s.rotateY(Math.PI/2);const r=o.clone();r.rotateY(Math.PI);const a=o.clone();a.rotateY(-Math.PI/2);const n=o.clone();n.rotateX(-Math.PI/2);const l=o.clone();l.rotateX(Math.PI/2);const u=new f.Gu$(e,t,t,0,.5*Math.PI,0,.5*Math.PI);u.translate(-.5,.5,.5);const c=u.clone(),h=u.clone();h.rotateZ(Math.PI/2);const d=u.clone();d.rotateZ(Math.PI);const p=u.clone();p.rotateZ(-Math.PI/2);const v=c.clone();v.rotateY(Math.PI);const m=h.clone();m.rotateY(Math.PI);const w=d.clone();w.rotateY(Math.PI);const b=p.clone();b.rotateY(Math.PI);const g=new f.Ho_(e,e,1,t,1,!0,0,Math.PI/2);g.translate(.5,0,.5);const P=g.clone(),x=g.clone();x.rotateZ(Math.PI/2);const q=g.clone();q.rotateZ(Math.PI);const C=g.clone();C.rotateZ(-Math.PI/2);const R=P.clone();R.rotateY(Math.PI);const M=x.clone();M.rotateY(Math.PI);const D=q.clone();D.rotateY(Math.PI);const T=C.clone();T.rotateY(Math.PI);const G=g.clone();G.rotateX(Math.PI/2);const I=G.clone();I.rotateZ(Math.PI/2);const S=G.clone();S.rotateZ(Math.PI);const z=G.clone();z.rotateZ(-Math.PI/2);const E=y([i,s,r,a,n,l,c,h,d,p,v,m,w,b,P,x,q,C,R,M,D,T,G,I,S,z]);this.copy(E)}}var C=o(617888);let R=o.p+"invertocat-01a584beb4c3f2a1.glb",M=`
if(gl_FragCoord.y < uRectData.w - uRectData.y || 
    gl_FragCoord.y > uRectData.w || 
    gl_FragCoord.x < uRectData.z || 
    gl_FragCoord.x > uRectData.z + uRectData.x){
    discard;
}
`,D=`
uniform vec3 uColor1;
uniform vec3 uColor2;
uniform vec3 uColor3;

uniform vec3 uBgColor;
uniform vec3 uInnerShadowColor;
uniform vec4 uRectData;
uniform vec4 uProgress;

varying vec2 vUv;
varying vec3 vNormal;
varying vec3 vPosition;

void main(){
  float sx = abs(vNormal.x);
  float sy = abs(vNormal.y);
  float sz = abs(vNormal.z);
  vec3 color = uColor1;
  vec3 white = vec3(1.0);

  vec2 f = vec2(0.2, 0.9);
  vec3 i = smoothstep(f.x, f.y, abs(vPosition));
  i = 1.0 - pow(i, vec3(2.0));

  float innerShadowX = pow(i.y * i.z, 2.0);
  float innerShadowY = pow(i.x * i.z, 2.0);
  float innerShadowZ = pow(i.x * i.y, 2.0);


  vec3 colorX = vec3(0.0);
  vec3 colorY = vec3(0.0);
  vec3 colorZ = vec3(0.0);
  #ifdef NORMAL2
    colorX = mix(uColor3, uColor2, smoothstep(1.2, -1.0, vPosition.z + 0.5));
    colorY = mix(uColor3, uColor2, smoothstep(1.2, -1.0, vPosition.z + 0.5));
    colorZ = mix(uInnerShadowColor, uColor2, innerShadowZ);
  #else
    colorX = mix(uColor3, uColor2, smoothstep(-0.3, 1.8, vPosition.y + 0.5));
    colorY = mix(uInnerShadowColor, uColor1, innerShadowY);
    colorZ = mix(uInnerShadowColor, uColor2, innerShadowZ);
  #endif

  float faceYFactor = (1.0 - smoothstep(0.7, 0.75, sy));
  float faceZFactor = (1.0 - smoothstep(0.7, 0.75, sz));

  color = mix(colorY, colorX, faceYFactor);
  color = mix(colorZ, color, faceZFactor);

  gl_FragColor = vec4(color, 1.0);

  #ifndef IS_GLASS_RENDER
  ${M}
  #endif

  gl_FragColor.rgb = pow(gl_FragColor.rgb, vec3(1.0/2.2));
  gl_FragColor.rgb = mix(uBgColor, gl_FragColor.rgb, uProgress.x);
}


`,T=`
  uniform vec3 uColor1;
  uniform vec3 uColor2;
  uniform vec4 uRectData;
  uniform vec3 uLightPos;

  varying vec2 vUv;
  varying vec3 vNormal;
  varying vec3 vNormal2;

  void main() {

    vec3 white = vec3(1.0);

    float l = dot(vNormal2, normalize(uLightPos)) * 0.5 + 0.5;

    l = pow(l, 4.0);


    vec3 color = mix(uColor1, uColor2, l);

    color = mix(color, white, vNormal.z);

    color = pow(color, vec3(1.0/2.2));

    ${M}
    gl_FragColor = vec4(color, 1.0);
  }
`,G=`
varying vec2 vUv;
varying vec3 vNormal;
varying vec3 vNormal2;

varying vec3 vPosition;
varying vec3 vWorldPosition;

#ifdef MOSAIC 
    varying vec2 vScreenPos;
    varying vec2 vCenterPos;
#endif

void main(){
    vUv = uv;
    vNormal = normal;
    vNormal2 = normalize(normalMatrix * normal);
    vPosition = position;

    vec4 worldPos = modelMatrix * vec4(position, 1.0);
    vec4 screenPos = projectionMatrix * viewMatrix * worldPos;
    vWorldPosition = worldPos.xyz;

    #ifdef MOSAIC 
        vec4 centerpos = projectionMatrix * modelViewMatrix * vec4(0.0, 0.0, 0.0, 1.0);
        vCenterPos = centerpos.xy / centerpos.w;
        vScreenPos = screenPos.xy / screenPos.w;
    #endif

    gl_Position = screenPos;
}
`;class I{group=new f.YJl;invertocatMesh=null;cubeGeometry;cubeConfig;progress=new f.IUQ(0,0,0,0);commonUniforms={uInnerShadowColor:{value:new f.Q1f(6286723)},uBgColor:{value:v},uPixelRatio:{value:1},uLightPos:{value:new f.Pq0(2,2,1).normalize()},uRectData:{value:new f.IUQ},uRectData2:{value:new f.IUQ},uResolution:{value:b}};isLoaded=!1;isNeededToPlayTl=!1;invertocatParams;tl=g.Ay.timeline({paused:!0});lightPos=new f.Pq0(1,1,1).normalize();constructor(e,t){this.cubeGeometry=e.cubeGeometry,this.cubeConfig=e.cubeConfig,this.invertocatParams=t,this.group.name="invertocatCube",this.commonUniforms.uRectData.value=e.rectData,this.commonUniforms.uRectData2.value=e._rectData}async create(e){e.add(this.group);let t=new C.B,o=this.createCubeMesh();this.group.userData.position={def:this.cubeConfig.position.clone(),offset:this.cubeConfig.offsetStart.position.clone(),current:new f.Pq0(0,0,0)},this.group.userData.progress=this.progress;let i=this.cubeConfig.scale;i instanceof f.Pq0?this.group.scale.copy(i):this.group.scale.set(i,i,i),this.group.userData.rotation={def:this.cubeConfig.rotation.clone(),offset:this.cubeConfig.offsetStart.rotation.clone(),current:new f.Pq0(0,0,0),defMatrix:new f.kn4,offsetMatrix:new f.kn4,currentMatrix:new f.kn4,defEuler:new f.O9p,offsetEuler:new f.O9p},this.group.add(o),await t.loadAsync(R).then(e=>{e.scene.traverse(e=>{e instanceof f.eaF&&(this.invertocatMesh=e,this.invertocatMesh.material=new f.BKk({vertexShader:G,fragmentShader:T,uniforms:{...this.commonUniforms,uColor1:{value:new f.Q1f(304946)},uColor2:{value:new f.Q1f(6286723)},uLightPos:{value:this.lightPos}}}),this.invertocatMesh.scale.set(.2,.2,.2),this.invertocatMesh.position.set(.87*this.invertocatParams.position.x,.87*this.invertocatParams.position.y,.87*this.invertocatParams.position.z),this.invertocatMesh.rotation.set(this.invertocatParams.rotation.x,this.invertocatParams.rotation.y,this.invertocatParams.rotation.z),this.group.add(this.invertocatMesh))}),this.createAnimation(),this.isLoaded=!0})}createCubeMesh(){let e,t=new f.IUQ(1,0,0,0),o=new f.IUQ(Math.random(),Math.random(),Math.random(),Math.random());e=new f.BKk({vertexShader:G,fragmentShader:D,uniforms:{...this.commonUniforms,uColor1:{value:new f.Q1f(167465)},uColor2:{value:new f.Q1f(0xbfffd1)},uColor3:{value:new f.Q1f(2204997)},uProgress:{value:t},uRandom:{value:o}}});let i=new f.eaF(this.cubeGeometry,e);return i.userData.progress=t,i}createAnimation(){let e=this.cubeConfig.delay,t=this.cubeConfig.duration;this.tl.add(()=>{this.group.visible=!0},e).to(this.group.userData.position.offset,{x:0,y:0,z:0,ease:"expo.out",duration:t},e).to(this.group.userData.rotation.offset,{x:0,y:0,z:0,ease:"expo.out",duration:t},e).to(this.group.userData.progress,{x:1,ease:"expo.out",duration:.8},e).to(this.group.userData.progress,{y:1,duration:1.5},e).to(this.group.userData.progress,{z:1,ease:"steps(8)",duration:1.8},e),this.invertocatMesh&&this.tl.to(this.invertocatMesh.position,{x:this.invertocatParams.position.x,y:this.invertocatParams.position.y,z:this.invertocatParams.position.z,ease:"expo.out",duration:3},e+.5),this.isNeededToPlayTl&&this.tl.play()}playTl(){this.isNeededToPlayTl=!0,this.isLoaded&&this.tl.play()}update(){let e=p();if(!e||void 0===this.group.userData.position||void 0===this.group.userData.rotation)return;this.commonUniforms.uPixelRatio.value=e.getPixelRatio();let t=this.group.userData.position,o=this.group.userData.rotation;t.current.copy(t.def).add(t.offset),this.group.position.copy(t.current);let i=this.cubeConfig.layout;window.innerWidth<768?(this.group.visible=i.mobile.visible,this.group.position.add(i.mobile.offset)):window.innerWidth<1011&&(this.group.visible=i.tablet.visible,this.group.position.add(i.tablet.offset)),o.defEuler.set(o.def.x,o.def.y,o.def.z,"XYZ"),o.offsetEuler.set(o.offset.x,o.offset.y,o.offset.z,"XYZ"),o.defMatrix.makeRotationFromEuler(o.defEuler),o.offsetMatrix.makeRotationFromEuler(o.offsetEuler),o.currentMatrix.multiplyMatrices(o.offsetMatrix,o.defMatrix),this.group.rotation.setFromRotationMatrix(o.currentMatrix)}}let S=o.p+"security-be7ea1e143b16773.png",z=`
vec3 rgb2hsv(vec3 c) {
    vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
    vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));

    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}
    
vec3 hsv2rgb(vec3 c) {
    vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

`,E=`
float mod289(float x){return x - floor(x * (1.0 / 289.0)) * 289.0;}
vec4 mod289(vec4 x){return x - floor(x * (1.0 / 289.0)) * 289.0;}
vec4 perm(vec4 x){return mod289(((x * 34.0) + 1.0) * x);}

float noise(vec3 p){
    vec3 a = floor(p);
    vec3 d = p - a;
    d = d * d * (3.0 - 2.0 * d);

    vec4 b = a.xxyy + vec4(0.0, 1.0, 0.0, 1.0);
    vec4 k1 = perm(b.xyxy);
    vec4 k2 = perm(k1.xyxy + b.zzww);

    vec4 c = k2 + a.zzzz;
    vec4 k3 = perm(c);
    vec4 k4 = perm(c + 1.0);

    vec4 o1 = fract(k3 * (1.0 / 41.0));
    vec4 o2 = fract(k4 * (1.0 / 41.0));

    vec4 o3 = o2 * d.z + o1 * (1.0 - d.z);
    vec2 o4 = o3.yw * d.x + o3.xz * (1.0 - d.x);

    return o4.y * d.y + o4.x * (1.0 - d.y);
}

// simplex noise
// TODO Optimize it more
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
`,k=`${E+z}
uniform vec4 uProgress;
uniform vec3 uColor1;
uniform vec4 uRectData;

varying vec3 vPosition;
varying vec3 vNormal;

void main(){
  vec3 no = abs(vNormal);
  float maxComponent = max(no.x, max(no.y, no.z));
  no = vec3(equal(no, vec3(maxComponent)));

  vec2 rainbowFactor = vec2(
    snoise(vec3(vPosition * 0.25 + no * 0.2 + uProgress.y + 2.0)),
    snoise(vec3(vPosition * 0.5 + no + uProgress.y * 2.0))
  ) * 0.5 + 0.5;


  vec3 rainbowColor = uColor1;
  vec3 hsv = rgb2hsv(rainbowColor);
  hsv.r -= rainbowFactor.x * 0.2;
  hsv.g -= rainbowFactor.y * 0.1;
  hsv.b += rainbowFactor.y * 0.2;

  #ifndef IS_GLASS_RENDER
  ${M}
  #endif

  rainbowColor = hsv2rgb(hsv);
  gl_FragColor = vec4(rainbowColor, 1.0);
}
`,_=[{delay:.1,scale:1,position:{def:new f.Pq0(0,-.6,0),offset:new f.Pq0(0,-2,0),current:new f.Pq0(0,0,0),duration:1.5,ease:"expo.out"},rotation:{def:new f.Pq0(.25*Math.PI,-(.2*Math.PI),0),offset:new f.Pq0(-Math.PI,0,0),current:new f.Pq0(0,0,0),duration:2,ease:"expo.out"}},{delay:.1,scale:1.3,position:{def:new f.Pq0(0,-.6,0),offset:new f.Pq0(0,-2,0),current:new f.Pq0(0,0,0),duration:1.5,ease:"expo.out"},rotation:{def:new f.Pq0(0,0,0),offset:new f.Pq0(-Math.PI,0,0),current:new f.Pq0(0,0,0),duration:2,ease:"expo.out"}},{delay:.1,scale:1,position:{def:new f.Pq0(1,-1.5,1),offset:new f.Pq0(0,-2,0),current:new f.Pq0(0,0,0),duration:1.5,ease:"expo.out"},rotation:{def:new f.Pq0(0,0,0),offset:new f.Pq0(0,Math.PI,0),current:new f.Pq0(0,0,0),duration:2,ease:"expo.out"}},{delay:.1,scale:1,position:{def:(i=new f.Pq0(2,-1,-3),i.x*=1+.08*1.1,i.y*=1+.08*1.1,i.z*=1+.08*1.1,i),offset:new f.Pq0(0,-2,0),current:new f.Pq0(0,0,0),duration:1.6,ease:"expo.out"},rotation:{def:new f.Pq0(0,0,0),offset:new f.Pq0(0,Math.PI,0),current:new f.Pq0(0,0,0),duration:2,ease:"expo.out"}}];class B{_cubeGeometry;params;group=new f.YJl;shieldGroup=new f.YJl;cubeGroup=new f.YJl;rectData;parentGroup=null;tmpQuaternion=new f.PTz;tmpEuler=new f.O9p;_rotationParam=new f.Pq0;constructor(e,t,o){this.params=e,this._cubeGeometry=t,this.rectData=o,this.group.add(this.shieldGroup),this.group.add(this.cubeGroup)}async create(e,t){if(this.parentGroup=e,e.add(this.group),"security"!==this.params.character)return;let o=_[this.params.layout];if(!o)return;this.group.scale.set(o.scale,o.scale,o.scale);let i=new f.IUQ(0,0,0,0),s=new f.Tap,r=await s.loadAsync(S),a=r.image.width/r.image.height,n=new f.eaF(new f.bdM(1.3*a,1.3),new f.BKk({vertexShader:`
        varying vec2 vUv;
        void main(){
          vUv = uv;
          gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
        }
        `,fragmentShader:`
        varying vec2 vUv;
        uniform sampler2D uTexture;
        uniform vec4 uRectData;
        uniform vec4 uProgress;

        void main(){
          vec4 color = texture2D(uTexture, vUv);
          ${M}

          color.rgb /= color.a;
          gl_FragColor = color;
          gl_FragColor.a *= uProgress.x;
        }
        `,uniforms:{uTexture:{value:r},uRectData:{value:this.rectData},uProgress:{value:i}},transparent:!0}));n.position.set(0,0,1.2),n.name="shield",this.shieldGroup.add(n);let l=new f.eaF(this._cubeGeometry,new f.BKk({vertexShader:G,fragmentShader:k,uniforms:{uColor1:{value:new f.Q1f(0xccedff)},uRectData:{value:this.rectData},uProgress:{value:i},uBgColor:{value:v}},defines:{MOSAIC:""}}));this.cubeGroup.add(l),l.rotation.order="ZXY",l.name="securityCube",l.userData.position={def:o.position.def.clone(),offset:o.position.offset.clone(),current:o.position.current.clone()},l.userData.rotation={def:new f.Pq0(0,0,0),offset:o.rotation.offset.clone(),defMatrix:new f.kn4,offsetMatrix:new f.kn4,currentMatrix:new f.kn4,defEuler:new f.O9p,offsetEuler:new f.O9p},this._rotationParam.copy(o.rotation.def),t.to(l.userData.position.offset,{x:0,y:0,z:0,ease:o.position.ease,duration:o.position.duration},0).to(l.userData.rotation.offset,{x:0,y:0,z:0,ease:o.rotation.ease,duration:o.rotation.duration},0).to(i,{x:1,ease:"expo.out",duration:1},0).to(i,{y:1,ease:"expo.out",duration:3},0)}update(e){let t=this.group.getObjectByName("securityCube");if(!t)return;let o=t.userData.position,i=t.userData.rotation;o.current.copy(o.def).add(o.offset),this.group.position.copy(o.current),i.defEuler.set(i.def.x,i.def.y,i.def.z,"ZXY"),i.offsetEuler.set(i.offset.x,i.offset.y,i.offset.z,"ZXY"),i.defMatrix.makeRotationFromEuler(i.defEuler),i.offsetMatrix.makeRotationFromEuler(i.offsetEuler),i.currentMatrix.multiplyMatrices(i.defMatrix,i.offsetMatrix),t.rotation.setFromRotationMatrix(i.currentMatrix),this.updateObjects(e)}updateObjects(e){let t=this.group.getObjectByName("shield");if(!t||!this.parentGroup)return;let o=this.tmpQuaternion.copy(this.parentGroup.quaternion).invert();this.shieldGroup.quaternion.copy(o),this.tmpEuler.set(this._rotationParam.x,this._rotationParam.y,this._rotationParam.z,"YXZ"),0===this.params.layout&&(this.tmpEuler.x-=e*Math.PI*.15,t.rotation.z=.6-e*Math.PI*.15,this.group.position.y+=.1*e,this.cubeGroup.quaternion.copy(o)),1===this.params.layout&&(t.rotation.z=.6-e*Math.PI*.15),this.tmpQuaternion.setFromEuler(this.tmpEuler),this.cubeGroup.quaternion.multiply(this.tmpQuaternion)}}let F={mona:[{desktop:{position:new f.Pq0(0,0,0),scale:22},table:{position:new f.Pq0(-.2,0,0),scale:13},mobile:{position:new f.Pq0(0,0,0),scale:8}},{desktop:{position:new f.Pq0(0,0,0),scale:18},table:{position:new f.Pq0(0,0,0),scale:11},mobile:{position:new f.Pq0(0,0,0),scale:6}},{desktop:{position:new f.Pq0(0,0,0),scale:18},table:{position:new f.Pq0(-.8,0,0),scale:10},mobile:{position:new f.Pq0(-3.5,0,0),scale:5.5}}],copilot:[{desktop:{position:new f.Pq0(0,0,0),scale:22},table:{position:new f.Pq0(.6,0,0),scale:13.5},mobile:{position:new f.Pq0(.8,0,0),scale:8}},{desktop:{position:new f.Pq0(0,0,0),scale:18},table:{position:new f.Pq0(.5,0,0),scale:11.7},mobile:{position:new f.Pq0(0,0,0),scale:7}},{desktop:{position:new f.Pq0(0,0,0),scale:17},table:{position:new f.Pq0(-.8,0,0),scale:10},mobile:{position:new f.Pq0(-3.5,0,0),scale:5.5}}],security:[{desktop:{position:new f.Pq0(0,0,0),scale:18},table:{position:new f.Pq0(0,0,0),scale:10},mobile:{position:new f.Pq0(0,0,0),scale:6}},{desktop:{position:new f.Pq0(0,0,0),scale:22},table:{position:new f.Pq0(0,0,0),scale:13},mobile:{position:new f.Pq0(0,0,0),scale:8}},{desktop:{position:new f.Pq0(0,0,0),scale:18},table:{position:new f.Pq0(0,0,0),scale:11.5},mobile:{position:new f.Pq0(0,0,0),scale:6}},{desktop:{position:new f.Pq0(0,0,0),scale:17},table:{position:new f.Pq0(-.8,0,0),scale:10},mobile:{position:new f.Pq0(-2.8,0,0),scale:5.5}}],invertocat:[{desktop:{position:new f.Pq0(0,0,0),scale:22},table:{position:new f.Pq0(-.2,0,0),scale:13},mobile:{position:new f.Pq0(0,0,0),scale:8}},{desktop:{position:new f.Pq0(0,0,0),scale:18},table:{position:new f.Pq0(0,0,0),scale:11},mobile:{position:new f.Pq0(0,0,0),scale:6}},{desktop:{position:new f.Pq0(0,0,0),scale:18},table:{position:new f.Pq0(-.8,0,0),scale:10},mobile:{position:new f.Pq0(-3.5,0,0),scale:5.5}}]},N=o.p+"copilot-e5051da1a2302051.glb",A=o.p+"copilot-normal-eye-088356c04f42ffbe.png",Y=o.p+"copilot-smile-eye-2fda8a6eeda68410.png",O=`${E+z}
  uniform vec3 uColor1;
  uniform vec3 uColor2;
  uniform vec3 uColor3;
  uniform vec4 uRectData;
  uniform float uNoiseScale;

  varying vec3 vNormal;
  varying vec3 vNormal2;
  varying vec3 vWorldPosition;

  void main() {
    float n = snoise(vNormal2 * uNoiseScale) * 0.5 + 0.5;
    n = smoothstep(0.0, 1.0, n);

    float n2 = snoise(vNormal2 * uNoiseScale + vec3(-1.5)) * 0.5 + 0.5;
    // n2 = smoothstep(0.5, 1.0, n2);

    vec3 color = mix(uColor1, uColor2, n);

    #if PART == 0
      color = mix(color, uColor3, n2 * 0.3);
    #endif

    float n3 = snoise(vNormal2 * uNoiseScale + vec3(0.5)) * 0.5 + 0.5;
    n3 = smoothstep(0.0, 1.0, n3);

    vec3 hsv = rgb2hsv(color);
    hsv.g -= n3 * 0.2;
    hsv.b += n3 * 0.4;

    #if PART == 0
    hsv.b += n2 * 0.1;
    #endif
    color = hsv2rgb(hsv);

    ${M}

    // color = pow(color, vec3(1.0/2.2));
    gl_FragColor = vec4(color, 1.0);
  }
`,U=`
  uniform sampler2D uTexture;
  uniform vec4 uRectData;

  varying vec2 vUv;
  
  void main() {
    vec4 color = texture2D(uTexture, vUv);
    ${M}
    gl_FragColor = color;
  }

`,L=`
  uniform vec3 uColor1;
  uniform vec3 uColor2;
  uniform vec4 uProgress;
  uniform vec4 uRectData;


  varying vec2 vUv;
  varying vec3 vNormal2;

  float getFresnel(vec3 normal, float power) {
    vec3 viewDir = vec3(0.0, 0.0, 1.0);
    return 1.0 - pow(max(dot(viewDir, normal), 0.0), power);
  }

  void main() {
    float fresnel = getFresnel(vNormal2, mix(5.0, 1.0, smoothstep(0.0, 1.0, vUv.x)));
    vec3 color = mix(uColor1, uColor2, fresnel);
    color = mix(uColor2 + 0.3, color, smoothstep(0.3, 0.8, vUv.x));

    color = pow(color, vec3(1.0/2.2));

    float alpha = 1.0;
    alpha *= mix(1.0 - fresnel, 1.0, smoothstep(0.3, 1.0, vUv.x));
    alpha *= smoothstep(0.0, 1.1, vUv.x);
    alpha *= smoothstep(1.0 - uProgress.z, 2.5 - uProgress.z * 1.5, vUv.x);

    ${M}
    gl_FragColor = vec4(color, alpha);
  }
`,Q=`
uniform vec4 uProgress;
varying vec2 vUv;
varying vec3 vNormal;
varying vec3 vNormal2;

varying vec3 vPosition;
varying vec3 vWorldPosition;

#ifdef MOSAIC 
    varying vec2 vScreenPos;
    varying vec2 vCenterPos;
#endif

void main(){
    vUv = uv;
    vNormal = normal;
    vNormal2 = normalize(normalMatrix * normal);

    vec3 pos = position;

    pos += normal * mix(0.2, 0.0, smoothstep(0.0, 0.8, uv.x));
    pos -= normal * mix(0.3, 0.0, uProgress.w);

    vPosition = pos;


    vec4 worldPos = modelMatrix * vec4(pos, 1.0);
    vec4 screenPos = projectionMatrix * viewMatrix * worldPos;
    vWorldPosition = worldPos.xyz;

    #ifdef MOSAIC 
        vec4 centerpos = projectionMatrix * modelViewMatrix * vec4(0.0, 0.0, 0.0, 1.0);
        vCenterPos = centerpos.xy / centerpos.w;
        vScreenPos = screenPos.xy / screenPos.w;
    #endif

    gl_Position = screenPos;
}
`;class W{group=new f.YJl;group2=new f.YJl;group3=new f.YJl;params;curve=new f.ibB(0,0,5,0,1.5*Math.PI,!1);progress=new f.IUQ(0,0,0,0);tube=null;offsetPos=new f.I9Y(0,0);rectData=new f.IUQ(0,0,0,0);tl=g.Ay.timeline({paused:!0});isLoaded=!1;isNeededToPlayTl=!1;tmpEuler=new f.O9p;tmpQuaternion=new f.PTz;constructor(e,t){this.params=e,this.rectData=t,this.group.add(this.group2),this.group2.add(this.group3)}async create(e,t){let o=new f.Tap,i=0===this.params.layout?Y:A,s=await o.loadAsync(i);s.anisotropy=8;let r=s.image.height/s.image.width;new C.B().load(N,t=>{t.scene.traverse(e=>{if(e instanceof f.eaF){let t=e.clone(),o={uColor1:{value:new f.Q1f(5333759)},uColor2:{value:new f.Q1f(9692159)},uColor3:{value:new f.Q1f(0xe4d1ff)},uRectData:{value:this.rectData},uNoiseScale:{value:.5}},i={PART:0};switch(t.material=new f.BKk({vertexShader:G,fragmentShader:O,uniforms:o,side:2,defines:i}),e.name){case"Goggle":case"Ears":case"Glass":let a=new f.eaF(t.geometry.clone(),t.material);a.position.copy(t.position),a.geometry.scale(-1,1,1),a.position.x*=-1,this.group3.add(a),this.group3.add(t);break;case"Eyes":let n=0===this.params.layout?.7:.6,l=new f.eaF(new f.bdM(n,n*r),new f.BKk({vertexShader:G,fragmentShader:U,uniforms:{uTexture:{value:s},uRectData:{value:this.rectData}},transparent:!0,side:2}));l.geometry.rotateY(-.3),0===this.params.layout?l.position.set(-.45,-.1,1.45):l.position.set(-.4,-.1,1.5);let u=l.clone();u.scale.set(-1,1,1),u.position.set(-l.position.x,l.position.y,l.position.z),this.group3.add(l),this.group3.add(u);break;default:this.group3.add(t)}switch(e.name){case"Goggle":o.uColor1.value.set(1592312),o.uColor2.value.set(9692159),o.uNoiseScale.value=.6,i.PART=1;break;case"Glass":case"Screen":o.uColor1.value.set(337393),o.uColor2.value.set(70267),o.uNoiseScale.value=.5,i.PART=2;break;case"Ears":o.uNoiseScale.value=.2}}}),e.add(this.group),this.createTl(),this.isLoaded=!0}),this.createPath()}createTl(){this.isNeededToPlayTl&&this.tl.play()}createPath(){}createTube(){let e=this.curve.getPoints(50).map(e=>new f.Pq0(e.x,e.y,0)),t=new f.B6O(e),o=new f.j6(t,64,.35,8,!1),i=new f.BKk({vertexShader:Q,fragmentShader:L,transparent:!0,uniforms:{uColor1:{value:new f.Q1f(3249407)},uColor2:{value:new f.Q1f(0x9fecff)},uProgress:{value:this.progress},uRectData:{value:this.rectData}}});this.tube=new f.eaF(o,i),this.group.add(this.tube),this.tube.position.set(this.offsetPos.x,this.offsetPos.y,0)}playTl(){this.isNeededToPlayTl=!0,this.isLoaded&&this.tl.play()}moveOnArc(){}update(e){this.moveOnArc(),this.tmpEuler.set(-(.6*e),0,0),this.group.quaternion.setFromEuler(this.tmpEuler)}}class X extends W{constructor(e,t){super(e,t),this.group.scale.set(.35,.35,.35)}createPath(){this.offsetPos.set(0,2.6),this.curve=new f.ibB(0,0,5,1.8*Math.PI,1.2*Math.PI,!0),this.createTube()}createTl(){this.tl.to(this.progress,{x:1,ease:"expo.out",duration:3},0).to(this.progress,{y:1,ease:"expo.out",duration:3},0).to(this.progress,{z:1,ease:"expo.out",duration:3},0).to(this.progress,{w:1,ease:"power2.out",duration:3},0),super.createTl()}moveOnArc(){let e=this.progress.x,t=this.curve.getPointAt(e),o=this.curve.getTangentAt(e);this.group2.position.set(t.x+this.offsetPos.x,t.y+this.offsetPos.y,0);let i=Math.atan2(o.y,o.x);this.group2.rotation.set(-.3+(1-this.progress.y)*4,.2,i-.5*Math.PI),this.group2.scale.set(e,e,e),this.tube&&(this.tube.rotation.z=(1-e)*.6*Math.PI)}update(e){super.update(e)}}class j extends W{constructor(e,t){super(e,t),this.group.scale.set(.3,.3,.3),this.group.position.z=3}createTl(){this.tl.to(this.progress,{x:1,ease:"elastic.out(1,1)",duration:2},.5).to(this.progress,{y:1,ease:"expo.out",duration:1},.5).to(this.progress,{z:1,ease:"expo.out",duration:3},.5).to(this.progress,{w:1,ease:"power2.out",duration:3},0),super.createTl()}createPath(){this.offsetPos.set(9,-1),this.curve=new f.B6O([new f.Pq0(0,-4,0),new f.Pq0(0,0,0)]),this.createTube(),this.tube&&this.tube.material instanceof f.BKk&&(this.tube.material.uniforms.uColor1.value.set(0xffffff),this.tube.scale.set(1.2,1,1.2))}moveOnArc(){let e=this.progress.x,t=f.cj9.lerp(-4,0,e);this.group3.position.set(0,0,-.35),this.group2.position.set(this.offsetPos.x,t+this.offsetPos.y+1,0),this.group2.rotation.set(-.3,-.5+(1-this.progress.z)*Math.PI,0),this.group2.scale.set(this.progress.y,this.progress.y,this.progress.y),this.tube&&(this.tube.position.y=-(4*(1-e))),window.innerWidth<1011&&(this.group.position.x=-.5)}}class $ extends W{constructor(e,t){super(e,t),this.group.scale.set(.3,.3,.3),this.group.position.z=3}createTl(){this.tl.to(this.progress,{x:1,ease:"elastic.out(1,1)",duration:2},.5).to(this.progress,{y:1,ease:"expo.out",duration:1},.5).to(this.progress,{z:1,ease:"expo.out",duration:3},.5).to(this.progress,{w:1,ease:"power2.out",duration:3},0),super.createTl()}createPath(){this.offsetPos.set(15.5,-.8),this.curve=new f.B6O([new f.Pq0(0,-4,0),new f.Pq0(0,0,0)]),this.createTube(),this.tube&&this.tube.material instanceof f.BKk&&(this.tube.material.uniforms.uColor1.value.set(0xffffff),this.tube.scale.set(1.2,1,1.2))}moveOnArc(){let e=this.progress.x,t=f.cj9.lerp(-4,0,e);if(this.group2.position.set(this.offsetPos.x,t+this.offsetPos.y+1,0),this.group2.rotation.set(.3,-.7+(1-this.progress.z)*Math.PI,0),this.group2.scale.set(this.progress.y,this.progress.y,this.progress.y),this.tube&&(this.tube.position.y=-(4*(1-e))),window.innerWidth<768){let e=.85*this.progress.y;this.group2.scale.set(e,e,e)}}}let Z=new f.Pq0(0,-1,0),H=e=>(e.add(Z),e.x*=1+.08*1.1,e.y*=1+.08*1.1,e.z*=1+.08*1.1,e),K=[{position:new f.Pq0(0,-1.2,0),rotation:new f.Pq0(.5*Math.PI,.5*Math.PI,0),cubeType:"invertocat",offsetStart:{position:new f.Pq0(0,-4,0),rotation:new f.Pq0(-Math.PI,0,0)},delay:0,duration:1.5,scale:1.5,layout:{tablet:{offset:new f.Pq0(0,0,0),visible:!0},mobile:{offset:new f.Pq0(0,0,0),visible:!0}}},{position:H(new f.Pq0(2,.6,-2)),rotation:new f.Pq0(0,0,Math.PI),cubeType:"invertocat",offsetStart:{position:new f.Pq0(0,-3,0),rotation:new f.Pq0(0,0,0)},delay:0,duration:1.5,scale:1,layout:{tablet:{offset:new f.Pq0(-.4,0,.4),visible:!0},mobile:{offset:new f.Pq0(-1.5,0,1.5),visible:!0}}},{position:H(new f.Pq0(3,0,-3)),rotation:new f.Pq0(0,.5*Math.PI,.5*Math.PI),cubeType:"invertocat",isGlassRender:!1,offsetStart:{position:new f.Pq0(0,-3,0),rotation:new f.Pq0(0,0,0)},delay:0,duration:1,scale:1,layout:{tablet:{offset:new f.Pq0(0,0,0),visible:!0},mobile:{offset:new f.Pq0(0,0,0),visible:!0}}}],V=o.p+"mona-normal-579fba27c91dc412.glb",J=o.p+"mona-upwardGlance-f17e759f1b600013.glb",ee=`${E+z}
uniform vec3 uColor1;
uniform vec3 uColor2;
uniform vec4 uRectData;

varying vec2 vUv;
varying vec3 vNormal;
varying vec3 vNormal2;
varying vec3 vPosition;

float getFresnel(vec3 normal, float power) {
  vec3 viewDir = vec3(0.0, -0.5, 1.0);
  return 1.0 - pow(max(dot(viewDir, normal), 0.0), power);
}

void main(){
  vec3 color = vNormal2 * 0.5 + 0.5;

  #ifdef HEAD
    float n = snoise(vNormal2 * 0.2) * 0.5 + 0.5;

    float fresnel = 1.0 - getFresnel(vNormal, 2.0);
    color = mix(uColor1, uColor2, fresnel);
    color = mix(color, uColor2, n * 0.7);
  #endif

  #ifdef FACE
    float fresnel = 1.0 - getFresnel(vNormal, 4.0);
    fresnel *= 0.5;

    float l = dot(normalize(vec3(0.0, 0.5, 1.0)), vNormal2) * 0.5 + 0.5;
    l = pow(l, 5.0);
    fresnel = mix(l, fresnel * 0.6 + 0.1, smoothstep(0.0, 0.3, 1.0 - vUv.y));
    fresnel = fresnel;
    fresnel = mix(fresnel, 1.0, smoothstep(0.5, 1.0, 1.0 - vUv.y));
    fresnel = pow(fresnel, 1.2);

    color = mix(uColor1, uColor2, fresnel);
  #endif

  #ifdef MOUTH
    color = uColor1;
  #endif

  #ifdef NOSE
    float l = dot(normalize(vec3(1.0)), vNormal2);
    l = smoothstep(0.8, 1.0, l);
    color = mix(uColor1, uColor2, l);
  #endif

  #ifdef EYE
    color = uColor1;
  #endif

  #ifdef EYELID
    color = uColor1;
  #endif

  #ifdef PUPIL
    float l = dot(normalize(vec3(0.0, 0.0, 1.0)), normalize(vNormal * vec3(0.5, 1.0, 0.4))) * 0.5 + 0.5;
    l = smoothstep(0.97, 1.0, l);
    color = mix(uColor1, uColor2, l);
  #endif

  #ifdef WHISKERS
    float f = smoothstep(0.0, 2.0, abs(vPosition.x));
    color = mix(uColor1, uColor2, f);
  #endif

  #ifdef EAR
    float f = smoothstep(0.1, 0.5, (0.5 - abs(vUv.x - 0.5)) + (1.0 - vUv.y));
    f = mix(f, 0.0, smoothstep(0.1, 0.9, vUv.y));
    color = mix(uColor1, uColor2, f);
  #endif

  ${M}

  color = pow(color, vec3(1.0/2.2));
  gl_FragColor = vec4(color, 1.0);
}
`;class et{group=new f.YJl;params;progress=new f.IUQ(0,0,0,0);rectData=new f.IUQ(0,0,0,0);tl=g.Ay.timeline({paused:!0});whiskers={original:[],mirrored:[]};isLoaded=!1;isNeededToPlayTl=!1;constructor(e,t){this.params=e,this.rectData=t,this.group.visible=!1}async create(e,t){let o=new C.B,i=0===this.params.layout?J:V;await o.loadAsync(i).then(e=>{let t=new f.YJl;t.name="EyeGroup",this.group.add(t),e.scene.traverse(e=>{if(e instanceof f.eaF){let o=e.geometry,i=this.createMaterial(e.name),s=o.clone();switch(s.scale(-1,1,1),e.name){case"Highlight_1":case"Highlight_2":let r=new f.eaF(o,i);r.position.copy(e.position),r.rotation.copy(e.rotation),this.group.add(r),r.name=e.name,1===this.params.layout&&(r.position.x*=-1,r.scale.x*=-1);break;case"Whiskers_1":case"Whiskers_2":let a=new f.eaF(s,i);a.position.copy(e.position),a.position.x*=-1,a.rotation.copy(e.rotation),this.group.add(a),a.name=`${e.name}_mirrored`;let n=new f.eaF(o,i);n.position.copy(e.position),n.rotation.copy(e.rotation),this.group.add(n),n.name=`${e.name}_original`,"Whiskers_1"===e.name&&(this.whiskers.original[0]=n,this.whiskers.mirrored[0]=a),"Whiskers_2"===e.name&&(this.whiskers.original[1]=n,this.whiskers.mirrored[1]=a);break;case"Eye":case"Pupil":case"Highlight":let l=new f.eaF(o,i);l.position.copy(e.position),l.rotation.copy(e.rotation),t.add(l),l.name=e.name;break;default:let u=y([o,s]),c=new f.eaF(u,i);c.position.copy(e.position),c.rotation.copy(e.rotation),this.group.add(c),c.name=e.name}}});let o=t.clone();o.name="EyeGroup_mirrored",o.scale.set(-1,1,1),this.group.add(o),this.createTl(),this.isLoaded=!0}),e.add(this.group)}createTl(){this.isNeededToPlayTl&&this.tl.play()}createMaterial(e){let t={},o={uColor1:{value:new f.Q1f(6506746)},uColor2:{value:new f.Q1f(0xc149d8)},uRectData:{value:this.rectData}};switch(e){case"Head":t={HEAD:""};break;case"Face":t={FACE:""},o.uColor1.value.set(0xdd37c3),o.uColor2.value.set(0xfed7e9);break;case"Mouth":t={MOUTH:""},o.uColor1.value.set(0);break;case"Nose":t={NOSE:""},o.uColor1.value.set(3481717),o.uColor2.value.set(0xffffff);break;case"Eye":case"Highlight":case"Highlight_1":case"Highlight_2":t={EYE:""},o.uColor1.value.set(0xf9e1f2);break;case"Pupil":t={PUPIL:""},o.uColor1.value.set(3547766),o.uColor2.value.set(6502623);break;case"EyeLid":t={EYELID:""},o.uColor1.value.set(0xb518b8);break;case"Whiskers_1":case"Whiskers_2":t={WHISKERS:""},o.uColor1.value.set(5324028),o.uColor2.value.set(9911291);break;case"Ear":t={EAR:""},o.uColor1.value.set(0xb95efe),o.uColor2.value.set(0xff53c3)}return new f.BKk({vertexShader:G,fragmentShader:ee,transparent:!0,side:2,uniforms:o,defines:t})}playTl(){this.isNeededToPlayTl=!0,this.isLoaded&&this.tl.play()}update(e){}}class eo extends et{constructor(e,t){super(e,t),this.group.scale.set(.16,.16,.16)}createTl(){this.tl.add(()=>{this.group.visible=!0},0);let e=this.group.getObjectByName("EyeGroup"),t=this.group.getObjectByName("EyeGroup_mirrored");e&&t&&this.tl.fromTo(e.position,{y:-.4,x:-.1},{y:0,x:0,ease:"expo.out",duration:2},1).fromTo(t.position,{y:-.4,x:.1},{y:0,x:0,ease:"expo.out",duration:2},1);let o=this.group.getObjectByName("Mouth");o&&this.tl.fromTo(o.position,{x:0},{x:.2,ease:"expo.out",duration:2},2).fromTo(o.rotation,{z:0},{z:.2,ease:"expo.out",duration:2},2).to(o.scale,{x:.8,y:.8,z:.8,ease:"expo.out",duration:2},2);let i=(e,t)=>{e.forEach((e,o)=>{this.tl.to(e.rotation,{z:-.4*t,duration:.5},.1*o).to(e.rotation,{z:.3*t,duration:.5},.5+.1*o).to(e.rotation,{z:-.2*t,duration:.5},1+.1*o).to(e.rotation,{z:.2*t,duration:.5},1.5+.1*o).to(e.rotation,{z:0,duration:.5},2+.1*o)})};i(this.whiskers.original,1),i(this.whiskers.mirrored,-1),this.group.rotation.order="ZYX",this.group.userData.rotation=this.group.rotation.clone(),this.group.userData.rotation.z=.25*Math.PI;let s=new f.Pq0(2.6,-2.6,0);this.tl.fromTo(this.group.userData.rotation,{x:2,y:3*Math.PI},{x:-.2,y:0,duration:3,ease:"expo.out"},0).fromTo(this.group.position,{x:s.x,y:s.y},{x:s.x-2,y:s.y+2,duration:3,ease:"expo.out"},0),super.createTl()}update(e){if(!this.group.userData.rotation)return;let t=new f.O9p(-(.5*e),0,0),o=new f.PTz().setFromEuler(t);this.group.quaternion.setFromEuler(this.group.userData.rotation),this.group.quaternion.multiply(o)}}class ei extends et{constructor(e,t){super(e,t),this.group.scale.set(.12,.12,.12)}createTl(){this.tl.add(()=>{this.group.visible=!0},0);let e=this.group.getObjectByName("EyeGroup"),t=this.group.getObjectByName("EyeGroup_mirrored");e&&t&&this.tl.fromTo(e.position,{y:.5},{y:0,ease:"expo.out",duration:3},.2).fromTo(t.position,{y:.5},{y:0,ease:"expo.out",duration:3},.2);let o=(e,t)=>{e.forEach((e,o)=>{this.tl.to(e.rotation,{z:-.4*t,duration:.5},0*o).to(e.rotation,{z:.25*t,duration:.5},.5+0*o).to(e.rotation,{z:-.1*t,duration:.5},1+0*o).to(e.rotation,{z:.1*t,duration:.5},1.5+0*o).to(e.rotation,{z:0,duration:.5},2+0*o)})};o(this.whiskers.original,1),o(this.whiskers.mirrored,-1),this.group.rotation.order="ZXY",this.group.userData.rotation=this.group.rotation.clone(),this.group.userData.position=this.group.position.clone(),this.tl.fromTo(this.group.userData.position,{x:2.5,y:-2},{x:2.5,y:-.1,duration:2,ease:"expo.out"},0).fromTo(this.group.userData.rotation,{x:.2*Math.PI,y:1.5*Math.PI},{x:-(.12*Math.PI),y:-(.14*Math.PI),duration:2,ease:"expo.out"},0),super.createTl()}update(e){if(!this.group.userData.rotation)return;let t=new f.O9p(-(.5*e),0,0),o=new f.PTz().setFromEuler(t);this.group.quaternion.setFromEuler(this.group.userData.rotation),this.group.quaternion.multiply(o),this.group.position.copy(this.group.userData.position),window.innerWidth<=768&&(this.group.position.x-=1.5)}}class es extends et{constructor(e,t){super(e,t),this.group.scale.set(.12,.12,.12)}createTl(){this.tl.add(()=>{this.group.visible=!0},0);let e=this.group.getObjectByName("EyeGroup"),t=this.group.getObjectByName("EyeGroup_mirrored");e&&t&&this.tl.fromTo(e.position,{y:.4},{y:0,ease:"expo.out",duration:3},.5).fromTo(t.position,{y:.4},{y:0,ease:"expo.out",duration:3},.5);let o=(e,t)=>{e.forEach((e,o)=>{this.tl.to(e.rotation,{z:-.4*t,duration:.5},0*o).to(e.rotation,{z:.25*t,duration:.5},.5+0*o).to(e.rotation,{z:-.1*t,duration:.5},1+0*o).to(e.rotation,{z:.1*t,duration:.5},1.5+0*o).to(e.rotation,{z:0,duration:.5},2+0*o)})};o(this.whiskers.original,1),o(this.whiskers.mirrored,-1),this.group.rotation.order="ZXY",this.group.userData.rotation=this.group.rotation.clone(),this.group.position.x=4.65,this.tl.fromTo(this.group.position,{y:-2},{y:-.1,duration:2,ease:"elastic.out(1, 1)"},0).fromTo(this.group.userData.rotation,{y:1.5*Math.PI},{y:-(.14*Math.PI),duration:1.5,ease:"expo.out"},0).fromTo(this.group.userData.rotation,{x:-(.1*Math.PI)},{x:.08*Math.PI,duration:3,ease:"expo.out"},0),super.createTl()}update(e){if(!this.group.userData.rotation)return;let t=new f.O9p(-(.3*e),0,0),o=new f.PTz().setFromEuler(t);this.group.quaternion.setFromEuler(this.group.userData.rotation),this.group.quaternion.multiply(o)}}let er=`
  uniform vec2 uResolution;
  uniform vec2 uFboSize;
  uniform sampler2D tGlass;
  uniform vec3 uColor2;
  uniform vec3 uBgColor;
  uniform vec4 uRectData;
  uniform vec4 uRectData2;
  uniform vec4 uProgress;
  uniform vec3 uLightPos;

  varying vec3 vPosition;
  varying vec3 vNormal;
  varying vec3 vNormal2;

  void main(){
    vec2 uv;
    uv.x = (gl_FragCoord.x - uRectData.z) / uRectData.x;
    uv.y = (gl_FragCoord.y - (uRectData.w - uRectData.y)) / uRectData.y;

    // Optional: clamp to [0,1] range
    uv = clamp(uv, 0.0, 1.0);

    vec4 color = vec4(0.0);
    // Apply distortion based on normal
    // similar to matcap uv calculation with only vNormal2
    vec2 distort = -normalize(vNormal2.xy) * 0.02;
    uv += distort;

    float light = dot(normalize(vNormal2), uLightPos) * 0.5 + 0.5;
    light = smoothstep(0.8, 1.0, light);

    color = texture2D(tGlass, uv);

    #ifdef WHITE_GLASS
      color.rgb = mix(vec3(1.0) + color.rgb, color.rgb, color.a);
      color.rgb = mix(color.rgb, vec3(1.0), 0.5);
    #else
      color.rgb = mix(uBgColor + color.rgb, color.rgb, color.a);
      color.rgb = mix(color.rgb, vec3(1.0), 0.1);
    #endif


    color.rgb = mix(color.rgb, uColor2, 0.2 * light);
    color.a = 1.0;

    ${M}
    gl_FragColor = color;

    gl_FragColor.rgb = mix(uBgColor, gl_FragColor.rgb, uProgress.x);
    // gl_FragColor = vec4(vNormal2, 1.0);
  }
`,ea=`${E+z}
uniform vec3 uColor1;
uniform vec3 uColor2;

uniform vec3 uBgColor;
uniform vec3 uInnerShadowColor;
uniform vec4 uRectData;
uniform vec4 uProgress;
uniform vec3 uRandom;
uniform mat3 normalMatrix;

varying vec2 vUv;
varying vec3 vNormal;
varying vec3 vPosition;
varying vec3 vWorldPosition;

void main(){

  vec3 color = uColor2;

  float alpha = 1.0;
  #ifndef IS_GLASS_RENDER
  ${M}
  #endif

  vec3 p = vPosition * 0.5 + 0.5;

  float gradientFactor = p.x + 1.0 - p.y;
  gradientFactor = pow(gradientFactor, 2.0);

  color = mix(uColor1, uColor2, p.z);
  alpha = gradientFactor * 0.2;


  #ifdef MOSAIC
    vec3 no = abs(vNormal);
    // Find which component is largest and create one-hot vector
    float maxComponent = max(no.x, max(no.y, no.z));
    no = vec3(equal(no, vec3(maxComponent)));

    vec3 no2 = normalize(normalMatrix * (no * sign(vNormal)));

    vec3 pos = floor((vPosition) * 4.0 + 0.5);
    float n = noise(pos + no + vec3(0.5, 1.0, 0.5) * -uProgress.z * 2.0);
    n = step(0.5, n);

    alpha *= mix(1.0, 1.5, n);
  #endif

  #ifdef RAINBOW
    vec3 rainbowFactor = vec3(
      snoise(vec3(vPosition * 0.75 + vec3(0.0, uProgress.y, 0.0))),
      snoise(vec3(vPosition * 0.75 + vec3(5.2) - vec3(0.0, uProgress.y, 0.0))),
      snoise(vec3(vPosition * 0.3 + vec3(10.4) - vec3(0.0, uProgress.y * 0.2, 0.0)))
    ) * 0.5 + 0.5;

    vec3 rainbowColor = uColor1;
    vec3 hsv = rgb2hsv(rainbowColor);
    hsv.r -= rainbowFactor.x * 0.18;
    hsv.g += rainbowFactor.y * 0.1 - uProgress.w * 0.2;
    hsv.b += rainbowFactor.y * 0.2;

    rainbowColor = hsv2rgb(hsv);
    color.rgb = rainbowColor;
    alpha = mix(alpha, 1.0, rainbowFactor.z);
  #endif

  alpha *= mix(1.0, 1.3, uProgress.w);

  gl_FragColor = vec4(color, alpha);

  gl_FragColor.rgb = pow(gl_FragColor.rgb, vec3(1.0/2.2));
}
`,en=`${E}
uniform vec4 uRectData;
uniform vec3 uColor1;
uniform vec3 uColor2;
uniform vec3 uBgColor;
uniform vec4 uProgress;
uniform vec3 uLightPos;
uniform vec3 uRandom;
uniform mat3 normalMatrix;

varying vec2 vUv;
varying vec3 vNormal;
varying vec3 vNormal2;
varying vec3 vPosition;

float random(vec3 st){
  return fract(sin(dot(st.xyz,vec3(12.9898,78.233, 45.164)))*43758.5453123);
}

void main(){


  vec3 no = abs(vNormal);
  // Find which component is largest and create one-hot vector
  float maxComponent = max(no.x, max(no.y, no.z));
  no = vec3(equal(no, vec3(maxComponent)));

  vec3 no2 = normalize(normalMatrix * (no * sign(vNormal)));

  vec3 pos = floor((vPosition) * 4.0 + 0.5);
  float n = noise(pos + no + vec3(0.5, 1.0, 0.5) * -uProgress.z * 2.0);
  float light = dot(normalize(no2), uLightPos) * 0.5 + 0.5;
  // distance from light
  float light2 = length(normalize(normalMatrix * vPosition) - uLightPos * 2.0);
  light2 = smoothstep(4.0, 0.0, light2);

  n = step(0.5, n);

  vec3 color1 = mix(uColor1 - 0.2, uColor1, light);
  vec3 color2 = mix(uColor2 - 0.7, uColor2, light);
  color2 += mix(-0.2, 0.1, light2);
  vec3 color = mix(color1, color2, n);

  #ifndef IS_GLASS_RENDER
  ${M}
  #endif

  color = mix(uBgColor, color, uProgress.x );

  gl_FragColor = vec4(color, 1.0);

  gl_FragColor.rgb = pow(gl_FragColor.rgb, vec3(1.0/2.2));

}
`,el=`${E+z}
  uniform vec3 uColor1;
  uniform vec3 uColor2;
  uniform vec3 uColor3;
  uniform vec3 uBgColor;
  uniform vec4 uProgress;
  uniform vec4 uRectData;

  varying vec3 vPosition;
  varying vec3 vNormal;

  void main(){
    vec3 no = abs(vNormal);
    // Find which component is largest and create one-hot vector
    float maxComponent = max(no.x, max(no.y, no.z));
    no = vec3(equal(no, vec3(maxComponent)));

    vec2 f = vec2(0.0, 0.9);
    vec3 i = smoothstep(f.x, f.y, abs(vPosition));
    i = 1.0 - pow(i, vec3(2.0));

    vec3 innerShadow = 1.0 - vec3(
      pow(i.y * i.z, 2.0),
      pow(i.x * i.z, 2.0),
      pow(i.x * i.y, 2.0)
    );

    vec4 color = vec4(vec3(0.0), 1.0);
    color.rgb = mix(uBgColor, vec3(0.5), innerShadow.x * innerShadow.y * innerShadow.z);

    vec2 rainbowFactor = vec2(
      snoise(vec3(vPosition * 0.5 + vec3(0.0, uProgress.y * 1.0, 0.0))),
      snoise(vec3(vPosition * 0.5 + vec3(5.2) - vec3(0.0, uProgress.y, 0.0)))
    ) * 0.5 + 0.5;


    vec3 rainbowColor = uColor1;
    vec3 hsv = rgb2hsv(rainbowColor);
    hsv.r -= rainbowFactor.x * 0.25;
    hsv.b += rainbowFactor.y * 0.2;

    rainbowColor = hsv2rgb(hsv);
    color.rgb = mix(color.rgb, rainbowColor, no.g);


    #ifndef IS_GLASS_RENDER
    ${M}
    #endif
    
    gl_FragColor = color;
    gl_FragColor.rgb = mix(uBgColor, gl_FragColor.rgb, uProgress.x);
  }
`,eu=`
uniform vec3 uColor1;
uniform vec3 uColor2;
uniform vec3 uColor3;

uniform vec3 uBgColor;
uniform vec3 uInnerShadowColor;
uniform vec3 uInnerShadowColor2;
uniform vec4 uRectData;
uniform vec4 uProgress;

varying vec2 vUv;
varying vec3 vNormal;
varying vec3 vNormal2;
varying vec3 vPosition;

void main(){
  float sx = abs(vNormal.x);
  float sy = abs(vNormal.y);
  float sz = abs(vNormal.z);
  vec3 color = uColor1;
  vec3 white = vec3(1.0);

  vec2 f = vec2(0.2, 0.9);
  vec3 i = smoothstep(f.x, f.y, abs(vPosition));
  i = 1.0 - pow(i, vec3(2.0));

  float innerShadowX = pow(i.y * i.z, 2.0);
  float innerShadowY = pow(i.x * i.z, 2.0);
  float innerShadowZ = pow(i.x * i.y, 2.0);


  vec3 colorX = vec3(0.0);
  vec3 colorY = vec3(0.0);
  vec3 colorZ = vec3(0.0);

  vec3 color1 = mix(pow(uColor1, vec3(1.5)) * 0.7, uColor1, vPosition.z + 0.5);


  colorX = mix(uColor1, uColor3, smoothstep(-0.3, 1.0, vPosition.y + 0.5));
  colorY = mix(uInnerShadowColor2, uColor2, innerShadowY);
  colorZ = mix(uColor1, uColor3, smoothstep(-0.3, 1.0, vPosition.y + 0.5));


  float faceYFactor = (1.0 - smoothstep(0.7, 0.75, sy));
  float faceZFactor = (1.0 - smoothstep(0.7, 0.75, sz));

  color = mix(colorY, colorX, faceYFactor);
  color = mix(colorZ, color, faceZFactor);

  float l = dot(normalize(vec3(-1, 0, 0)), vNormal2) * 0.5 + 0.5;
  color = mix(color * 0.7, color, l);


  gl_FragColor = vec4(color, 1.0);

  #ifndef IS_GLASS_RENDER
  ${M}
  #endif

  gl_FragColor.rgb = pow(gl_FragColor.rgb, vec3(1.0/2.2));
  gl_FragColor.rgb = mix(uBgColor, gl_FragColor.rgb, uProgress.x);
}
`,ec=`
uniform vec3 uColor1;
uniform vec3 uColor2;
uniform vec3 uColor3;

uniform vec3 uBgColor;
uniform vec3 uInnerShadowColor;
uniform vec3 uInnerShadowColor2;
uniform vec4 uRectData;
uniform vec4 uProgress;

varying vec2 vUv;
varying vec3 vNormal;
varying vec3 vPosition;

void main(){
  float sx = abs(vNormal.x);
  float sy = abs(vNormal.y);
  float sz = abs(vNormal.z);
  vec3 color = uColor1;
  vec3 white = vec3(1.0);

  vec2 f = vec2(0.2, 0.9);
  vec3 i = smoothstep(f.x, f.y, abs(vPosition));
  i = 1.0 - pow(i, vec3(2.0));

  float innerShadowX = pow(i.y * i.z, 2.0);
  float innerShadowY = pow(i.x * i.z, 2.0);
  float innerShadowZ = pow(i.x * i.y, 2.0);


  vec3 colorX = vec3(0.0);
  vec3 colorY = vec3(0.0);
  vec3 colorZ = vec3(0.0);

  vec3 color1 = mix(pow(uColor1, vec3(1.5)) * 0.7, uColor1, vPosition.z + 0.5);

  colorX = mix(uColor2, uColor3, smoothstep(-0.3, 1.0, vPosition.z + 0.5));
  colorY = mix(uInnerShadowColor, color1, innerShadowY);
  colorZ = mix(uInnerShadowColor2, uColor2, innerShadowZ);

  float faceYFactor = (1.0 - smoothstep(0.7, 0.75, sy));
  float faceZFactor = (1.0 - smoothstep(0.7, 0.75, sz));

  color = mix(colorY, colorX, faceYFactor);
  color = mix(colorZ, color, faceZFactor);

  gl_FragColor = vec4(color, 1.0);

  #ifndef IS_GLASS_RENDER
  ${M}
  #endif

  gl_FragColor.rgb = pow(gl_FragColor.rgb, vec3(1.0/2.2));
  gl_FragColor.rgb = mix(uBgColor, gl_FragColor.rgb, uProgress.x);
}


`;class ef{mesh;cubeGeometry;glassEffect;cubeConfig;progress=new f.IUQ(0,0,0,0);commonUniforms={uInnerShadowColor:{value:new f.Q1f(6286723)},uBgColor:{value:v},uPixelRatio:{value:1},uLightPos:{value:new f.Pq0(2,2,1).normalize()},uRectData:{value:new f.IUQ},uRectData2:{value:new f.IUQ},uResolution:{value:b}};constructor(e){this.cubeGeometry=e.cubeGeometry,this.glassEffect=e.glassEffect,this.cubeConfig=e.cubeConfig,this.commonUniforms.uRectData.value=e.rectData,this.commonUniforms.uRectData2.value=e._rectData,this.mesh=this.createCubeMesh(this.cubeConfig.cubeType),this.mesh.userData.position={def:this.cubeConfig.position.clone(),offset:this.cubeConfig.offsetStart.position.clone(),current:new f.Pq0(0,0,0)};const t=this.cubeConfig.scale;t instanceof f.Pq0?this.mesh.scale.copy(t):this.mesh.scale.set(t,t,t),this.mesh.userData.rotation={def:this.cubeConfig.rotation.clone(),offset:this.cubeConfig.offsetStart.rotation.clone(),current:new f.Pq0(0,0,0),defMatrix:new f.kn4,offsetMatrix:new f.kn4,currentMatrix:new f.kn4,defEuler:new f.O9p,offsetEuler:new f.O9p,scrollDiffEuler:new f.O9p(0,0,0),scrollDiffMatrix:new f.kn4},this.mesh.visible=!1}createCubeMesh(e){let t,o=new f.IUQ(Math.random(),Math.random(),Math.random(),Math.random());switch(e){case"normal":case"normal2":default:t=new f.BKk({vertexShader:G,fragmentShader:D,uniforms:{...this.commonUniforms,uColor1:{value:new f.Q1f(167465)},uColor2:{value:new f.Q1f(0xbfffd1)},uColor3:{value:new f.Q1f(2204997)},uProgress:{value:this.progress},uRandom:{value:o}}}),"normal2"===e&&(t.defines.NORMAL2="");break;case"mosaic":t=new f.BKk({vertexShader:G,fragmentShader:en,uniforms:{...this.commonUniforms,uColor1:{value:new f.Q1f(3264864)},uColor2:{value:new f.Q1f(0xbfffd1)},uProgress:{value:this.progress},uRandom:{value:o}}});break;case"glass":t=new f.BKk({vertexShader:G,fragmentShader:er,uniforms:{...this.commonUniforms,uColor1:{value:new f.Q1f(167465)},uColor2:{value:new f.Q1f(0xbfffd1)},uFboSize:{value:this.glassEffect?.fboSize},tGlass:{value:this.glassEffect?.fbo1.texture},uProgress:{value:this.progress},uRandom:{value:o}}});break;case"glassNoBlur":case"glassRainbowNoBlur":case"glassMosaic":t=new f.BKk({vertexShader:G,fragmentShader:ea,uniforms:{...this.commonUniforms,uColor1:{value:new f.Q1f("glassRainbowNoBlur"===e?0xdef6ff:0xc9f3ff)},uColor2:{value:new f.Q1f(0xbfffd1)},uFboSize:{value:this.glassEffect?.fboSize},tGlass:{value:this.glassEffect?.fbo1.texture},uProgress:{value:this.progress},uRandom:{value:o}},transparent:!0}),"glassMosaic"===e&&(t.defines.MOSAIC=""),"glassRainbowNoBlur"===e&&(t.defines.RAINBOW="");break;case"whiteGreen":t=new f.BKk({vertexShader:G,fragmentShader:ec,uniforms:{...this.commonUniforms,uInnerShadowColor2:{value:new f.Q1f(1891583)},uColor1:{value:new f.Q1f(5689239)},uColor2:{value:new f.Q1f(0xf2fdff)},uColor3:{value:new f.Q1f(0xa9f1c3)},uProgress:{value:this.progress},uRandom:{value:o}}});break;case"whiteBlue":t=new f.BKk({vertexShader:G,fragmentShader:eu,uniforms:{...this.commonUniforms,uInnerShadowColor2:{value:new f.Q1f(1891583)},uColor1:{value:new f.Q1f(0xa7d8f5)},uColor2:{value:new f.Q1f(0xf2fdff)},uColor3:{value:new f.Q1f(0xd4f6f7)},uProgress:{value:this.progress},uRandom:{value:o}}});break;case"rainbow":t=new f.BKk({vertexShader:G,fragmentShader:el,uniforms:{...this.commonUniforms,uColor1:{value:new f.Q1f(0xdef6ff)},uColor2:{value:new f.Q1f(0xffdeed)},uColor3:{value:new f.Q1f(0xfffdde)},uProgress:{value:this.progress},uRandom:{value:o}}})}return new f.eaF(this.cubeGeometry,t)}createAnimation(e){let t=this.cubeConfig.delay,o=this.cubeConfig.duration;e.add(()=>{this.mesh.visible=!0},t).to(this.mesh.userData.position.offset,{x:0,y:0,z:0,ease:"expo.out",duration:o},t).to(this.mesh.userData.rotation.offset,{x:0,y:0,z:0,ease:"expo.out",duration:o},t).to(this.progress,{x:1,ease:"expo.out",duration:.8},t).to(this.progress,{y:1,duration:1.5},t).to(this.progress,{z:1,ease:"steps(8)",duration:1.8},t)}update(e){this.commonUniforms.uPixelRatio.value=e.getPixelRatio();let t=this.mesh.userData.position,o=this.mesh.userData.rotation;t.current.copy(t.def).add(t.offset),this.mesh.position.copy(t.current);let i=this.cubeConfig.layout;this.mesh.visible=!0,window.innerWidth<768?(this.mesh.visible=i.mobile.visible,this.mesh.position.add(i.mobile.offset)):window.innerWidth<1011&&(this.mesh.visible=i.tablet.visible,this.mesh.position.add(i.tablet.offset)),o.defEuler.set(o.def.x,o.def.y,o.def.z,"XYZ"),o.offsetEuler.set(o.offset.x,o.offset.y,o.offset.z,"XYZ"),o.defMatrix.makeRotationFromEuler(o.defEuler),o.offsetMatrix.makeRotationFromEuler(o.offsetEuler),o.scrollDiffEuler.x+=.01,o.scrollDiffMatrix.makeRotationFromEuler(o.scrollDiffEuler),o.currentMatrix.copy(o.offsetMatrix),o.currentMatrix.multiply(o.defMatrix),this.mesh.rotation.setFromRotationMatrix(o.currentMatrix)}}let eh=new f.Pq0(-10.7,-1,0),ed=e=>(e.add(eh),e.x*=1.08,e.y*=1.08,e.z*=1.08,e),ep={offsetStart:{position:new f.Pq0(0,-4,0),rotation:new f.Pq0(-Math.PI,0,0)},delay:0,duration:1,scale:1},ev=[{position:ed(new f.Pq0(0,0,0)),rotation:new f.Pq0(0,0,0),cubeType:"normal",isGlassRender:!0,...ep,layout:{tablet:{offset:new f.Pq0(.5,0,0),visible:!1},mobile:{offset:new f.Pq0(1.2,0,0),visible:!1}}},{position:ed(new f.Pq0(1,0,0)),rotation:new f.Pq0(-Math.PI/2,0,0),cubeType:"normal",isGlassRender:!0,...ep,layout:{tablet:{offset:new f.Pq0(.5,0,0),visible:!1},mobile:{offset:new f.Pq0(1.2,0,0),visible:!1}}},{position:ed(new f.Pq0(2,0,0)),rotation:new f.Pq0(0,0,0),cubeType:"normal",isGlassRender:!0,...ep,layout:{tablet:{offset:new f.Pq0(.5,0,0),visible:!1},mobile:{offset:new f.Pq0(1.2,0,0),visible:!1}}},{position:ed(new f.Pq0(3,0,0)),rotation:new f.Pq0(-Math.PI/2,0,0),cubeType:"normal",isGlassRender:!0,...ep,layout:{tablet:{offset:new f.Pq0(.5,0,0),visible:!0},mobile:{offset:new f.Pq0(1.2,0,0),visible:!1}}},{position:ed(new f.Pq0(4,0,0)),rotation:new f.Pq0(0,0,0),cubeType:"normal",isGlassRender:!0,...ep,layout:{tablet:{offset:new f.Pq0(.5,0,0),visible:!0},mobile:{offset:new f.Pq0(1.2,0,0),visible:!0}}},{position:ed(new f.Pq0(5,0,0)),rotation:new f.Pq0(0,0,0),cubeType:"glass",isGlassRender:!1,...ep,layout:{tablet:{offset:new f.Pq0(.5,0,0),visible:!0},mobile:{offset:new f.Pq0(1.2,0,0),visible:!0}}},{position:ed(new f.Pq0(6.7,0,0)),rotation:new f.Pq0(0,0,0),cubeType:"normal",isGlassRender:!1,...ep,layout:{tablet:{offset:new f.Pq0(.5,0,0),visible:!0},mobile:{offset:new f.Pq0(1.2,0,0),visible:!0}}},{position:ed(new f.Pq0(14,0,0)),rotation:new f.Pq0(0,0,0),cubeType:"normal",isGlassRender:!0,...ep,layout:{tablet:{offset:new f.Pq0(-.5,0,0),visible:!0},mobile:{offset:new f.Pq0(-1.2,0,0),visible:!0}}},{position:ed(new f.Pq0(15,0,0)),rotation:new f.Pq0(0,0,0),cubeType:"glass",isGlassRender:!1,...ep,layout:{tablet:{offset:new f.Pq0(-.5,0,0),visible:!0},mobile:{offset:new f.Pq0(-1.2,0,0),visible:!0}}},{position:ed(new f.Pq0(16,0,0)),rotation:new f.Pq0(0,0,0),cubeType:"normal",isGlassRender:!1,...ep,layout:{tablet:{offset:new f.Pq0(-.5,0,0),visible:!0},mobile:{offset:new f.Pq0(-1.2,0,0),visible:!0}}},{position:ed(new f.Pq0(17,0,0)),rotation:new f.Pq0(-Math.PI/2,0,0),cubeType:"normal",isGlassRender:!1,...ep,layout:{tablet:{offset:new f.Pq0(-.5,0,0),visible:!0},mobile:{offset:new f.Pq0(-1.2,0,0),visible:!1}}},{position:ed(new f.Pq0(18,0,0)),rotation:new f.Pq0(0,0,0),cubeType:"normal",isGlassRender:!1,...ep,layout:{tablet:{offset:new f.Pq0(-.5,0,0),visible:!0},mobile:{offset:new f.Pq0(-1.2,0,0),visible:!1}}},{position:ed(new f.Pq0(20,0,0)),rotation:new f.Pq0(0,0,0),cubeType:"normal",isGlassRender:!1,...ep,layout:{tablet:{offset:new f.Pq0(-.5,0,0),visible:!1},mobile:{offset:new f.Pq0(-1.2,0,0),visible:!1}}}];ev.forEach((e,t)=>{e.delay=Math.abs(2*(t/(ev.length-1))-1),e.duration=1});let em={rotation:new f.Pq0(.25*Math.PI,-(.2*Math.PI),0),rotationOrder:"YXZ",groupAnim:{start:new f.Pq0(0,-.5,0),end:new f.Pq0(0,0,0),duration:4,ease:"expo.out"},cubes:ev},ew=new f.Pq0(0,-1,0),eb=e=>(e.add(ew),e.x*=1+.08*1.1,e.y*=1+.08*1.1,e.z*=1+.08*1.1,e),eg={offsetStart:{position:new f.Pq0(0,-3,0),rotation:new f.Pq0(0,0,0)},delay:0,duration:1,scale:1},eP=[{position:eb(new f.Pq0(-3,-1,6)),rotation:new f.Pq0(0,Math.PI,.5*Math.PI),cubeType:"normal",isGlassRender:!1,...eg,layout:{tablet:{offset:new f.Pq0(0,0,0),visible:!1},mobile:{offset:new f.Pq0(0,0,0),visible:!1}}},{position:eb(new f.Pq0(-3,-1,5)),rotation:new f.Pq0(0,.5*Math.PI,0),cubeType:"normal",isGlassRender:!1,...eg,layout:{tablet:{offset:new f.Pq0(0,0,0),visible:!0},mobile:{offset:new f.Pq0(4.5,-3,0),visible:!0}}},{position:eb(new f.Pq0(-3,0,4)),rotation:new f.Pq0(0,0,0),cubeType:"mosaic",isGlassRender:!1,...eg,layout:{tablet:{offset:new f.Pq0(0,0,0),visible:!0},mobile:{offset:new f.Pq0(4.5,-3,0),visible:!0}}},{position:eb(new f.Pq0(-3,0,3)),rotation:new f.Pq0(0,0,0),cubeType:"glass",isGlassRender:!1,...eg,layout:{tablet:{offset:new f.Pq0(0,0,0),visible:!0},mobile:{offset:new f.Pq0(4.5,-3,0),visible:!0}}},{position:eb(new f.Pq0(-3,0,2)),rotation:new f.Pq0(0,.5*Math.PI,0),cubeType:"normal",isGlassRender:!0,...eg,layout:{tablet:{offset:new f.Pq0(0,0,0),visible:!0},mobile:{offset:new f.Pq0(4.5,-3,0),visible:!0}}},{position:eb(new f.Pq0(0,-1,0)),rotation:new f.Pq0(0,Math.PI,.5*Math.PI),cubeType:"normal",isGlassRender:!1,...eg,layout:{tablet:{offset:new f.Pq0(0,0,0),visible:!0},mobile:{offset:new f.Pq0(0,0,0),visible:!1}}},{position:eb(new f.Pq0(-1,0,0)),rotation:new f.Pq0(0,0,0),cubeType:"normal",isGlassRender:!0,...eg,layout:{tablet:{offset:new f.Pq0(0,0,0),visible:!0},mobile:{offset:new f.Pq0(0,0,0),visible:!1}}},{position:eb(new f.Pq0(0,0,0)),rotation:new f.Pq0(0,0,0),cubeType:"whiteGreen",isGlassRender:!1,...eg,layout:{tablet:{offset:new f.Pq0(0,0,0),visible:!0},mobile:{offset:new f.Pq0(0,0,0),visible:!1}}},{position:eb(new f.Pq0(3,-1,-3)),rotation:new f.Pq0(0,.5*Math.PI,.5*Math.PI),cubeType:"normal",isGlassRender:!1,...eg,layout:{tablet:{offset:new f.Pq0(0,0,0),visible:!0},mobile:{offset:new f.Pq0(-2.6,1.5,0),visible:!0}}},{position:eb(new f.Pq0(3,0,-3)),rotation:new f.Pq0(0,0,0),cubeType:"normal",isGlassRender:!1,...eg,layout:{tablet:{offset:new f.Pq0(0,0,0),visible:!0},mobile:{offset:new f.Pq0(-2.6,1.5,0),visible:!0}}},{position:eb(new f.Pq0(4,0,-3)),rotation:new f.Pq0(0,0,0),cubeType:"mosaic",isGlassRender:!1,...eg,layout:{tablet:{offset:new f.Pq0(0,0,0),visible:!0},mobile:{offset:new f.Pq0(0,0,0),visible:!1}}},{position:eb(new f.Pq0(5,-1.2,-3)),rotation:new f.Pq0(0,Math.PI,.5*Math.PI),cubeType:"normal",isGlassRender:!0,...eg,layout:{tablet:{offset:new f.Pq0(0,0,0),visible:!1},mobile:{offset:new f.Pq0(0,0,0),visible:!1}}},{position:eb(new f.Pq0(6,-1.2,-3)),rotation:new f.Pq0(0,0,0),cubeType:"glass",isGlassRender:!1,...eg,layout:{tablet:{offset:new f.Pq0(0,0,0),visible:!0},mobile:{offset:new f.Pq0(0,0,0),visible:!1}}}];eP.forEach((e,t)=>{e.delay=(1-Math.abs(2*(t/(eP.length-1))-1))*.5,e.duration=1});let ey={rotation:new f.Pq0(-(.22*Math.PI),-(.25*Math.PI),0),rotationOrder:"XYZ",groupAnim:{start:new f.Pq0(0,-1,0),end:new f.Pq0(0,0,0),duration:4,ease:"expo.out"},cubes:eP},ex=new f.Pq0(0,-1,0),eq=e=>(e.add(ex),e.x*=1+.08*1.1,e.y*=1+.08*1.1,e.z*=1+.08*1.1,e),eC={offsetStart:{position:new f.Pq0(0,-3,0),rotation:new f.Pq0(0,0,0)},delay:0,duration:1,scale:1},eR=[{position:eq(new f.Pq0(-3.8,0,3.8)),rotation:new f.Pq0(0,0,0),cubeType:"normal",isGlassRender:!1,...eC,layout:{tablet:{offset:new f.Pq0(.6,0,-.6),visible:!0},mobile:{offset:new f.Pq0(0,0,0),visible:!1}}},{position:eq(new f.Pq0(-3.8,0,2.8)),rotation:new f.Pq0(.5*Math.PI,0,0),cubeType:"normal",isGlassRender:!1,...eC,layout:{tablet:{offset:new f.Pq0(.6,0,-.6),visible:!0},mobile:{offset:new f.Pq0(0,0,0),visible:!1}}},{position:eq(new f.Pq0(-2.8,0,2.8)),rotation:new f.Pq0(0,0,0),cubeType:"mosaic",isGlassRender:!1,...eC,layout:{tablet:{offset:new f.Pq0(.6,0,-.6),visible:!0},mobile:{offset:new f.Pq0(0,0,0),visible:!1}}},{position:eq(new f.Pq0(-1.8,0,1.8)),rotation:new f.Pq0(.5*Math.PI,0,0),cubeType:"normal2",isGlassRender:!1,...eC,layout:{tablet:{offset:new f.Pq0(.6,0,-.6),visible:!0},mobile:{offset:new f.Pq0(0,0,0),visible:!1}}},{position:eq(new f.Pq0(0,0,0)),rotation:new f.Pq0(0,0,0),cubeType:"normal",isGlassRender:!1,...eC,layout:{tablet:{offset:new f.Pq0(0,0,0),visible:!0},mobile:{offset:new f.Pq0(0,0,0),visible:!1}}},{position:eq(new f.Pq0(0,0,-1)),rotation:new f.Pq0(0,0,0),cubeType:"rainbow",isGlassRender:!0,...eC,layout:{tablet:{offset:new f.Pq0(0,0,0),visible:!0},mobile:{offset:new f.Pq0(0,0,0),visible:!0}}},{position:eq(new f.Pq0(1,0,-1)),rotation:new f.Pq0(0,0,0),cubeType:"glass",isGlassRender:!1,...eC,layout:{tablet:{offset:new f.Pq0(0,0,0),visible:!0},mobile:{offset:new f.Pq0(0,0,0),visible:!0}}},{position:eq(new f.Pq0(1,0,-2)),rotation:new f.Pq0(0,0,0),cubeType:"normal",isGlassRender:!0,...eC,layout:{tablet:{offset:new f.Pq0(0,0,0),visible:!0},mobile:{offset:new f.Pq0(0,0,0),visible:!0}}},{position:eq(new f.Pq0(2,0,-2)),rotation:new f.Pq0(0,0,0),cubeType:"glass",isGlassRender:!1,...eC,layout:{tablet:{offset:new f.Pq0(0,0,0),visible:!0},mobile:{offset:new f.Pq0(0,0,0),visible:!0}}},{position:eq(new f.Pq0(3,0,-3)),rotation:new f.Pq0(0,.5*Math.PI,.5*Math.PI),cubeType:"normal",isGlassRender:!1,...eC,layout:{tablet:{offset:new f.Pq0(0,0,0),visible:!0},mobile:{offset:new f.Pq0(0,0,0),visible:!0}}},{position:eq(new f.Pq0(3,0,-4)),rotation:new f.Pq0(.5*Math.PI,0,0),cubeType:"normal",isGlassRender:!1,...eC,layout:{tablet:{offset:new f.Pq0(0,0,0),visible:!0},mobile:{offset:new f.Pq0(0,0,0),visible:!0}}},{position:eq(new f.Pq0(4,0,-4)),rotation:new f.Pq0(0,-(.5*Math.PI),.5*Math.PI),cubeType:"normal2",isGlassRender:!1,...eC,layout:{tablet:{offset:new f.Pq0(0,0,0),visible:!0},mobile:{offset:new f.Pq0(0,0,0),visible:!0}}}];eR.forEach((e,t)=>{e.delay=Math.abs(2*(t/(eR.length-1))-1),e.duration=1});let eM={rotation:new f.Pq0(.2*Math.PI,-(.25*Math.PI),0),rotationOrder:"XYZ",groupAnim:{start:new f.Pq0(0,-1,0),end:new f.Pq0(0,0,0),duration:4,ease:"expo.out"},cubes:eR},eD=new f.Pq0(0,-1,0),eT=e=>(e.add(eD),e.x*=1+.08*1.1,e.y*=1+.08*1.1,e.z*=1+.08*1.1,e),eG={offsetStart:{position:new f.Pq0(0,-3,0),rotation:new f.Pq0(0,0,0)},delay:0,duration:1,scale:1},eI=[{position:eT(new f.Pq0(-3.8,0,3.8)),rotation:new f.Pq0(0,0,0),cubeType:"normal",isGlassRender:!1,...eG,layout:{tablet:{offset:new f.Pq0(.6,0,-.6),visible:!0},mobile:{offset:new f.Pq0(0,0,0),visible:!1}}},{position:eT(new f.Pq0(-3.8,0,2.8)),rotation:new f.Pq0(.5*Math.PI,0,0),cubeType:"normal",isGlassRender:!1,...eG,layout:{tablet:{offset:new f.Pq0(.6,0,-.6),visible:!0},mobile:{offset:new f.Pq0(0,0,0),visible:!1}}},{position:eT(new f.Pq0(-2.8,0,2.8)),rotation:new f.Pq0(0,0,0),cubeType:"mosaic",isGlassRender:!1,...eG,layout:{tablet:{offset:new f.Pq0(.6,0,-.6),visible:!0},mobile:{offset:new f.Pq0(0,0,0),visible:!1}}},{position:eT(new f.Pq0(-1.8,0,1.8)),rotation:new f.Pq0(.5*Math.PI,0,0),cubeType:"normal2",isGlassRender:!1,...eG,layout:{tablet:{offset:new f.Pq0(.6,0,-.6),visible:!0},mobile:{offset:new f.Pq0(0,0,0),visible:!1}}},{position:eT(new f.Pq0(0,0,0)),rotation:new f.Pq0(0,0,0),cubeType:"normal",isGlassRender:!1,...eG,layout:{tablet:{offset:new f.Pq0(0,0,0),visible:!0},mobile:{offset:new f.Pq0(0,0,0),visible:!1}}},{position:eT(new f.Pq0(0,0,-1)),rotation:new f.Pq0(0,0,0),cubeType:"rainbow",isGlassRender:!0,...eG,layout:{tablet:{offset:new f.Pq0(0,0,0),visible:!0},mobile:{offset:new f.Pq0(0,0,0),visible:!0}}},{position:eT(new f.Pq0(1,0,-1)),rotation:new f.Pq0(0,0,0),cubeType:"glass",isGlassRender:!1,...eG,layout:{tablet:{offset:new f.Pq0(0,0,0),visible:!0},mobile:{offset:new f.Pq0(0,0,0),visible:!0}}},{position:eT(new f.Pq0(1,0,-2)),rotation:new f.Pq0(Math.PI/2,0,0),cubeType:"normal2",isGlassRender:!0,...eG,layout:{tablet:{offset:new f.Pq0(0,0,0),visible:!0},mobile:{offset:new f.Pq0(0,0,0),visible:!0}}},{position:eT(new f.Pq0(2,0,-2)),rotation:new f.Pq0(0,0,0),cubeType:"glass",isGlassRender:!1,...eG,layout:{tablet:{offset:new f.Pq0(0,0,0),visible:!0},mobile:{offset:new f.Pq0(0,0,0),visible:!0}}},{position:eT(new f.Pq0(3,0,-3)),rotation:new f.Pq0(0,.5*Math.PI,.5*Math.PI),cubeType:"normal",isGlassRender:!1,...eG,layout:{tablet:{offset:new f.Pq0(0,0,0),visible:!0},mobile:{offset:new f.Pq0(0,0,0),visible:!0}}},{position:eT(new f.Pq0(3,0,-4)),rotation:new f.Pq0(.5*Math.PI,0,0),cubeType:"normal",isGlassRender:!1,...eG,layout:{tablet:{offset:new f.Pq0(0,0,0),visible:!0},mobile:{offset:new f.Pq0(0,0,0),visible:!0}}},{position:eT(new f.Pq0(4,0,-4)),rotation:new f.Pq0(0,-(.5*Math.PI),.5*Math.PI),cubeType:"normal2",isGlassRender:!1,...eG,layout:{tablet:{offset:new f.Pq0(0,0,0),visible:!0},mobile:{offset:new f.Pq0(0,0,0),visible:!0}}}];eI.forEach((e,t)=>{e.delay=Math.abs(2*(t/(eI.length-1))-1),e.duration=1});let eS={rotation:new f.Pq0(.2*Math.PI,-(.25*Math.PI),0),rotationOrder:"XYZ",groupAnim:{start:new f.Pq0(0,-1,0),end:new f.Pq0(0,0,0),duration:4,ease:"expo.out"},cubes:eI},ez=new f.Pq0(-11,-1,0),eE=e=>(e.add(ez),e.x*=1.08,e.y*=1.08,e.z*=1.08,e),ek={offsetStart:{position:new f.Pq0(0,-4,0),rotation:new f.Pq0(-Math.PI,0,0)},delay:0,duration:1,scale:1},e_=[{position:eE(new f.Pq0(0,0,0)),rotation:new f.Pq0(0,0,0),cubeType:"normal",isGlassRender:!0,...ek,layout:{tablet:{offset:new f.Pq0(0,0,0),visible:!1},mobile:{offset:new f.Pq0(1.5,0,0),visible:!1}}},{position:eE(new f.Pq0(1,0,0)),rotation:new f.Pq0(-Math.PI/2,0,0),cubeType:"normal",isGlassRender:!0,...ek,layout:{tablet:{offset:new f.Pq0(0,0,0),visible:!1},mobile:{offset:new f.Pq0(1.5,0,0),visible:!1}}},{position:eE(new f.Pq0(2,0,0)),rotation:new f.Pq0(0,0,0),cubeType:"normal",isGlassRender:!0,...ek,layout:{tablet:{offset:new f.Pq0(0,0,0),visible:!0},mobile:{offset:new f.Pq0(1.5,0,0),visible:!1}}},{position:eE(new f.Pq0(3,0,0)),rotation:new f.Pq0(-Math.PI/2,0,0),cubeType:"normal",isGlassRender:!0,...ek,layout:{tablet:{offset:new f.Pq0(0,0,0),visible:!0},mobile:{offset:new f.Pq0(1.5,0,0),visible:!0}}},{position:eE(new f.Pq0(4,0,0)),rotation:new f.Pq0(0,0,0),cubeType:"normal",isGlassRender:!0,...ek,layout:{tablet:{offset:new f.Pq0(0,0,0),visible:!0},mobile:{offset:new f.Pq0(1.5,0,0),visible:!0}}},{position:eE(new f.Pq0(5,0,0)),rotation:new f.Pq0(0,0,0),cubeType:"glass",isGlassRender:!1,...ek,layout:{tablet:{offset:new f.Pq0(0,0,0),visible:!0},mobile:{offset:new f.Pq0(1.5,0,0),visible:!0}}},{position:eE(new f.Pq0(6.7,0,0)),rotation:new f.Pq0(0,0,0),cubeType:"normal",isGlassRender:!1,...ek,layout:{tablet:{offset:new f.Pq0(0,0,0),visible:!0},mobile:{offset:new f.Pq0(1.5,0,0),visible:!1}}},{position:eE(new f.Pq0(15.5,0,0)),rotation:new f.Pq0(-Math.PI/2,0,0),cubeType:"whiteGreen",isGlassRender:!1,...ek,layout:{tablet:{offset:new f.Pq0(0,0,0),visible:!0},mobile:{offset:new f.Pq0(-3,0,0),visible:!0}}},{position:eE(new f.Pq0(16.5,0,0)),rotation:new f.Pq0(0,0,0),cubeType:"whiteGreen",isGlassRender:!1,...ek,layout:{tablet:{offset:new f.Pq0(0,0,0),visible:!0},mobile:{offset:new f.Pq0(-3,0,0),visible:!0}}},{position:eE(new f.Pq0(17.5,0,0)),rotation:new f.Pq0(-Math.PI/2,0,0),cubeType:"whiteGreen",isGlassRender:!1,...ek,layout:{tablet:{offset:new f.Pq0(0,0,0),visible:!0},mobile:{offset:new f.Pq0(-3,0,0),visible:!0}}},{position:eE(new f.Pq0(18.5,0,0)),rotation:new f.Pq0(0,0,0),cubeType:"whiteGreen",isGlassRender:!1,...ek,layout:{tablet:{offset:new f.Pq0(0,0,0),visible:!1},mobile:{offset:new f.Pq0(-3,0,0),visible:!0}}},{position:eE(new f.Pq0(19.5,0,0)),rotation:new f.Pq0(-Math.PI/2,0,0),cubeType:"whiteGreen",isGlassRender:!1,...ek,layout:{tablet:{offset:new f.Pq0(0,0,0),visible:!1},mobile:{offset:new f.Pq0(-3,0,0),visible:!1}}},{position:eE(new f.Pq0(20.5,0,0)),rotation:new f.Pq0(0,0,0),cubeType:"whiteGreen",isGlassRender:!1,...ek,layout:{tablet:{offset:new f.Pq0(0,0,0),visible:!1},mobile:{offset:new f.Pq0(-3,0,0),visible:!1}}},{position:eE(new f.Pq0(21.5,0,0)),rotation:new f.Pq0(-Math.PI/2,0,0),cubeType:"whiteGreen",isGlassRender:!1,...ek,layout:{tablet:{offset:new f.Pq0(0,0,0),visible:!1},mobile:{offset:new f.Pq0(-3,0,0),visible:!1}}}];e_.forEach((e,t)=>{e.delay=Math.abs(2*(t/(e_.length-1))-1),e.duration=1});let eB={rotation:new f.Pq0(.25*Math.PI,-(.2*Math.PI),0),rotationOrder:"YXZ",groupAnim:{start:new f.Pq0(0,-.5,0),end:new f.Pq0(0,0,0),duration:4,ease:"expo.out"},cubes:e_},eF=new f.Pq0(0,-1,0),eN=e=>(e.add(eF),e.x*=1+.08*1.1,e.y*=1+.08*1.1,e.z*=1+.08*1.1,e),eA={offsetStart:{position:new f.Pq0(0,-3,0),rotation:new f.Pq0(0,0,0)},delay:0,duration:1,scale:1},eY=[{position:eN(new f.Pq0(-3,-1,5)),rotation:new f.Pq0(0,.5*Math.PI,0),cubeType:"glassNoBlur",isGlassRender:!1,...eA,layout:{tablet:{offset:new f.Pq0(0,0,0),visible:!0},mobile:{offset:new f.Pq0(0,0,0),visible:!1}}},{position:eN(new f.Pq0(-3,0,4)),rotation:new f.Pq0(0,0,0),cubeType:"mosaic",isGlassRender:!1,...eA,layout:{tablet:{offset:new f.Pq0(0,0,0),visible:!0},mobile:{offset:new f.Pq0(1,0,-2),visible:!0}}},{position:eN(new f.Pq0(-2,-1,4)),rotation:new f.Pq0(0,0,0),cubeType:"glassNoBlur",isGlassRender:!1,...eA,layout:{tablet:{offset:new f.Pq0(0,0,0),visible:!0},mobile:{offset:new f.Pq0(0,0,0),visible:!1}}},{position:eN(new f.Pq0(-3,0,2)),rotation:new f.Pq0(0,.5*Math.PI,0),cubeType:"glassMosaic",isGlassRender:!1,...eA,layout:{tablet:{offset:new f.Pq0(0,0,0),visible:!0},mobile:{offset:new f.Pq0(0,0,0),visible:!1}}},{position:eN(new f.Pq0(-1.2,0,0)),rotation:new f.Pq0(0,0,0),cubeType:"normal",isGlassRender:!1,...eA,layout:{tablet:{offset:new f.Pq0(0,0,0),visible:!0},mobile:{offset:new f.Pq0(0,0,0),visible:!0}}},{position:eN(new f.Pq0(0,0,0)),rotation:new f.Pq0(0,0,0),cubeType:"whiteGreen",isGlassRender:!1,...eA,layout:{tablet:{offset:new f.Pq0(0,0,0),visible:!0},mobile:{offset:new f.Pq0(0,0,0),visible:!0}}},{position:eN(new f.Pq0(3,0,-3)),rotation:new f.Pq0(0,0,0),cubeType:"glassNoBlur",isGlassRender:!1,...eA,layout:{tablet:{offset:new f.Pq0(0,0,0),visible:!0},mobile:{offset:new f.Pq0(0,0,0),visible:!1}}},{position:eN(new f.Pq0(4,0,-3)),rotation:new f.Pq0(0,0,0),cubeType:"mosaic",isGlassRender:!1,...eA,layout:{tablet:{offset:new f.Pq0(0,0,0),visible:!0},mobile:{offset:new f.Pq0(0,0,0),visible:!1}}},{position:eN(new f.Pq0(5,-1.2,-3)),rotation:new f.Pq0(0,Math.PI,.5*Math.PI),cubeType:"glassNoBlur",isGlassRender:!1,...eA,layout:{tablet:{offset:new f.Pq0(0,0,0),visible:!0},mobile:{offset:new f.Pq0(0,0,0),visible:!1}}}];eY.forEach((e,t)=>{e.delay=(1-Math.abs(2*(t/(eY.length-1))-1))*.5,e.duration=1});let eO={rotation:new f.Pq0(-(.2*Math.PI),-(.25*Math.PI),0),rotationOrder:"XYZ",groupAnim:{start:new f.Pq0(0,-1,0),end:new f.Pq0(0,0,0),duration:4,ease:"expo.out"},cubes:eY},eU=new f.Pq0(0,-1.4,0),eL=e=>(e.add(eU),e.x*=1+.08*1.1,e.y*=1+.08*1.1,e.z*=1+.08*1.1,e),eQ={position:new f.Pq0(0,-3,0),rotation:new f.Pq0(0,0,0)},eW={offsetStart:eQ,delay:0,duration:1,scale:1},eX=[{position:eL(new f.Pq0(-3,-1,6)),rotation:new f.Pq0(0,0,0),cubeType:"whiteBlue",isGlassRender:!1,...eW,layout:{tablet:{offset:new f.Pq0(.9,0,-.9),visible:!0},mobile:{offset:new f.Pq0(0,0,0),visible:!1}}},{position:eL(new f.Pq0(-3,-1,5)),rotation:new f.Pq0(0,0,0),cubeType:"whiteBlue",isGlassRender:!1,...eW,layout:{tablet:{offset:new f.Pq0(.9,0,-.9),visible:!0},mobile:{offset:new f.Pq0(2,0,-2),visible:!0}}},{position:eL(new f.Pq0(-3,-2,4)),rotation:new f.Pq0(0,Math.PI,.5*Math.PI),cubeType:"normal",isGlassRender:!1,...eW,layout:{tablet:{offset:new f.Pq0(.9,0,-.9),visible:!0},mobile:{offset:new f.Pq0(0,0,0),visible:!1}}},{position:eL(new f.Pq0(-3,-1,2)),rotation:new f.Pq0(0,.5*Math.PI,0),cubeType:"normal",isGlassRender:!1,...eW,layout:{tablet:{offset:new f.Pq0(.9,0,-.9),visible:!0},mobile:{offset:new f.Pq0(0,0,0),visible:!1}}},{position:eL(new f.Pq0(-3,0,4)),rotation:new f.Pq0(0,0,0),cubeType:"mosaic",isGlassRender:!1,...eW,layout:{tablet:{offset:new f.Pq0(.9,0,-.9),visible:!0},mobile:{offset:new f.Pq0(2,0,-2),visible:!0}}},{position:eL(new f.Pq0(-2,-1.5,3.5)),rotation:new f.Pq0(0,.5*Math.PI,0),cubeType:"whiteGreen",isGlassRender:!1,offsetStart:eQ,delay:0,duration:1,scale:1.5,layout:{tablet:{offset:new f.Pq0(.9,0,-.9),visible:!0},mobile:{offset:new f.Pq0(0,0,0),visible:!1}}},{position:eL(new f.Pq0(3.5,-1.5,-2)),rotation:new f.Pq0(0,.5*Math.PI,0),cubeType:"whiteGreen",isGlassRender:!1,offsetStart:eQ,delay:0,duration:1,scale:1.5,layout:{tablet:{offset:new f.Pq0(-.9,0,.9),visible:!0},mobile:{offset:new f.Pq0(0,0,0),visible:!0}}},{position:eL(new f.Pq0(4,0,-3)),rotation:new f.Pq0(0,0,0),cubeType:"mosaic",isGlassRender:!1,...eW,layout:{tablet:{offset:new f.Pq0(-.9,0,.9),visible:!0},mobile:{offset:new f.Pq0(0,0,0),visible:!1}}},{position:eL(new f.Pq0(5,-1.2,-3)),rotation:new f.Pq0(.5*Math.PI,0,-(.5*Math.PI)),cubeType:"normal",isGlassRender:!1,...eW,layout:{tablet:{offset:new f.Pq0(-.9,0,.9),visible:!0},mobile:{offset:new f.Pq0(-3,1.3,2),visible:!0}}},{position:eL(new f.Pq0(6,-1.2,-3)),rotation:new f.Pq0(0,0,0),cubeType:"normal",isGlassRender:!1,...eW,layout:{tablet:{offset:new f.Pq0(-.9,0,.9),visible:!0},mobile:{offset:new f.Pq0(0,0,0),visible:!1}}}];eX.forEach((e,t)=>{e.delay=(1-Math.abs(2*(t/(eX.length-1))-1))*.5,e.duration=1});let ej={rotation:new f.Pq0(-(.2*Math.PI),-(.25*Math.PI),0),rotationOrder:"XYZ",groupAnim:{start:new f.Pq0(0,-1,0),end:new f.Pq0(0,0,0),duration:4,ease:"expo.out"},cubes:eX},e$=new f.Pq0(0,-1.2,0),eZ=e=>(e.add(e$),e.x*=1+.08*1.1,e.y*=1+.08*1.1,e.z*=1+.08*1.1,e),eH={offsetStart:{position:new f.Pq0(0,-3,0),rotation:new f.Pq0(0,0,0)},delay:0,duration:1,scale:1},eK=[{position:eZ(new f.Pq0(-3,-1,6)),rotation:new f.Pq0(0,Math.PI,.5*Math.PI),cubeType:"normal",isGlassRender:!1,...eH,layout:{tablet:{offset:new f.Pq0(0,0,0),visible:!0},mobile:{offset:new f.Pq0(1,0,-1.5),visible:!0}}},{position:eZ(new f.Pq0(-3,-2,4)),rotation:new f.Pq0(0,Math.PI,.5*Math.PI),cubeType:"normal",isGlassRender:!1,...eH,layout:{tablet:{offset:new f.Pq0(0,0,0),visible:!0},mobile:{offset:new f.Pq0(1,0,-1.5),visible:!0}}},{position:eZ(new f.Pq0(-3,-1,2)),rotation:new f.Pq0(0,.5*Math.PI,0),cubeType:"normal",isGlassRender:!1,...eH,layout:{tablet:{offset:new f.Pq0(0,0,0),visible:!0},mobile:{offset:new f.Pq0(1,0,-1.5),visible:!0}}},{position:eZ(new f.Pq0(-3,0,4)),rotation:new f.Pq0(0,0,0),cubeType:"mosaic",isGlassRender:!1,...eH,layout:{tablet:{offset:new f.Pq0(0,0,0),visible:!0},mobile:{offset:new f.Pq0(1,0,-1.5),visible:!0}}},{position:eZ(new f.Pq0(-3,0,3)),rotation:new f.Pq0(0,0,0),cubeType:"glass",isGlassRender:!1,...eH,layout:{tablet:{offset:new f.Pq0(0,0,0),visible:!0},mobile:{offset:new f.Pq0(1,0,-1.5),visible:!0}}},{position:eZ(new f.Pq0(-3,0,2)),rotation:new f.Pq0(0,.5*Math.PI,0),cubeType:"normal",isGlassRender:!0,...eH,layout:{tablet:{offset:new f.Pq0(0,0,0),visible:!0},mobile:{offset:new f.Pq0(1,0,-1.5),visible:!0}}},{position:eZ(new f.Pq0(-1,.2,.6)),rotation:new f.Pq0(Math.PI,0,0),cubeType:"normal",isGlassRender:!0,...eH,layout:{tablet:{offset:new f.Pq0(0,0,0),visible:!0},mobile:{offset:new f.Pq0(0,0,0),visible:!0}}},{position:eZ(new f.Pq0(.6,.2,-1)),rotation:new f.Pq0(Math.PI,.5*Math.PI,0),cubeType:"normal",isGlassRender:!0,...eH,layout:{tablet:{offset:new f.Pq0(0,0,0),visible:!0},mobile:{offset:new f.Pq0(0,0,0),visible:!0}}},{position:eZ(new f.Pq0(2,0,-3)),rotation:new f.Pq0(0,0,0),cubeType:"normal",isGlassRender:!0,...eH,layout:{tablet:{offset:new f.Pq0(0,0,0),visible:!0},mobile:{offset:new f.Pq0(-1.5,0,1),visible:!0}}},{position:eZ(new f.Pq0(3,0,-3)),rotation:new f.Pq0(0,0,0),cubeType:"glass",isGlassRender:!1,...eH,layout:{tablet:{offset:new f.Pq0(0,0,0),visible:!0},mobile:{offset:new f.Pq0(-1.5,0,1),visible:!0}}},{position:eZ(new f.Pq0(4,0,-3)),rotation:new f.Pq0(0,0,0),cubeType:"mosaic",isGlassRender:!1,...eH,layout:{tablet:{offset:new f.Pq0(0,0,0),visible:!0},mobile:{offset:new f.Pq0(-1.5,0,1),visible:!0}}},{position:eZ(new f.Pq0(5,0,-4)),rotation:new f.Pq0(0,.5*Math.PI,.5*Math.PI),cubeType:"normal",isGlassRender:!1,...eH,layout:{tablet:{offset:new f.Pq0(0,0,0),visible:!0},mobile:{offset:new f.Pq0(-1.5,0,1),visible:!0}}}];eK.forEach((e,t)=>{e.delay=(1-Math.abs(2*(t/(eK.length-1))-1))*.5,e.duration=1});let eV={rotation:new f.Pq0(-(.2*Math.PI),-(.25*Math.PI),0),rotationOrder:"XYZ",groupAnim:{start:new f.Pq0(0,-1,0),end:new f.Pq0(0,0,0),duration:4,ease:"expo.out"},cubes:eK},eJ=new f.Pq0(0,-1,0),e0=e=>(e.add(eJ),e.x*=1+.08*1.1,e.y*=1+.08*1.1,e.z*=1+.08*1.1,e),e1={offsetStart:{position:new f.Pq0(0,-3,0),rotation:new f.Pq0(0,0,0)},delay:0,duration:1,scale:1},e2=[{position:e0(new f.Pq0(-3.8,0,3.8)),rotation:new f.Pq0(0,0,0),cubeType:"normal",isGlassRender:!1,...e1,layout:{tablet:{offset:new f.Pq0(.6,0,-.6),visible:!0},mobile:{offset:new f.Pq0(0,0,0),visible:!1}}},{position:e0(new f.Pq0(-3.8,0,2.8)),rotation:new f.Pq0(.5*Math.PI,0,0),cubeType:"normal",isGlassRender:!1,...e1,layout:{tablet:{offset:new f.Pq0(.6,0,-.6),visible:!0},mobile:{offset:new f.Pq0(0,0,0),visible:!1}}},{position:e0(new f.Pq0(-2.8,0,2.8)),rotation:new f.Pq0(0,0,0),cubeType:"mosaic",isGlassRender:!1,...e1,layout:{tablet:{offset:new f.Pq0(.6,0,-.6),visible:!0},mobile:{offset:new f.Pq0(0,0,0),visible:!1}}},{position:e0(new f.Pq0(-1.8,0,1.8)),rotation:new f.Pq0(.5*Math.PI,0,0),cubeType:"normal2",isGlassRender:!1,...e1,layout:{tablet:{offset:new f.Pq0(.6,0,-.6),visible:!0},mobile:{offset:new f.Pq0(0,0,0),visible:!1}}},{position:e0(new f.Pq0(0,0,0)),rotation:new f.Pq0(0,0,0),cubeType:"normal",isGlassRender:!1,...e1,layout:{tablet:{offset:new f.Pq0(0,0,0),visible:!0},mobile:{offset:new f.Pq0(0,0,0),visible:!0}}},{position:e0(new f.Pq0(0,0,-1)),rotation:new f.Pq0(0,0,0),cubeType:"rainbow",isGlassRender:!0,...e1,layout:{tablet:{offset:new f.Pq0(0,0,0),visible:!0},mobile:{offset:new f.Pq0(0,0,0),visible:!0}}},{position:e0(new f.Pq0(1,0,-1)),rotation:new f.Pq0(0,0,0),cubeType:"glass",isGlassRender:!1,...e1,layout:{tablet:{offset:new f.Pq0(0,0,0),visible:!0},mobile:{offset:new f.Pq0(0,0,0),visible:!0}}},{position:e0(new f.Pq0(1,0,-2)),rotation:new f.Pq0(.5*Math.PI,0,0),cubeType:"normal2",isGlassRender:!0,...e1,layout:{tablet:{offset:new f.Pq0(0,0,0),visible:!0},mobile:{offset:new f.Pq0(0,0,0),visible:!0}}},{position:e0(new f.Pq0(3,0,-4)),rotation:new f.Pq0(0,.5*Math.PI,.5*Math.PI),cubeType:"normal",isGlassRender:!1,...e1,layout:{tablet:{offset:new f.Pq0(0,0,0),visible:!0},mobile:{offset:new f.Pq0(0,0,0),visible:!0}}},{position:e0(new f.Pq0(4,0,-4)),rotation:new f.Pq0(.5*Math.PI,0,0),cubeType:"normal2",isGlassRender:!1,...e1,layout:{tablet:{offset:new f.Pq0(0,0,0),visible:!0},mobile:{offset:new f.Pq0(0,0,0),visible:!0}}}];e2.forEach((e,t)=>{e.delay=Math.abs(2*(t/(e2.length-1))-1),e.duration=1});let e3={rotation:new f.Pq0(Math.PI/5,-(.25*Math.PI),0),rotationOrder:"XYZ",groupAnim:{start:new f.Pq0(0,-1,0),end:new f.Pq0(0,0,0),duration:4,ease:"expo.out"},cubes:e2},e5=new f.Pq0(0,-1,0),e4=e=>(e.add(e5),e.x*=1+.08*1.1,e.y*=1+.08*1.1,e.z*=1+.08*1.1,e),e8={offsetStart:{position:new f.Pq0(0,-3,0),rotation:new f.Pq0(0,0,0)},delay:0,duration:1,scale:1},e6=[{position:e4(new f.Pq0(-3,-1,6)),rotation:new f.Pq0(0,Math.PI,.5*Math.PI),cubeType:"normal",isGlassRender:!1,...e8,layout:{tablet:{offset:new f.Pq0(.4,0,-.4),visible:!0},mobile:{offset:new f.Pq0(2,0,-2),visible:!0}}},{position:e4(new f.Pq0(-3,-1,5)),rotation:new f.Pq0(0,.5*Math.PI,0),cubeType:"normal",isGlassRender:!1,...e8,layout:{tablet:{offset:new f.Pq0(.4,0,-.4),visible:!0},mobile:{offset:new f.Pq0(2,0,-2),visible:!0}}},{position:e4(new f.Pq0(-3,-2,4)),rotation:new f.Pq0(0,Math.PI,.5*Math.PI),cubeType:"normal",isGlassRender:!1,...e8,layout:{tablet:{offset:new f.Pq0(.4,0,-.4),visible:!0},mobile:{offset:new f.Pq0(2,0,-2),visible:!0}}},{position:e4(new f.Pq0(-3,-1,2)),rotation:new f.Pq0(0,.5*Math.PI,0),cubeType:"normal",isGlassRender:!1,...e8,layout:{tablet:{offset:new f.Pq0(.4,0,-.4),visible:!0},mobile:{offset:new f.Pq0(2,0,-2),visible:!0}}},{position:e4(new f.Pq0(-3,0,4)),rotation:new f.Pq0(0,0,0),cubeType:"mosaic",isGlassRender:!1,...e8,layout:{tablet:{offset:new f.Pq0(.4,0,-.4),visible:!0},mobile:{offset:new f.Pq0(2,0,-2),visible:!0}}},{position:e4(new f.Pq0(-3,0,3)),rotation:new f.Pq0(0,0,0),cubeType:"glass",isGlassRender:!1,...e8,layout:{tablet:{offset:new f.Pq0(.4,0,-.4),visible:!0},mobile:{offset:new f.Pq0(2,0,-2),visible:!0}}},{position:e4(new f.Pq0(-3,0,2)),rotation:new f.Pq0(0,.5*Math.PI,0),cubeType:"normal",isGlassRender:!0,...e8,layout:{tablet:{offset:new f.Pq0(.4,0,-.4),visible:!0},mobile:{offset:new f.Pq0(2,0,-2),visible:!0}}},{position:e4(new f.Pq0(0,-1,0)),rotation:new f.Pq0(0,Math.PI,.5*Math.PI),cubeType:"normal",isGlassRender:!1,...e8,layout:{tablet:{offset:new f.Pq0(0,0,0),visible:!0},mobile:{offset:new f.Pq0(0,0,0),visible:!1}}},{position:e4(new f.Pq0(-1,0,0)),rotation:new f.Pq0(0,0,0),cubeType:"normal",isGlassRender:!0,...e8,layout:{tablet:{offset:new f.Pq0(0,0,0),visible:!0},mobile:{offset:new f.Pq0(0,0,0),visible:!1}}},{position:e4(new f.Pq0(0,0,0)),rotation:new f.Pq0(0,0,0),cubeType:"whiteGreen",isGlassRender:!1,...e8,layout:{tablet:{offset:new f.Pq0(0,0,0),visible:!0},mobile:{offset:new f.Pq0(1.76,0,-1.76),visible:!0}}},{position:e4(new f.Pq0(2,-.4,-2)),rotation:new f.Pq0(.5*Math.PI,.5*Math.PI,0),cubeType:"normal",isGlassRender:!1,...e8,layout:{tablet:{offset:new f.Pq0(-.4,0,.4),visible:!0},mobile:{offset:new f.Pq0(-1.5,0,1.5),visible:!0}}},{position:e4(new f.Pq0(3,0,-3)),rotation:new f.Pq0(0,0,0),cubeType:"normal",isGlassRender:!1,...e8,layout:{tablet:{offset:new f.Pq0(-.4,0,.4),visible:!0},mobile:{offset:new f.Pq0(0,0,0),visible:!1}}},{position:e4(new f.Pq0(4,0,-3)),rotation:new f.Pq0(0,0,0),cubeType:"mosaic",isGlassRender:!1,...e8,layout:{tablet:{offset:new f.Pq0(-.4,0,.4),visible:!0},mobile:{offset:new f.Pq0(0,0,0),visible:!1}}},{position:e4(new f.Pq0(5,-1.2,-3)),rotation:new f.Pq0(0,Math.PI,.5*Math.PI),cubeType:"normal",isGlassRender:!0,...e8,layout:{tablet:{offset:new f.Pq0(-.4,0,.4),visible:!0},mobile:{offset:new f.Pq0(0,0,0),visible:!1}}},{position:e4(new f.Pq0(6,-1.2,-3)),rotation:new f.Pq0(0,0,0),cubeType:"glass",isGlassRender:!1,...e8,layout:{tablet:{offset:new f.Pq0(-.4,0,.4),visible:!0},mobile:{offset:new f.Pq0(0,0,0),visible:!1}}}];e6.forEach((e,t)=>{e.delay=1-Math.abs(2*(t/(e6.length-1))-1),e.duration=1});let e9={rotation:new f.Pq0(-Math.PI/5,-(.25*Math.PI),0),rotationOrder:"XYZ",scale:1,groupAnim:{start:new f.Pq0(0,-1,0),end:new f.Pq0(0,0,0),duration:4,ease:"expo.out"},cubes:e6},e7=new f.Pq0(0,-1,0),te=e=>(e.add(e7),e.x*=1+.08*1.1,e.y*=1+.08*1.1,e.z*=1+.08*1.1,e),tt={offsetStart:{position:new f.Pq0(0,-3,0),rotation:new f.Pq0(0,0,0)},delay:0,duration:1,scale:1},to=[{position:te(new f.Pq0(-3.8,0,3.8)),rotation:new f.Pq0(0,0,0),cubeType:"normal",isGlassRender:!1,...tt,layout:{tablet:{offset:new f.Pq0(.6,0,-.6),visible:!1},mobile:{offset:new f.Pq0(0,0,0),visible:!1}}},{position:te(new f.Pq0(-3.8,0,2.8)),rotation:new f.Pq0(.5*Math.PI,0,0),cubeType:"normal",isGlassRender:!1,...tt,layout:{tablet:{offset:new f.Pq0(.3,0,-.39999999999999997),visible:!0},mobile:{offset:new f.Pq0(0,0,0),visible:!1}}},{position:te(new f.Pq0(-2.8,0,2.8)),rotation:new f.Pq0(0,0,0),cubeType:"mosaic",isGlassRender:!1,...tt,layout:{tablet:{offset:new f.Pq0(.6,0,-.6),visible:!0},mobile:{offset:new f.Pq0(0,0,0),visible:!1}}},{position:te(new f.Pq0(-1.8,0,1.8)),rotation:new f.Pq0(.5*Math.PI,0,0),cubeType:"normal2",isGlassRender:!1,...tt,layout:{tablet:{offset:new f.Pq0(.6,0,-.6),visible:!0},mobile:{offset:new f.Pq0(0,0,0),visible:!1}}},{position:te(new f.Pq0(0,0,0)),rotation:new f.Pq0(0,0,0),cubeType:"normal",isGlassRender:!1,...tt,layout:{tablet:{offset:new f.Pq0(0,0,0),visible:!0},mobile:{offset:new f.Pq0(0,0,0),visible:!1}}},{position:te(new f.Pq0(0,0,-1)),rotation:new f.Pq0(0,0,0),cubeType:"rainbow",isGlassRender:!0,...tt,layout:{tablet:{offset:new f.Pq0(0,0,0),visible:!0},mobile:{offset:new f.Pq0(0,0,0),visible:!0}}},{position:te(new f.Pq0(1,0,-1)),rotation:new f.Pq0(0,0,0),cubeType:"glass",isGlassRender:!1,...tt,layout:{tablet:{offset:new f.Pq0(0,0,0),visible:!0},mobile:{offset:new f.Pq0(0,0,0),visible:!0}}},{position:te(new f.Pq0(1,0,-2)),rotation:new f.Pq0(0,0,0),cubeType:"normal",isGlassRender:!0,...tt,layout:{tablet:{offset:new f.Pq0(0,0,0),visible:!0},mobile:{offset:new f.Pq0(0,0,0),visible:!0}}},{position:te(new f.Pq0(2,0,-2)),rotation:new f.Pq0(0,0,0),cubeType:"glass",isGlassRender:!1,...tt,layout:{tablet:{offset:new f.Pq0(0,0,0),visible:!0},mobile:{offset:new f.Pq0(0,0,0),visible:!0}}},{position:te(new f.Pq0(3,0,-4)),rotation:new f.Pq0(.5*Math.PI,0,0),cubeType:"normal",isGlassRender:!1,...tt,layout:{tablet:{offset:new f.Pq0(0,0,0),visible:!0},mobile:{offset:new f.Pq0(0,0,0),visible:!0}}},{position:te(new f.Pq0(4,0,-4)),rotation:new f.Pq0(0,-(.5*Math.PI),.5*Math.PI),cubeType:"normal2",isGlassRender:!1,...tt,layout:{tablet:{offset:new f.Pq0(0,0,0),visible:!0},mobile:{offset:new f.Pq0(0,0,0),visible:!0}}}];to.forEach((e,t)=>{e.delay=Math.abs(2*(t/(to.length-1))-1),e.duration=1});let ti={rotation:new f.Pq0(.2*Math.PI,-(.25*Math.PI),0),rotationOrder:"XYZ",groupAnim:{start:new f.Pq0(0,-1,0),end:new f.Pq0(0,0,0),duration:4,ease:"expo.out"},cubes:to};class ts{camera=new f.qUd(-1,1,1,-1,.1,3e3);cubes=[];cubeGroup=new f.YJl;fbo1=new f.nWS(10,10);fbo2=new f.nWS(10,10);pixelRatio=.5;fboSize=new f.I9Y(10,10);rectData;blurPlane;blurRadius=12;texelSize=new f.I9Y(1/m.x,1/m.y);weights=[];blurUniforms={tDiffuse:{value:this.fbo2.texture},weights:{value:this.weights},direction:{value:new f.I9Y(1,0)},texelSize:{value:this.texelSize}};constructor(e){this.rectData=e,this.camera.far=h.far,this.camera.near=h.near,this.camera.position.copy(h.position),this.camera.updateProjectionMatrix(),this.blurPlane=new f.eaF(new f.bdM(2,2),new f.BKk),this.createGaussianBlur()}createGaussianBlur(){let e=this.blurRadius/3,t=0;for(let o=-this.blurRadius;o<=this.blurRadius;o++){let i=Math.exp(-(o*o)/(2*e*e));this.weights.push(i),t+=i}for(let e=0;e<this.weights.length;e++)this.weights[e]/=t;let o=`
      uniform sampler2D tDiffuse;
      uniform float weights[${this.weights.length}];
      uniform vec2 direction;
      uniform vec2 texelSize;
      varying vec2 vUv;

      void main() {
        vec4 color = vec4(0.0);
        for (int i = -${this.blurRadius}; i <= ${this.blurRadius}; i++) {
          vec2 offset = direction * float(i) * texelSize;
          color += texture2D(tDiffuse, vUv + offset) * weights[i + ${this.blurRadius}];
        }
        gl_FragColor = color;
      }
    `;this.blurPlane.material=new f.BKk({vertexShader:`
        varying vec2 vUv;
        void main(){
          vUv = uv;
          gl_Position = vec4(position, 1.0);
        }
      `,fragmentShader:o,uniforms:this.blurUniforms})}createSimpleCube(e){let t=e.material,o=new f.iNn(1.16,1.16,1.16),i=new f.BKk({vertexShader:t.vertexShader,fragmentShader:t.fragmentShader,uniforms:{...t.uniforms},transparent:!0,defines:{IS_GLASS_RENDER:"",...t.defines}}),s=new f.eaF(o,i);s.userData.originalCube=e,this.cubes.push(s),this.cubeGroup.add(s)}resize(){this.fboSize.set(Math.max(1,this.rectData.x*this.pixelRatio),Math.max(1,this.rectData.y*this.pixelRatio)),this.fbo1.setSize(this.fboSize.x,this.fboSize.y),this.fbo2.setSize(this.fboSize.x,this.fboSize.y),this.texelSize.set(1/this.fboSize.x,1/this.fboSize.y),this.camera.left=-this.rectData.x/2,this.camera.right=this.rectData.x/2,this.camera.top=this.rectData.y/2,this.camera.bottom=-this.rectData.y/2,this.camera.updateProjectionMatrix()}update(e,t,o){let i=p();i&&(this.cubeGroup.scale.set(t,t,t),this.cubeGroup.rotation.copy(e.rotation),this.cubeGroup.position.copy(e.position).add(o).multiplyScalar(t),this.cubes.forEach(e=>{let t=e.userData.originalCube;e.position.copy(t.position),e.rotation.copy(t.rotation),e.scale.copy(t.scale)}),i.setRenderTarget(this.fbo1),i.render(this.cubeGroup,this.camera),this.blurUniforms.tDiffuse.value=this.fbo1.texture,this.blurUniforms.direction.value.set(1,0),i.setRenderTarget(this.fbo2),i.render(this.blurPlane,this.camera),i.setRenderTarget(null),this.blurUniforms.tDiffuse.value=this.fbo2.texture,this.blurUniforms.direction.value.set(0,1),i.setRenderTarget(this.fbo1),i.render(this.blurPlane,this.camera),i.setRenderTarget(null))}}let tr={mona:[em,ey,eM],copilot:[eB,eO,eS],security:[ej,em,eV,e3],invertocat:[em,e9,ti]};class ta{group=new f.YJl;group2=new f.YJl;singleCubes=[];cubeGeometry;glassEffect;rectData;_rectData;parentGroup;singleBigCube=null;tl;constructor(e,t,o){this.parentGroup=t,this.rectData=t.userData.rectData,this._rectData=t.userData._rectData,this.cubeGeometry=e,this.glassEffect=new ts(this._rectData),this.tl=o,this.group.add(this.group2)}createCubes(e){let t;if(t=tr[e.character][e.layout]){if(this.group2.rotation.order=t.rotationOrder,this.group2.rotation.x=t.rotation.x,this.group2.rotation.y=t.rotation.y,this.group2.rotation.z=t.rotation.z,this.group2.userData.defRotation=this.group2.rotation.clone(),this.group2.position.copy(t.groupAnim.start),this.tl.to(this.group2.position,{x:t.groupAnim.end.x,y:t.groupAnim.end.y,z:t.groupAnim.end.z,ease:t.groupAnim.ease,duration:t.groupAnim.duration},0),"copilot"===e.character&&0===e.layout){let e={position:new f.Pq0(2,-1.2,0),rotation:new f.Pq0(4*Math.PI/5,.25*Math.PI,0),cubeType:"normal",isGlassRender:!1,offsetStart:{position:new f.Pq0(0,-4,0),rotation:new f.Pq0(-Math.PI,0,0)},delay:0,duration:2,scale:1.4,layout:{tablet:{offset:new f.Pq0(0,0,0),visible:!0},mobile:{offset:new f.Pq0(0,0,0),visible:!1}}};this.singleBigCube=new ef({cubeConfig:e,cubeGeometry:this.cubeGeometry,glassEffect:this.glassEffect,rectData:this.rectData,_rectData:this._rectData}),this.singleBigCube.createAnimation(this.tl),this.singleCubes.push(this.singleBigCube),this.group.add(this.singleBigCube.mesh)}t.cubes.forEach(e=>{let t=new ef({cubeConfig:e,cubeGeometry:this.cubeGeometry,glassEffect:this.glassEffect,rectData:this.rectData,_rectData:this._rectData});t.createAnimation(this.tl);let o=t.mesh;this.singleCubes.push(t),this.group2.add(o),e.isGlassRender&&this.glassEffect.createSimpleCube(o)})}}createDebugGlass(){let e,t=new f.eaF(new f.bdM(1,1),new f.V9B({map:this.glassEffect.fbo1.texture,depthTest:!1}));t.renderOrder=9999,setTimeout(()=>{let e=.3*this.glassEffect.fboSize.x,o=.3*this.glassEffect.fboSize.y;t.scale.set(e,o,1),t.position.set(-w.x/2+e/2,w.y/2-o/2,0)},200);let o=this.parentGroup;for(;o.parent;)if("Scene"===(o=o.parent).type){e=o;break}e.add(t)}resize(){this.glassEffect.resize()}update(e,t,o){let i=p();i&&(this.singleCubes.forEach(e=>{e.update(i)}),this.group2.rotation.x=this.group2.userData.defRotation.x-t*Math.PI*.15,this.singleBigCube&&(this.singleBigCube.mesh.rotation.x-=t*Math.PI*.15),this.glassEffect.update(this.group2,e,o))}}let tn=`${E+z}
uniform vec4 uRectData;
uniform vec3 uBgColor;
uniform vec4 uProgress;

varying vec2 vUv;
varying vec3 vNormal;
varying vec3 vNormal2;
varying vec3 vPosition;
varying vec2 vScreenPos;
varying vec2 vCenterPos;

void main(){
  vec3 pos = floor(vPosition * 5.0 / 1.2);
  vec3 noiseFactor = floor((vNormal * 1.4));
  float n = noise(pos + noiseFactor) * 0.5 + 0.5;

  float light = dot(normalize(vNormal2), normalize(vec3(1.0, 4.0, 1.0))) * 0.5 + 0.5;

  vec2 centerDistance = vScreenPos - vCenterPos;

  float l = length(centerDistance);
  l = smoothstep(0.08, 0.0, l);

  n = smoothstep(0.3, 1.0, n);

  vec3 hsv = vec3(0.9, 0.4, 1.0);
  hsv.r -= l * 0.4;
  vec3 centerColor = hsv2rgb(hsv);
  centerColor = mix(centerColor, vec3(1.0, 0.9, 0.5), smoothstep(0.5, 1.0, l) * 0.4);

  vec3 color = mix(centerColor * 0.1 + 0.9, centerColor, n);
  color = mix(color * 0.8, color, light);

  ${M}

  color = mix(uBgColor, color, uProgress.x );

  gl_FragColor = vec4(color, 1.0);


}
`;class tl{_cubeGeometry;mesh=null;constructor(e){this._cubeGeometry=e}create(e,t){let o=new f.IUQ(0,0,0,0),i=new f.eaF(this._cubeGeometry,new f.BKk({vertexShader:G,fragmentShader:tn,uniforms:{uRectData:{value:e.userData.rectData},uProgress:{value:o},uBgColor:{value:v}},defines:{MOSAIC:""}}));i.rotation.order="ZXY",i.scale.set(.5,.5,.5),i.name="rainbowCube",i.userData.position={def:new f.Pq0(-.4,.4,0),offset:new f.Pq0(0,0,0),current:new f.Pq0(0,0,0)},i.userData.rotation={def:new f.Pq0(Math.PI/5,-(.25*Math.PI),.25*Math.PI),offset:new f.Pq0(0,3*Math.PI,0),current:new f.Pq0(0,0,0)},t.to(i.userData.position.offset,{x:0,y:0,z:0,ease:"expo.out",duration:1.5},.4).to(i.userData.rotation.offset,{y:0,ease:"expo.out",duration:3},.4).to(o,{x:1,ease:"expo.out",duration:1},.4).fromTo(i.scale,{x:0,y:0,z:0},{x:.5,y:.5,z:.5,ease:"expo.out",duration:2},.4),this.mesh=i,e.add(i)}update(){if(!this.mesh)return;let e=this.mesh.userData.position,t=this.mesh.userData.rotation;e.current.copy(e.def).add(e.offset),this.mesh.position.copy(e.current),t.current.copy(t.def).add(t.offset),this.mesh.rotation.set(t.current.x,t.current.y,t.current.z),this.mesh.scale.set(.5,.5,.5),window.innerWidth<=768?this.mesh.scale.set(.4,.4,.4):window.innerWidth<=1011&&this.mesh.scale.set(.4,.4,.4)}}class tu{params=null;group=new f.YJl;_cubeGeometry;tl=g.Ay.timeline({paused:!0});rainbowMozaicCube=null;securityCube=null;copilot=null;mona=null;invertocatCube=null;groupScale=25;isAssetLoaded=!1;isAnimationStarted=!1;cubes=null;scrollProgress=0;constructor(e){this._cubeGeometry=e}async createScene(e,t,o){if(this.group.userData.ditherId=t,this.group.userData.domElement=e,this.params=o,this.group.userData.rectData=new f.IUQ(1,1,1,1),this.group.userData._rectData=new f.IUQ(1,1,1,1),this.cubes=new ta(this._cubeGeometry,this.group,this.tl),this.cubes.createCubes(o),this.group.add(this.cubes.group),"mona"===o.character)switch(o.layout){case 0:this.mona=new eo(o,this.group.userData.rectData),await this.mona.create(this.group,this.tl);break;case 1:this.mona=new ei(o,this.group.userData.rectData),await this.mona.create(this.group,this.tl);break;case 2:this.mona=new es(o,this.group.userData.rectData),await this.mona.create(this.group,this.tl)}if("copilot"===o.character)switch(o.layout){case 0:this.copilot=new X(o,this.group.userData.rectData),await this.copilot.create(this.group,this.tl);break;case 1:this.copilot=new j(o,this.group.userData.rectData),await this.copilot.create(this.group,this.tl);break;case 2:this.copilot=new $(o,this.group.userData.rectData),await this.copilot.create(this.group,this.tl)}if("security"===o.character&&(this.securityCube=new B(o,this._cubeGeometry,this.group.userData.rectData),await this.securityCube.create(this.cubes.group2,this.tl)),"invertocat"===o.character){let e={rotation:new f.Pq0,position:new f.Pq0};switch(o.layout){case 0:e.rotation.set(0,.5*Math.PI,-(.5*Math.PI)),e.position.set(.67,0,0);break;case 1:e.rotation.set(0,0,Math.PI),e.position.set(0,0,.67);break;case 2:e.rotation.set(0,.5*Math.PI,Math.PI),e.position.set(.67,0,0)}this.invertocatCube=new I({cubeConfig:K[o.layout],cubeGeometry:this._cubeGeometry,rectData:this.group.userData.rectData,_rectData:this.group.userData._rectData},e),this.invertocatCube.create(this.cubes.group2)}"mona"===o.character&&0===o.layout&&(this.rainbowMozaicCube=new tl(this._cubeGeometry),this.rainbowMozaicCube.create(this.group,this.tl)),this.isAssetLoaded=!0}resize(){this.updateRectData(),this.cubes&&this.cubes.resize()}updateRectData(){let e=this.group.userData.domElement.getBoundingClientRect();this.group.userData._rectData.set(e.width,e.height,e.left,m.y-e.top-.1*w.y),this.group.userData.rectData.copy(this.group.userData._rectData);let t=p();return t&&this.group.userData.rectData.multiplyScalar(t.getPixelRatio()),e}update(e){if(!this.params)return;let t=P(),o=F[this.params.character][this.params.layout],i=o.desktop.scale,s=o.desktop.position;window.innerWidth<=768?(i=o.mobile.scale,s=o.mobile.position):window.innerWidth<=1011&&(i=o.table.scale,s=o.table.position);let r=this.updateRectData(),a=r.left+r.width/2-w.x/2,n=-(r.top+r.height/2-w.y/2),l=r.width/i;this.group.scale.set(l,l,l),this.group.position.set(a+s.x*l,n+s.y*l,0);let u=r.bottom>=0&&r.right>=0&&r.top<=w.y&&r.left<=w.x;this.scrollProgress=1-r.bottom/(w.y+r.height),this.scrollProgress=Math.min(Math.max(this.scrollProgress,0),1),t?this.scrollProgress=0:this.scrollProgress=this.scrollProgress-.5,this.isAssetLoaded&&!this.isAnimationStarted&&u&&(this.isAnimationStarted=!0,t?this.tl.progress(1):this.tl.play(),this.copilot&&(t?this.copilot.tl.progress(1):this.copilot.playTl()),this.mona&&(t?this.mona.tl.progress(1):this.mona.playTl()),this.invertocatCube&&(t?this.invertocatCube.tl.progress(1):this.invertocatCube.playTl())),u&&(this.mona&&this.mona.update(this.scrollProgress),this.copilot&&this.copilot.update(this.scrollProgress),this.rainbowMozaicCube&&this.rainbowMozaicCube.update(),this.securityCube&&this.securityCube.update(this.scrollProgress),this.invertocatCube&&this.invertocatCube.update(),this.cubes&&this.cubes.update(l,this.scrollProgress,s))}}class tc{group=new f.YJl;layouts=[];_cubeGeometry;constructor(){this._cubeGeometry=new q(.08,8)}updateRegisterBrandedDivider(e){let t=this.layouts.map(e=>e.group.userData.ditherId),o=e.map(e=>e.id);this.layouts=this.layouts.filter(e=>!!o.includes(e.group.userData.ditherId)||(this.group.remove(e.group),!1)),e.forEach(e=>{t.includes(e.id)||this.createScene(e.element,e.id,e.params)}),this.resize(),setTimeout(()=>{this.resize()},100)}async createScene(e,t,o){if(!p())return;let i=new tu(this._cubeGeometry);this.group.add(i.group),this.layouts.push(i),await i.createScene(e,t,o)}resize(){this.layouts.forEach(e=>{e.resize()})}update(e,t,o){this.layouts.forEach(e=>{e.update(o)})}}let tf=`
// https://www.shadertoy.com/view/7sfXDn
float Bayer2(vec2 a) {
    a = floor(a);
    return fract(a.x / 2. + a.y * a.y * .75);
}

#define Bayer4(a)   (Bayer2 (.5 *(a)) * .25 + Bayer2(a))
#define Bayer8(a)   (Bayer4 (.5 *(a)) * .25 + Bayer2(a))
#define Bayer16(a)  (Bayer8 (.5 *(a)) * .25 + Bayer2(a))
#define Bayer32(a)  (Bayer16(.5 *(a)) * .25 + Bayer2(a))
#define Bayer64(a)  (Bayer32(.5 *(a)) * .25 + Bayer2(a))
`,th=`${E+tf}
uniform float uTime;
uniform sampler2D uDitheringTexture;
uniform vec2 uResolution;
uniform vec3 uProgress;

void main(){
  vec2 st = floor(gl_FragCoord.xy / 4.0);
  vec2 uv = st / (uResolution / 4.0);
  uv -= 0.5;
  uv.x *= uResolution.x / uResolution.y;
  uv += 0.5;
  float n = noise(vec3(uv * 1.3 + (uTime + uProgress.x * 20.0) * 0.1, (uTime + uProgress.x * 20.0) * 0.1));
  n = smoothstep(0.3, 1.0, n);

  float dithering = texture2D(uDitheringTexture, st / 8.0).r;
  float grayscale = step(dithering + 0.01, n);
  gl_FragColor = vec4(grayscale, dithering, 0.0, 1.0);
}
`,td=`${tf}
uniform float uTime;
uniform sampler2D uDitheringTexture;
uniform vec2 uResolution;
uniform vec3 uProgress;

void main(){
  float threshold = 0.5 + 0.5 * sin((uTime + uProgress.x * 20.0) * 0.15);
  float range = 0.5;

  vec2 st = floor(gl_FragCoord.xy / 4.0);

  vec2 uv = st / (uResolution / 4.0);
  uv -= 0.5;
  uv.x *= uResolution.x / uResolution.y;
  uv += 0.5;
  float wave = smoothstep(threshold - range, threshold + range, length(uv - vec2(0.5)));

  float dithering = texture2D(uDitheringTexture, st / 8.0).r;
  wave = step(dithering + 0.01, wave);

  gl_FragColor = vec4(wave, dithering, 0.0, 1.0);
}
`,tp=`
uniform float uTime;
uniform sampler2D uDitheringTexture;
uniform vec2 uResolution;
uniform vec3 uProgress;


void main(){

  vec2 st = floor(gl_FragCoord.xy / 4.0);
  vec2 uv = st / (uResolution / 4.0);
  uv -= 0.5;
  uv.x *= uResolution.x / uResolution.y;
  uv += 0.5;


  float threshold = 0.5 + 0.5 * sin((uTime + uProgress.x * 20.0) * 0.1 + uv.x * 2.0);
  float range = 0.5;
  float wave = smoothstep(threshold - range, threshold + range, uv.y);

  float dithering = texture2D(uDitheringTexture, st / 8.0).r;
  float grayscale = step(dithering + 0.01, wave);


  gl_FragColor = vec4(grayscale, 0.0, 0.0, 1.0);
}
`;class tv{fbo=new f.nWS(8,8,{minFilter:1003,magFilter:1003,wrapS:1e3,wrapT:1e3});plane;constructor(){this.plane=new f.eaF(new f.bdM(2,2),new f.BKk({vertexShader:`
          varying vec2 vUv;
          void main() {
            vUv = uv;
            gl_Position = vec4(position, 1.0);
          }
        `,fragmentShader:`${tf}
          varying vec2 vUv;
          void main() {
            float dithering = Bayer64(gl_FragCoord.xy);
            gl_FragColor = vec4(vec3(dithering), 1.0);
          }
        `}))}renderOnce(){let e=p();e&&(e.setRenderTarget(this.fbo),e.render(this.plane,new f.i7d))}}class tm{dimensions=new f.I9Y(1,1);fbo=new f.nWS(1,1);scene=new f.Z58;camera=new f.i7d;uniforms={uTime:{value:100*Math.random()},uResolution:{value:new f.I9Y(1,1)},uProgress:{value:new f.IUQ(0,0,0,0)}};constructor(e,t,o,i){this.resize(e,t);const s=new f.bdM(2,2),r=new f.BKk({vertexShader:`
        void main() {
          gl_Position = vec4(position, 1.0);
        }
      `,fragmentShader:o,uniforms:{...this.uniforms,uDitheringTexture:{value:i}},depthTest:!1,depthWrite:!1}),a=new f.eaF(s,r);this.scene.add(a)}resize(e,t){this.dimensions.set(e,t),this.dimensions.x=Math.floor(4*this.dimensions.x)/4,this.dimensions.y=Math.floor(4*this.dimensions.y)/4,this.fbo.setSize(this.dimensions.x,this.dimensions.y),this.uniforms.uResolution.value.set(this.dimensions.x,this.dimensions.y)}render(e,t){let o=p();if(!o)return;this.uniforms.uTime.value+=e;let i=this.uniforms.uProgress.value;i.x+=(1-i.x)*Math.min(1,1.6*t),o.setRenderTarget(this.fbo),o.render(this.scene,this.camera)}}let tw=`
  uniform sampler2D uTexture;
  uniform vec3 uColor0;
  uniform vec3 uColor1;
  uniform vec3 uDotColor;
  uniform float uDotOpacity;
  uniform vec4 uProgress;
  uniform vec3 uBgColor;
  varying vec2 vUv;

  float parabola(float x, float k) {
    return pow(4.0 * x * (1.0 - x), k);
  }

  void main(){
    vec3 data = texture2D(uTexture, vUv).rgb;
    float grayscale = data.r;
    float fadein = data.g;

    vec3 gradient = mix(uColor0, uColor1, smoothstep(0.0, 1.5 + (1.0 - uProgress.x) * 4.0, vUv.y));
    vec3 color = mix(gradient, uDotColor + vUv.y, grayscale * smoothstep(0.9, 0.0, vUv.y) * uProgress.z * uDotOpacity);

    // Correct for gamma
    color = pow(color, 1.0 / vec3(2.2));

    color = mix(uBgColor, color, (uProgress.x * uProgress.x));

    gl_FragColor = vec4(color, 1.0);
  }
`,tb=`
  uniform sampler2D uTexture;
  uniform vec3 uColor0;
  uniform vec3 uColor1;
  uniform vec3 uColor2;
  uniform vec3 uColor3;
  uniform float uColor0Weight;
  uniform float uColor1Weight;
  uniform float uColor2Weight;
  uniform float uColor3Weight;
  uniform float uRegionScale;
  uniform float uDetailScale;
  uniform float uDetailAmount;
  uniform float uWarpAmount;
  uniform float uSoftness;
  uniform float uXOffset;
  uniform float uYOffset;
  uniform vec3 uDotColor;
  uniform float uDotOpacity;
  uniform float uAspect;
  uniform vec4 uProgress;
  uniform vec3 uBgColor;
  varying vec2 vUv;

  ${E}

  float noise2(vec2 p) {
    // 'snoise' returns a value in -1..1, so we remap it to 0..1
    return snoise(vec3(p, 0.0)) * 0.5 + 0.5;
  }

  float biasNoise(float noise, float weightA, float weightB) {
    float total = weightA + weightB;
    if (total <= 0.0) return 0.5;

    float split = weightA / total;
    // Remap so [0, split] stretches to [0, 0.5] and [split, 1] to [0.5, 1]
    if (noise < split) {
      return split == 0.0 ? 0.5 : (noise / split) * 0.5;
    }

    return split == 1.0 ? 0.5 : 0.5 + ((noise - split) / (1.0 - split)) * 0.5;
  }

  vec3 pearlGradient(vec2 uv) {
    vec2 p = vec2(uv.x * uAspect + uXOffset, uv.y + uYOffset);

    // Add some warping
    float warpX = noise2(p * uRegionScale + vec2(13.1, 7.7)) - 0.5;
    float warpY = noise2(p * uRegionScale + vec2(91.3, 41.2)) - 0.5;
    p += vec2(warpX, warpY) * uWarpAmount;

    // Low-frequency noise so neighbouring pixels make similar
    // blend decisions and produce coherent colour zones
    float regionPairA = noise2(p * uRegionScale);
    float regionPairB = noise2(p * uRegionScale + vec2(50.0, 50.0));
    float regionBlend = noise2(p * uRegionScale + vec2(100.0, 100.0));

    // High-frequency noise so each zone gets local colour variation
    float detailPairA = noise2(p * uDetailScale + vec2(200.0, 200.0));
    float detailPairB = noise2(p * uDetailScale * 1.3 + vec2(300.0, 300.0));
    float detailBlend = noise2(p * uDetailScale + vec2(400.0, 400.0));

    // Combine each region with its detail
    float noisePairA = clamp(regionPairA + (detailPairA - 0.5) * uDetailAmount, 0.0, 1.0);
    float noisePairB = clamp(regionPairB + (detailPairB - 0.5) * uDetailAmount, 0.0, 1.0);
    float noiseBlend = clamp(regionBlend + (detailBlend - 0.5) * uDetailAmount, 0.0, 1.0);

    float smoothstepLow = (1.0 - uSoftness) * 0.5;
    float smoothstepHigh = 1.0 - smoothstepLow;

    // Get weighted noise values to blend the 4 colours for this pixel
    float noiseAWeighted = biasNoise(noisePairA, uColor0Weight, uColor1Weight);
    vec3 colorA = mix(uColor0, uColor1, smoothstep(smoothstepLow, smoothstepHigh, noiseAWeighted));

    float noiseBWeighted = biasNoise(noisePairB, uColor2Weight, uColor3Weight);
    vec3 colorB = mix(uColor2, uColor3, smoothstep(smoothstepLow, smoothstepHigh, noiseBWeighted));

    float noiseBlendWeighted = biasNoise(noiseBlend, uColor0Weight + uColor1Weight, uColor2Weight + uColor3Weight);
    vec3 color = mix(colorA, colorB, smoothstep(smoothstepLow, smoothstepHigh, noiseBlendWeighted));
    return color;
  }

  void main() {
    vec3 rec709 = vec3(0.2126, 0.7152, 0.0722);
    vec3 data = texture2D(uTexture, vUv).rgb;
    float grayscale = data.r;
    float fadein = data.g;

    vec3 gradient = pearlGradient(vUv);

    // Luminance-based dithering effect dot falloff to match the noise patterns
    float luminance = dot(gradient, rec709);
    float dotFalloff = smoothstep(0.8, 0.95, luminance);

    vec3 color = mix(gradient, uDotColor + vUv.y, grayscale * dotFalloff * uProgress.z * uDotOpacity);
    color = mix(uBgColor, color, (uProgress.x * uProgress.x));

    gl_FragColor = vec4(color, 1.0);
  }
`,tg={security:{backgroundType:"linearGradient",uniforms:{uColor0:{value:new f.Q1f(14335)},uColor1:{value:new f.Q1f(0xffffff)},uDotColor:{value:new f.Q1f(0xc7e2ff)}}},copilot:{backgroundType:"linearGradient",uniforms:{uColor0:{value:new f.Q1f(9122813)},uColor1:{value:new f.Q1f(0xffffff)},uDotColor:{value:new f.Q1f(0xb983fe)}}},pearl:{backgroundType:"noiseGradient",uniforms:{uColor0:{value:new f.Q1f(0xbecdf8)},uColor1:{value:new f.Q1f(0xccefda)},uColor2:{value:new f.Q1f(0xfcf0d7)},uColor3:{value:new f.Q1f(0xf0d7eb)},uDotColor:{value:new f.Q1f(0xf3e1fe)},uColor0Weight:{value:2.6},uColor1Weight:{value:1.9},uColor2Weight:{value:.3},uColor3Weight:{value:.9},uRegionScale:{value:.2},uDetailScale:{value:.4},uDetailAmount:{value:.85},uWarpAmount:{value:1.5},uSoftness:{value:.88},uXOffset:{value:1.72},uYOffset:{value:-4.71}},backgroundVisibilityThreshold:.3},default:{backgroundType:"linearGradient",uniforms:{uColor0:{value:new f.Q1f(558891)},uColor1:{value:new f.Q1f(0xffffff)},uDotColor:{value:new f.Q1f(0xc0ffd1)}}}},tP={linearGradient:tw,noiseGradient:tb};class ty{bayerTexture=new tv;group=new f.YJl;planes=[];commonUniforms={uBgColor:{value:v}};get isReducedMotion(){return P()}constructor(){this.bayerTexture.renderOnce()}updateRegisterDither(e){let t=this.planes.map(e=>e.userData.ditherId),o=e.map(e=>e.id);this.planes=this.planes.filter(e=>!!o.includes(e.userData.ditherId)||(this.removePlane(e),!1)),e.forEach(e=>{t.includes(e.id)||this.createPlane(e.element,e.id,e.params)})}resize(){this.planes.forEach(e=>{let t=e.userData.ditheringAnimation,o=e.userData.domElement.getBoundingClientRect();"noiseGradient"===e.userData.backgroundType&&(e.userData.uniforms.uAspect={value:o.width/o.height}),t.resize(o.width,o.height)})}update(e,t){for(let o=0;o<this.planes.length;o++){let i=this.planes[o],s=i.userData.domElement.getBoundingClientRect(),r=s.width,a=s.height,n=s.left-w.x/2+r/2,l=-((s.top-w.y/2+a/2)*1);i.position.set(n,l,0),i.scale.set(r,a,1);let u=s.bottom>=0&&s.right>=0&&s.top<=w.y&&s.left<=w.x,c=Math.max(0,Math.min(s.right,w.x)-Math.max(s.left,0))*Math.max(0,Math.min(s.bottom,w.y)-Math.max(s.top,0))/(r*a);if(u){let o=i.userData.ditheringAnimation,s=i.userData.progress;if("noiseGradient"===i.userData.backgroundType&&(i.userData.uniforms.uAspect.value=r/a),i.userData.hasEnteredViewport||(i.userData.hasEnteredViewport=!0,i.userData.fadeIn&&!this.isReducedMotion&&this.animateBackgroundIn(i)?.pause(0)),i.userData.startTime||i.userData.backgroundVisibilityThreshold&&!(c>=i.userData.backgroundVisibilityThreshold)||(i.userData.startTime=performance.now(),i.userData.fadeIn&&!this.isReducedMotion&&this.animateBackgroundIn(i)),this.isReducedMotion)s.set(1,1,1,1),o.render(0,0);else{let r=performance.now()-i.userData.startTime;s.x+=(1-s.x)*Math.min(1,2.5*t),s.y+=(1-s.y)*Math.min(1,+t),r>500&&(s.z+=(1-s.z)*Math.min(1,+t)),o.render(e,t)}}}}getFragmentShaderByType(e){switch(e){case"wave":default:return tp;case"ripple":return td;case"noise":return th;case"random":{let e=[tp,td,th],t=Math.floor(Math.random()*e.length);return e[t]}}}createPlane(e,t,o){let i=tg[o.color]||tg.default,s=this.getFragmentShaderByType(o.type),r=e.getBoundingClientRect(),a=new tm(r.width,r.height,s,this.bayerTexture.fbo.texture),n=new f.IUQ(0,0,0,0);o.fadeIn||(n.set(1,1,1,1),a.uniforms.uProgress.value.set(1,1,1,1));let l=Object.fromEntries(Object.entries(i.uniforms).map(([e,t])=>{let o=t.value;return[e,{value:o instanceof f.Q1f?o.clone():o}]})),u={uTexture:{value:a.fbo.texture},uProgress:{value:n},uDotOpacity:{value:o.dotOpacity??1},...this.commonUniforms,...l};"noiseGradient"===i.backgroundType&&(u.uAspect={value:r.width/r.height});let c=new f.eaF(new f.bdM(1,1),new f.BKk({vertexShader:G,fragmentShader:tP[i.backgroundType],uniforms:u,transparent:!0}));c.userData.uniforms=u,c.userData.domElement=e,c.userData.ditherId=t,c.userData.progress=n,c.userData.ditheringAnimation=a,c.userData.backgroundType=i.backgroundType,c.userData.fadeIn=o.fadeIn,c.userData.hasEnteredViewport=!1,c.userData.hasAnimatedIn=!1,c.userData.abortController=new AbortController,"noiseGradient"===i.backgroundType&&(c.userData.backgroundVisibilityThreshold=i.backgroundVisibilityThreshold,this.isReducedMotion||this.interactNoiseGradient(c)),this.group.add(c),this.planes.push(c)}removePlane(e){e.userData.abortController?.abort(),"noiseGradient"===e.userData.backgroundType&&(g.Ay.killTweensOf(e.userData.uniforms.uXOffset),g.Ay.killTweensOf(e.userData.uniforms.uYOffset)),this.group.remove(e)}animateBackgroundIn(e){if("noiseGradient"===e.userData.backgroundType&&e.userData.fadeIn){let t=tg.pearl.uniforms,o={uXOffset:t.uXOffset.value,uYOffset:t.uYOffset.value};return g.Ay.from(o,{uXOffset:.5*t.uXOffset.value,uYOffset:.5*t.uYOffset.value,duration:3,ease:"power4.out",onUpdate:()=>{e.userData.uniforms.uXOffset.value=o.uXOffset,e.userData.uniforms.uYOffset.value=o.uYOffset},onComplete:()=>{e.userData.hasAnimatedIn=!0}})}}debugNoiseGradient(e){let t=e.userData.domElement,o=e.userData.uniforms,{signal:i}=e.userData.abortController,s=!1;t.addEventListener("mousedown",()=>{s=!0},{signal:i}),window.addEventListener("mouseup",()=>{s=!1},{signal:i}),t.addEventListener("mousemove",e=>{if(!s)return;let i=t.getBoundingClientRect(),r=(e.clientX-i.left)/i.width*10,a=(e.clientY-i.top)/i.height*10;o.uXOffset.value=r,o.uYOffset.value=a,console.log(`uXOffset=${r.toFixed(2)} uYOffset=${a.toFixed(2)}`)},{signal:i})}interactNoiseGradient(e){let t=e.userData.domElement,o=e.userData.uniforms,{signal:i}=e.userData.abortController,s=o.uXOffset.value,r=o.uYOffset.value,a=window.matchMedia("(hover: hover)").matches,n=null,l={uXOffset:s,uYOffset:r},u=(t,o,i=.4)=>{n?.kill(),n=g.Ay.fromTo(l,{uXOffset:e.userData.uniforms.uXOffset.value,uYOffset:e.userData.uniforms.uYOffset.value},{uXOffset:t,uYOffset:o,duration:i,ease:"power4.out",onUpdate:()=>{e.userData.uniforms.uXOffset.value=l.uXOffset,e.userData.uniforms.uYOffset.value=l.uYOffset}})},c=(o,i)=>{let a=t.getBoundingClientRect(),n=e.userData.uniforms.uAspect.value,l=(o-a.left)/a.width*2-1,c=(i-a.top)/a.height*2-1;u(s+(l>=0?.1*l:-(-.1*l))*n,r+-1*(c>=0?.1*c:-(-.1*c)))},f=()=>{u(s,r,.8)};if(a){t.addEventListener("mousemove",e=>{c(e.clientX,e.clientY)},{signal:i}),t.addEventListener("mouseleave",f,{signal:i});return}let h=!1;t.addEventListener("touchstart",()=>{h=!0},{passive:!0,signal:i}),window.addEventListener("touchend",()=>{h&&(h=!1,f())},{passive:!0,signal:i}),t.addEventListener("touchmove",t=>{let o=t.touches[0];h&&o&&e.userData.hasAnimatedIn&&c(o.clientX,o.clientY)},{passive:!0,signal:i})}}let tx=`${E+z}
uniform vec3 uColor1;
uniform vec3 uColor2;
uniform vec3 uColor3;

uniform vec4 uRectData;
uniform vec4 uProgress;

varying vec2 vUv;
varying vec3 vNormal;
varying vec3 vPosition;
varying vec3 vWorldPosition;

vec2 RECT_SIZE = vec2(1600.0, 580.0);

void main() {

  ${M}

  vec2 uv = vUv;
  uv -= 0.5;
  uv *= uRectData.xy / uRectData.y;
  uv /= RECT_SIZE / RECT_SIZE.y; 
  uv += 0.5;

  float l = length(uv * (RECT_SIZE / RECT_SIZE.y));

  l *= mix(0.1, 1.0, uProgress.y);

  vec3 color = uColor1;
  color = mix(mix(color, vec3(1.0), 0.4), color, uProgress.x);
  color = mix(color, uColor2, smoothstep(0.0, 1.0, l));
  color = mix(color, uColor3, smoothstep(1.5, 3.0, l));

  // color = mix(mix(uColor1, vec3(1.0), 0.8), color, uProgress.x);

  color = pow(color, vec3(1.0 / 2.2));

  gl_FragColor = vec4(color,  1.0);
}
`,tq=new f.Pq0(0,0,0),tC=e=>(e.add(tq),e.x*=1+.08*1.1,e.y*=1+.08*1.1,e.z*=1+.08*1.1,e),tR={position:new f.Pq0(-10,0,0),rotation:new f.Pq0(0,0,0)},tM=[{position:tC(new f.Pq0(-3,1,0)),rotation:new f.Pq0(0,0,0),cubeType:"mosaic",isGlassRender:!1,offsetStart:tR,delay:0,duration:3,scale:1,layout:{tablet:{offset:new f.Pq0(0,0,0),visible:!0},mobile:{offset:new f.Pq0(0,0,0),visible:!0}}},{position:tC(new f.Pq0(-3,0,-1)),rotation:new f.Pq0(.5*Math.PI,0,0),cubeType:"normal",isGlassRender:!1,offsetStart:tR,delay:.1,duration:3,scale:1,layout:{tablet:{offset:new f.Pq0(0,0,0),visible:!0},mobile:{offset:new f.Pq0(0,0,0),visible:!0}}},{position:tC(new f.Pq0(0,0,0)),rotation:new f.Pq0(.5*Math.PI,0,0),cubeType:"invertocat",isGlassRender:!1,offsetStart:tR,delay:.5,duration:5,scale:1,layout:{tablet:{offset:new f.Pq0(0,0,0),visible:!0},mobile:{offset:new f.Pq0(0,0,0),visible:!0}}},{position:tC(new f.Pq0(-1.5,0,0)),rotation:new f.Pq0(0,0,0),cubeType:"glassNoBlur",isGlassRender:!1,offsetStart:tR,delay:.5,duration:5,scale:new f.Pq0(1.92,1,1),layout:{tablet:{offset:new f.Pq0(0,0,0),visible:!0},mobile:{offset:new f.Pq0(0,0,0),visible:!0}}},{position:tC(new f.Pq0(-3,-1,0)),rotation:new f.Pq0(0,0,0),cubeType:"whiteGreen",isGlassRender:!1,offsetStart:tR,delay:.3,duration:4,scale:1,layout:{tablet:{offset:new f.Pq0(0,0,0),visible:!0},mobile:{offset:new f.Pq0(0,0,0),visible:!0}}},{position:tC(new f.Pq0(-3,0,1)),rotation:new f.Pq0(0,0,0),cubeType:"glassRainbowNoBlur",isGlassRender:!1,offsetStart:tR,delay:.1,duration:4,scale:1,layout:{tablet:{offset:new f.Pq0(0,0,0),visible:!0},mobile:{offset:new f.Pq0(0,0,0),visible:!0}}}];class tD{bgGroup=new f.YJl;group=new f.YJl;cubeGroup=new f.YJl;id=null;element;_cubeGeometry;singleCubes=[];rectData=new f.IUQ(1,1,1,1);_rectData=new f.IUQ(1,1,1,1);tl=g.Ay.timeline({paused:!0});groupScale=12;scrollProgress=0;isAnimationStarted=!1;invertocatCube=null;defaultRot=new f.Pq0(-(.2*Math.PI),-(.25*Math.PI),0);animRot=new f.Pq0(-(.2*Math.PI),0,0);constructor(){this._cubeGeometry=new q(.08,8),this.cubeGroup.rotation.order="XYZ",this.cubeGroup.userData._position=new f.Pq0(0,-4,0),this.tl.to(this.animRot,{x:this.defaultRot.x,y:this.defaultRot.y,z:this.defaultRot.z,duration:2,ease:"power2.out"},0).to(this.cubeGroup.userData._position,{y:0,ease:"power2.out",duration:2},0);const e=document.createElement("div");this.element=e,this.group.add(this.cubeGroup),this.group.add(this.bgGroup)}updateRegisterEnterpriseHero(e){this.id=e.id,this.element=e.element,this.group.userData.rectData=this.rectData,this.group.userData._rectData=this._rectData,this.createScene()}unregisterEnterpriseHero(){this.group.clear(),this.cubeGroup.clear(),this.bgGroup.clear(),this.id=null}async createScene(){tM.forEach((e,t)=>{if("invertocat"===e.cubeType){let t={position:new f.Pq0(.67,0,0),rotation:new f.Pq0(-(.5*Math.PI),.5*Math.PI,0)};this.invertocatCube=new I({cubeConfig:e,cubeGeometry:this._cubeGeometry,rectData:this.rectData,_rectData:this._rectData},t),this.invertocatCube.create(this.cubeGroup),this.invertocatCube.lightPos.set(1,-1,1).normalize()}else{let o=new ef({cubeConfig:e,cubeGeometry:this._cubeGeometry,rectData:this.rectData,_rectData:this._rectData}),i=o.mesh;this.cubeGroup.add(i),i.renderOrder=t,o.createAnimation(this.tl),"glassNoBlur"===e.cubeType&&(o.progress.w=4,this.tl.to(o.progress,{w:0,duration:3},e.delay+3)),"glassRainbowNoBlur"===e.cubeType&&(o.progress.w=2,this.tl.to(o.progress,{w:0,duration:1},e.delay+.5)),this.singleCubes.push(o)}});let e=new f.IUQ(0,0,0,0),t=new f.eaF(new f.bdM(1,1),new f.BKk({uniforms:{uColor1:{value:new f.Q1f(0xa0defb)},uColor2:{value:new f.Q1f(0xe7e5fb)},uColor3:{value:new f.Q1f(0xeaf3f4)},uRectData:{value:this.rectData},uProgress:{value:e}},vertexShader:G,fragmentShader:tx}));this.tl.to(e,{x:1,duration:2},0).to(e,{y:1,duration:4},0),this.bgGroup.add(t),this.bgGroup.userData.progress=e}resize(){this.updateRectData()}updateRectData(){let e=this.element.getBoundingClientRect();this._rectData.set(e.width,e.height,e.left,m.y-e.top-.1*w.y),this.rectData.copy(this._rectData);let t=p();return t&&this.rectData.multiplyScalar(t.getPixelRatio()),e}update(e){let t=this.updateRectData(),o=t.left+t.width/2-w.x/2,i=-(t.top+t.height/2-w.y/2),s=Math.min(1600,t.width)/this.groupScale;this.cubeGroup.scale.set(s,s,s),this.group.position.set(o,i,0),this.bgGroup.scale.set(t.width,t.height,1),this.bgGroup.position.z=-1e3,this.cubeGroup.position.y=this.cubeGroup.userData._position.y*s,this.cubeGroup.position.y+=this.scrollProgress*s*.6,this.cubeGroup.rotation.set(this.animRot.x,this.animRot.y,this.animRot.z),this.cubeGroup.rotation.x-=this.scrollProgress*Math.PI*.1;let r=t.bottom>=0&&t.right>=0&&t.top<=w.y&&t.left<=w.x;if(this.scrollProgress=window.scrollY/(w.y+t.height),this.scrollProgress=Math.min(Math.max(this.scrollProgress,0),1),this.invertocatCube&&this.invertocatCube.isLoaded&&!this.isAnimationStarted&&r&&(this.isAnimationStarted=!0,this.tl.play(),this.invertocatCube.playTl()),r){let e=p();if(!e)return;this.singleCubes.forEach(t=>{t.update(e)}),this.invertocatCube&&this.invertocatCube.update()}}}f.ppV.legacyMode=!1;class tT{camera=h;renderer;windowSize=w;canvasSize=m;canvasResSize=b;scene=new f.Z58;clock=new f.zD7;time=0;delta=1;scrollY={current:0,target:0};scrollDelta=0;scrollOffset=new f.I9Y(0,0);pixelRatio=1;ditheringEffect;brandedDivider;enterpriseHero;offsetByWrapperTop=!1;_ditherOffsetByWrapperTop=!1;_brandedDividerOffsetByWrapperTop=!1;resizeFuncArray=[];updateFuncArray=[];constructor(e){P()&&g.os.globalTimeline.timeScale(0);const t=new f.JeP({canvas:e.canvas,antialias:!0,alpha:!0});this.renderer=t,(e=>{d=e})(t),t.setClearColor(v,0),t.outputEncoding=3001,t.toneMapping=1,t.toneMappingExposure=1,t.physicallyCorrectLights=!0,this.pixelRatio=Math.min(window.devicePixelRatio,2),t.setPixelRatio(this.pixelRatio),this.ditheringEffect=new ty,this.scene.add(this.ditheringEffect.group),this.brandedDivider=new tc,this.scene.add(this.brandedDivider.group),this.enterpriseHero=new tD,this.scene.add(this.enterpriseHero.group),this.clock.start()}updateRegisterDither(e){this._ditherOffsetByWrapperTop=e.some(e=>e.offsetByWrapperTop),this.offsetByWrapperTop=this._ditherOffsetByWrapperTop||this._brandedDividerOffsetByWrapperTop,this.ditheringEffect.updateRegisterDither(e)}updateRegisterBrandedDivider(e){this._brandedDividerOffsetByWrapperTop=e.some(e=>e.offsetByWrapperTop),this.offsetByWrapperTop=this._ditherOffsetByWrapperTop||this._brandedDividerOffsetByWrapperTop,this.brandedDivider.updateRegisterBrandedDivider(e)}updateRegisterEnterpriseHero(e){this.enterpriseHero.updateRegisterEnterpriseHero(e)}switchBackgroundColor({isWhite:e}){e?v.set(0xffffff):v.set(0)}addWebGLObject({group:e,onResize:t,onUpdate:o}){this.scene.add(e),this.resizeFuncArray.push(t),this.updateFuncArray.push(o)}resize(e,t){w.set(e,t);let o=1.2*w.y,i=w.x;m.set(i,o),b.copy(m).multiplyScalar(this.pixelRatio);let s=p();s&&(s.setSize(i,o),h.left=-i/2,h.right=i/2,h.top=o/2,h.bottom=-o/2,h.updateProjectionMatrix()),this.resizeFuncArray.forEach(e=>{e()}),this.ditheringEffect.resize(),this.brandedDivider.resize(),this.enterpriseHero.resize()}scroll(e){this.scrollY.target=window.scrollY;let t=this.scrollY.current;this.scrollY.current+=(this.scrollY.target-this.scrollY.current)*Math.min(1,4*e),this.scrollDelta=Math.abs(this.scrollY.current-t)}update(){let e=p();if(e){let t=0;if(this.offsetByWrapperTop){let o=e.domElement.parentElement;t=o?o.getBoundingClientRect().top:0,this.scrollOffset.set(window.scrollX,-(.1*w.y)-t)}else this.scrollOffset.set(window.scrollX,window.scrollY-.1*w.y);e.domElement.style.transform=`translate(0px, ${this.scrollOffset.y}px)`;let o=this.clock.getDelta();this.scroll(o);let i=o*(this.scrollDelta<.1?0:1);this.time=0,this.updateFuncArray.forEach(e=>{e(i,o)}),this.ditheringEffect.update(i,o),this.brandedDivider.update(this.time,i,o),this.enterpriseHero.update(o),e.setRenderTarget(null),e.render(this.scene,h)}}}function tG({children:e,mode:t="light"}){let[o,i]=(0,a.useState)([]),[r,l]=(0,a.useState)([]),[u,c]=(0,a.useState)(null),f=(0,a.useCallback)(e=>{i(t=>t.find(t=>t.id===e.id)?t:[...t,e])},[]),h=(0,a.useCallback)(e=>{i(t=>t.filter(t=>t.id!==e))},[]),d=(0,a.useCallback)(e=>{l(t=>t.some(t=>t.id===e.id)?t:[...t,e])},[]),p=(0,a.useCallback)(e=>{l(t=>t.filter(t=>t.id!==e))},[]),v=(0,a.useCallback)(e=>{u||c(t=>t||e)},[]),m=(0,a.useCallback)(e=>{c(t=>t?.id===e?null:t)},[]),w=(0,a.useRef)(null),b=(0,a.useRef)(null),g=(0,a.useRef)(null);(0,a.useEffect)(()=>{if(w.current){b.current=new tT({canvas:w.current}),"light"===t?b.current.switchBackgroundColor({isWhite:!0}):b.current.switchBackgroundColor({isWhite:!1});let e=()=>{if(b.current&&w.current){let e=document.body.clientWidth,t=window.innerHeight;b.current.resize(e,t)}},o=()=>{b.current?.update(),g.current=requestAnimationFrame(o)};return e(),window.addEventListener("resize",e),o(),()=>{window.removeEventListener("resize",e),g.current&&cancelAnimationFrame(g.current)}}},[]),(0,a.useEffect)(()=>{b.current&&b.current.updateRegisterDither(o)},[o]),(0,a.useEffect)(()=>{b.current&&b.current.updateRegisterBrandedDivider(r)},[r]),(0,a.useEffect)(()=>{u&&b.current?.updateRegisterEnterpriseHero(u)},[u]);let P={registerDither:f,unregisterDither:h,registerBrandedDivider:d,unregisterBrandedDivider:p,registerEnterpriseHero:v,unregisterEnterpriseHero:m,artwork:b.current};return(0,s.jsx)(n,{value:P,children:(0,s.jsxs)("div",{style:{position:"relative",overflow:"hidden"},children:[(0,s.jsx)("canvas",{ref:w,style:{pointerEvents:"none",position:"absolute",top:0,left:0,zIndex:0},"aria-hidden":"true",tabIndex:-1}),e]})})}tG.displayName="WebGLPage";let tI=o.p+"copilot_head-e5051da1a2302051.glb",tS=o.p+"ear-e66a523a033aab1e.webp",tz=o.p+"eyes-d65c2b4389677cd6.webp",tE=o.p+"glass-d4c3f0a6ef341a78.webp",tk=o.p+"goggle-9a6fe9e86c3010f5.webp",t_=o.p+"head-9f9717fa05af369d.webp",tB=o.p+"matcap-e3d5ea725297708f.webp",tF=o.p+"screen-d774d3666b0ea059.webp",tN=o.p+"vento-cf31c4a05898b3c7.webp",tA={Ears:{src:tS,texture:null,flipY:!1,isFace:!0,isGoggle:!1,fresnelIntensity:.6,fresnelColor:new f.Q1f(0xa9fbff),fresnelPosRange:new f.I9Y(2,-1),matcapIntensity:1,specularIntensity:1},Eyes:{src:tz,texture:null,flipY:!1,isFace:!0,isGoggle:!1,fresnelIntensity:0,fresnelColor:new f.Q1f(0xbf70ff),fresnelPosRange:new f.I9Y(2,-1),matcapIntensity:0,specularIntensity:0},Glass:{src:tE,texture:null,flipY:!1,isFace:!1,isGoggle:!0,fresnelIntensity:1,fresnelColor:new f.Q1f(5452467),fresnelPosRange:new f.I9Y(0,1),matcapIntensity:.5,specularIntensity:0},Goggle:{src:tk,texture:null,flipY:!1,isFace:!1,isGoggle:!0,fresnelIntensity:.5,fresnelColor:new f.Q1f(9559807),fresnelPosRange:new f.I9Y(0,1),matcapIntensity:2,specularIntensity:0},Head:{src:t_,texture:null,flipY:!1,isFace:!0,isGoggle:!1,fresnelIntensity:.6,fresnelColor:new f.Q1f(0xa9fbff),fresnelPosRange:new f.I9Y(2,-2),matcapIntensity:1,specularIntensity:1},Screen:{src:tF,texture:null,flipY:!1,isFace:!0,isGoggle:!1,fresnelIntensity:1,fresnelColor:new f.Q1f(1118102),fresnelPosRange:new f.I9Y(2,-1),matcapIntensity:0,specularIntensity:1},Vents:{src:tN,texture:null,flipY:!1,isFace:!0,isGoggle:!1,fresnelIntensity:0,fresnelColor:new f.Q1f(0xbf70ff),fresnelPosRange:new f.I9Y(2,-1),matcapIntensity:1,specularIntensity:1}},tY={matcap:{src:tB,texture:null,flipY:!0}},tO={head:{src:tI,scene:new f.Z58}};class tU{originalPos;mousemoveFuncs;pos;targetElementPos;targetElementSize;isMousemove=!1;constructor(e,t){this.targetElementPos=e,this.targetElementSize=t,this.originalPos=new f.I9Y,this.mousemoveFuncs=[],this.pos={target:new f.I9Y(0,0),current:new f.I9Y(0,0),current2:new f.I9Y(0,0)}}onMousemove(e){this.isMousemove=!0;let t=(e.clientX-this.targetElementPos.x)/this.targetElementSize.x;t=(t-.5)*2;let o=(e.clientY-this.targetElementPos.y)/this.targetElementSize.y;o=(.5-o)*2,this.updateMousePos(t,o)}onTouchstart(e){if(this.isMousemove=!0,e.touches[0]){let t=(e.touches[0].clientX-this.targetElementPos.x)/this.targetElementSize.x;t=(t-.5)*2;let o=(e.touches[0].clientY-this.targetElementPos.y)/this.targetElementSize.y;o=(.5-o)*2,this.updateMousePos(t,o)}}updateMousePos(e,t){for(let o of(this.pos.target.set(e,t),this.mousemoveFuncs))o()}addMousemoveFunc(e){this.mousemoveFuncs.push(e)}resize(){}update(e){this.pos.current.lerp(this.pos.target,Math.min(1,2*e)),this.pos.current2.lerp(this.pos.target,Math.min(1,1.5*e))}}let tL=`

uniform sampler2D map;
uniform sampler2D matcap;
uniform float fresnelBias;
uniform float fresnelScale;
uniform float fresnelPower;
uniform float uFresnelIntensity;
uniform vec3 uFresnelColor;
uniform vec2 uFresnelPosRange;
uniform float uSpecularIntensity;
uniform vec3 uLightPosition;

varying vec3 vViewPosition;
varying vec2 vUv;
varying vec3 vNormal;
varying vec3 vLocalPosition;

//http://gamedev.stackexchange.com/questions/59797/glsl-shader-change-hue-saturation-brightness
vec3 rgb2hsv(vec3 c)
{
    vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
    vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));

    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c)
{
    vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}


void main() {
        vec4 diffuseColor = vec4(1.0);
        vec4 sampledDiffuseColor = texture2D( map, vUv );
        diffuseColor *= sampledDiffuseColor;

        vec3 normal = normalize( vNormal );
        float light = dot(normal, normalize(uLightPosition)) * 0.5 + 0.5;
        float specular_1 = dot(normal, normalize(vec3(0.5, 1, 1))) * 0.5 + 0.5;
        specular_1 = smoothstep(0.95, 1.0, specular_1);

        float specular_2 = dot(normal, normalize(vec3(-0.5, -1, 1))) * 0.5 + 0.5;
        specular_2 = smoothstep(0.95, 1.0, specular_1);

        float specular = max(specular_1, specular_2) * uSpecularIntensity;




        vec3 viewDir = normalize( vViewPosition );
        vec3 x = normalize( vec3( viewDir.z, 0.0, - viewDir.x ) );
        vec3 y = cross( viewDir, x );
        vec2 uv = vec2( dot( x, normal ), dot( y, normal ) ) * 0.495 + 0.5;

        vec4 matcapColor = texture2D( matcap, uv );
        matcapColor = linearToOutputTexel(matcapColor);

        vec3 outgoingLight = diffuseColor.rgb;

        float fp = fresnelPower;

        float fresnel = fresnelBias + fresnelScale * pow(1.0 - dot(normalize(vNormal), vec3(0.0, 0.0, 1.0)), fp);

        fresnel = min(fresnel, 1.0);


        float gradientPos = smoothstep(uFresnelPosRange.x, uFresnelPosRange.y, vLocalPosition.y); // Gradient based on y-position
        vec4 fresnelColor = vec4(uFresnelColor, 1.0);

        gl_FragColor = vec4( outgoingLight, diffuseColor.a );
        gl_FragColor = linearToOutputTexel( gl_FragColor );
        gl_FragColor = mix(gl_FragColor, fresnelColor, uFresnelIntensity * fresnel * gradientPos);


        float glowIntensity = length(vec3(0.0, -1.0, 0.0) - vLocalPosition);
        glowIntensity = smoothstep(0.5, 0.0, glowIntensity);

        vec3 hsv = rgb2hsv(gl_FragColor.rgb);
        hsv.r -= glowIntensity * 0.05;
        hsv.g += 0.1 - specular * 0.2;
        hsv.b += mix(-0.2, 0.1, matcapColor.g) + specular * 0.1;
        hsv.b = clamp(hsv.b, 0.0, 1.0);
        gl_FragColor.rgb = hsv2rgb(hsv);
        gl_FragColor.rgb += glowIntensity * 0.2 + light * 0.3 * uFresnelIntensity;



        gl_FragColor.rgb = pow(gl_FragColor.rgb, vec3(1.8));

        // debug
        // gl_FragColor.rgb = vec3(fresnel);
}
`,tQ=`

uniform bool uIsEye;
uniform float uWink;
varying vec2 vUv;
varying vec3 vNormal;
varying vec3 vViewPosition;
varying vec3 vLocalPosition;

float parabola(float x){
        return -pow(2.0 * x, 2.0);
}



void main() {
        vUv = uv;
        vec3 objectNormal = normal;
        vec3 transformedNormal = objectNormal;
        transformedNormal = normalMatrix * transformedNormal;
        vNormal = normalize( transformedNormal );

        vec3 transformed = vec3( position );
        vLocalPosition = transformed;

        vec4 worldPosition = modelMatrix * vec4(transformed, 1.0);
        vViewPosition.y = worldPosition.y;

        transformed.y += parabola(transformed.x) * uWink * 2.0;

        vec4 mvPosition = vec4( transformed, 1.0 );
        mvPosition = modelViewMatrix * mvPosition;
        vViewPosition = - mvPosition.xyz;
        gl_Position = projectionMatrix * mvPosition;
}
`,tW=new f.Pq0(.6,.6,1);class tX{group=new f.YJl;animationGroup_1=new f.YJl;animationGroup_2=new f.YJl;animationGroup_3=new f.YJl;goggleGroup=new f.YJl;faceGroup=new f.YJl;eyesMeshes={left:null,right:null};targetElement;targetElementSize=new f.I9Y(1,1);targetElementPos=new f.I9Y(0,0);windowSize;meshes=[];uniforms={fresnelBias:{value:0},fresnelScale:{value:2},fresnelPower:{value:1},uLightPosition:{value:new f.Pq0(.5,1,-1).normalize()}};isInitTlPlayed=!1;initTl;mouseMng;lookatProgress={target:0,current:0};lookatTarget=new f.Pq0(0,0,1);lookatTarget_default=new f.Pq0(0,0,1);globalPosition=new f.Pq0(0,0,0);isBlinking=!1;blinkTimer=null;constructor(e,t){this.targetElement=e,this.windowSize=t,this.group.add(this.animationGroup_1),this.animationGroup_1.add(this.animationGroup_2),this.animationGroup_2.add(this.animationGroup_3),this.animationGroup_3.add(this.goggleGroup),this.animationGroup_3.add(this.faceGroup),this.mouseMng=new tU(this.targetElementPos,this.targetElementSize),this.initTl=g.Ay.timeline({paused:!0,onComplete:()=>{this.createBlinkEyes()}}),(e=>{let t,o,i;Promise.all([...(t=new f.Tap,Object.values(tY).map(e=>new Promise((o,i)=>{t.load(e.src,t=>{e.texture=t,t.flipY=e.flipY,o(t)},void 0,e=>i(e instanceof Error?e:Error("Asset load failed")))}))),...(o=new C.B,Object.values(tO).map(e=>new Promise((t,i)=>{o.load(e.src,o=>{e.scene=o.scene,t(o.scene)},void 0,e=>i(e instanceof Error?e:Error("Asset load failed")))}))),...(i=new f.Tap,Object.values(tA).map(e=>new Promise((t,o)=>{i.load(e.src,o=>{e.texture=o,o.flipY=e.flipY,t(o)},void 0,e=>o(e instanceof Error?e:Error("Asset load failed")))})))]).then(()=>{e&&e()})})(()=>{this.init(),this.initTl.add(()=>{this.group.visible=!0}).fromTo(this.animationGroup_1.position,{y:-2},{y:0,ease:"elastic.out(1,0.5)",duration:1.5},0).fromTo(this.animationGroup_3.scale,{x:0,y:0,z:0},{x:1,y:1,z:1,ease:"expo.out",duration:.3},0)})}init(){for(let[e,t]of Object.entries(tA))if(t.texture){let o=tO.head.scene?.getObjectByName(e);if(o)switch(e){case"Eyes":case"Ears":case"Goggle":case"Glass":{let i=this.createMaterial(t,e),s=this.createMaterial(t,e),r=new f.eaF(o.geometry.clone(),i),a=new f.eaF(o.geometry.clone(),s);r.name=`${e}_left`,a.name=`${e}_right`,a.geometry.scale(-1,1,1),"Eyes"===e&&(r.position.copy(o.position),a.position.copy(o.position),a.position.x*=-1,this.eyesMeshes.left=r,this.eyesMeshes.right=a),this.meshes.push({mesh:r,isGoggle:t.isGoggle,isFace:t.isFace}),this.meshes.push({mesh:a,isGoggle:t.isGoggle,isFace:t.isFace}),t.isGoggle&&(this.goggleGroup.add(r),this.goggleGroup.add(a)),t.isFace&&(this.faceGroup.add(r),this.faceGroup.add(a));break}default:{let i=this.createMaterial(t,e),s=new f.eaF(o.geometry.clone(),i);s.name=e,this.meshes.push({mesh:s,isGoggle:t.isGoggle,isFace:t.isFace}),s.matrixWorldNeedsUpdate=!0,t.isGoggle&&this.goggleGroup.add(s),t.isFace&&this.faceGroup.add(s)}}}}createMaterial(e,t){let o={uWink:{value:0}},i={...this.uniforms,map:{value:e.texture},matcap:{value:tY.matcap.texture},uFresnelIntensity:{value:e.fresnelIntensity},uIsEye:{value:"Eyes"===t},uFresnelColor:{value:e.fresnelColor},uFresnelPosRange:{value:e.fresnelPosRange},uSpecularIntensity:{value:e.specularIntensity},...o},s=new f.BKk({vertexShader:tQ,fragmentShader:tL,uniforms:i,transparent:!0,side:2,defines:{GLASS:+("Glass"===t)}});return s.userData.uniforms=o,s}createBlinkEyes(){this.isBlinking=!0;let e=g.Ay.timeline({onComplete:()=>{this.isBlinking=!1;let e=1e3*f.cj9.lerp(2,6,Math.random());this.blinkTimer=setTimeout(()=>{this.createBlinkEyes()},e)},defaults:{ease:"power3.out"}}),t=.8>Math.random()?"blinkType1":"blinkType2",o=[this.eyesMeshes.left?this.eyesMeshes.left.scale:new f.Pq0(1,1,1),this.eyesMeshes.right?this.eyesMeshes.right.scale:new f.Pq0(1,1,1)];"blinkType1"===t?e.to(o,.1,{y:.1},0).to(o,.3,{y:1},.2):e.to(o,.1,{y:.1},0).to(o,.2,{y:1},.2).to(o,.3,{y:.1},.4).to(o,.3,{y:1},.7)}resize(){}onMousemove(e){this.mouseMng.onMousemove(e)}onTouchstart(e){this.mouseMng.onTouchstart(e)}update(e,t){let o=this.targetElement.getBoundingClientRect(),i=o.left+o.width/2-this.windowSize.x/2,s=-(o.top+o.height/2-this.windowSize.y/2);this.group.position.set(i,s,-(2*(.25*o.width))),this.targetElementPos.set(o.left,o.top),this.targetElementSize.set(o.width,o.height);let r=o.bottom>=0&&o.right>=0&&o.top<=this.windowSize.y&&o.left<=this.windowSize.x;!this.isInitTlPlayed&&r&&(this.isInitTlPlayed=!0,this.initTl.play()),this.group.scale.set(.25*o.width,.25*o.width,.25*o.width);let a=this.mouseMng.pos.target.length();this.lookatProgress.target=f.cj9.clamp(f.cj9.mapLinear(a,5,3,0,1),0,1),this.mouseMng.isMousemove||(this.lookatProgress.target=0),this.lookatProgress.current+=(this.lookatProgress.target-this.lookatProgress.current)*Math.min(1,6*t),this.lookatTarget_default.copy(tW),this.lookatTarget.set(.2*this.mouseMng.pos.current.x,.2*this.mouseMng.pos.current.y,1),this.lookatTarget.lerp(this.lookatTarget_default,1-this.lookatProgress.current);let n=new f.Pq0;this.animationGroup_2.getWorldPosition(n),this.lookatTarget.x+=n.x,this.lookatTarget.y+=n.y,this.lookatTarget.z+=n.z,this.animationGroup_2.lookAt(this.lookatTarget),this.mouseMng.update(t)}}},513759(e,t,o){let i="GraphQLTraces",s="GraphQLTracingRefresh",r=a()?decodeURIComponent(new URLSearchParams(window.location.search).get("disable_clusters")||"").split(",").filter(e=>""!==e):[];function a(){return"u">typeof window}function n(e){if(!a()||!l()||!e)return;let t=window;t&&!t[i]&&(t[i]=[]),t&&e.__trace&&(t[i].push(e.__trace),"function"==typeof t[s]&&t[s]())}function l(){if(!a())return!1;let e=window;return"true"===new URLSearchParams(window.location.search).get("_tracing")||e&&void 0!==e[i]}function u(){return r.length>0}function c(e){if(!a()||!l()&&!u())return e;let t=new URL(e,window.location.origin);return l()&&t.searchParams.set("_tracing","true"),u()&&t.searchParams.set("disable_clusters",r.join(",")),t.pathname+t.search}function f(e){return r.indexOf(e)>-1}function h(e){if(!a())return;let t=r.indexOf(e);t>-1?r.splice(t,1):r.push(e);let o=new URLSearchParams(window.location.search);o.set("disable_clusters",r.join(",")),window.location.search=o.toString()}o.d(t,{Av:()=>n,HX:()=>f,M_:()=>h,RD:()=>c},{BM:i,rb:s})},35040(e,t,o){o.d(t,{W:()=>d});var i=o(474848),s=o(626067),r=o(916522),a=o(355368),n=o(296540),l=o(724944);function u(e){return e.replace(/\/$/,"")||"/"}let c=e=>{if(void 0===e.actual)return!1;let t=new URL(e.url,void 0),o=new URL(e.actual,void 0),i=t.hostname===o.hostname,s=u(t.pathname)===u(o.pathname);return i&&s};var f=o(551587);let h="subnav",d=(0,s.tx)()?e=>{let t,o,s,u,d,p,v,m,w,b,g,P,y,x,q=(0,r.c)(42);q[0]!==e?({ref:s,component:t,...o}=e,q[0]=e,q[1]=t,q[2]=o,q[3]=s):(t=q[1],o=q[2],s=q[3]);let[C,R]=(0,n.useState)(void 0);q[4]!==C||q[5]!==t.fields.subheading?(u=t.fields.subheading&&!c({url:t.fields.subheading.fields.href,actual:C}),q[4]=C,q[5]=t.fields.subheading,q[6]=u):u=q[6];let M=u;q[7]===Symbol.for("react.memo_cache_sentinel")?(d=()=>{R(window.location.href)},p=[],q[7]=d,q[8]=p):(d=q[7],p=q[8]),(0,n.useEffect)(d,p);let D=o["data-color-mode"],T=o.className,G=o.hasShadow,I=`subnav-heading-link-${t.fields.heading.sys.id}`,S=t.fields.heading.fields.href;if(q[9]!==t.fields.heading.fields.text?(v=(0,f.$C)({action:t.fields.heading.fields.text,tag:"link",location:h}),q[9]=t.fields.heading.fields.text,q[10]=v):v=q[10],q[11]!==t.fields.heading.fields.href||q[12]!==t.fields.heading.fields.text||q[13]!==I||q[14]!==v?(m=(0,i.jsx)(a.SubNav.Heading,{"data-ref":I,href:S,...v,children:t.fields.heading.fields.text}),q[11]=t.fields.heading.fields.href,q[12]=t.fields.heading.fields.text,q[13]=I,q[14]=v,q[15]=m):m=q[15],q[16]!==C||q[17]!==t.fields.subheading?(w=t.fields.subheading&&(0,i.jsx)(a.SubNav.SubHeading,{"data-ref":`subnav-subheading-link-${t.fields.subheading.sys.id}`,href:t.fields.subheading.fields.href,...c({url:t.fields.subheading.fields.href,actual:C})?{"aria-current":"page"}:{},...(0,f.$C)({action:t.fields.subheading.fields.text,tag:"link",location:h}),children:t.fields.subheading.fields.text}),q[16]=C,q[17]=t.fields.subheading,q[18]=w):w=q[18],q[19]!==C||q[20]!==t.fields.links||q[21]!==o.linkVariant){let e;q[23]!==C||q[24]!==o.linkVariant?(e=e=>{if((0,l.P)(e)){let{href:t,text:s}=e.fields,r=c({url:t,actual:C});return(0,i.jsx)(a.SubNav.Link,{"data-ref":`subnav-link-${e.sys.id}`,href:t,variant:o.linkVariant,...r?{"aria-current":"page"}:{},...(0,f.$C)({action:s,tag:"link",location:h}),children:s},e.sys.id)}let{heading:t,links:s}=e.fields,r=void 0===s?[]:s;return(0,i.jsxs)(a.SubNav.Link,{href:t.fields.href,variant:o.linkVariant,...c({url:t.fields.href,actual:C})?{"aria-current":"page"}:{},children:[t.fields.text,r.length>0&&(0,i.jsx)(a.SubNav.SubMenu,{children:r.map(e=>(0,i.jsx)(a.SubNav.Link,{href:e.fields.href,variant:o.linkVariant,"data-ref":`subnav-submenu-link-${e.sys.id}`,...c({url:e.fields.href,actual:C})?{"aria-current":"page"}:{},...(0,f.$C)({action:e.fields.text,tag:"link",context:t.fields.text,location:h}),children:e.fields.text},e.sys.id))})]},t.sys.id)},q[23]=C,q[24]=o.linkVariant,q[25]=e):e=q[25],b=t.fields.links.map(e),q[19]=C,q[20]=t.fields.links,q[21]=o.linkVariant,q[22]=b}else b=q[22];return q[26]!==t.fields.cta?(g=void 0!==t.fields.cta&&(0,i.jsx)(a.SubNav.Action,{href:t.fields.cta.fields.href,"data-ref":`subnav-cta-action-${t.fields.cta.sys.id}`,children:t.fields.cta.fields.text}),q[26]=t.fields.cta,q[27]=g):g=q[27],q[28]!==o.className||q[29]!==o.hasShadow||q[30]!==s||q[31]!==m||q[32]!==w||q[33]!==b||q[34]!==g?(P=(0,i.jsxs)(a.SubNav,{className:T,hasShadow:G,ref:s,children:[m,w,b,g]}),q[28]=o.className,q[29]=o.hasShadow,q[30]=s,q[31]=m,q[32]=w,q[33]=b,q[34]=g,q[35]=P):P=q[35],q[36]!==M?(y=M&&(0,i.jsx)(a.Box,{paddingBlockStart:{narrow:64,regular:"none"}}),q[36]=M,q[37]=y):y=q[37],q[38]!==P||q[39]!==y||q[40]!==D?(x=(0,i.jsxs)("div",{"data-color-mode":D,children:[P,y]}),q[38]=P,q[39]=y,q[40]=D,q[41]=x):x=q[41],x}:({ref:e,component:t,...o})=>{let[s,r]=(0,n.useState)(void 0),u=t.fields.subheading&&!c({url:t.fields.subheading.fields.href,actual:s});return(0,n.useEffect)(()=>{r(window.location.href)},[]),(0,i.jsxs)("div",{"data-color-mode":o["data-color-mode"],children:[(0,i.jsxs)(a.SubNav,{className:o.className,hasShadow:o.hasShadow,ref:e,children:[(0,i.jsx)(a.SubNav.Heading,{"data-ref":`subnav-heading-link-${t.fields.heading.sys.id}`,href:t.fields.heading.fields.href,...(0,f.$C)({action:t.fields.heading.fields.text,tag:"link",location:h}),children:t.fields.heading.fields.text}),t.fields.subheading&&(0,i.jsx)(a.SubNav.SubHeading,{"data-ref":`subnav-subheading-link-${t.fields.subheading.sys.id}`,href:t.fields.subheading.fields.href,...c({url:t.fields.subheading.fields.href,actual:s})?{"aria-current":"page"}:{},...(0,f.$C)({action:t.fields.subheading.fields.text,tag:"link",location:h}),children:t.fields.subheading.fields.text}),t.fields.links.map(e=>{if((0,l.P)(e)){let{href:t,text:r}=e.fields,n=c({url:t,actual:s});return(0,i.jsx)(a.SubNav.Link,{"data-ref":`subnav-link-${e.sys.id}`,href:t,variant:o.linkVariant,...n?{"aria-current":"page"}:{},...(0,f.$C)({action:r,tag:"link",location:h}),children:r},e.sys.id)}let{heading:t,links:r=[]}=e.fields;return(0,i.jsxs)(a.SubNav.Link,{href:t.fields.href,variant:o.linkVariant,...c({url:t.fields.href,actual:s})?{"aria-current":"page"}:{},children:[t.fields.text,r.length>0&&(0,i.jsx)(a.SubNav.SubMenu,{children:r.map(e=>(0,i.jsx)(a.SubNav.Link,{href:e.fields.href,variant:o.linkVariant,"data-ref":`subnav-submenu-link-${e.sys.id}`,...c({url:e.fields.href,actual:s})?{"aria-current":"page"}:{},...(0,f.$C)({action:e.fields.text,tag:"link",context:t.fields.text,location:h}),children:e.fields.text},e.sys.id))})]},t.sys.id)}),void 0!==t.fields.cta&&(0,i.jsx)(a.SubNav.Action,{href:t.fields.cta.fields.href,"data-ref":`subnav-cta-action-${t.fields.cta.sys.id}`,children:t.fields.cta.fields.text})]}),u&&(0,i.jsx)(a.Box,{paddingBlockStart:{narrow:64,regular:"none"}})]})};d.displayName="ContentfulSubnav"},178597(e,t,o){var i=o(705045),s=o(941763),r=o(513759);async function a(e,t={}){let o,n,l,u;var c,f=e;if(new URL(f,window.location.origin).origin!==window.location.origin)throw Error("Can not make cross-origin requests from verifiedFetch");let{tracingEnabled:h,fetchPath:d}=(o=new URL(c=e,window.location.href),(l=(n=new URL(window.location.href,window.location.origin)).searchParams.get("_features"))&&!o.searchParams.has("_features")&&o.searchParams.set("_features",l),(u=n.searchParams.get("_tracing"))&&!o.searchParams.has("_tracing")&&o.searchParams.set("_tracing",u),{tracingEnabled:!!u,fetchPath:c.startsWith(window.location.origin)?o.href:`${o.pathname}${o.search}`}),p={...t.headers,"GitHub-Verified-Fetch":"true",...(0,i.kt)()},v=await fetch(d,{...t,headers:p}),m=v?.headers?.get("X-Github-Request-Id");if(m&&(0,s.Ex)(m),h&&v){let e=v.clone();try{let t=await e.text(),o=t&&JSON.parse(t);(0,r.Av)(o)}catch{}}return v}function n(e,t){let o={...t?.headers??{},Accept:"application/json","Content-Type":"application/json"},i=t?.body?JSON.stringify(t.body):void 0;return a(e,{...t,body:i,headers:o})}function l(e,t={}){let o={...t.headers,"GitHub-Is-React":"true"};return a(e,{...t,headers:o})}function u(e,t){let o={...t?.headers??{},"GitHub-Is-React":"true"};return n(e,{...t,headers:o})}o.d(t,{DI:()=>a,QJ:()=>l,Sr:()=>u,lS:()=>n})}}]);
//# sourceMappingURL=20034-bb332fde903d9815-face61cdfda695c0.js.map
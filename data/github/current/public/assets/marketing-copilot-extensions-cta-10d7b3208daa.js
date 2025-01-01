"use strict";(globalThis.webpackChunk=globalThis.webpackChunk||[]).push([["marketing-copilot-extensions-cta"],{97379:(e,t,i)=>{var s=i(68151);let n={linear:function(e){return e},easeInSine:function(e){return -1*Math.cos(Math.PI/2*e)+1},easeOutSine:function(e){return Math.sin(Math.PI/2*e)},easeInOutSine:function(e){return -.5*(Math.cos(Math.PI*e)-1)},easeInQuad:function(e){return e*e},easeOutQuad:function(e){return e*(2-e)},easeInOutQuad:function(e){return e<.5?2*e*e:-1+(4-2*e)*e},easeInCubic:function(e){return e*e*e},easeOutCubic:function(e){let t=e-1;return t*t*t+1},easeInOutCubic:function(e){return e<.5?4*e*e*e:(e-1)*(2*e-2)*(2*e-2)+1},easeInQuart:function(e){return e*e*e*e},easeOutQuart:function(e){let t=e-1;return 1-t*t*t*t},easeInOutQuart:function(e){let t=e-1;return e<.5?8*e*e*e*e:1-8*t*t*t*t},easeInQuint:function(e){return e*e*e*e*e},easeOutQuint:function(e){let t=e-1;return 1+t*t*t*t*t},easeInOutQuint:function(e){let t=e-1;return e<.5?16*e*e*e*e*e:1+16*t*t*t*t*t},easeInExpo:function(e){return 0===e?0:Math.pow(2,10*(e-1))},easeOutExpo:function(e){return 1===e?1:-Math.pow(2,-10*e)+1},easeInOutExpo:function(e){if(0===e||1===e)return e;let t=2*e,i=t-1;return t<1?.5*Math.pow(2,10*i):.5*(-Math.pow(2,-10*i)+2)},easeInCirc:function(e){return -1*(Math.sqrt(1-e/1*e)-1)},easeOutCirc:function(e){let t=e-1;return Math.sqrt(1-t*t)},easeInOutCirc:function(e){let t=2*e,i=t-2;return t<1?-.5*(Math.sqrt(1-t*t)-1):.5*(Math.sqrt(1-i*i)+1)},easeInBack:function(e,t=1.70158){return e*e*((t+1)*e-t)},easeOutBack:function(e,t=1.70158){let i=e/1-1;return i*i*((t+1)*i+t)+1},easeInOutBack:function(e,t=1.70158){let i=2*e,s=i-2,n=1.525*t;return i<1?.5*i*i*((n+1)*i-n):.5*(s*s*((n+1)*s+n)+2)},easeInElastic:function(e,t=.7){if(0===e||1===e)return e;let i=e/1-1,s=1-t;return-(Math.pow(2,10*i)*Math.sin(2*Math.PI*(i-s/(2*Math.PI)*Math.asin(1))/s))},easeOutElastic:function(e,t=.7){if(0===e||1===e)return e;let i=1-t,s=2*e;return Math.pow(2,-10*s)*Math.sin(2*Math.PI*(s-i/(2*Math.PI)*Math.asin(1))/i)+1},easeInOutElastic:function(e,t=.65){if(0===e||1===e)return e;let i=1-t,s=2*e,n=s-1,a=i/(2*Math.PI)*Math.asin(1);return s<1?-(Math.pow(2,10*n)*Math.sin(2*Math.PI*(n-a)/i)*.5):Math.pow(2,-10*n)*Math.sin(2*Math.PI*(n-a)/i)*.5+1},easeInBounce:o,easeOutBounce:a,easeInOutBounce:function(e){return e<.5?.5*o(2*e):.5*a(2*e-1)+.5}};function a(e){let t=e/1;if(t<1/2.75)return 7.5625*t*t;if(t<2/2.75){let e=t-1.5/2.75;return 7.5625*e*e+.75}if(t<2.5/2.75){let e=t-2.25/2.75;return 7.5625*e*e+.9375}{let e=t-2.625/2.75;return 7.5625*e*e+.984375}}function o(e){return 1-a(1-e)}let r=class Timeline{to(e,t,i,s){let n,a=0;if(void 0===s||isNaN(s)){if(this.animations.length>0){let e=this.animations[this.animations.length-1];e&&(a=e.duration+e.delay)}else a=0}else a=s;n=Array.isArray(e)?e:[e],this.animations.push({datas:n,duration:t,easing:i.easing||this.easing,onComplete:i.onComplete,onUpdate:i.onUpdate,values:[],delay:a,properties:i,isStarted:!1,isLast:!1,isFinished:!1});let o=0,r=0;for(let e of this.animations){let t=e.duration+e.delay;o<t&&(o=t,this.lastIndex=r),e.isLast=!1,r++}return this}start(){this.startTime=new Date,this.oldTime=new Date;let e=this.animations[this.lastIndex];e&&(e.isLast=!0),window.addEventListener("visibilitychange",this.onVisiblitychange),this.animate()}arrangeDatas(e){let{properties:t,datas:i,values:s}=e;for(let e in t){let n=0,a=[],o=[],r=[];switch(e){case"easing":case"onComplete":case"onUpdate":break;default:for(let s of i)null!==s&&"object"==typeof s&&(a[n]=s[e],o[n]=s[e],r[n]=t[e],n++);s.push({key:e,start:a,current:o,end:r})}}}calcProgress(e,t,i){return Math.max(0,Math.min(1,(i-e)/(t-e)))}calcLerp(e,t,i){return e+(t-e)*i}constructor(e){this.animate=()=>{let e=new Date;this.isWindowFocus||(this.oldTime=e);let t=e.getTime()-this.oldTime.getTime();for(let i of(this.time+=t,this.oldTime=e,this.animations)){let{datas:e,duration:t,easing:s,values:a,delay:o}=i;if(this.time>o&&!i.isFinished){i.isStarted||(i.isStarted=!0,this.arrangeDatas(i));let r=this.calcProgress(0,t,this.time-o),l=n[s];void 0!==l&&(r=l(r));for(let t=0;t<a.length;t++){let i=a[t];for(let t=0;t<e.length;t++){let s=e[t];void 0!==i&&(i.current[t]=this.calcLerp(i.start[t],i.end[t],r),"object"==typeof s&&null!==s&&(s[i.key]=i.current[t]))}}if(i.onUpdate){i.onUpdate();return}1===r&&(i.isFinished=!0,i.onComplete&&i.onComplete(),i.isLast&&(this.isFinished=!0))}}this.isFinished?(window.removeEventListener("visibilitychange",this.onVisiblitychange),this.onComplete()):(this.onUpdate(),requestAnimationFrame(this.animate))},this.onVisiblitychange=()=>{"visible"===document.visibilityState?this.isWindowFocus=!0:this.isWindowFocus=!1},this.easing=e.easing||"linear",this.options=e,this.onUpdate=e.onUpdate||function(){},this.onComplete=e.onComplete||function(){},this.isFinished=!1,this.lastIndex=0,this.isWindowFocus=!0,this.animations=[],this.startTime=new Date,this.oldTime=new Date,this.time=0}};var l=i(39437);let u=class Animations{init(){this.createIntroAnimation()}createIntroAnimation(){this.createBlinkEyes()}createBlinkEyes(){this.isBlinking=!0;let e=new r({onComplete:()=>{this.isBlinking=!1;let e=1e3*(0,s.Cc)(2,6,Math.random());this.blinkTimer=setTimeout(()=>{this.createBlinkEyes()},e)},easing:"easeOutCubic"}),t=.8>Math.random()?"blinkType1":"blinkType2",i=this.eyesMeshes.left,n=this.eyesMeshes.right,a=[i?i.scale:1,n?n.scale:1];"blinkType1"===t?e.to(a,50,{y:.1},0).to(a,150,{y:1},100).start():e.to(a,50,{y:.1},0).to(a,100,{y:1},100).to(a,150,{y:.1}).to(a,150,{y:1}).start()}createClickAnimation(){this.isPlayingClickAnim||this.createJump()}createJump(){if(this.isPlayingClickAnim)return;this.isPlayingClickAnim=!0,this.isBlinking||(this.blinkTimer&&clearTimeout(this.blinkTimer),this.createSmile());let e={anim_rotating:this.goggleGroup.userData.rotateX.anim_rotating},t=new r({onComplete:()=>{this.isPlayingClickAnim=!1},onUpdate:()=>{this.goggleGroup.userData.rotateX.anim_rotating=e.anim_rotating},easing:"easeOutCubic"}),i=this.animationGroup.scale,s=this.animationGroup.position,n=this.animationGroup.rotation;t.to(i,300,{y:.95,x:1.05},0).to(i,300,{y:1.03,x:.97}).to(i,300,{y:.98,x:1.02}).to(i,300,{y:1.015,x:.985}).to(i,300,{y:.97,x:1.03}).to(i,300,{y:1,x:1}).to(n,200,{x:.2},0).to(n,500,{x:-.1},200).to(n,300,{x:0},700).to(s,100,{y:-.2},0).to(s,300,{y:1.8},100).to(s,300,{y:0,easing:"easeInQuad"},400).to(s,300,{y:.8},700).to(s,200,{y:-.4,easing:"easeInQuad"},1e3).to(s,200,{y:0},1200);let a=[this.goggleGroup.position];t.to(a,300,{y:.5},200).to(a,200,{y:0},600).to(a,300,{y:.3},800).to(a,400,{y:0},1100).to([e],200,{anim_rotating:.1},1100).to([e],200,{anim_rotating:0},1300).start()}createSmile(){let e=new r({onComplete:()=>{let e=1e3*(0,s.Cc)(1,4,Math.random());this.blinkTimer=setTimeout(()=>{this.createBlinkEyes()},e)},easing:"easeOutQuad"}),t=this.eyesMeshes.left,i=this.eyesMeshes.right,n=[t?t.scale:new l.Pq0(1,1,1),i?i.scale:new l.Pq0(1,1,1)],a=[t.material.userData.uniforms.uWink,i.material.userData.uniforms.uWink],o=t?t.position.y:0,u=[t?t.position:new l.Pq0(0,0,0),i?i.position:new l.Pq0(0,0,0)];e.to(n,100,{y:.6},0).to(n,250,{y:1},1500).to(a,100,{value:.3},0).to(a,100,{value:0},1500).to(u,200,{y:o+.1},0).to(u,200,{y:o},1500).start()}resize(){}update(){}constructor({animationGroup:e,goggleGroup:t,eyesMeshes:i,common:s}){this.isPlayingClickAnim=!1,this.isBlinking=!1,this.common=s,this.goggleGroup=t,this.eyesMeshes=i,this.animationGroup=e,this.init()}},c=`
#define MATCAP
varying vec3 vViewPosition;
uniform bool uIsEye;
uniform float uWink;
#include <common>
#include <uv_pars_vertex>
#include <color_pars_vertex>
#include <displacementmap_pars_vertex>
#include <fog_pars_vertex>
#include <normal_pars_vertex>
#include <morphtarget_pars_vertex>
#include <skinning_pars_vertex>
#include <logdepthbuf_pars_vertex>
#include <clipping_planes_pars_vertex>

float parabola(float x){
	return -pow(2.0 * x, 2.0);
}

void main() {
	#include <uv_vertex>
	#include <color_vertex>
	#include <morphcolor_vertex>
	#include <beginnormal_vertex>
	#include <morphnormal_vertex>
	#include <skinbase_vertex>
	#include <skinnormal_vertex>
	#include <defaultnormal_vertex>
	#include <normal_vertex>
	#include <begin_vertex>
	#include <morphtarget_vertex>
	#include <skinning_vertex>
	#include <displacementmap_vertex>

    vec4 worldPosition = modelMatrix * vec4(position, 1.0);
    vViewPosition.y = worldPosition.y;

	transformed.y += parabola(transformed.x) * uWink * 2.0;

	#include <project_vertex>
	#include <logdepthbuf_vertex>
	#include <clipping_planes_vertex>
	#include <fog_vertex>
	vViewPosition = - mvPosition.xyz;
}
`,h=`
#define MATCAP
uniform vec3 diffuse;
uniform float opacity;
uniform sampler2D matcap;
uniform float fresnelBias;
uniform float fresnelScale;
uniform float fresnelPower;
uniform float uFresnelIntensity;
uniform float uFresnelGamma;

varying vec3 vViewPosition;
#include <common>
#include <dithering_pars_fragment>
#include <color_pars_fragment>
#include <uv_pars_fragment>
#include <map_pars_fragment>
#include <alphamap_pars_fragment>
#include <alphatest_pars_fragment>
#include <fog_pars_fragment>
#include <normal_pars_fragment>
#include <bumpmap_pars_fragment>
#include <normalmap_pars_fragment>
#include <logdepthbuf_pars_fragment>
#include <clipping_planes_pars_fragment>
void main() {
	#include <clipping_planes_fragment>
	vec4 diffuseColor = vec4( diffuse, opacity );
	#include <logdepthbuf_fragment>
	#include <map_fragment>
	#include <color_fragment>
	#include <alphamap_fragment>
	#include <alphatest_fragment>
	#include <normal_fragment_begin>
	#include <normal_fragment_maps>
	vec3 viewDir = normalize( vViewPosition );
	vec3 x = normalize( vec3( viewDir.z, 0.0, - viewDir.x ) );
	vec3 y = cross( viewDir, x );
	vec2 uv = vec2( dot( x, normal ), dot( y, normal ) ) * 0.495 + 0.5;
	#ifdef USE_MATCAP
		vec4 matcapColor = texture2D( matcap, uv );
	#else
		vec4 matcapColor = vec4( vec3( mix( 0.2, 0.8, uv.y ) ), 1.0 );
	#endif
	vec3 outgoingLight = diffuseColor.rgb * matcapColor.rgb;
	float fresnel = fresnelBias + fresnelScale * pow(1.0 - dot(normalize(vNormal), vec3(0.0, 0.0, 1.0)), fresnelPower);
	float gradient = smoothstep(0.0, 0.5, vNormal.y);
	float gradientPos = smoothstep(0.5, -1.0, vViewPosition.y); // Gradient based on y-position
	vec4 accentGreen = vec4(0.0, 0.4, 0.015, 1.0); // #00FF46
	vec4 fresnelColor = vec4(vec3(0.0, fresnel * gradient, fresnel * gradient * 0.275), fresnel*gradient);
	// fresnelColor *= gradientPos;
	#include <output_fragment>
	// gl_FragColor = mix(gl_FragColor, accentGreen, fresnelColor.a * uFresnelIntensity);
	gl_FragColor.rgb = mix(pow(gl_FragColor.rgb, vec3(1.15)), pow(gl_FragColor.rgb, vec3(uFresnelGamma)), fresnel);

	// gl_FragColor.rgb = vec3(fresnel);



	#include <tonemapping_fragment>
	#include <encodings_fragment>
	#include <fog_fragment>
	#include <premultiplied_alpha_fragment>
	#include <dithering_fragment>
}
`,m=class CopilotHead{init(){this.addMeshes(),this.createAnimations()}addMeshes(){let e=[];if(this.assets.gltfs.head.scene)for(let t of(this.assets.gltfs.head.scene.traverse(t=>{if(t.isMesh){let i;switch(t.name){case"Goggle":case"LeftEye":case"RightEye":case"Glass001":i=this.assets.images.bakedGoggle.texture;break;case"HeadBase":i=this.assets.images.bakedHead.texture;break;case"Screen":i=this.assets.images.bakedOther.texture}let s="HeadBase"===t.name,n="RightEye"===t.name||"LeftEye"===t.name,a="Goggle"===t.name?.9:.5;switch(t.material=this.createMaterial(i,s,n,a),t.name){case"Goggle":case"Glass001":e.push({object:t,isGoggle:!0});break;default:e.push({object:t,isFace:!0})}"RightEye"===t.name?this.eyesMeshes.right=t:"LeftEye"===t.name&&(this.eyesMeshes.left=t)}}),e)){let e=t.object;e.parent&&e.parent.remove(e),t.isGoggle&&this.goggleGroup.add(e),t.isFace&&this.faceGroup.add(e)}}createMaterial(e,t,i,s){let n={uWink:{value:0}},a=new l.FNr({map:e,matcap:this.assets.images.matcap.texture,transparent:!0});return a.onBeforeCompile=e=>{e.uniforms={...e.uniforms,...this.uniforms,uFresnelIntensity:{value:t?1:0},uIsEye:{value:i},uFresnelGamma:{value:s},...n},e.vertexShader=c,e.fragmentShader=h},a.userData.uniforms=n,a}createAnimations(){this.animations=new u({animationGroup:this.animationGroup,goggleGroup:this.goggleGroup,eyesMeshes:this.eyesMeshes,common:this.common}),this.mouseMng.addMousemoveFunc(this.raycast.bind(this))}doHappyReaction(){this.animations.createClickAnimation()}raycast(){this.raycaster.setFromCamera(this.mouseMng.pos.target,this.common.camera),this.raycaster.intersectObject(this.group).length>0?this.isRaycastHit=!0:this.isRaycastHit=!1}update(){this.breathing.rotation=.05*Math.sin(2*this.common.time),this.breathing.position=.08*Math.sin((this.common.time+.25)*2);let e=this.mouseMng.pos.target.length();this.mouseIntensity.target=(0,s.y4)(2,1,e),this.mouseIntensity.current+=(this.mouseIntensity.target-this.mouseIntensity.current)*(0,s.p1)(3,this.common.delta),this.lookatTarget.set(.6*this.mouseMng.pos.current.x,.6*this.mouseMng.pos.current.y,1),this.lookatTarget.lerp(this.lookatTarget_default,1-this.mouseIntensity.current),this.lookatTarget.y+=this.breathing.rotation,this.animations?.isPlayingClickAnim?this.lookatTargetProgress+=(1-this.lookatTargetProgress)*(0,s.p1)(3,this.common.delta):this.lookatTargetProgress+=(0-this.lookatTargetProgress)*(0,s.p1)(3,this.common.delta),this.lookatTarget2.set(this.lookatTarget.x,0,this.lookatTarget.z).lerp(this.lookatTarget,1-this.lookatTargetProgress),this.lookatTarget2.y+=this.group.position.y,this.orientationGroup.lookAt(this.lookatTarget2),this.orientationGroup.position.y=this.breathing.position;let t=(0,s.y4)(0,.5,this.mouseMng.pos.current2.y);for(let e in t=Math.min(t=(0,s.Cc)(0,t,this.mouseIntensity.current)+(this.breathing.rotation+1)*1.2,1),this.goggleGroup.userData.rotateX.orientation=(0,s.Cc)(.1,-.08,t),this.goggleGroup.rotation.x=0,this.goggleGroup.userData.rotateX){let t=this.goggleGroup.userData.rotateX[e];this.goggleGroup.rotation.x+=t}}resize(e){this.group.position.y=e*this.common.copilotAreaOffset.y}constructor(e,t,i){this.lookatTarget=new l.Pq0(0,0,0),this.lookatTarget2=new l.Pq0(0,0,0),this.lookatTargetProgress=0,this.lookatTarget_default=new l.Pq0(0,0,1),this.mouseMng=i,this.common=e,this.assets=t,this.group=new l.YJl,this.orientationGroup=new l.YJl,this.animationGroup=new l.YJl,this.group.add(this.orientationGroup),this.orientationGroup.add(this.animationGroup),this.goggleGroup=new l.YJl,this.faceGroup=new l.YJl,this.animationGroup.add(this.goggleGroup),this.animationGroup.add(this.faceGroup),this.eyesMeshes={left:null,right:null},this.breathing={rotation:0,position:0},this.goggleGroup.userData.rotateX={orientation:0,anim_rotating:0},this.raycaster=new l.tBo,this.isRaycastHit=!1,this.mouseIntensity={target:0,current:0},this.uniforms={fresnelBias:{value:.01},fresnelScale:{value:2},fresnelPower:{value:3}},this.common.scene.add(this.group)}};var d=i(19810);let g=class MouseMng{init(){window.addEventListener("mousemove",e=>{if(!this.common)return;let t=(e.clientX-this.common?.wrapperOffset.x+this.common?.copilotAreaOffset.x)/this.common?.sizes.x;t=(t-.5)*2;let i=(e.clientY-this.common?.wrapperOffset.y+this.common?.copilotAreaOffset.y)/this.common?.sizes.y;i=(.5-i)*2,t=Math.max(-1,Math.min(1,t)),i=Math.max(-1,Math.min(1,i)),this.updateMousePos(t,i)}),window.addEventListener("touchstart",e=>{if(this.common&&e.touches[0]){let t=(e.touches[0].clientX-this.common?.wrapperOffset.x+this.common?.copilotAreaOffset.x)/this.common?.sizes.x;t=(t-.5)*2;let i=(e.touches[0].clientY-this.common?.wrapperOffset.y+this.common?.copilotAreaOffset.y)/this.common?.sizes.y;i=(.5-i)*2,this.updateMousePos(t,i)}})}updateMousePos(e,t){for(let i of(this.pos.target.set(e,t),this.mousemoveFuncs))i()}addMousemoveFunc(e){this.mousemoveFuncs.push(e)}resize(){}update(){this.common&&(this.pos.current.lerp(this.pos.target,(0,s.p1)(2,this.common.delta)),this.pos.current2.lerp(this.pos.target,(0,s.p1)(1.5,this.common.delta)))}constructor(e){this.common=e,this.originalPos=new l.I9Y,this.mousemoveFuncs=[],this.pos={target:new l.I9Y(0,0),current:new l.I9Y(0,0),current2:new l.I9Y(0,0)},this.init()}};var p=i(17888);let f="/images/modules/site/lab/",v=class Assets{async load(e){let t=[...this.loadImages(),...this.loadGltfs()];try{await Promise.all(t),this.isLoaded=!0,e&&e()}catch(e){console.log("Error loading assets",e)}}loadGltfs(){let e=new p.B;return Object.values(this.gltfs).map(t=>new Promise((i,s)=>{e.load(t.src,e=>{t.scene=e.scene,i(e.scene)},void 0,e=>s(e))}))}loadImages(){let e=new l.Tap;return Object.values(this.images).map(t=>new Promise((i,s)=>{e.load(t.src,e=>{t.texture=e,e.flipY=t.flipY,t.encoding&&(e.encoding=t.encoding),i(e)},void 0,e=>s(e))}))}constructor(){this.images={bakedGoggle:{src:`${f}bakedGoggle.png`,texture:null,flipY:!1,encoding:l.S2Q},bakedHead:{src:`${f}bakedHead.png`,texture:null,flipY:!1,encoding:l.S2Q},bakedOther:{src:`${f}bakedOther.png`,texture:null,flipY:!1,encoding:l.S2Q},matcap:{src:`${f}matcap.png`,texture:null,flipY:!0},starShape:{src:`${f}star-shape.jpg`,texture:null,flipY:!1},starShapeShadow:{src:`${f}star-shape-shadow.jpg`,texture:null,flipY:!1},starShapeGlow:{src:`${f}star-shape-glow.jpg`,texture:null,flipY:!1}},this.gltfs={head:{src:`${f}copilot.glb`,scene:null}},this.isLoaded=!1}};var y=i(42089);(0,i(21403).lB)(".js-cta-background",e=>{let t=new v,i=document.querySelector(".js-copilot-head"),s=document.querySelector(".js-cta-banner > div"),n=document.querySelector(".js-cta-pause-button"),a=new d.A(s,i,e,2),o=new g(a),r=new y.A(a,t,!1),l=new m(a,t,o),u=document.querySelectorAll(".js-cta-banner a");t.load(()=>{for(let e of(r.init(),l.init(),u))e.addEventListener("mouseenter",()=>{l.doHappyReaction(),r.speedUp()}),e.addEventListener("mouseleave",()=>{r.speedDown()});_(),M()}),window.addEventListener("scroll",()=>{a.scroll()}),window.addEventListener("resize",()=>{_()});let c=!1,h=!1,p=!1,f=!1,_=()=>{a.resize();let e=a.sizes.y/Math.tan(a.camera.fov*Math.PI/360)*.5,t=a.cameraDistance/e;l.resize(t),r.resize(t),(h||p)&&b()},w=new IntersectionObserver(e=>{for(let t of e)x(t.isIntersecting)}),x=e=>{c=e};w.observe(e),n?.addEventListener("click",()=>{(h=!h)&&c&&(x(!1),n.classList.add("isPaused")),h||c||(x(!0),n.classList.remove("isPaused"))});let b=()=>{r.update(),l.update(),a.renderer.setClearColor(16777215,0),a.renderer.setRenderTarget(null),a.renderer.render(a.scene,a.camera)},M=()=>{a.update(),!c||h||p?f||(f=!0,b()):(o.update(),b());let e=window.matchMedia("(prefers-reduced-motion)");p=!1,e.matches&&(p=!0),window.requestAnimationFrame(M)}})}},e=>{var t=t=>e(e.s=t);e.O(0,["vendors-node_modules_github_selector-observer_dist_index_esm_js","vendors-node_modules_three_build_three_module_js","vendors-node_modules_three_examples_jsm_loaders_GLTFLoader_js","app_assets_modules_copilot-extensions-cta_background_ts-app_assets_modules_copilot-extensions-cfde7a"],()=>t(97379)),e.O()}]);
//# sourceMappingURL=marketing-copilot-extensions-cta-b660e4d3999c.js.map
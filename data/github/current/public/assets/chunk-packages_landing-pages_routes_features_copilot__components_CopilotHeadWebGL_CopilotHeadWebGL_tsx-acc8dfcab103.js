"use strict";(globalThis.webpackChunk_github_ui_github_ui=globalThis.webpackChunk_github_ui_github_ui||[]).push([["packages_landing-pages_routes_features_copilot__components_CopilotHeadWebGL_CopilotHeadWebGL_tsx"],{13063:(e,t,i)=>{i.r(t),i.d(t,{default:()=>I});var s=i(74848),n=i(50467);function o(e,t,i){return Math.max(0,Math.min(1,(i-e)/(t-e)))}var a=i(39437);let r=new class Common{init(e,t){this.clock=new a.zD7,this.canvasWrapper=e,this.pixelRatio=Math.min(window.devicePixelRatio,2),this.renderer=new a.JeP({canvas:t,antialias:!0,alpha:!0}),this.renderer.setPixelRatio(this.pixelRatio),this.renderer.outputEncoding=a.S2Q,this.renderer.toneMapping=a.FV,this.renderer.toneMappingExposure=1.5,this.renderer.setClearColor(0xffffff,0),this.resize()}resize(){let e=this.canvasWrapper.getBoundingClientRect(),t=e.width,i=e.height;this.aspect=t/i,this.sizes.set(t,i),this.wrapperOffset.set(e.left,e.top),this.camera.aspect=this.aspect,this.camera.updateProjectionMatrix(),this.renderer.setSize(t,i)}getEase(e){return Math.min(1,this.delta*e)}update(){let e=this.clock.getDelta();this.delta=e,this.time+=this.delta}constructor(){(0,n._)(this,"sizes",void 0),(0,n._)(this,"pixelRatio",void 0),(0,n._)(this,"aspect",void 0),(0,n._)(this,"scene",void 0),(0,n._)(this,"camera",void 0),(0,n._)(this,"wrapperOffset",void 0),(0,n._)(this,"delta",void 0),(0,n._)(this,"time",void 0),this.sizes=new a.I9Y,this.pixelRatio=1,this.aspect=1,this.scene=new a.Z58,this.camera=new a.ubm(45,this.aspect,.1,200),this.camera.position.set(0,0,11),this.scene.add(this.camera),this.wrapperOffset=new a.I9Y,this.delta=0,this.time=0}},l=new class Controls{getRandomAnim(e){let t=Math.floor(Math.random()*this.frequences.length),i=this.frequences[t];return e&&"wink"===i&&(i="jamp1"),i}init(){}constructor(){(0,n._)(this,"params",void 0),(0,n._)(this,"frequences",void 0),this.params={clickAction:"random",blinkingSpeed:2},this.frequences=["jump1","jump1","jump3","jump3","wink","wink","shake","shake"]}},c=new class MouseMng{init(){window.addEventListener("mousemove",e=>{let t=(e.clientX-r.wrapperOffset.x)/r.sizes.x;t=(t-.5)*2;let i=(e.clientY-r.wrapperOffset.y)/r.sizes.y;i=(.5-i)*2,this.updateMousePos(t,i)}),window.addEventListener("touchstart",e=>{if(e.touches[0]){let t=(e.touches[0].clientX-r.wrapperOffset.x)/r.sizes.x;t=(t-.5)*2;let i=(e.touches[0].clientY-r.wrapperOffset.y)/r.sizes.y;i=(.5-i)*2,this.updateMousePos(t,i)}})}updateMousePos(e,t){for(let i of(this.pos.target.set(e,t),this.mousemoveFuncs))i()}addMousemoveFunc(e){this.mousemoveFuncs.push(e)}resize(){}update(){this.pos.current.lerp(this.pos.target,r.getEase(2)),this.pos.current2.lerp(this.pos.target,r.getEase(1.5))}constructor(){(0,n._)(this,"originalPos",void 0),(0,n._)(this,"mousemoveFuncs",void 0),(0,n._)(this,"pos",void 0),this.originalPos=new a.I9Y,this.mousemoveFuncs=[],this.pos={target:new a.I9Y(-3,-3),current:new a.I9Y(-3,-3),current2:new a.I9Y(-3,-3)}}},u={linear:function(e){return e},easeInSine:function(e){return -1*Math.cos(Math.PI/2*e)+1},easeOutSine:function(e){return Math.sin(Math.PI/2*e)},easeInOutSine:function(e){return -.5*(Math.cos(Math.PI*e)-1)},easeInQuad:function(e){return e*e},easeOutQuad:function(e){return e*(2-e)},easeInOutQuad:function(e){return e<.5?2*e*e:-1+(4-2*e)*e},easeInCubic:function(e){return e*e*e},easeOutCubic:function(e){let t=e-1;return t*t*t+1},easeInOutCubic:function(e){return e<.5?4*e*e*e:(e-1)*(2*e-2)*(2*e-2)+1},easeInQuart:function(e){return e*e*e*e},easeOutQuart:function(e){let t=e-1;return 1-t*t*t*t},easeInOutQuart:function(e){let t=e-1;return e<.5?8*e*e*e*e:1-8*t*t*t*t},easeInQuint:function(e){return e*e*e*e*e},easeOutQuint:function(e){let t=e-1;return 1+t*t*t*t*t},easeInOutQuint:function(e){let t=e-1;return e<.5?16*e*e*e*e*e:1+16*t*t*t*t*t},easeInExpo:function(e){return 0===e?0:Math.pow(2,10*(e-1))},easeOutExpo:function(e){return 1===e?1:-Math.pow(2,-10*e)+1},easeInOutExpo:function(e){if(0===e||1===e)return e;let t=2*e,i=t-1;return t<1?.5*Math.pow(2,10*i):.5*(-Math.pow(2,-10*i)+2)},easeInCirc:function(e){return -1*(Math.sqrt(1-e/1*e)-1)},easeOutCirc:function(e){let t=e-1;return Math.sqrt(1-t*t)},easeInOutCirc:function(e){let t=2*e,i=t-2;return t<1?-.5*(Math.sqrt(1-t*t)-1):.5*(Math.sqrt(1-i*i)+1)},easeInBack:function(e,t=1.70158){return e*e*((t+1)*e-t)},easeOutBack:function(e,t=1.70158){let i=e/1-1;return i*i*((t+1)*i+t)+1},easeInOutBack:function(e,t=1.70158){let i=2*e,s=i-2,n=1.525*t;return i<1?.5*i*i*((n+1)*i-n):.5*(s*s*((n+1)*s+n)+2)},easeInElastic:function(e,t=.7){if(0===e||1===e)return e;let i=e/1-1,s=1-t;return-(Math.pow(2,10*i)*Math.sin(2*Math.PI*(i-s/(2*Math.PI)*Math.asin(1))/s))},easeOutElastic:function(e,t=.7){if(0===e||1===e)return e;let i=1-t,s=2*e;return Math.pow(2,-10*s)*Math.sin(2*Math.PI*(s-i/(2*Math.PI)*Math.asin(1))/i)+1},easeInOutElastic:function(e,t=.65){if(0===e||1===e)return e;let i=1-t,s=2*e,n=s-1,o=i/(2*Math.PI)*Math.asin(1);return s<1?-(Math.pow(2,10*n)*Math.sin(2*Math.PI*(n-o)/i)*.5):Math.pow(2,-10*n)*Math.sin(2*Math.PI*(n-o)/i)*.5+1},easeInBounce:g,easeOutBounce:h,easeInOutBounce:function(e){return e<.5?.5*g(2*e):.5*h(2*e-1)+.5}};function h(e){let t=e/1;if(t<1/2.75)return 7.5625*t*t;if(t<2/2.75){let e=t-1.5/2.75;return 7.5625*e*e+.75}if(t<2.5/2.75){let e=t-2.25/2.75;return 7.5625*e*e+.9375}{let e=t-2.625/2.75;return 7.5625*e*e+.984375}}function g(e){return 1-h(1-e)}let p=class Timeline{to(e,t,i,s){let n,o=0;if(void 0===s||isNaN(s))if(this.animations.length>0){let e=this.animations[this.animations.length-1];e&&(o=e.duration+e.delay)}else o=0;else o=s;n=Array.isArray(e)?e:[e],this.animations.push({datas:n,duration:t,easing:i.easing||this.easing,onComplete:i.onComplete,onUpdate:i.onUpdate,values:[],delay:o,properties:i,isStarted:!1,isLast:!1,isFinished:!1});let a=0,r=0;for(let e of this.animations){let t=e.duration+e.delay;a<t&&(a=t,this.lastIndex=r),e.isLast=!1,r++}return this}start(){this.startTime=new Date,this.oldTime=new Date;let e=this.animations[this.lastIndex];e&&(e.isLast=!0),window.addEventListener("visibilitychange",this.onVisiblitychange),this.animate()}arrangeDatas(e){let{properties:t,datas:i,values:s}=e;for(let e in t){let n=0,o=[],a=[],r=[];switch(e){case"easing":case"onComplete":case"onUpdate":break;default:for(let s of i)null!==s&&"object"==typeof s&&(o[n]=s[e],a[n]=s[e],r[n]=t[e],n++);s.push({key:e,start:o,current:a,end:r})}}}calcProgress(e,t,i){return Math.max(0,Math.min(1,(i-e)/(t-e)))}calcLerp(e,t,i){return e+(t-e)*i}constructor(e){(0,n._)(this,"animations",void 0),(0,n._)(this,"easing",void 0),(0,n._)(this,"options",void 0),(0,n._)(this,"onUpdate",void 0),(0,n._)(this,"onComplete",void 0),(0,n._)(this,"isFinished",void 0),(0,n._)(this,"lastIndex",void 0),(0,n._)(this,"isWindowFocus",void 0),(0,n._)(this,"startTime",void 0),(0,n._)(this,"oldTime",void 0),(0,n._)(this,"time",void 0),(0,n._)(this,"animate",()=>{let e=new Date;this.isWindowFocus||(this.oldTime=e);let t=e.getTime()-this.oldTime.getTime();for(let i of(this.time+=t,this.oldTime=e,this.animations)){let{datas:e,duration:t,easing:s,values:n,delay:o}=i;if(this.time>o&&!i.isFinished){i.isStarted||(i.isStarted=!0,this.arrangeDatas(i));let a=this.calcProgress(0,t,this.time-o),r=u[s];void 0!==r&&(a=r(a));for(let t=0;t<n.length;t++){let i=n[t];for(let t=0;t<e.length;t++){let s=e[t];void 0!==i&&(i.current[t]=this.calcLerp(i.start[t],i.end[t],a),"object"==typeof s&&null!==s&&(s[i.key]=i.current[t]))}}if(i.onUpdate)return void i.onUpdate();1===a&&(i.isFinished=!0,i.onComplete&&i.onComplete(),i.isLast&&(this.isFinished=!0))}}this.isFinished?(window.removeEventListener("visibilitychange",this.onVisiblitychange),this.onComplete()):(this.onUpdate(),requestAnimationFrame(this.animate))}),(0,n._)(this,"onVisiblitychange",()=>{"visible"===document.visibilityState?this.isWindowFocus=!0:this.isWindowFocus=!1}),this.easing=e.easing||"linear",this.options=e,this.onUpdate=e.onUpdate||function(){},this.onComplete=e.onComplete||function(){},this.isFinished=!1,this.lastIndex=0,this.isWindowFocus=!0,this.animations=[],this.startTime=new Date,this.oldTime=new Date,this.time=0}},m=class Animations{init(){setTimeout(()=>{this.createEntrance()},450)}createEntrance(){let e={radius:11,radian:2*Math.PI,lookat:new a.Pq0(0,0,0)},t=new p({onComplete:()=>{this.isFinishedEntrance=!0,this.createBlinkEyes()},easing:"linear",onUpdate:()=>{let t=Math.sin(e.radian)*e.radius,i=Math.cos(e.radian)*e.radius;r.camera.position.set(t,0,i),r.camera.lookAt(e.lookat)}});this.group.visible=!0,t.to(this.group.scale,1e3,{x:1,y:1,z:1,easing:"easeOutBack"},0).to(e,1500,{radian:0,easing:"easeOutBack"},0),t.start()}createBlinkEyes(){this.isBlinking=!0;let e=new p({onComplete:()=>{this.isBlinking=!1;let e=1e3*(2+4*Math.random());this.blinkTimer=setTimeout(()=>{this.createBlinkEyes()},e)},easing:"easeOutCubic"}),t=.8>Math.random()?"blinkType1":"blinkType2",i=l.params.blinkingSpeed/1e3,s=this.eyesMeshes.left,n=this.eyesMeshes.right,o=[s?s.scale:1,n?n.scale:1];"blinkType1"===t?e.to(o,.1/i,{y:.1},0).to(o,.3/i,{y:1},.2/i).start():e.to(o,.1/i,{y:.1},0).to(o,.2/i,{y:1},.2/i).to(o,.3/i,{y:.1}).to(o,.3/i,{y:1}).start()}createClickAnimation(){if(this.isFinishedEntrance&&!this.isPlayingClickAnim)switch("random"===l.params.clickAction?this.clickAction=l.getRandomAnim(this.isBlinking):this.clickAction=l.params.clickAction,this.clickAction){case"wink":if(this.isBlinking)return;this.blinkTimer&&clearTimeout(this.blinkTimer),this.createWink();break;case"jump1":case"jump2":case"jump3":this.createJump();break;case"shake":if(this.isBlinking)return;this.blinkTimer&&clearTimeout(this.blinkTimer),this.createShake()}}createWink(){if(this.isPlayingClickAnim)return;this.isPlayingClickAnim=!0;let e=new p({onComplete:()=>{this.isPlayingClickAnim=!1;let e=1e3*(1+3*Math.random());this.blinkTimer=setTimeout(()=>{this.createBlinkEyes()},e)},easing:"easeOutCubic"}),t=c.pos.current.x>0,i=t?this.eyesMeshes.left:this.eyesMeshes.right,s=i?i.scale:new a.Pq0(1,1,1),n=t?-.4:.4,o=[this.animationGroup.rotation],r=[this.animationGroup.scale],l=i?i.material.userData.uniforms:null;e.to(s,100,{y:.1},250).to(s,200,{y:1},650).to(l.uWink,100,{value:1},250).to(l.uWink,100,{value:0},650),e.to(r,200,{x:1.03,y:.97},0).to(r,400,{x:1,y:1},200).to(r,200,{x:1.02,y:.98},600).to(r,400,{x:1,y:1},800).to(o,250,{z:-(.2*n)},0).to(o,400,{z:n},250).to(o,600,{z:0},500).start()}createJump(){if(this.isPlayingClickAnim)return;this.isPlayingClickAnim=!0,"jump1"!==this.clickAction&&this.createRotating();let e=new p({onComplete:()=>{"jump1"===this.clickAction&&(this.isPlayingClickAnim=!1)},easing:"easeOutCubic"}),t=this.animationGroup.scale,i=this.animationGroup.position,s=this.animationGroup.rotation;e.to(t,200,{y:.95,x:1.05},0).to(t,100,{y:1.05,x:.95}).to(t,200,{y:1,x:1}).to(t,200,{y:1.03,x:.97}).to(t,200,{y:.97,x:1.03}).to(t,300,{y:1,x:1}).to(s,200,{x:.2},0).to(s,500,{x:-.1},200).to(s,300,{x:0},700).to(i,200,{y:-.2},0).to(i,300,{y:1.5},200).to(i,300,{y:-.2,easing:"easeInQuad"},500).to(i,200,{y:0},800);let n=[this.goggleGroup.position];switch(this.clickAction){case"jump2":case"jump3":e.to(n,400,{y:.6},300).to(n,400,{y:0},700).start();break;default:e.start()}}createRotating(){let e={anim_rotating:this.goggleGroup.userData.rotateX.anim_rotating},t=new p({onComplete:()=>{this.isPlayingClickAnim=!1},onUpdate:()=>{this.goggleGroup.userData.rotateX.anim_rotating=e.anim_rotating},easing:"easeOutCubic"}),i=0,s=[],n=[],o=0,a=100;for(let e=0;e<4;e++){let t=Math.random(),i=.1+.19999999999999998*t,r=150+50*t,l=.05+.05*t;3===e&&(l=0),e%2==0&&(i*=-1,l*=-1),s[e]={offset:i,duration:r,delay:o},n[e]={offset:l,duration:r,delay:a},o+=r,a+=r}let r=[this.animationGroup.rotation];for(let e of("jump3"===this.clickAction&&(i=2*Math.PI,t.to(r,200,{z:.1},0).to(r,200,{z:0},200).to(r,500,{y:Math.PI,easing:"easeInCubic"},0).to(r,700,{y:i,easing:"easeOutCubic"},500).to(r,400,{z:-.1},600).to(r,300,{z:0},1e3)),s))t.to(r,e.duration,{y:i+e.offset},e.delay+1300);for(let e of(t.to(r,300,{y:i,onComplete:()=>{this.animationGroup.rotation.y=0}}),n))t.to(r,e.duration,{z:e.offset,easing:"easeOutQuad"},e.delay+1300);t.to([e],700,{anim_rotating:.35},600).to([e],500,{anim_rotating:0},1500).start()}createShake(){if(this.isPlayingClickAnim)return;this.isPlayingClickAnim=!0;let e=new p({onComplete:()=>{this.isPlayingClickAnim=!1;let e=1e3*(1+3*Math.random());this.blinkTimer=setTimeout(()=>{this.createBlinkEyes()},e)},easing:"easeOutQuad"}),t=this.animationGroup.rotation,i=this.eyesMeshes.left,s=this.eyesMeshes.right,n=[i?i.scale:new a.Pq0(1,1,1),s?s.scale:new a.Pq0(1,1,1)],o=[i.material.userData.uniforms.uWink,s.material.userData.uniforms.uWink],r=[this.animationGroup.scale],l=[];for(let e=0;e<6;e++){let t=Math.random(),i=.1+.1*t,s=150+50*t;e%2==0&&(i*=-1),l[e]={offset:i,duration:s}}for(let i of l)e.to(t,i.duration,{y:i.offset});e.to(t,200,{y:0}).to(t,1e3,{x:-.3},0).to(t,500,{x:0},1e3).to(n,100,{y:.35},0).to(n,250,{y:1},1e3).to(o,100,{value:1.2},0).to(o,100,{value:0},1e3),e.to(r,200,{x:1.02,y:.98},0).to(r,400,{x:1,y:1},200).to(r,200,{x:1.02,y:.98},600).to(r,400,{x:1,y:1},800).start()}resize(){}update(){}constructor({group:e,animationGroup:t,goggleGroup:i,faceGroup:s,eyesMeshes:o}){(0,n._)(this,"animationGroup",void 0),(0,n._)(this,"group",void 0),(0,n._)(this,"goggleGroup",void 0),(0,n._)(this,"faceGroup",void 0),(0,n._)(this,"eyesMeshes",void 0),(0,n._)(this,"isFinishedEntrance",void 0),(0,n._)(this,"isPlayingClickAnim",void 0),(0,n._)(this,"isBlinking",void 0),(0,n._)(this,"clickAction",void 0),this.group=e,this.goggleGroup=i,this.faceGroup=s,this.eyesMeshes=o,this.animationGroup=t,this.isFinishedEntrance=!1,this.isPlayingClickAnim=!1,this.isBlinking=!1,this.init()}},d=`

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
	vec3 objectNormal = vec3( normal );
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
`,f=`

uniform sampler2D map;
uniform sampler2D matcap;
uniform float fresnelBias;
uniform float fresnelScale;
uniform float fresnelPower;
uniform float uFresnelIntensity;
uniform vec3 uFresnelColor;
uniform vec2 uFresnelPosRange;
uniform float uSpecularIntensity;

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
	float light = dot(normal, vec3(1, 1, -1)) * 0.5 + 0.5;
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

	// #if GLASS == 1
	//   fresnel = dot(normal, normalize(vec3(0.0, 2, 1))) * 0.5 + 0.5;
	// 	fresnel = smoothstep(0.6, 0.85, fresnel);
	// #endif
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
	gl_FragColor.rgb += glowIntensity * 0.2 + light * 0.1 * uFresnelIntensity;



	gl_FragColor.rgb = pow(gl_FragColor.rgb, vec3(0.9));

	// debug
	// gl_FragColor.rgb = matcapColor.ggg;
}
`;var v=i(17888);let y=new class Assets{load(e){Promise.all([...this.loadImages(),...this.loadGltfs(),...this.loadDiffuses()]).then(()=>{e&&e()})}loadGltfs(){let e=new v.B;return Object.values(this.gltfs).map(t=>new Promise((i,s)=>{e.load(t.src,e=>{t.scene=e.scene,i(e.scene)},void 0,e=>s(e))}))}loadImages(){let e=new a.Tap;return Object.values(this.images).map(t=>new Promise((i,s)=>{e.load(t.src,e=>{t.texture=e,e.flipY=t.flipY,t.encoding&&(e.encoding=t.encoding),i(e)},void 0,e=>s(e))}))}loadDiffuses(){let e=new a.Tap;return Object.values(this.diffuses).map(t=>new Promise((i,s)=>{e.load(t.src,e=>{t.texture=e,e.flipY=t.flipY,t.encoding&&(e.encoding=t.encoding),i(e)},void 0,e=>s(e))}))}constructor(){(0,n._)(this,"images",void 0),(0,n._)(this,"gltfs",void 0),(0,n._)(this,"diffuses",void 0);let e="/images/modules/site/lab/";this.diffuses={Ears:{src:`${e}copilot/ear.webp`,texture:null,flipY:!1,encoding:a.S2Q,isFace:!0,isGoggle:!1,fresnelIntensity:.6,fresnelColor:new a.Q1f(0xa9fbff),fresnelPosRange:new a.I9Y(2,-1),matcapIntensity:1,specularIntensity:1},Eyes:{src:`${e}copilot/eyes.webp`,texture:null,flipY:!1,encoding:a.S2Q,isFace:!0,isGoggle:!1,fresnelIntensity:0,fresnelColor:new a.Q1f(0xbf70ff),fresnelPosRange:new a.I9Y(2,-1),matcapIntensity:0,specularIntensity:0},Glass:{src:`${e}copilot/glass.webp`,texture:null,flipY:!1,encoding:a.S2Q,isFace:!1,isGoggle:!0,fresnelIntensity:1,fresnelColor:new a.Q1f(5452467),fresnelPosRange:new a.I9Y(0,1),matcapIntensity:.5,specularIntensity:0},Goggle:{src:`${e}copilot/goggle.webp`,texture:null,flipY:!1,encoding:a.S2Q,isFace:!1,isGoggle:!0,fresnelIntensity:.5,fresnelColor:new a.Q1f(9559807),fresnelPosRange:new a.I9Y(0,1),matcapIntensity:2,specularIntensity:0},Head:{src:`${e}copilot/head.webp`,texture:null,flipY:!1,encoding:a.S2Q,isFace:!0,isGoggle:!1,fresnelIntensity:.6,fresnelColor:new a.Q1f(0xa9fbff),fresnelPosRange:new a.I9Y(2,-2),matcapIntensity:1,specularIntensity:1},Screen:{src:`${e}copilot/screen.webp`,texture:null,flipY:!1,encoding:a.S2Q,isFace:!0,isGoggle:!1,fresnelIntensity:1,fresnelColor:new a.Q1f(1875),fresnelPosRange:new a.I9Y(2,-1),matcapIntensity:0,specularIntensity:1},Vents:{src:`${e}copilot/vento.webp`,texture:null,flipY:!1,encoding:a.S2Q,isFace:!0,isGoggle:!1,fresnelIntensity:0,fresnelColor:new a.Q1f(0xbf70ff),fresnelPosRange:new a.I9Y(2,-1),matcapIntensity:1,specularIntensity:1}},this.images={matcap:{src:`${e}matcap.png`,texture:null,flipY:!0}},this.gltfs={head:{src:`${e}copilot/copilot_head.glb`,scene:null}}}},w=class CopilotHead{init(){this.addMeshes(),this.createAnimations()}addMeshes(){let e=[];if(y.gltfs.head.scene){for(let[t,i]of Object.entries(y.diffuses))if(i.texture){let s=y.gltfs.head.scene.getObjectByName(t);if(s)switch(t){case"Eyes":case"Ears":case"Goggle":case"Glass":{let n=this.createMaterial(i,t),o=this.createMaterial(i,t),r=new a.eaF(s.geometry.clone(),n),l=new a.eaF(s.geometry.clone(),o);r.name=`${t}_left`,l.name=`${t}_right`,l.geometry.scale(-1,1,1),"Eyes"===t&&(r.position.copy(s.position),l.position.copy(s.position),l.position.x*=-1,this.eyesMeshes.left=r,this.eyesMeshes.right=l),e.push({mesh:r,isGoggle:i.isGoggle,isFace:i.isFace}),e.push({mesh:l,isGoggle:i.isGoggle,isFace:i.isFace}),i.isGoggle&&(this.goggleGroup.add(r),this.goggleGroup.add(l)),i.isFace&&(this.faceGroup.add(r),this.faceGroup.add(l));break}default:{let n=this.createMaterial(i,t),o=new a.eaF(s.geometry.clone(),n);o.name=t,e.push({mesh:o,isGoggle:i.isGoggle,isFace:i.isFace}),i.isGoggle&&this.goggleGroup.add(o),i.isFace&&this.faceGroup.add(o)}}}}}createMaterial(e,t){let i={uWink:{value:0}},s=new a.BKk({vertexShader:d,fragmentShader:f,uniforms:{...this.uniforms,map:{value:e.texture},matcap:{value:y.images.matcap.texture},uFresnelIntensity:{value:e.fresnelIntensity},uIsEye:{value:"Eyes"===t},uFresnelColor:{value:e.fresnelColor},uFresnelPosRange:{value:e.fresnelPosRange},uSpecularIntensity:{value:e.specularIntensity},...i},transparent:!0,side:a.$EB,defines:{GLASS:+("Glass"===t)}});return s.userData.uniforms=i,s}createAnimations(){this.animations=new m({group:this.group,animationGroup:this.animationGroup,goggleGroup:this.goggleGroup,faceGroup:this.faceGroup,eyesMeshes:this.eyesMeshes}),c.addMousemoveFunc(this.raycast.bind(this)),document.body.addEventListener("click",()=>{this.isRaycastHit&&this.animations.createClickAnimation()})}raycast(){this.raycaster.setFromCamera(c.pos.target,r.camera),this.raycaster.intersectObject(this.group).length>0?this.isRaycastHit=!0:this.isRaycastHit=!1}update(){this.breathing.rotation=.05*Math.sin(2*r.time),this.breathing.position=.08*Math.sin((r.time+.25)*2);let e=c.pos.target.length();this.mouseIntensity.target=o(3,1.3,e),this.mouseIntensity.current+=(this.mouseIntensity.target-this.mouseIntensity.current)*r.getEase(6),this.lookatTarget.set(.5*c.pos.current.x,.5*c.pos.current.y,1),this.lookatTarget.lerp(this.lookatTarget_default,1-this.mouseIntensity.current),this.lookatTarget.y+=this.breathing.rotation,this.orientationGroup.lookAt(this.lookatTarget),this.orientationGroup.position.y=this.breathing.position;let t=o(0,.5,c.pos.current2.y);for(let e in t=Math.min(t=0+(t-0)*this.mouseIntensity.current+(this.breathing.rotation+1)*1.2,1),this.goggleGroup.userData.rotateX.orientation=.1+-.18*t,this.goggleGroup.rotation.x=0,this.goggleGroup.userData.rotateX){let t=this.goggleGroup.userData.rotateX[e];this.goggleGroup.rotation.x+=t}}constructor(){(0,n._)(this,"group",void 0),(0,n._)(this,"orientationGroup",void 0),(0,n._)(this,"animationGroup",void 0),(0,n._)(this,"goggleGroup",void 0),(0,n._)(this,"faceGroup",void 0),(0,n._)(this,"eyesMeshes",void 0),(0,n._)(this,"breathing",void 0),(0,n._)(this,"lookatTarget",void 0),(0,n._)(this,"lookatTarget_default",void 0),(0,n._)(this,"raycaster",void 0),(0,n._)(this,"isRaycastHit",void 0),(0,n._)(this,"mouseIntensity",void 0),(0,n._)(this,"uniforms",void 0),this.group=new a.YJl,this.group.visible=!1,this.group.scale.set(.01,.01,.01),this.orientationGroup=new a.YJl,this.animationGroup=new a.YJl,this.group.add(this.orientationGroup),this.orientationGroup.add(this.animationGroup),this.goggleGroup=new a.YJl,this.faceGroup=new a.YJl,this.animationGroup.add(this.goggleGroup),this.animationGroup.add(this.faceGroup),this.eyesMeshes={left:null,right:null},this.breathing={rotation:0,position:0},this.goggleGroup.userData.rotateX={orientation:0,anim_rotating:0},this.lookatTarget=new a.Pq0,this.lookatTarget_default=new a.Pq0(-.4,-.2,1),this.raycaster=new a.tBo,this.isRaycastHit=!1,this.mouseIntensity={target:0,current:0},this.uniforms={fresnelBias:{value:0},fresnelScale:{value:2},fresnelPower:{value:1}}}};var x=i(55368),b=i(61430),k=i(96540),_=i(14440);function I(){let e=(0,k.useRef)(null),t=(0,k.useRef)(!1);return(0,k.useEffect)(()=>{if(!(0,_.ZN)())return;let i=e.current;if(!i)return;let s=i.querySelector("canvas");if(!s)return;r.init(i,s),l.init(),c.init();let n=new w;t.current||y.load(()=>{n.init(),t.current=!0}),r.scene.add(n.group);let o=null,a=null,u=()=>{o&&(window.cancelAnimationFrame(o),o=null),o=window.requestAnimationFrame(()=>{r.resize()})},h=()=>{let e=()=>{r.update(),c.update(),n.update(),r.renderer.render(r.scene,r.camera),a=window.requestAnimationFrame(e)};e(),window.addEventListener("resize",u),window.addEventListener("scroll",u)},g=()=>{a&&(window.cancelAnimationFrame(a),a=null),window.removeEventListener("resize",u),window.removeEventListener("scroll",u)},p=new IntersectionObserver(e=>{for(let t of e)t.isIntersecting?h():g()},{threshold:.1});return e.current&&p.observe(e.current),()=>{t.current=!0}},[]),(0,s.jsx)(x.Box,{className:"lp-Hero-head hide-reduced-motion",children:(0,s.jsx)("div",{className:"lp-Hero-headSize",children:(0,s.jsx)("div",{className:"lp-Hero-headBlink",ref:e,children:(0,s.jsx)("canvas",{...(0,b.P)({action:"copilot_head",tag:"canvas",context:"hero",location:"hero"})})})})})}try{I.displayName||(I.displayName="CopilotHeadWebGL")}catch{}}}]);
//# sourceMappingURL=packages_landing-pages_routes_features_copilot__components_CopilotHeadWebGL_CopilotHeadWebGL_tsx-fc1386f86f7e.js.map
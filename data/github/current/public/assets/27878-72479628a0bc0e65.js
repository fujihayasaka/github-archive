performance.mark("js-parse-end:27878-72479628a0bc0e65.js");
"use strict";(globalThis.rspackChunk_github_ui_github_ui=globalThis.rspackChunk_github_ui_github_ui||[]).push([[27878],{595422(e,t,i){var o=i(571354),s=i.n(o),n=i(576314),r=i.n(n)()(s());r.push([e.id,`/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

.monaco-keybinding {
	display: flex;
	align-items: center;
	line-height: 10px;
}

.monaco-keybinding > .monaco-keybinding-key {
	display: inline-block;
	border-style: solid;
	border-width: 1px;
	border-radius: 3px;
	vertical-align: middle;
	font-size: 11px;
	padding: 3px 5px;
	margin: 0 2px;
}

.monaco-keybinding > .monaco-keybinding-key:first-child {
	margin-left: 0;
}

.monaco-keybinding > .monaco-keybinding-key:last-child {
	margin-right: 0;
}

.monaco-keybinding > .monaco-keybinding-key-separator {
	display: inline-block;
}

.monaco-keybinding > .monaco-keybinding-key-chord-separator {
	width: 6px;
}
`,"",{version:3,sources:["webpack://./node_modules/monaco-editor/esm/vs/base/browser/ui/keybindingLabel/keybindingLabel.css"],names:[],mappings:"AAAA;;;+FAG+F;;AAE/F;CACC,aAAa;CACb,mBAAmB;CACnB,iBAAiB;AAClB;;AAEA;CACC,qBAAqB;CACrB,mBAAmB;CACnB,iBAAiB;CACjB,kBAAkB;CAClB,sBAAsB;CACtB,eAAe;CACf,gBAAgB;CAChB,aAAa;AACd;;AAEA;CACC,cAAc;AACf;;AAEA;CACC,eAAe;AAChB;;AAEA;CACC,qBAAqB;AACtB;;AAEA;CACC,UAAU;AACX",sourcesContent:["/*---------------------------------------------------------------------------------------------\n *  Copyright (c) Microsoft Corporation. All rights reserved.\n *  Licensed under the MIT License. See License.txt in the project root for license information.\n *--------------------------------------------------------------------------------------------*/\n\n.monaco-keybinding {\n	display: flex;\n	align-items: center;\n	line-height: 10px;\n}\n\n.monaco-keybinding > .monaco-keybinding-key {\n	display: inline-block;\n	border-style: solid;\n	border-width: 1px;\n	border-radius: 3px;\n	vertical-align: middle;\n	font-size: 11px;\n	padding: 3px 5px;\n	margin: 0 2px;\n}\n\n.monaco-keybinding > .monaco-keybinding-key:first-child {\n	margin-left: 0;\n}\n\n.monaco-keybinding > .monaco-keybinding-key:last-child {\n	margin-right: 0;\n}\n\n.monaco-keybinding > .monaco-keybinding-key-separator {\n	display: inline-block;\n}\n\n.monaco-keybinding > .monaco-keybinding-key-chord-separator {\n	width: 6px;\n}\n"],sourceRoot:""}]),i.d(t,{},{A:r})},767340(e,t,i){var o=i(571354),s=i.n(o),n=i(576314),r=i.n(n)()(s());r.push([e.id,`/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

.monaco-list {
	position: relative;
	height: 100%;
	width: 100%;
	white-space: nowrap;
}

.monaco-list.mouse-support {
	user-select: none;
	-webkit-user-select: none;
}

.monaco-list > .monaco-scrollable-element {
	height: 100%;
}

.monaco-list-rows {
	position: relative;
	width: 100%;
	height: 100%;
}

.monaco-list.horizontal-scrolling .monaco-list-rows {
	width: auto;
	min-width: 100%;
}

.monaco-list-row {
	position: absolute;
	box-sizing: border-box;
	overflow: hidden;
	width: 100%;
}

.monaco-list.mouse-support .monaco-list-row {
	cursor: pointer;
	touch-action: none;
}

/* Make sure the scrollbar renders above overlays (sticky scroll) */
.monaco-list .monaco-scrollable-element > .scrollbar.vertical,
.monaco-pane-view > .monaco-split-view2.vertical > .monaco-scrollable-element > .scrollbar.vertical {
	z-index: 14;
}

/* for OS X ballistic scrolling */
.monaco-list-row.scrolling {
	display: none !important;
}

/* Focus */
.monaco-list.element-focused,
.monaco-list.selection-single,
.monaco-list.selection-multiple {
	outline: 0 !important;
}

/* Dnd */
.monaco-drag-image {
	display: inline-block;
	padding: 1px 7px;
	border-radius: 10px;
	font-size: 12px;
	position: absolute;
	z-index: 1000;
}

/* Filter */

.monaco-list-type-filter-message {
	position: absolute;
	box-sizing: border-box;
	width: 100%;
	height: 100%;
	top: 0;
	left: 0;
	padding: 40px 1em 1em 1em;
	text-align: center;
	white-space: normal;
	opacity: 0.7;
	pointer-events: none;
}

.monaco-list-type-filter-message:empty {
	display: none;
}
`,"",{version:3,sources:["webpack://./node_modules/monaco-editor/esm/vs/base/browser/ui/list/list.css"],names:[],mappings:"AAAA;;;+FAG+F;;AAE/F;CACC,kBAAkB;CAClB,YAAY;CACZ,WAAW;CACX,mBAAmB;AACpB;;AAEA;CACC,iBAAiB;CACjB,yBAAyB;AAC1B;;AAEA;CACC,YAAY;AACb;;AAEA;CACC,kBAAkB;CAClB,WAAW;CACX,YAAY;AACb;;AAEA;CACC,WAAW;CACX,eAAe;AAChB;;AAEA;CACC,kBAAkB;CAClB,sBAAsB;CACtB,gBAAgB;CAChB,WAAW;AACZ;;AAEA;CACC,eAAe;CACf,kBAAkB;AACnB;;AAEA,mEAAmE;AACnE;;CAEC,WAAW;AACZ;;AAEA,iCAAiC;AACjC;CACC,wBAAwB;AACzB;;AAEA,UAAU;AACV;;;CAGC,qBAAqB;AACtB;;AAEA,QAAQ;AACR;CACC,qBAAqB;CACrB,gBAAgB;CAChB,mBAAmB;CACnB,eAAe;CACf,kBAAkB;CAClB,aAAa;AACd;;AAEA,WAAW;;AAEX;CACC,kBAAkB;CAClB,sBAAsB;CACtB,WAAW;CACX,YAAY;CACZ,MAAM;CACN,OAAO;CACP,yBAAyB;CACzB,kBAAkB;CAClB,mBAAmB;CACnB,YAAY;CACZ,oBAAoB;AACrB;;AAEA;CACC,aAAa;AACd",sourcesContent:["/*---------------------------------------------------------------------------------------------\n *  Copyright (c) Microsoft Corporation. All rights reserved.\n *  Licensed under the MIT License. See License.txt in the project root for license information.\n *--------------------------------------------------------------------------------------------*/\n\n.monaco-list {\n	position: relative;\n	height: 100%;\n	width: 100%;\n	white-space: nowrap;\n}\n\n.monaco-list.mouse-support {\n	user-select: none;\n	-webkit-user-select: none;\n}\n\n.monaco-list > .monaco-scrollable-element {\n	height: 100%;\n}\n\n.monaco-list-rows {\n	position: relative;\n	width: 100%;\n	height: 100%;\n}\n\n.monaco-list.horizontal-scrolling .monaco-list-rows {\n	width: auto;\n	min-width: 100%;\n}\n\n.monaco-list-row {\n	position: absolute;\n	box-sizing: border-box;\n	overflow: hidden;\n	width: 100%;\n}\n\n.monaco-list.mouse-support .monaco-list-row {\n	cursor: pointer;\n	touch-action: none;\n}\n\n/* Make sure the scrollbar renders above overlays (sticky scroll) */\n.monaco-list .monaco-scrollable-element > .scrollbar.vertical,\n.monaco-pane-view > .monaco-split-view2.vertical > .monaco-scrollable-element > .scrollbar.vertical {\n	z-index: 14;\n}\n\n/* for OS X ballistic scrolling */\n.monaco-list-row.scrolling {\n	display: none !important;\n}\n\n/* Focus */\n.monaco-list.element-focused,\n.monaco-list.selection-single,\n.monaco-list.selection-multiple {\n	outline: 0 !important;\n}\n\n/* Dnd */\n.monaco-drag-image {\n	display: inline-block;\n	padding: 1px 7px;\n	border-radius: 10px;\n	font-size: 12px;\n	position: absolute;\n	z-index: 1000;\n}\n\n/* Filter */\n\n.monaco-list-type-filter-message {\n	position: absolute;\n	box-sizing: border-box;\n	width: 100%;\n	height: 100%;\n	top: 0;\n	left: 0;\n	padding: 40px 1em 1em 1em;\n	text-align: center;\n	white-space: normal;\n	opacity: 0.7;\n	pointer-events: none;\n}\n\n.monaco-list-type-filter-message:empty {\n	display: none;\n}\n"],sourceRoot:""}]),i.d(t,{},{A:r})},885043(e,t,i){i.d(t,{x:()=>k,l:()=>x});var o=i(614333),s=i(720396),n=i(165568),r=i(498315),l=i(310998),a=i(771386),d=i(785072),h=i.n(d),c=i(697825),u=i.n(c),m=i(777659),p=i.n(m),g=i(655056),b=i.n(g),v=i(510540),f=i.n(v),w=i(341113),y=i.n(w),A=i(595422),C={};C.styleTagTransform=y(),C.setAttributes=b(),C.insert=p().bind(null,"head"),C.domAPI=u(),C.insertStyleElement=f(),h()(A.A,C),A.A&&A.A.locals&&A.A.locals;var D=i(3765);let S=o.$,x={keybindingLabelBackground:void 0,keybindingLabelForeground:void 0,keybindingLabelBorder:void 0,keybindingLabelBottomBorder:void 0,keybindingLabelShadow:void 0};class k extends l.jG{constructor(e,t,i){super(),this.os=t,this.keyElements=new Set,this.options=i||Object.create(null);const r=this.options.keybindingLabelForeground;this.domNode=o.BC(e,S(".monaco-keybinding")),r&&(this.domNode.style.color=r),this.hover=this._register((0,s.i)().setupUpdatableHover((0,n.nZ)("mouse"),this.domNode,"")),this.didEverRender=!1,e.appendChild(this.domNode)}get element(){return this.domNode}set(e,t){this.didEverRender&&this.keybinding===e&&k.areSame(this.matches,t)||(this.keybinding=e,this.matches=t,this.render())}render(){var e;if(this.clear(),this.keybinding){let t=this.keybinding.getChords();t[0]&&this.renderChord(this.domNode,t[0],this.matches?this.matches.firstPart:null);for(let e=1;e<t.length;e++)o.BC(this.domNode,S("span.monaco-keybinding-key-chord-separator",void 0," ")),this.renderChord(this.domNode,t[e],this.matches?this.matches.chordPart:null);let i=null!=(e=this.options.disableTitle)&&e?void 0:this.keybinding.getAriaLabel()||void 0;this.hover.update(i),this.domNode.setAttribute("aria-label",i||"")}else this.options&&this.options.renderUnboundKeybindings&&this.renderUnbound(this.domNode);this.didEverRender=!0}clear(){o.w_(this.domNode),this.keyElements.clear()}renderChord(e,t,i){let o=r.Of.modifierLabels[this.os];t.ctrlKey&&this.renderKey(e,o.ctrlKey,!!(null==i?void 0:i.ctrlKey),o.separator),t.shiftKey&&this.renderKey(e,o.shiftKey,!!(null==i?void 0:i.shiftKey),o.separator),t.altKey&&this.renderKey(e,o.altKey,!!(null==i?void 0:i.altKey),o.separator),t.metaKey&&this.renderKey(e,o.metaKey,!!(null==i?void 0:i.metaKey),o.separator);let s=t.keyLabel;s&&this.renderKey(e,s,!!(null==i?void 0:i.keyCode),"")}renderKey(e,t,i,s){o.BC(e,this.createKeyElement(t,i?".highlight":"")),s&&o.BC(e,S("span.monaco-keybinding-key-separator",void 0,s))}renderUnbound(e){o.BC(e,this.createKeyElement((0,D.kg)("unbound","Unbound")))}createKeyElement(e,t=""){let i=S("span.monaco-keybinding-key"+t,void 0,e);return this.keyElements.add(i),this.options.keybindingLabelBackground&&(i.style.backgroundColor=this.options.keybindingLabelBackground),this.options.keybindingLabelBorder&&(i.style.borderColor=this.options.keybindingLabelBorder),this.options.keybindingLabelBottomBorder&&(i.style.borderBottomColor=this.options.keybindingLabelBottomBorder),this.options.keybindingLabelShadow&&(i.style.boxShadow=`inset 0 -1px 0 ${this.options.keybindingLabelShadow}`),i}static areSame(e,t){return e===t||!e&&!t||!!e&&!!t&&(0,a.aI)(e.firstPart,t.firstPart)&&(0,a.aI)(e.chordPart,t.chordPart)}}},933697(e,t,i){var o=i(413338),s=i(978903),n=i(2106),r=i(310998);i(767119);var l=i(276006);class a{get templateId(){return this.renderer.templateId}constructor(e,t){this.renderer=e,this.modelProvider=t}renderTemplate(e){return{data:this.renderer.renderTemplate(e),disposable:r.jG.None}}renderElement(e,t,i,o){var n;if(null==(n=i.disposable)||n.dispose(),!i.data)return;let r=this.modelProvider();if(r.isResolved(e))return this.renderer.renderElement(r.get(e),e,i.data,o);let l=new s.Qi,a=r.resolve(e,l.token);i.disposable={dispose:()=>l.cancel()},this.renderer.renderPlaceholder(e,i.data),a.then(t=>this.renderer.renderElement(t,e,i.data,o))}disposeTemplate(e){e.disposable&&(e.disposable.dispose(),e.disposable=void 0),e.data&&(this.renderer.disposeTemplate(e.data),e.data=void 0)}}class d{constructor(e,t){this.modelProvider=e,this.accessibilityProvider=t}getWidgetAriaLabel(){return this.accessibilityProvider.getWidgetAriaLabel()}getAriaLabel(e){let t=this.modelProvider();return t.isResolved(e)?this.accessibilityProvider.getAriaLabel(t.get(e)):null}}class h{constructor(e,t,i,o,s={}){const n=()=>this.model,r=o.map(e=>new a(e,n));this.list=new l.B8(e,t,i,r,function(e,t){return{...t,accessibilityProvider:t.accessibilityProvider&&new d(e,t.accessibilityProvider)}}(n,s))}updateOptions(e){this.list.updateOptions(e)}getHTMLElement(){return this.list.getHTMLElement()}get onDidFocus(){return this.list.onDidFocus}get widget(){return this.list}get onDidDispose(){return this.list.onDidDispose}get onMouseDblClick(){return n.Jh.map(this.list.onMouseDblClick,({element:e,index:t,browserEvent:i})=>({element:void 0===e?void 0:this._model.get(e),index:t,browserEvent:i}))}get onPointer(){return n.Jh.map(this.list.onPointer,({element:e,index:t,browserEvent:i})=>({element:void 0===e?void 0:this._model.get(e),index:t,browserEvent:i}))}get onDidChangeSelection(){return n.Jh.map(this.list.onDidChangeSelection,({elements:e,indexes:t,browserEvent:i})=>({elements:e.map(e=>this._model.get(e)),indexes:t,browserEvent:i}))}get model(){return this._model}set model(e){this._model=e,this.list.splice(0,this.list.length,(0,o.y1)(e.length))}getFocus(){return this.list.getFocus()}getSelection(){return this.list.getSelection()}getSelectedElements(){return this.getSelection().map(e=>this.model.get(e))}style(e){this.list.style(e)}dispose(){this.list.dispose()}}i.d(t,{Y:()=>h})},107300(e,t,i){i.d(t,{ur:()=>S,uO:()=>B});var o=i(939587),s=i(614333),n=i(934061),r=i(830474),l=i(82208),a=i(413338),d=i(565958),h=i(988846),c=i(2106),u=i(310998),m=i(382199),p=i(994513);function g(e,t){let i=[];for(let o of t){if(e.start>=o.range.end)continue;if(e.end<o.range.start)break;let t=m.Q.intersect(e,o.range);m.Q.isEmpty(t)||i.push({range:t,size:o.size})}return i}function b({start:e,end:t},i){return{start:e+i,end:t+i}}class v{get paddingTop(){return this._paddingTop}set paddingTop(e){this._size=this._size+e-this._paddingTop,this._paddingTop=e}constructor(e){this.groups=[],this._size=0,this._paddingTop=0,this._paddingTop=null!=e?e:0,this._size=this._paddingTop}splice(e,t,i=[]){let o=i.length-t,s=g({start:0,end:e},this.groups),n=g({start:e+t,end:1/0},this.groups).map(e=>({range:b(e.range,o),size:e.size})),r=i.map((t,i)=>({range:{start:e+i,end:e+i+1},size:t.size}));this.groups=function(...e){return function(e){let t=[],i=null;for(let o of e){let e=o.range.start,s=o.range.end,n=o.size;if(i&&n===i.size){i.range.end=s;continue}i={range:{start:e,end:s},size:n},t.push(i)}return t}(e.reduce((e,t)=>e.concat(t),[]))}(s,r,n),this._size=this._paddingTop+this.groups.reduce((e,t)=>e+t.size*(t.range.end-t.range.start),0)}get count(){let e=this.groups.length;return e?this.groups[e-1].range.end:0}get size(){return this._size}indexAt(e){if(e<0)return -1;if(e<this._paddingTop)return 0;let t=0,i=this._paddingTop;for(let o of this.groups){let s=o.range.end-o.range.start,n=i+s*o.size;if(e<n)return t+Math.floor((e-i)/o.size);t+=s,i=n}return t}indexAfter(e){return Math.min(this.indexAt(e)+1,this.count)}positionAt(e){if(e<0)return -1;let t=0,i=0;for(let o of this.groups){let s=o.range.end-o.range.start,n=i+s;if(e<n)return this._paddingTop+t+(e-i)*o.size;t+=s*o.size,i=n}return -1}}class f{constructor(e){this.renderers=e,this.cache=new Map,this.transactionNodesPendingRemoval=new Set,this.inTransaction=!1}alloc(e){let t=this.getTemplateCache(e).pop(),i=!1;if(t)(i=this.transactionNodesPendingRemoval.has(t.domNode))&&this.transactionNodesPendingRemoval.delete(t.domNode);else{let i=(0,s.$)(".monaco-list-row"),o=this.getRenderer(e).renderTemplate(i);t={domNode:i,templateId:e,templateData:o}}return{row:t,isReusingConnectedDomNode:i}}release(e){e&&this.releaseRow(e)}transact(e){if(this.inTransaction)throw Error("Already in transaction");this.inTransaction=!0;try{e()}finally{for(let e of this.transactionNodesPendingRemoval)this.doRemoveNode(e);this.transactionNodesPendingRemoval.clear(),this.inTransaction=!1}}releaseRow(e){let{domNode:t,templateId:i}=e;t&&(this.inTransaction?this.transactionNodesPendingRemoval.add(t):this.doRemoveNode(t)),this.getTemplateCache(i).push(e)}doRemoveNode(e){var t;e.classList.remove("scrolling");try{null==(t=e.parentElement)||t.removeChild(e)}catch(e){}}getTemplateCache(e){let t=this.cache.get(e);return t||(t=[],this.cache.set(e,t)),t}dispose(){this.cache.forEach((e,t)=>{for(let i of e)this.getRenderer(t).disposeTemplate(i.templateData),i.templateData=null}),this.cache.clear(),this.transactionNodesPendingRemoval.clear()}getRenderer(e){let t=this.renderers.get(e);if(!t)throw Error(`No renderer found for ${e}`);return t}}var w=i(494327),y=i(562992),A=function(e,t,i,o){var s,n=arguments.length,r=n<3?t:null===o?o=Object.getOwnPropertyDescriptor(t,i):o;if("object"==typeof Reflect&&"function"==typeof Reflect.decorate)r=Reflect.decorate(e,t,i,o);else for(var l=e.length-1;l>=0;l--)(s=e[l])&&(r=(n<3?s(r):n>3?s(t,i,r):s(t,i))||r);return n>3&&r&&Object.defineProperty(t,i,r),r};let C={CurrentDragAndDropData:void 0},D={useShadows:!0,verticalScrollMode:1,setRowLineHeight:!0,setRowHeight:!0,supportDynamicHeights:!1,dnd:{getDragElements:e=>[e],getDragURI:()=>null,onDragStart(){},onDragOver:()=>!1,drop(){},dispose(){}},horizontalScrolling:!1,transformOptimization:!0,alwaysConsumeMouseWheel:!0};class S{constructor(e){this.elements=e}update(){}getData(){return this.elements}}class x{constructor(e){this.elements=e}update(){}getData(){return this.elements}}class k{constructor(){this.types=[],this.files=[]}update(e){if(e.types&&this.types.splice(0,this.types.length,...e.types),e.files){this.files.splice(0,this.files.length);for(let t=0;t<e.files.length;t++){let i=e.files.item(t);i&&(i.size||i.type)&&this.files.push(i)}}}getData(){return{types:this.types,files:this.files}}}class E{constructor(e){(null==e?void 0:e.getSetSize)?this.getSetSize=e.getSetSize.bind(e):this.getSetSize=(e,t,i)=>i,(null==e?void 0:e.getPosInSet)?this.getPosInSet=e.getPosInSet.bind(e):this.getPosInSet=(e,t)=>t+1,(null==e?void 0:e.getRole)?this.getRole=e.getRole.bind(e):this.getRole=e=>"listitem",(null==e?void 0:e.isChecked)?this.isChecked=e.isChecked.bind(e):this.isChecked=e=>void 0}}class B{get contentHeight(){return this.rangeMap.size}get onDidScroll(){return this.scrollableElement.onScroll}get scrollableElementDomNode(){return this.scrollableElement.getDomNode()}get horizontalScrolling(){return this._horizontalScrolling}set horizontalScrolling(e){if(e!==this._horizontalScrolling){if(e&&this.supportDynamicHeights)throw Error("Horizontal scrolling and dynamic heights not supported simultaneously");if(this._horizontalScrolling=e,this.domNode.classList.toggle("horizontal-scrolling",this._horizontalScrolling),this._horizontalScrolling){for(let e of this.items)this.measureItemWidth(e);this.updateScrollWidth(),this.scrollableElement.setScrollDimensions({width:(0,s.y6)(this.domNode)}),this.rowsContainer.style.width=`${Math.max(this.scrollWidth||0,this.renderWidth)}px`}else this.scrollableElementWidthDelayer.cancel(),this.scrollableElement.setScrollDimensions({width:this.renderWidth,scrollWidth:this.renderWidth}),this.rowsContainer.style.width=""}}constructor(e,t,i,o=D){var n,a,h,m,g,b,v,w,y,A,C,S,x;if(this.virtualDelegate=t,this.domId=`list_id_${++B.InstanceCount}`,this.renderers=new Map,this.renderWidth=0,this._scrollHeight=0,this.scrollableElementUpdateDisposable=null,this.scrollableElementWidthDelayer=new d.ve(50),this.splicing=!1,this.dragOverAnimationStopDisposable=u.jG.None,this.dragOverMouseY=0,this.canDrop=!1,this.currentDragFeedbackDisposable=u.jG.None,this.onDragLeaveTimeout=u.jG.None,this.disposables=new u.Cm,this._onDidChangeContentHeight=new c.vl,this._onDidChangeContentWidth=new c.vl,this.onDidChangeContentHeight=c.Jh.latch(this._onDidChangeContentHeight.event,void 0,this.disposables),this._horizontalScrolling=!1,o.horizontalScrolling&&o.supportDynamicHeights)throw Error("Horizontal scrolling and dynamic heights not supported simultaneously");for(const e of(this.items=[],this.itemId=0,this.rangeMap=this.createRangeMap(null!=(n=o.paddingTop)?n:0),i))this.renderers.set(e.templateId,e);this.cache=this.disposables.add(new f(this.renderers)),this.lastRenderTop=0,this.lastRenderHeight=0,this.domNode=document.createElement("div"),this.domNode.className="monaco-list",this.domNode.classList.add(this.domId),this.domNode.tabIndex=0,this.domNode.classList.toggle("mouse-support","boolean"!=typeof o.mouseSupport||o.mouseSupport),this._horizontalScrolling=null!=(a=o.horizontalScrolling)?a:D.horizontalScrolling,this.domNode.classList.toggle("horizontal-scrolling",this._horizontalScrolling),this.paddingBottom=void 0===o.paddingBottom?0:o.paddingBottom,this.accessibilityProvider=new E(o.accessibilityProvider),this.rowsContainer=document.createElement("div"),this.rowsContainer.className="monaco-list-rows",(null!=(h=o.transformOptimization)?h:D.transformOptimization)&&(this.rowsContainer.style.transform="translate3d(0px, 0px, 0px)",this.rowsContainer.style.overflow="hidden",this.rowsContainer.style.contain="strict"),this.disposables.add(r.q.addTarget(this.rowsContainer)),this.scrollable=this.disposables.add(new p.yE({forceIntegerValues:!0,smoothScrollDuration:null!=(m=o.smoothScrolling)&&m?125:0,scheduleAtNextAnimationFrame:e=>(0,s.PG)((0,s.zk)(this.domNode),e)})),this.scrollableElement=this.disposables.add(new l.oO(this.rowsContainer,{alwaysConsumeMouseWheel:null!=(g=o.alwaysConsumeMouseWheel)?g:D.alwaysConsumeMouseWheel,horizontal:1,vertical:null!=(b=o.verticalScrollMode)?b:D.verticalScrollMode,useShadows:null!=(v=o.useShadows)?v:D.useShadows,mouseWheelScrollSensitivity:o.mouseWheelScrollSensitivity,fastScrollSensitivity:o.fastScrollSensitivity,scrollByPage:o.scrollByPage},this.scrollable)),this.domNode.appendChild(this.scrollableElement.getDomNode()),e.appendChild(this.domNode),this.scrollableElement.onScroll(this.onScroll,this,this.disposables),this.disposables.add((0,s.ko)(this.rowsContainer,r.B.Change,e=>this.onTouchChange(e))),this.disposables.add((0,s.ko)(this.scrollableElement.getDomNode(),"scroll",e=>e.target.scrollTop=0)),this.disposables.add((0,s.ko)(this.domNode,"dragover",e=>this.onDragOver(this.toDragEvent(e)))),this.disposables.add((0,s.ko)(this.domNode,"drop",e=>this.onDrop(this.toDragEvent(e)))),this.disposables.add((0,s.ko)(this.domNode,"dragleave",e=>this.onDragLeave(this.toDragEvent(e)))),this.disposables.add((0,s.ko)(this.domNode,"dragend",e=>this.onDragEnd(e))),this.setRowLineHeight=null!=(w=o.setRowLineHeight)?w:D.setRowLineHeight,this.setRowHeight=null!=(y=o.setRowHeight)?y:D.setRowHeight,this.supportDynamicHeights=null!=(A=o.supportDynamicHeights)?A:D.supportDynamicHeights,this.dnd=null!=(C=o.dnd)?C:this.disposables.add(D.dnd),this.layout(null==(S=o.initialSize)?void 0:S.height,null==(x=o.initialSize)?void 0:x.width)}updateOptions(e){let t;if(void 0!==e.paddingBottom&&(this.paddingBottom=e.paddingBottom,this.scrollableElement.setScrollDimensions({scrollHeight:this.scrollHeight})),void 0!==e.smoothScrolling&&this.scrollable.setSmoothScrollDuration(125*!!e.smoothScrolling),void 0!==e.horizontalScrolling&&(this.horizontalScrolling=e.horizontalScrolling),void 0!==e.scrollByPage&&(t={...null!=t?t:{},scrollByPage:e.scrollByPage}),void 0!==e.mouseWheelScrollSensitivity&&(t={...null!=t?t:{},mouseWheelScrollSensitivity:e.mouseWheelScrollSensitivity}),void 0!==e.fastScrollSensitivity&&(t={...null!=t?t:{},fastScrollSensitivity:e.fastScrollSensitivity}),t&&this.scrollableElement.updateOptions(t),void 0!==e.paddingTop&&e.paddingTop!==this.rangeMap.paddingTop){let t=this.getRenderRange(this.lastRenderTop,this.lastRenderHeight),i=e.paddingTop-this.rangeMap.paddingTop;this.rangeMap.paddingTop=e.paddingTop,this.render(t,Math.max(0,this.lastRenderTop+i),this.lastRenderHeight,void 0,void 0,!0),this.setScrollTop(this.lastRenderTop),this.eventuallyUpdateScrollDimensions(),this.supportDynamicHeights&&this._rerender(this.lastRenderTop,this.lastRenderHeight)}}createRangeMap(e){return new v(e)}splice(e,t,i=[]){if(this.splicing)throw Error("Can't run recursive splices.");this.splicing=!0;try{return this._splice(e,t,i)}finally{this.splicing=!1,this._onDidChangeContentHeight.fire(this.contentHeight)}}_splice(e,t,i=[]){let o,s=this.getRenderRange(this.lastRenderTop,this.lastRenderHeight),n=m.Q.intersect(s,{start:e,end:e+t}),r=new Map;for(let e=n.end-1;e>=n.start;e--){let t=this.items[e];if(t.dragStartDisposable.dispose(),t.checkedDisposable.dispose(),t.row){let i=r.get(t.templateId);i||(i=[],r.set(t.templateId,i));let o=this.renderers.get(t.templateId);o&&o.disposeElement&&o.disposeElement(t.element,e,t.row.templateData,t.size),i.unshift(t.row)}t.row=null,t.stale=!0}let l={start:e+t,end:this.items.length},a=m.Q.intersect(l,s),d=m.Q.relativeComplement(l,s),h=i.map(e=>({id:String(this.itemId++),element:e,templateId:this.virtualDelegate.getTemplateId(e),size:this.virtualDelegate.getHeight(e),width:void 0,hasDynamicHeight:!!this.virtualDelegate.hasDynamicHeight&&this.virtualDelegate.hasDynamicHeight(e),lastDynamicHeightWidth:void 0,row:null,uri:void 0,dropTarget:!1,dragStartDisposable:u.jG.None,checkedDisposable:u.jG.None,stale:!1}));0===e&&t>=this.items.length?(this.rangeMap=this.createRangeMap(this.rangeMap.paddingTop),this.rangeMap.splice(0,0,h),o=this.items,this.items=h):(this.rangeMap.splice(e,t,h),o=this.items.splice(e,t,...h));let c=i.length-t,p=this.getRenderRange(this.lastRenderTop,this.lastRenderHeight),g=b(a,c),v=m.Q.intersect(p,g);for(let e=v.start;e<v.end;e++)this.updateItemInDOM(this.items[e],e);for(let e of m.Q.relativeComplement(g,p))for(let t=e.start;t<e.end;t++)this.removeItemFromDOM(t);let f=d.map(e=>b(e,c));for(let t of[{start:e,end:e+i.length},...f].map(e=>m.Q.intersect(p,e)).reverse())for(let e=t.end-1;e>=t.start;e--){let t=this.items[e],i=r.get(t.templateId),o=null==i?void 0:i.pop();this.insertItemInDOM(e,o)}for(let e of r.values())for(let t of e)this.cache.release(t);return this.eventuallyUpdateScrollDimensions(),this.supportDynamicHeights&&this._rerender(this.scrollTop,this.renderHeight),o.map(e=>e.element)}eventuallyUpdateScrollDimensions(){this._scrollHeight=this.contentHeight,this.rowsContainer.style.height=`${this._scrollHeight}px`,this.scrollableElementUpdateDisposable||(this.scrollableElementUpdateDisposable=(0,s.PG)((0,s.zk)(this.domNode),()=>{this.scrollableElement.setScrollDimensions({scrollHeight:this.scrollHeight}),this.updateScrollWidth(),this.scrollableElementUpdateDisposable=null}))}eventuallyUpdateScrollWidth(){this.horizontalScrolling?this.scrollableElementWidthDelayer.trigger(()=>this.updateScrollWidth()):this.scrollableElementWidthDelayer.cancel()}updateScrollWidth(){if(!this.horizontalScrolling)return;let e=0;for(let t of this.items)void 0!==t.width&&(e=Math.max(e,t.width));this.scrollWidth=e,this.scrollableElement.setScrollDimensions({scrollWidth:0===e?0:e+10}),this._onDidChangeContentWidth.fire(this.scrollWidth)}rerender(){if(this.supportDynamicHeights){for(let e of this.items)e.lastDynamicHeightWidth=void 0;this._rerender(this.lastRenderTop,this.lastRenderHeight)}}get length(){return this.items.length}get renderHeight(){return this.scrollableElement.getScrollDimensions().height}get firstVisibleIndex(){return this.getRenderRange(this.lastRenderTop,this.lastRenderHeight).start}element(e){return this.items[e].element}indexOf(e){return this.items.findIndex(t=>t.element===e)}domElement(e){let t=this.items[e].row;return t&&t.domNode}elementHeight(e){return this.items[e].size}elementTop(e){return this.rangeMap.positionAt(e)}indexAt(e){return this.rangeMap.indexAt(e)}indexAfter(e){return this.rangeMap.indexAfter(e)}layout(e,t){let i={height:"number"==typeof e?e:(0,s.H4)(this.domNode)};this.scrollableElementUpdateDisposable&&(this.scrollableElementUpdateDisposable.dispose(),this.scrollableElementUpdateDisposable=null,i.scrollHeight=this.scrollHeight),this.scrollableElement.setScrollDimensions(i),void 0!==t&&(this.renderWidth=t,this.supportDynamicHeights&&this._rerender(this.scrollTop,this.renderHeight)),this.horizontalScrolling&&this.scrollableElement.setScrollDimensions({width:"number"==typeof t?t:(0,s.y6)(this.domNode)})}render(e,t,i,o,s,n=!1){let r=this.getRenderRange(t,i),l=m.Q.relativeComplement(r,e).reverse(),a=m.Q.relativeComplement(e,r);if(n){let t=m.Q.intersect(e,r);for(let e=t.start;e<t.end;e++)this.updateItemInDOM(this.items[e],e)}this.cache.transact(()=>{for(let e of a)for(let t=e.start;t<e.end;t++)this.removeItemFromDOM(t);for(let e of l)for(let t=e.end-1;t>=e.start;t--)this.insertItemInDOM(t)}),void 0!==o&&(this.rowsContainer.style.left=`-${o}px`),this.rowsContainer.style.top=`-${t}px`,this.horizontalScrolling&&void 0!==s&&(this.rowsContainer.style.width=`${Math.max(s,this.renderWidth)}px`),this.lastRenderTop=t,this.lastRenderHeight=i}insertItemInDOM(e,t){var i,o,n;let r=this.items[e];if(!r.row)if(t)r.row=t,r.stale=!0;else{let e=this.cache.alloc(r.templateId);r.row=e.row,r.stale||(r.stale=e.isReusingConnectedDomNode)}let l=this.accessibilityProvider.getRole(r.element)||"listitem";r.row.domNode.setAttribute("role",l);let a=this.accessibilityProvider.isChecked(r.element);if("boolean"==typeof a)r.row.domNode.setAttribute("aria-checked",String(!!a));else if(a){let e=e=>r.row.domNode.setAttribute("aria-checked",String(!!e));e(a.value),r.checkedDisposable=a.onDidChange(()=>e(a.value))}if(r.stale||!r.row.domNode.parentElement){let t=null!=(n=null==(o=null==(i=this.items.at(e+1))?void 0:i.row)?void 0:o.domNode)?n:null;(r.row.domNode.parentElement!==this.rowsContainer||r.row.domNode.nextElementSibling!==t)&&this.rowsContainer.insertBefore(r.row.domNode,t),r.stale=!1}this.updateItemInDOM(r,e);let d=this.renderers.get(r.templateId);if(!d)throw Error(`No renderer found for template id ${r.templateId}`);null==d||d.renderElement(r.element,e,r.row.templateData,r.size);let h=this.dnd.getDragURI(r.element);r.dragStartDisposable.dispose(),r.row.domNode.draggable=!!h,h&&(r.dragStartDisposable=(0,s.ko)(r.row.domNode,"dragstart",e=>this.onDragStart(r.element,h,e))),this.horizontalScrolling&&(this.measureItemWidth(r),this.eventuallyUpdateScrollWidth())}measureItemWidth(e){if(!e.row||!e.row.domNode)return;e.row.domNode.style.width="fit-content",e.width=(0,s.y6)(e.row.domNode);let t=(0,s.zk)(e.row.domNode).getComputedStyle(e.row.domNode);t.paddingLeft&&(e.width+=parseFloat(t.paddingLeft)),t.paddingRight&&(e.width+=parseFloat(t.paddingRight)),e.row.domNode.style.width=""}updateItemInDOM(e,t){e.row.domNode.style.top=`${this.elementTop(t)}px`,this.setRowHeight&&(e.row.domNode.style.height=`${e.size}px`),this.setRowLineHeight&&(e.row.domNode.style.lineHeight=`${e.size}px`),e.row.domNode.setAttribute("data-index",`${t}`),e.row.domNode.setAttribute("data-last-element",t===this.length-1?"true":"false"),e.row.domNode.setAttribute("data-parity",t%2==0?"even":"odd"),e.row.domNode.setAttribute("aria-setsize",String(this.accessibilityProvider.getSetSize(e.element,t,this.length))),e.row.domNode.setAttribute("aria-posinset",String(this.accessibilityProvider.getPosInSet(e.element,t))),e.row.domNode.setAttribute("id",this.getElementDomId(t)),e.row.domNode.classList.toggle("drop-target",e.dropTarget)}removeItemFromDOM(e){let t=this.items[e];if(t.dragStartDisposable.dispose(),t.checkedDisposable.dispose(),t.row){let i=this.renderers.get(t.templateId);i&&i.disposeElement&&i.disposeElement(t.element,e,t.row.templateData,t.size),this.cache.release(t.row),t.row=null}this.horizontalScrolling&&this.eventuallyUpdateScrollWidth()}getScrollTop(){return this.scrollableElement.getScrollPosition().scrollTop}setScrollTop(e,t){this.scrollableElementUpdateDisposable&&(this.scrollableElementUpdateDisposable.dispose(),this.scrollableElementUpdateDisposable=null,this.scrollableElement.setScrollDimensions({scrollHeight:this.scrollHeight})),this.scrollableElement.setScrollPosition({scrollTop:e,reuseAnimation:t})}get scrollTop(){return this.getScrollTop()}set scrollTop(e){this.setScrollTop(e)}get scrollHeight(){return this._scrollHeight+10*!!this.horizontalScrolling+this.paddingBottom}get onMouseClick(){return c.Jh.map(this.disposables.add(new n.f(this.domNode,"click")).event,e=>this.toMouseEvent(e),this.disposables)}get onMouseDblClick(){return c.Jh.map(this.disposables.add(new n.f(this.domNode,"dblclick")).event,e=>this.toMouseEvent(e),this.disposables)}get onMouseMiddleClick(){return c.Jh.filter(c.Jh.map(this.disposables.add(new n.f(this.domNode,"auxclick")).event,e=>this.toMouseEvent(e),this.disposables),e=>1===e.browserEvent.button,this.disposables)}get onMouseDown(){return c.Jh.map(this.disposables.add(new n.f(this.domNode,"mousedown")).event,e=>this.toMouseEvent(e),this.disposables)}get onMouseOver(){return c.Jh.map(this.disposables.add(new n.f(this.domNode,"mouseover")).event,e=>this.toMouseEvent(e),this.disposables)}get onMouseOut(){return c.Jh.map(this.disposables.add(new n.f(this.domNode,"mouseout")).event,e=>this.toMouseEvent(e),this.disposables)}get onContextMenu(){return c.Jh.any(c.Jh.map(this.disposables.add(new n.f(this.domNode,"contextmenu")).event,e=>this.toMouseEvent(e),this.disposables),c.Jh.map(this.disposables.add(new n.f(this.domNode,r.B.Contextmenu)).event,e=>this.toGestureEvent(e),this.disposables))}get onTouchStart(){return c.Jh.map(this.disposables.add(new n.f(this.domNode,"touchstart")).event,e=>this.toTouchEvent(e),this.disposables)}get onTap(){return c.Jh.map(this.disposables.add(new n.f(this.rowsContainer,r.B.Tap)).event,e=>this.toGestureEvent(e),this.disposables)}toMouseEvent(e){let t=this.getItemIndexFromEventTarget(e.target||null),i=void 0===t?void 0:this.items[t];return{browserEvent:e,index:t,element:i&&i.element}}toTouchEvent(e){let t=this.getItemIndexFromEventTarget(e.target||null),i=void 0===t?void 0:this.items[t];return{browserEvent:e,index:t,element:i&&i.element}}toGestureEvent(e){let t=this.getItemIndexFromEventTarget(e.initialTarget||null),i=void 0===t?void 0:this.items[t];return{browserEvent:e,index:t,element:i&&i.element}}toDragEvent(e){let t=this.getItemIndexFromEventTarget(e.target||null),i=void 0===t?void 0:this.items[t],o=i&&i.element,s=this.getTargetSector(e,t);return{browserEvent:e,index:t,element:o,sector:s}}onScroll(e){try{let t=this.getRenderRange(this.lastRenderTop,this.lastRenderHeight);this.render(t,e.scrollTop,e.height,e.scrollLeft,e.scrollWidth),this.supportDynamicHeights&&this._rerender(e.scrollTop,e.height,e.inSmoothScrolling)}catch(t){throw console.error("Got bad scroll event:",e),t}}onTouchChange(e){e.preventDefault(),e.stopPropagation(),this.scrollTop-=e.translationY}onDragStart(e,t,i){var n,r;if(!i.dataTransfer)return;let l=this.dnd.getDragElements(e);if(i.dataTransfer.effectAllowed="copyMove",i.dataTransfer.setData(o.t.TEXT,t),i.dataTransfer.setDragImage){let e;this.dnd.getDragLabel&&(e=this.dnd.getDragLabel(l,i)),void 0===e&&(e=String(l.length));let t=(0,s.$)(".monaco-drag-image");t.textContent=e;let o=(e=>{for(;e&&!e.classList.contains("monaco-workbench");)e=e.parentElement;return e||this.domNode.ownerDocument})(this.domNode);o.appendChild(t),i.dataTransfer.setDragImage(t,-10,-10),setTimeout(()=>o.removeChild(t),0)}this.domNode.classList.add("dragging"),this.currentDragData=new S(l),C.CurrentDragAndDropData=new x(l),null==(r=(n=this.dnd).onDragStart)||r.call(n,this.currentDragData,i)}onDragOver(e){var t,i,o,s;let n;if(e.browserEvent.preventDefault(),this.onDragLeaveTimeout.dispose(),C.CurrentDragAndDropData&&"vscode-ui"===C.CurrentDragAndDropData.getData()||(this.setupDragAndDropScrollTopAnimation(e.browserEvent),!e.browserEvent.dataTransfer))return!1;if(!this.currentDragData)if(C.CurrentDragAndDropData)this.currentDragData=C.CurrentDragAndDropData;else{if(!e.browserEvent.dataTransfer.types)return!1;this.currentDragData=new k}let r=this.dnd.onDragOver(this.currentDragData,e.element,e.index,e.sector,e.browserEvent);if(this.canDrop="boolean"==typeof r?r:r.accept,!this.canDrop)return this.currentDragFeedback=void 0,this.currentDragFeedbackDisposable.dispose(),!1;e.browserEvent.dataTransfer.dropEffect="boolean"!=typeof r&&(null==(t=r.effect)?void 0:t.type)===0?"copy":"move",n="boolean"!=typeof r&&r.feedback?r.feedback:void 0===e.index?[-1]:[e.index],n=-1===(n=(0,a.dM)(n).filter(e=>e>=-1&&e<this.length).sort((e,t)=>e-t))[0]?[-1]:n;let l="boolean"!=typeof r&&r.effect&&r.effect.position?r.effect.position:"drop-target";if(o=this.currentDragFeedback,s=n,(Array.isArray(o)&&Array.isArray(s)?(0,a.aI)(o,s):o===s)&&this.currentDragFeedbackPosition===l)return!0;if(this.currentDragFeedback=n,this.currentDragFeedbackPosition=l,this.currentDragFeedbackDisposable.dispose(),-1===n[0])this.domNode.classList.add(l),this.rowsContainer.classList.add(l),this.currentDragFeedbackDisposable=(0,u.s)(()=>{this.domNode.classList.remove(l),this.rowsContainer.classList.remove(l)});else{if(n.length>1&&"drop-target"!==l)throw Error("Can't use multiple feedbacks with position different than 'over'");for(let e of("drop-target-after"===l&&n[0]<this.length-1&&(n[0]+=1,l="drop-target-before"),n)){let t=this.items[e];t.dropTarget=!0,null==(i=t.row)||i.domNode.classList.add(l)}this.currentDragFeedbackDisposable=(0,u.s)(()=>{var e;for(let t of n){let i=this.items[t];i.dropTarget=!1,null==(e=i.row)||e.domNode.classList.remove(l)}})}return!0}onDragLeave(e){var t,i;this.onDragLeaveTimeout.dispose(),this.onDragLeaveTimeout=(0,d.EQ)(()=>this.clearDragOverFeedback(),100,this.disposables),this.currentDragData&&(null==(i=(t=this.dnd).onDragLeave)||i.call(t,this.currentDragData,e.element,e.index,e.browserEvent))}onDrop(e){if(!this.canDrop)return;let t=this.currentDragData;this.teardownDragAndDropScrollTopAnimation(),this.clearDragOverFeedback(),this.domNode.classList.remove("dragging"),this.currentDragData=void 0,C.CurrentDragAndDropData=void 0,t&&e.browserEvent.dataTransfer&&(e.browserEvent.preventDefault(),t.update(e.browserEvent.dataTransfer),this.dnd.drop(t,e.element,e.index,e.sector,e.browserEvent))}onDragEnd(e){var t,i;this.canDrop=!1,this.teardownDragAndDropScrollTopAnimation(),this.clearDragOverFeedback(),this.domNode.classList.remove("dragging"),this.currentDragData=void 0,C.CurrentDragAndDropData=void 0,null==(i=(t=this.dnd).onDragEnd)||i.call(t,e)}clearDragOverFeedback(){this.currentDragFeedback=void 0,this.currentDragFeedbackPosition=void 0,this.currentDragFeedbackDisposable.dispose(),this.currentDragFeedbackDisposable=u.jG.None}setupDragAndDropScrollTopAnimation(e){if(!this.dragOverAnimationDisposable){let e=(0,s.cL)(this.domNode).top;this.dragOverAnimationDisposable=(0,s.i0)((0,s.zk)(this.domNode),this.animateDragAndDropScrollTop.bind(this,e))}this.dragOverAnimationStopDisposable.dispose(),this.dragOverAnimationStopDisposable=(0,d.EQ)(()=>{this.dragOverAnimationDisposable&&(this.dragOverAnimationDisposable.dispose(),this.dragOverAnimationDisposable=void 0)},1e3,this.disposables),this.dragOverMouseY=e.pageY}animateDragAndDropScrollTop(e){if(void 0===this.dragOverMouseY)return;let t=this.dragOverMouseY-e,i=this.renderHeight-35;t<35?this.scrollTop+=Math.max(-14,Math.floor(.3*(t-35))):t>i&&(this.scrollTop+=Math.min(14,Math.floor(.3*(t-i))))}teardownDragAndDropScrollTopAnimation(){this.dragOverAnimationStopDisposable.dispose(),this.dragOverAnimationDisposable&&(this.dragOverAnimationDisposable.dispose(),this.dragOverAnimationDisposable=void 0)}getTargetSector(e,t){if(void 0===t)return;let i=Math.floor(e.offsetY/this.items[t].size/.25);return(0,y.qE)(i,0,3)}getItemIndexFromEventTarget(e){let t=this.scrollableElement.getDomNode(),i=e;for(;i instanceof HTMLElement&&i!==this.rowsContainer&&t.contains(i);){let e=i.getAttribute("data-index");if(e){let t=Number(e);if(!isNaN(t))return t}i=i.parentElement}}getRenderRange(e,t){return{start:this.rangeMap.indexAt(e),end:this.rangeMap.indexAfter(e+t-1)}}_rerender(e,t,i){let o,s,n=this.getRenderRange(e,t);e===this.elementTop(n.start)?(o=n.start,s=0):n.end-n.start>1&&(o=n.start+1,s=this.elementTop(o)-e);let r=0;for(;;){let l=this.getRenderRange(e,t),a=!1;for(let e=l.start;e<l.end;e++){let t=this.probeDynamicHeight(e);0!==t&&this.rangeMap.splice(e,1,[this.items[e]]),r+=t,a=a||0!==t}if(!a){for(let e of(0!==r&&this.eventuallyUpdateScrollDimensions(),m.Q.relativeComplement(n,l)))for(let t=e.start;t<e.end;t++)this.items[t].row&&this.removeItemFromDOM(t);for(let e of m.Q.relativeComplement(l,n).reverse())for(let t=e.end-1;t>=e.start;t--)this.insertItemInDOM(t);for(let e=l.start;e<l.end;e++)this.items[e].row&&this.updateItemInDOM(this.items[e],e);if("number"==typeof o){let t=this.scrollable.getFutureScrollPosition().scrollTop-e,n=this.elementTop(o)-s+t;this.setScrollTop(n,i)}this._onDidChangeContentHeight.fire(this.contentHeight);return}}}probeDynamicHeight(e){var t,i,o;let n=this.items[e];if(this.virtualDelegate.getDynamicHeight){let e=this.virtualDelegate.getDynamicHeight(n.element);if(null!==e){let t=n.size;return n.size=e,n.lastDynamicHeightWidth=this.renderWidth,e-t}}if(!n.hasDynamicHeight||n.lastDynamicHeightWidth===this.renderWidth||this.virtualDelegate.hasDynamicHeight&&!this.virtualDelegate.hasDynamicHeight(n.element))return 0;let r=n.size;if(n.row)return n.row.domNode.style.height="",n.size=n.row.domNode.offsetHeight,0!==n.size||(0,s.QX)(n.row.domNode,(0,s.zk)(n.row.domNode).document.body)||console.warn("Measuring item node that is not in DOM! Add ListView to the DOM before measuring row height!"),n.lastDynamicHeightWidth=this.renderWidth,n.size-r;let{row:l}=this.cache.alloc(n.templateId);l.domNode.style.height="",this.rowsContainer.appendChild(l.domNode);let a=this.renderers.get(n.templateId);if(!a)throw new w.D7("Missing renderer for templateId: "+n.templateId);return a.renderElement(n.element,e,l.templateData,void 0),n.size=l.domNode.offsetHeight,null==(t=a.disposeElement)||t.call(a,n.element,e,l.templateData,void 0),null==(o=(i=this.virtualDelegate).setDynamicHeight)||o.call(i,n.element,n.size),n.lastDynamicHeightWidth=this.renderWidth,this.rowsContainer.removeChild(l.domNode),this.cache.release(l),n.size-r}getElementDomId(e){return`${this.domId}_${e}`}dispose(){var e,t;for(let t of this.items)if(t.dragStartDisposable.dispose(),t.checkedDisposable.dispose(),t.row){let i=this.renderers.get(t.row.templateId);i&&(null==(e=i.disposeElement)||e.call(i,t.element,-1,t.row.templateData,void 0),i.disposeTemplate(t.row.templateData))}this.items=[],this.domNode&&this.domNode.parentNode&&this.domNode.parentNode.removeChild(this.domNode),null==(t=this.dragOverAnimationDisposable)||t.dispose(),this.disposables.dispose()}}B.InstanceCount=0,A([h.B],B.prototype,"onMouseClick",null),A([h.B],B.prototype,"onMouseDblClick",null),A([h.B],B.prototype,"onMouseMiddleClick",null),A([h.B],B.prototype,"onMouseDown",null),A([h.B],B.prototype,"onMouseOver",null),A([h.B],B.prototype,"onMouseOut",null),A([h.B],B.prototype,"onContextMenu",null),A([h.B],B.prototype,"onTouchStart",null),A([h.B],B.prototype,"onTap",null)},276006(e,t,i){i.d(t,{hb:()=>j,B8:()=>et,MH:()=>q,_C:()=>n,W0:()=>P,Bm:()=>function e(t){return!!("A"===t.tagName&&t.classList.contains("monaco-button")||"DIV"===t.tagName&&t.classList.contains("monaco-button-dropdown"))||!t.classList.contains("monaco-list")&&!!t.parentElement&&e(t.parentElement)},B6:()=>T,b$:()=>O,bm:()=>L,mh:()=>K,tX:()=>U,Es:()=>H,xu:()=>_,bG:()=>Q});var o,s,n,r,l=i(614333),a=i(934061),d=i(287594),h=i(830474),c=i(556066);class u{constructor(e){this.spliceables=e}splice(e,t,i){this.spliceables.forEach(o=>o.splice(e,t,i))}}var m=i(413338),p=i(565958),g=i(694901),b=i(988846),v=i(2106),f=i(897669),w=i(310998),y=i(562992),A=i(263339),C=i(779359);i(767119);class D extends Error{constructor(e,t){super(`ListError [${e}] ${t}`)}}var S=i(107300),x=i(373956),k=i(724288),E=function(e,t,i,o){var s,n=arguments.length,r=n<3?t:null===o?o=Object.getOwnPropertyDescriptor(t,i):o;if("object"==typeof Reflect&&"function"==typeof Reflect.decorate)r=Reflect.decorate(e,t,i,o);else for(var l=e.length-1;l>=0;l--)(s=e[l])&&(r=(n<3?s(r):n>3?s(t,i,r):s(t,i))||r);return n>3&&r&&Object.defineProperty(t,i,r),r};class B{constructor(e){this.trait=e,this.renderedElements=[]}get templateId(){return`template:${this.trait.name}`}renderTemplate(e){return e}renderElement(e,t,i){let o=this.renderedElements.findIndex(e=>e.templateData===i);if(o>=0){let e=this.renderedElements[o];this.trait.unrender(i),e.index=t}else this.renderedElements.push({index:t,templateData:i});this.trait.renderIndex(t,i)}splice(e,t,i){let o=[];for(let s of this.renderedElements)s.index<e?o.push(s):s.index>=e+t&&o.push({index:s.index+i-t,templateData:s.templateData});this.renderedElements=o}renderIndexes(e){for(let{index:t,templateData:i}of this.renderedElements)e.indexOf(t)>-1&&this.trait.renderIndex(t,i)}disposeTemplate(e){let t=this.renderedElements.findIndex(t=>t.templateData===e);t<0||this.renderedElements.splice(t,1)}}class I{get name(){return this._trait}get renderer(){return new B(this)}constructor(e){this._trait=e,this.indexes=[],this.sortedIndexes=[],this._onChange=new v.vl,this.onChange=this._onChange.event}splice(e,t,i){let o=i.length-t,s=e+t,n=[],r=0;for(;r<this.sortedIndexes.length&&this.sortedIndexes[r]<e;)n.push(this.sortedIndexes[r++]);for(let t=0;t<i.length;t++)i[t]&&n.push(t+e);for(;r<this.sortedIndexes.length&&this.sortedIndexes[r]>=s;)n.push(this.sortedIndexes[r++]+o);this.renderer.splice(e,t,i.length),this._set(n,n)}renderIndex(e,t){t.classList.toggle(this._trait,this.contains(e))}unrender(e){e.classList.remove(this._trait)}set(e,t){return this._set(e,[...e].sort(V),t)}_set(e,t,i){let o=this.indexes,s=this.sortedIndexes;this.indexes=e,this.sortedIndexes=t;let n=G(s,e);return this.renderer.renderIndexes(n),this._onChange.fire({indexes:e,browserEvent:i}),o}get(){return this.indexes}contains(e){return(0,m.El)(this.sortedIndexes,e,V)>=0}dispose(){(0,w.AS)(this._onChange)}}E([b.B],I.prototype,"renderer",null);class N extends I{constructor(e){super("selected"),this.setAriaSelected=e}renderIndex(e,t){super.renderIndex(e,t),this.setAriaSelected&&(this.contains(e)?t.setAttribute("aria-selected","true"):t.setAttribute("aria-selected","false"))}}class F{constructor(e,t,i){this.trait=e,this.view=t,this.identityProvider=i}splice(e,t,i){if(!this.identityProvider)return this.trait.splice(e,t,Array(i.length).fill(!1));let o=this.trait.get().map(e=>this.identityProvider.getId(this.view.element(e)).toString());if(0===o.length)return this.trait.splice(e,t,Array(i.length).fill(!1));let s=new Set(o),n=i.map(e=>s.has(this.identityProvider.getId(e).toString()));this.trait.splice(e,t,n)}}function T(e){return"INPUT"===e.tagName||"TEXTAREA"===e.tagName}function M(e,t){return!!e.classList.contains(t)||!e.classList.contains("monaco-list")&&!!e.parentElement&&M(e.parentElement,t)}function L(e){return M(e,"monaco-editor")}function O(e){return M(e,"monaco-custom-toggle")}function P(e){return M(e,"action-item")}function _(e){return M(e,"monaco-tree-sticky-row")}function H(e){return e.classList.contains("monaco-tree-sticky-container")}class z{get onKeyDown(){return v.Jh.chain(this.disposables.add(new a.f(this.view.domNode,"keydown")).event,e=>e.filter(e=>!T(e.target)).map(e=>new d.Z(e)))}constructor(e,t,i){this.list=e,this.view=t,this.disposables=new w.Cm,this.multipleSelectionDisposables=new w.Cm,this.multipleSelectionSupport=i.multipleSelectionSupport,this.disposables.add(this.onKeyDown(e=>{switch(e.keyCode){case 3:return this.onEnter(e);case 16:return this.onUpArrow(e);case 18:return this.onDownArrow(e);case 11:return this.onPageUpArrow(e);case 12:return this.onPageDownArrow(e);case 9:return this.onEscape(e);case 31:this.multipleSelectionSupport&&(A.zx?e.metaKey:e.ctrlKey)&&this.onCtrlA(e)}}))}updateOptions(e){void 0!==e.multipleSelectionSupport&&(this.multipleSelectionSupport=e.multipleSelectionSupport)}onEnter(e){e.preventDefault(),e.stopPropagation(),this.list.setSelection(this.list.getFocus(),e.browserEvent)}onUpArrow(e){e.preventDefault(),e.stopPropagation(),this.list.focusPrevious(1,!1,e.browserEvent);let t=this.list.getFocus()[0];this.list.setAnchor(t),this.list.reveal(t),this.view.domNode.focus()}onDownArrow(e){e.preventDefault(),e.stopPropagation(),this.list.focusNext(1,!1,e.browserEvent);let t=this.list.getFocus()[0];this.list.setAnchor(t),this.list.reveal(t),this.view.domNode.focus()}onPageUpArrow(e){e.preventDefault(),e.stopPropagation(),this.list.focusPreviousPage(e.browserEvent);let t=this.list.getFocus()[0];this.list.setAnchor(t),this.list.reveal(t),this.view.domNode.focus()}onPageDownArrow(e){e.preventDefault(),e.stopPropagation(),this.list.focusNextPage(e.browserEvent);let t=this.list.getFocus()[0];this.list.setAnchor(t),this.list.reveal(t),this.view.domNode.focus()}onCtrlA(e){e.preventDefault(),e.stopPropagation(),this.list.setSelection((0,m.y1)(this.list.length),e.browserEvent),this.list.setAnchor(void 0),this.view.domNode.focus()}onEscape(e){this.list.getSelection().length&&(e.preventDefault(),e.stopPropagation(),this.list.setSelection([],e.browserEvent),this.list.setAnchor(void 0),this.view.domNode.focus())}dispose(){this.disposables.dispose(),this.multipleSelectionDisposables.dispose()}}E([b.B],z.prototype,"onKeyDown",null),(o=n||(n={}))[o.Automatic=0]="Automatic",o[o.Trigger=1]="Trigger",(s=r||(r={}))[s.Idle=0]="Idle",s[s.Typing=1]="Typing";let $=new class{mightProducePrintableCharacter(e){return!e.ctrlKey&&!e.metaKey&&!e.altKey&&(e.keyCode>=31&&e.keyCode<=56||e.keyCode>=21&&e.keyCode<=30||e.keyCode>=98&&e.keyCode<=107||e.keyCode>=85&&e.keyCode<=95)}};class R{constructor(e,t,i,o,s){this.list=e,this.view=t,this.keyboardNavigationLabelProvider=i,this.keyboardNavigationEventFilter=o,this.delegate=s,this.enabled=!1,this.state=r.Idle,this.mode=n.Automatic,this.triggered=!1,this.previouslyFocused=-1,this.enabledDisposables=new w.Cm,this.disposables=new w.Cm,this.updateOptions(e.options)}updateOptions(e){var t,i;null==(t=e.typeNavigationEnabled)||t?this.enable():this.disable(),this.mode=null!=(i=e.typeNavigationMode)?i:n.Automatic}enable(){if(this.enabled)return;let e=!1,t=v.Jh.chain(this.enabledDisposables.add(new a.f(this.view.domNode,"keydown")).event,t=>t.filter(e=>!T(e.target)).filter(()=>this.mode===n.Automatic||this.triggered).map(e=>new d.Z(e)).filter(t=>e||this.keyboardNavigationEventFilter(t)).filter(e=>this.delegate.mightProducePrintableCharacter(e)).forEach(e=>l.fs.stop(e,!0)).map(e=>e.browserEvent.key)),i=v.Jh.debounce(t,()=>null,800,void 0,void 0,void 0,this.enabledDisposables);v.Jh.reduce(v.Jh.any(t,i),(e,t)=>null===t?null:(e||"")+t,void 0,this.enabledDisposables)(this.onInput,this,this.enabledDisposables),i(this.onClear,this,this.enabledDisposables),t(()=>e=!0,void 0,this.enabledDisposables),i(()=>e=!1,void 0,this.enabledDisposables),this.enabled=!0,this.triggered=!1}disable(){this.enabled&&(this.enabledDisposables.clear(),this.enabled=!1,this.triggered=!1)}onClear(){var e;let t=this.list.getFocus();if(t.length>0&&t[0]===this.previouslyFocused){let i=null==(e=this.list.options.accessibilityProvider)?void 0:e.getAriaLabel(this.list.element(t[0]));"string"==typeof i?(0,c.xE)(i):i&&(0,c.xE)(i.get())}this.previouslyFocused=-1}onInput(e){if(!e){this.state=r.Idle,this.triggered=!1;return}let t=this.list.getFocus(),i=t.length>0?t[0]:0,o=+(this.state===r.Idle);this.state=r.Typing;for(let t=0;t<this.list.length;t++){let s=(i+t+o)%this.list.length,n=this.keyboardNavigationLabelProvider.getKeyboardNavigationLabel(this.view.element(s)),r=n&&n.toString();if(this.list.options.typeNavigationEnabled){if(void 0!==r){if((0,f.WP)(e,r)){this.previouslyFocused=i,this.list.setFocus([s]),this.list.reveal(s);return}let t=(0,f.O)(e,r);if(t&&t[0].end-t[0].start>1&&1===t.length){this.previouslyFocused=i,this.list.setFocus([s]),this.list.reveal(s);return}}}else if(void 0===r||(0,f.WP)(e,r)){this.previouslyFocused=i,this.list.setFocus([s]),this.list.reveal(s);return}}}dispose(){this.disable(),this.enabledDisposables.dispose(),this.disposables.dispose()}}class W{constructor(e,t){this.list=e,this.view=t,this.disposables=new w.Cm;const i=v.Jh.chain(this.disposables.add(new a.f(t.domNode,"keydown")).event,e=>e.filter(e=>!T(e.target)).map(e=>new d.Z(e)));v.Jh.chain(i,e=>e.filter(e=>2===e.keyCode&&!e.ctrlKey&&!e.metaKey&&!e.shiftKey&&!e.altKey))(this.onTab,this,this.disposables)}onTab(e){if(e.target!==this.view.domNode)return;let t=this.list.getFocus();if(0===t.length)return;let i=this.view.domElement(t[0]);if(!i)return;let o=i.querySelector("[tabIndex]");if(!o||!(o instanceof HTMLElement)||-1===o.tabIndex)return;let s=(0,l.zk)(o).getComputedStyle(o);"hidden"!==s.visibility&&"none"!==s.display&&(e.preventDefault(),e.stopPropagation(),o.focus())}dispose(){this.disposables.dispose()}}function U(e){return A.zx?e.browserEvent.metaKey:e.browserEvent.ctrlKey}function K(e){return e.browserEvent.shiftKey}let J={isSelectionSingleChangeEvent:U,isSelectionRangeChangeEvent:K};class q{constructor(e){this.list=e,this.disposables=new w.Cm,this._onPointer=new v.vl,this.onPointer=this._onPointer.event,!1!==e.options.multipleSelectionSupport&&(this.multipleSelectionController=this.list.options.multipleSelectionController||J),this.mouseSupport=void 0===e.options.mouseSupport||!!e.options.mouseSupport,this.mouseSupport&&(e.onMouseDown(this.onMouseDown,this,this.disposables),e.onContextMenu(this.onContextMenu,this,this.disposables),e.onMouseDblClick(this.onDoubleClick,this,this.disposables),e.onTouchStart(this.onMouseDown,this,this.disposables),this.disposables.add(h.q.addTarget(e.getHTMLElement()))),v.Jh.any(e.onMouseClick,e.onMouseMiddleClick,e.onTap)(this.onViewPointer,this,this.disposables)}updateOptions(e){void 0!==e.multipleSelectionSupport&&(this.multipleSelectionController=void 0,e.multipleSelectionSupport&&(this.multipleSelectionController=this.list.options.multipleSelectionController||J))}isSelectionSingleChangeEvent(e){return!!this.multipleSelectionController&&this.multipleSelectionController.isSelectionSingleChangeEvent(e)}isSelectionRangeChangeEvent(e){return!!this.multipleSelectionController&&this.multipleSelectionController.isSelectionRangeChangeEvent(e)}isSelectionChangeEvent(e){return this.isSelectionSingleChangeEvent(e)||this.isSelectionRangeChangeEvent(e)}onMouseDown(e){L(e.browserEvent.target)||(0,l.bq)()!==e.browserEvent.target&&this.list.domFocus()}onContextMenu(e){if(T(e.browserEvent.target)||L(e.browserEvent.target))return;let t=void 0===e.index?[]:[e.index];this.list.setFocus(t,e.browserEvent)}onViewPointer(e){var t;if(!this.mouseSupport||T(e.browserEvent.target)||L(e.browserEvent.target)||e.browserEvent.isHandledByList)return;e.browserEvent.isHandledByList=!0;let i=e.index;if(void 0===i){this.list.setFocus([],e.browserEvent),this.list.setSelection([],e.browserEvent),this.list.setAnchor(void 0);return}if(this.isSelectionChangeEvent(e))return this.changeSelection(e);this.list.setFocus([i],e.browserEvent),this.list.setAnchor(i),t=e.browserEvent,(0,l.Er)(t)&&2===t.button||this.list.setSelection([i],e.browserEvent),this._onPointer.fire(e)}onDoubleClick(e){if(T(e.browserEvent.target)||L(e.browserEvent.target)||this.isSelectionChangeEvent(e)||e.browserEvent.isHandledByList)return;e.browserEvent.isHandledByList=!0;let t=this.list.getFocus();this.list.setSelection(t,e.browserEvent)}changeSelection(e){let t=e.index,i=this.list.getAnchor();if(this.isSelectionRangeChangeEvent(e)){if(void 0===i){let e=this.list.getFocus()[0];i=null!=e?e:t,this.list.setAnchor(i)}let o=Math.min(i,t),s=Math.max(i,t),n=(0,m.y1)(o,s+1),r=this.list.getSelection(),l=function(e,t){let i=e.indexOf(t);if(-1===i)return[];let o=[],s=i-1;for(;s>=0&&e[s]===t-(i-s);)o.push(e[s--]);for(o.reverse(),s=i;s<e.length&&e[s]===t+(s-i);)o.push(e[s++]);return o}(G(r,[i]),i);if(0===l.length)return;let a=G(n,function(e,t){let i=[],o=0,s=0;for(;o<e.length||s<t.length;)if(o>=e.length)i.push(t[s++]);else if(s>=t.length)i.push(e[o++]);else if(e[o]===t[s]){o++,s++;continue}else e[o]<t[s]?i.push(e[o++]):s++;return i}(r,l));this.list.setSelection(a,e.browserEvent),this.list.setFocus([t],e.browserEvent)}else if(this.isSelectionSingleChangeEvent(e)){let i=this.list.getSelection(),o=i.filter(e=>e!==t);this.list.setFocus([t]),this.list.setAnchor(t),i.length===o.length?this.list.setSelection([...o,t],e.browserEvent):this.list.setSelection(o,e.browserEvent)}}dispose(){this.disposables.dispose()}}class j{constructor(e,t){this.styleElement=e,this.selectorSuffix=t}style(e){var t,i;let o=this.selectorSuffix&&`.${this.selectorSuffix}`,s=[];e.listBackground&&s.push(`.monaco-list${o} .monaco-list-rows { background: ${e.listBackground}; }`),e.listFocusBackground&&(s.push(`.monaco-list${o}:focus .monaco-list-row.focused { background-color: ${e.listFocusBackground}; }`),s.push(`.monaco-list${o}:focus .monaco-list-row.focused:hover { background-color: ${e.listFocusBackground}; }`)),e.listFocusForeground&&s.push(`.monaco-list${o}:focus .monaco-list-row.focused { color: ${e.listFocusForeground}; }`),e.listActiveSelectionBackground&&(s.push(`.monaco-list${o}:focus .monaco-list-row.selected { background-color: ${e.listActiveSelectionBackground}; }`),s.push(`.monaco-list${o}:focus .monaco-list-row.selected:hover { background-color: ${e.listActiveSelectionBackground}; }`)),e.listActiveSelectionForeground&&s.push(`.monaco-list${o}:focus .monaco-list-row.selected { color: ${e.listActiveSelectionForeground}; }`),e.listActiveSelectionIconForeground&&s.push(`.monaco-list${o}:focus .monaco-list-row.selected .codicon { color: ${e.listActiveSelectionIconForeground}; }`),e.listFocusAndSelectionBackground&&s.push(`
				.monaco-drag-image,
				.monaco-list${o}:focus .monaco-list-row.selected.focused { background-color: ${e.listFocusAndSelectionBackground}; }
			`),e.listFocusAndSelectionForeground&&s.push(`
				.monaco-drag-image,
				.monaco-list${o}:focus .monaco-list-row.selected.focused { color: ${e.listFocusAndSelectionForeground}; }
			`),e.listInactiveFocusForeground&&(s.push(`.monaco-list${o} .monaco-list-row.focused { color:  ${e.listInactiveFocusForeground}; }`),s.push(`.monaco-list${o} .monaco-list-row.focused:hover { color:  ${e.listInactiveFocusForeground}; }`)),e.listInactiveSelectionIconForeground&&s.push(`.monaco-list${o} .monaco-list-row.focused .codicon { color:  ${e.listInactiveSelectionIconForeground}; }`),e.listInactiveFocusBackground&&(s.push(`.monaco-list${o} .monaco-list-row.focused { background-color:  ${e.listInactiveFocusBackground}; }`),s.push(`.monaco-list${o} .monaco-list-row.focused:hover { background-color:  ${e.listInactiveFocusBackground}; }`)),e.listInactiveSelectionBackground&&(s.push(`.monaco-list${o} .monaco-list-row.selected { background-color:  ${e.listInactiveSelectionBackground}; }`),s.push(`.monaco-list${o} .monaco-list-row.selected:hover { background-color:  ${e.listInactiveSelectionBackground}; }`)),e.listInactiveSelectionForeground&&s.push(`.monaco-list${o} .monaco-list-row.selected { color: ${e.listInactiveSelectionForeground}; }`),e.listHoverBackground&&s.push(`.monaco-list${o}:not(.drop-target):not(.dragging) .monaco-list-row:hover:not(.selected):not(.focused) { background-color: ${e.listHoverBackground}; }`),e.listHoverForeground&&s.push(`.monaco-list${o}:not(.drop-target):not(.dragging) .monaco-list-row:hover:not(.selected):not(.focused) { color:  ${e.listHoverForeground}; }`);let n=(0,l.gI)(e.listFocusAndSelectionOutline,(0,l.gI)(e.listSelectionOutline,null!=(t=e.listFocusOutline)?t:""));n&&s.push(`.monaco-list${o}:focus .monaco-list-row.focused.selected { outline: 1px solid ${n}; outline-offset: -1px;}`),e.listFocusOutline&&s.push(`
				.monaco-drag-image,
				.monaco-list${o}:focus .monaco-list-row.focused { outline: 1px solid ${e.listFocusOutline}; outline-offset: -1px; }
				.monaco-workbench.context-menu-visible .monaco-list${o}.last-focused .monaco-list-row.focused { outline: 1px solid ${e.listFocusOutline}; outline-offset: -1px; }
			`);let r=(0,l.gI)(e.listSelectionOutline,null!=(i=e.listInactiveFocusOutline)?i:"");r&&s.push(`.monaco-list${o} .monaco-list-row.focused.selected { outline: 1px dotted ${r}; outline-offset: -1px; }`),e.listSelectionOutline&&s.push(`.monaco-list${o} .monaco-list-row.selected { outline: 1px dotted ${e.listSelectionOutline}; outline-offset: -1px; }`),e.listInactiveFocusOutline&&s.push(`.monaco-list${o} .monaco-list-row.focused { outline: 1px dotted ${e.listInactiveFocusOutline}; outline-offset: -1px; }`),e.listHoverOutline&&s.push(`.monaco-list${o} .monaco-list-row:hover { outline: 1px dashed ${e.listHoverOutline}; outline-offset: -1px; }`),e.listDropOverBackground&&s.push(`
				.monaco-list${o}.drop-target,
				.monaco-list${o} .monaco-list-rows.drop-target,
				.monaco-list${o} .monaco-list-row.drop-target { background-color: ${e.listDropOverBackground} !important; color: inherit !important; }
			`),e.listDropBetweenBackground&&(s.push(`
			.monaco-list${o} .monaco-list-rows.drop-target-before .monaco-list-row:first-child::before,
			.monaco-list${o} .monaco-list-row.drop-target-before::before {
				content: ""; position: absolute; top: 0px; left: 0px; width: 100%; height: 1px;
				background-color: ${e.listDropBetweenBackground};
			}`),s.push(`
			.monaco-list${o} .monaco-list-rows.drop-target-after .monaco-list-row:last-child::after,
			.monaco-list${o} .monaco-list-row.drop-target-after::after {
				content: ""; position: absolute; bottom: 0px; left: 0px; width: 100%; height: 1px;
				background-color: ${e.listDropBetweenBackground};
			}`)),e.tableColumnsBorder&&s.push(`
				.monaco-table > .monaco-split-view2,
				.monaco-table > .monaco-split-view2 .monaco-sash.vertical::before,
				.monaco-workbench:not(.reduce-motion) .monaco-table:hover > .monaco-split-view2,
				.monaco-workbench:not(.reduce-motion) .monaco-table:hover > .monaco-split-view2 .monaco-sash.vertical::before {
					border-color: ${e.tableColumnsBorder};
				}

				.monaco-workbench:not(.reduce-motion) .monaco-table > .monaco-split-view2,
				.monaco-workbench:not(.reduce-motion) .monaco-table > .monaco-split-view2 .monaco-sash.vertical::before {
					border-color: transparent;
				}
			`),e.tableOddRowsBackgroundColor&&s.push(`
				.monaco-table .monaco-list-row[data-parity=odd]:not(.focused):not(.selected):not(:hover) .monaco-table-tr,
				.monaco-table .monaco-list:not(:focus) .monaco-list-row[data-parity=odd].focused:not(.selected):not(:hover) .monaco-table-tr,
				.monaco-table .monaco-list:not(.focused) .monaco-list-row[data-parity=odd].focused:not(.selected):not(:hover) .monaco-table-tr {
					background-color: ${e.tableOddRowsBackgroundColor};
				}
			`),this.styleElement.textContent=s.join("\n")}}let Q={listFocusBackground:"#7FB0D0",listActiveSelectionBackground:"#0E639C",listActiveSelectionForeground:"#FFFFFF",listActiveSelectionIconForeground:"#FFFFFF",listFocusAndSelectionOutline:"#90C2F9",listFocusAndSelectionBackground:"#094771",listFocusAndSelectionForeground:"#FFFFFF",listInactiveSelectionBackground:"#3F3F46",listInactiveSelectionIconForeground:"#FFFFFF",listHoverBackground:"#2A2D2E",listDropOverBackground:"#383B3D",listDropBetweenBackground:"#EEEEEE",treeIndentGuidesStroke:"#a9a9a9",treeInactiveIndentGuidesStroke:g.Q1.fromHex("#a9a9a9").transparent(.4).toString(),tableColumnsBorder:g.Q1.fromHex("#cccccc").transparent(.2).toString(),tableOddRowsBackgroundColor:g.Q1.fromHex("#cccccc").transparent(.04).toString(),listBackground:void 0,listFocusForeground:void 0,listInactiveSelectionForeground:void 0,listInactiveFocusForeground:void 0,listInactiveFocusBackground:void 0,listHoverForeground:void 0,listFocusOutline:void 0,listInactiveFocusOutline:void 0,listSelectionOutline:void 0,listHoverOutline:void 0,treeStickyScrollBackground:void 0,treeStickyScrollBorder:void 0,treeStickyScrollShadow:void 0},Y={keyboardSupport:!0,mouseSupport:!0,multipleSelectionSupport:!0,dnd:{getDragURI:()=>null,onDragStart(){},onDragOver:()=>!1,drop(){},dispose(){}}};function G(e,t){let i=[],o=0,s=0;for(;o<e.length||s<t.length;)if(o>=e.length)i.push(t[s++]);else if(s>=t.length)i.push(e[o++]);else if(e[o]===t[s]){i.push(e[o]),o++,s++;continue}else e[o]<t[s]?i.push(e[o++]):i.push(t[s++]);return i}let V=(e,t)=>e-t;class Z{constructor(e,t){this._templateId=e,this.renderers=t}get templateId(){return this._templateId}renderTemplate(e){return this.renderers.map(t=>t.renderTemplate(e))}renderElement(e,t,i,o){let s=0;for(let n of this.renderers)n.renderElement(e,t,i[s++],o)}disposeElement(e,t,i,o){var s;let n=0;for(let r of this.renderers)null==(s=r.disposeElement)||s.call(r,e,t,i[n],o),n+=1}disposeTemplate(e){let t=0;for(let i of this.renderers)i.disposeTemplate(e[t++])}}class X{constructor(e){this.accessibilityProvider=e,this.templateId="a18n"}renderTemplate(e){return{container:e,disposables:new w.Cm}}renderElement(e,t,i){let o=this.accessibilityProvider.getAriaLabel(e),s=o&&"string"!=typeof o?o:(0,k.lk)(o);i.disposables.add((0,k.fm)(e=>{this.setAriaLabel(e.readObservable(s),i.container)}));let n=this.accessibilityProvider.getAriaLevel&&this.accessibilityProvider.getAriaLevel(e);"number"==typeof n?i.container.setAttribute("aria-level",`${n}`):i.container.removeAttribute("aria-level")}setAriaLabel(e,t){e?t.setAttribute("aria-label",e):t.removeAttribute("aria-label")}disposeElement(e,t,i,o){i.disposables.clear()}disposeTemplate(e){e.disposables.dispose()}}class ee{constructor(e,t){this.list=e,this.dnd=t}getDragElements(e){let t=this.list.getSelectedElements();return t.indexOf(e)>-1?t:[e]}getDragURI(e){return this.dnd.getDragURI(e)}getDragLabel(e,t){if(this.dnd.getDragLabel)return this.dnd.getDragLabel(e,t)}onDragStart(e,t){var i,o;null==(o=(i=this.dnd).onDragStart)||o.call(i,e,t)}onDragOver(e,t,i,o,s){return this.dnd.onDragOver(e,t,i,o,s)}onDragLeave(e,t,i,o){var s,n;null==(n=(s=this.dnd).onDragLeave)||n.call(s,e,t,i,o)}onDragEnd(e){var t,i;null==(i=(t=this.dnd).onDragEnd)||i.call(t,e)}drop(e,t,i,o,s){this.dnd.drop(e,t,i,o,s)}dispose(){this.dnd.dispose()}}class et{get onDidChangeFocus(){return v.Jh.map(this.eventBufferer.wrapEvent(this.focus.onChange),e=>this.toListEvent(e),this.disposables)}get onDidChangeSelection(){return v.Jh.map(this.eventBufferer.wrapEvent(this.selection.onChange),e=>this.toListEvent(e),this.disposables)}get domId(){return this.view.domId}get onDidScroll(){return this.view.onDidScroll}get onMouseClick(){return this.view.onMouseClick}get onMouseDblClick(){return this.view.onMouseDblClick}get onMouseMiddleClick(){return this.view.onMouseMiddleClick}get onPointer(){return this.mouseController.onPointer}get onMouseDown(){return this.view.onMouseDown}get onMouseOver(){return this.view.onMouseOver}get onMouseOut(){return this.view.onMouseOut}get onTouchStart(){return this.view.onTouchStart}get onTap(){return this.view.onTap}get onContextMenu(){let e=!1,t=v.Jh.chain(this.disposables.add(new a.f(this.view.domNode,"keydown")).event,t=>t.map(e=>new d.Z(e)).filter(t=>e=58===t.keyCode||t.shiftKey&&68===t.keyCode).map(e=>l.fs.stop(e,!0)).filter(()=>!1)),i=v.Jh.chain(this.disposables.add(new a.f(this.view.domNode,"keyup")).event,t=>t.forEach(()=>e=!1).map(e=>new d.Z(e)).filter(e=>58===e.keyCode||e.shiftKey&&68===e.keyCode).map(e=>l.fs.stop(e,!0)).map(({browserEvent:e})=>{let t=this.getFocus(),i=t.length?t[0]:void 0,o=void 0!==i?this.view.element(i):void 0,s=void 0!==i?this.view.domElement(i):this.view.domNode;return{index:i,element:o,anchor:s,browserEvent:e}})),o=v.Jh.chain(this.view.onContextMenu,t=>t.filter(t=>!e).map(({element:e,index:t,browserEvent:i})=>({element:e,index:t,anchor:new x.P((0,l.zk)(this.view.domNode),i),browserEvent:i})));return v.Jh.any(t,i,o)}get onKeyDown(){return this.disposables.add(new a.f(this.view.domNode,"keydown")).event}get onDidFocus(){return v.Jh.signal(this.disposables.add(new a.f(this.view.domNode,"focus",!0)).event)}get onDidBlur(){return v.Jh.signal(this.disposables.add(new a.f(this.view.domNode,"blur",!0)).event)}constructor(e,t,i,o,s=Y){var n,r,a,d;this.user=e,this._options=s,this.focus=new I("focused"),this.anchor=new I("anchor"),this.eventBufferer=new v.at,this._ariaLabel="",this.disposables=new w.Cm,this._onDidDispose=new v.vl,this.onDidDispose=this._onDidDispose.event;const h=this._options.accessibilityProvider&&this._options.accessibilityProvider.getWidgetRole?null==(n=this._options.accessibilityProvider)?void 0:n.getWidgetRole():"list";this.selection=new N("listbox"!==h);const c=[this.focus.renderer,this.selection.renderer];this.accessibilityProvider=s.accessibilityProvider,this.accessibilityProvider&&(c.push(new X(this.accessibilityProvider)),null==(a=(r=this.accessibilityProvider).onDidChangeActiveDescendant)||a.call(r,this.onDidChangeActiveDescendant,this,this.disposables)),o=o.map(e=>new Z(e.templateId,[...c,e]));const m={...s,dnd:s.dnd&&new ee(this,s.dnd)};if(this.view=this.createListView(t,i,o,m),this.view.domNode.setAttribute("role",h),s.styleController)this.styleController=s.styleController(this.view.domId);else{const e=(0,l.li)(this.view.domNode);this.styleController=new j(e,this.view.domId)}if(this.spliceable=new u([new F(this.focus,this.view,s.identityProvider),new F(this.selection,this.view,s.identityProvider),new F(this.anchor,this.view,s.identityProvider),this.view]),this.disposables.add(this.focus),this.disposables.add(this.selection),this.disposables.add(this.anchor),this.disposables.add(this.view),this.disposables.add(this._onDidDispose),this.disposables.add(new W(this,this.view)),("boolean"!=typeof s.keyboardSupport||s.keyboardSupport)&&(this.keyboardController=new z(this,this.view,s),this.disposables.add(this.keyboardController)),s.keyboardNavigationLabelProvider){const e=s.keyboardNavigationDelegate||$;this.typeNavigationController=new R(this,this.view,s.keyboardNavigationLabelProvider,null!=(d=s.keyboardNavigationEventFilter)?d:()=>!0,e),this.disposables.add(this.typeNavigationController)}this.mouseController=this.createMouseController(s),this.disposables.add(this.mouseController),this.onDidChangeFocus(this._onFocusChange,this,this.disposables),this.onDidChangeSelection(this._onSelectionChange,this,this.disposables),this.accessibilityProvider&&(this.ariaLabel=this.accessibilityProvider.getWidgetAriaLabel()),!1!==this._options.multipleSelectionSupport&&this.view.domNode.setAttribute("aria-multiselectable","true")}createListView(e,t,i,o){return new S.uO(e,t,i,o)}createMouseController(e){return new q(this)}updateOptions(e={}){var t,i;this._options={...this._options,...e},null==(t=this.typeNavigationController)||t.updateOptions(this._options),void 0!==this._options.multipleSelectionController&&(this._options.multipleSelectionSupport?this.view.domNode.setAttribute("aria-multiselectable","true"):this.view.domNode.removeAttribute("aria-multiselectable")),this.mouseController.updateOptions(e),null==(i=this.keyboardController)||i.updateOptions(e),this.view.updateOptions(e)}get options(){return this._options}splice(e,t,i=[]){if(e<0||e>this.view.length)throw new D(this.user,`Invalid start index: ${e}`);if(t<0)throw new D(this.user,`Invalid delete count: ${t}`);(0!==t||0!==i.length)&&this.eventBufferer.bufferEvents(()=>this.spliceable.splice(e,t,i))}rerender(){this.view.rerender()}element(e){return this.view.element(e)}indexOf(e){return this.view.indexOf(e)}indexAt(e){return this.view.indexAt(e)}get length(){return this.view.length}get contentHeight(){return this.view.contentHeight}get onDidChangeContentHeight(){return this.view.onDidChangeContentHeight}get scrollTop(){return this.view.getScrollTop()}set scrollTop(e){this.view.setScrollTop(e)}get scrollHeight(){return this.view.scrollHeight}get renderHeight(){return this.view.renderHeight}get firstVisibleIndex(){return this.view.firstVisibleIndex}get ariaLabel(){return this._ariaLabel}set ariaLabel(e){this._ariaLabel=e,this.view.domNode.setAttribute("aria-label",e)}domFocus(){this.view.domNode.focus({preventScroll:!0})}layout(e,t){this.view.layout(e,t)}setSelection(e,t){for(let t of e)if(t<0||t>=this.length)throw new D(this.user,`Invalid index ${t}`);this.selection.set(e,t)}getSelection(){return this.selection.get()}getSelectedElements(){return this.getSelection().map(e=>this.view.element(e))}setAnchor(e){if(void 0===e)return void this.anchor.set([]);if(e<0||e>=this.length)throw new D(this.user,`Invalid index ${e}`);this.anchor.set([e])}getAnchor(){return(0,m.Fy)(this.anchor.get(),void 0)}getAnchorElement(){let e=this.getAnchor();return void 0===e?void 0:this.element(e)}setFocus(e,t){for(let t of e)if(t<0||t>=this.length)throw new D(this.user,`Invalid index ${t}`);this.focus.set(e,t)}focusNext(e=1,t=!1,i,o){if(0===this.length)return;let s=this.focus.get(),n=this.findNextIndex(s.length>0?s[0]+e:0,t,o);n>-1&&this.setFocus([n],i)}focusPrevious(e=1,t=!1,i,o){if(0===this.length)return;let s=this.focus.get(),n=this.findPreviousIndex(s.length>0?s[0]-e:0,t,o);n>-1&&this.setFocus([n],i)}async focusNextPage(e,t){let i=this.view.indexAt(this.view.getScrollTop()+this.view.renderHeight);i=0===i?0:i-1;let o=this.getFocus()[0];if(o!==i&&(void 0===o||i>o)){let s=this.findPreviousIndex(i,!1,t);s>-1&&o!==s?this.setFocus([s],e):this.setFocus([i],e)}else{let s=this.view.getScrollTop(),n=s+this.view.renderHeight;i>o&&(n-=this.view.elementHeight(i)),this.view.setScrollTop(n),this.view.getScrollTop()!==s&&(this.setFocus([]),await (0,p.wR)(0),await this.focusNextPage(e,t))}}async focusPreviousPage(e,t,i=()=>0){let o,s=i(),n=this.view.getScrollTop()+s;o=0===n?this.view.indexAt(n):this.view.indexAfter(n-1);let r=this.getFocus()[0];if(r!==o&&(void 0===r||r>=o)){let i=this.findNextIndex(o,!1,t);i>-1&&r!==i?this.setFocus([i],e):this.setFocus([o],e)}else this.view.setScrollTop(n-this.view.renderHeight-s),this.view.getScrollTop()+i()!==n&&(this.setFocus([]),await (0,p.wR)(0),await this.focusPreviousPage(e,t,i))}focusLast(e,t){if(0===this.length)return;let i=this.findPreviousIndex(this.length-1,!1,t);i>-1&&this.setFocus([i],e)}focusFirst(e,t){this.focusNth(0,e,t)}focusNth(e,t,i){if(0===this.length)return;let o=this.findNextIndex(e,!1,i);o>-1&&this.setFocus([o],t)}findNextIndex(e,t=!1,i){for(let o=0;o<this.length&&(!(e>=this.length)||t);o++){if(e%=this.length,!i||i(this.element(e)))return e;e++}return -1}findPreviousIndex(e,t=!1,i){for(let o=0;o<this.length&&(!(e<0)||t);o++){if(e=(this.length+e%this.length)%this.length,!i||i(this.element(e)))return e;e--}return -1}getFocus(){return this.focus.get()}getFocusedElements(){return this.getFocus().map(e=>this.view.element(e))}reveal(e,t,i=0){if(e<0||e>=this.length)throw new D(this.user,`Invalid index ${e}`);let o=this.view.getScrollTop(),s=this.view.elementTop(e),n=this.view.elementHeight(e);if((0,C.Et)(t)){let e=n-this.view.renderHeight+i;this.view.setScrollTop(e*(0,y.qE)(t,0,1)+s-i)}else{let e=s+n,t=o+this.view.renderHeight;s<o+i&&e>=t||(s<o+i||e>=t&&n>=this.view.renderHeight?this.view.setScrollTop(s-i):e>=t&&this.view.setScrollTop(e-this.view.renderHeight))}}getRelativeTop(e,t=0){if(e<0||e>=this.length)throw new D(this.user,`Invalid index ${e}`);let i=this.view.getScrollTop(),o=this.view.elementTop(e),s=this.view.elementHeight(e);if(o<i+t||o+s>i+this.view.renderHeight)return null;let n=s-this.view.renderHeight+t;return Math.abs((i+t-o)/n)}getHTMLElement(){return this.view.domNode}getScrollableElement(){return this.view.scrollableElementDomNode}getElementID(e){return this.view.getElementDomId(e)}getElementTop(e){return this.view.elementTop(e)}style(e){this.styleController.style(e)}toListEvent({indexes:e,browserEvent:t}){return{indexes:e,elements:e.map(e=>this.view.element(e)),browserEvent:t}}_onFocusChange(){let e=this.focus.get();this.view.domNode.classList.toggle("element-focused",e.length>0),this.onDidChangeActiveDescendant()}onDidChangeActiveDescendant(){var e;let t=this.focus.get();if(t.length>0){let i;(null==(e=this.accessibilityProvider)?void 0:e.getActiveDescendantId)&&(i=this.accessibilityProvider.getActiveDescendantId(this.view.element(t[0]))),this.view.domNode.setAttribute("aria-activedescendant",i||this.view.getElementDomId(t[0]))}else this.view.domNode.removeAttribute("aria-activedescendant")}_onSelectionChange(){let e=this.selection.get();this.view.domNode.classList.toggle("selection-none",0===e.length),this.view.domNode.classList.toggle("selection-single",1===e.length),this.view.domNode.classList.toggle("selection-multiple",e.length>1)}dispose(){this._onDidDispose.fire(),this.disposables.dispose(),this._onDidDispose.dispose()}}E([b.B],et.prototype,"onDidChangeFocus",null),E([b.B],et.prototype,"onDidChangeSelection",null),E([b.B],et.prototype,"onContextMenu",null),E([b.B],et.prototype,"onKeyDown",null),E([b.B],et.prototype,"onDidFocus",null),E([b.B],et.prototype,"onDidBlur",null)},641575(e,t,i){var o,s,n,r,l=i(555893),a=i(830474),d=i(614333),h=i(287594),c=i(373956),u=i(777439),m=i(223473),p=i(528239),g=i(82208),b=i(427969),v=i(565958),f=i(126048),w=i(519892),y=i(858881),A=i(324594),C=i(310998),D=i(263339),S=i(916844);let x=/\(&([^\s&])\)|(^|[^&])&([^\s&])/,k=/(&amp;)?(&amp;)([^\s&])/g;(o=n||(n={}))[o.Right=0]="Right",o[o.Left=1]="Left",(s=r||(r={}))[s.Above=0]="Above",s[s.Below=1]="Below";class E extends u.E{constructor(e,t,i,o){e.classList.add("monaco-menu-container"),e.setAttribute("role","presentation");const s=document.createElement("div");s.classList.add("monaco-menu"),s.setAttribute("role","presentation"),super(s,{orientation:1,actionViewItemProvider:e=>this.doGetActionViewItem(e,i,n),context:i.context,actionRunner:i.actionRunner,ariaLabel:i.ariaLabel,ariaRole:"menu",focusOnlyEnabledItems:!0,triggerKeys:{keys:[3,...D.zx||D.j9?[10]:[]],keyDown:!0}}),this.menuStyles=o,this.menuElement=s,this.actionsList.tabIndex=0,this.initializeOrUpdateStyleSheet(e,o),this._register(a.q.addTarget(s)),this._register((0,d.ko)(s,d.Bx.KEY_DOWN,e=>{new h.Z(e).equals(2)&&e.preventDefault()})),i.enableMnemonics&&this._register((0,d.ko)(s,d.Bx.KEY_DOWN,e=>{let t=e.key.toLocaleLowerCase();if(this.mnemonics.has(t)){d.fs.stop(e,!0);let i=this.mnemonics.get(t);if(1===i.length&&(i[0]instanceof I&&i[0].container&&this.focusItemByElement(i[0].container),i[0].onClick(e)),i.length>1){let e=i.shift();e&&e.container&&(this.focusItemByElement(e.container),i.push(e)),this.mnemonics.set(t,i)}}})),D.j9&&this._register((0,d.ko)(s,d.Bx.KEY_DOWN,e=>{let t=new h.Z(e);t.equals(14)||t.equals(11)?(this.focusedItem=this.viewItems.length-1,this.focusNext(),d.fs.stop(e,!0)):(t.equals(13)||t.equals(12))&&(this.focusedItem=0,this.focusPrevious(),d.fs.stop(e,!0))})),this._register((0,d.ko)(this.domNode,d.Bx.MOUSE_OUT,e=>{let t=e.relatedTarget;(0,d.QX)(t,this.domNode)||(this.focusedItem=void 0,this.updateFocus(),e.stopPropagation())})),this._register((0,d.ko)(this.actionsList,d.Bx.MOUSE_OVER,e=>{let t=e.target;if(t&&(0,d.QX)(t,this.actionsList)&&t!==this.actionsList){for(;t.parentElement!==this.actionsList&&null!==t.parentElement;)t=t.parentElement;if(t.classList.contains("action-item")){let e=this.focusedItem;this.setFocusedItem(t),e!==this.focusedItem&&this.updateFocus()}}})),this._register(a.q.addTarget(this.actionsList)),this._register((0,d.ko)(this.actionsList,a.B.Tap,e=>{let t=e.initialTarget;if(t&&(0,d.QX)(t,this.actionsList)&&t!==this.actionsList){for(;t.parentElement!==this.actionsList&&null!==t.parentElement;)t=t.parentElement;if(t.classList.contains("action-item")){let e=this.focusedItem;this.setFocusedItem(t),e!==this.focusedItem&&this.updateFocus()}}}));const n={parent:this};this.mnemonics=new Map,this.scrollableElement=this._register(new g.MU(s,{alwaysConsumeMouseWheel:!0,horizontal:2,vertical:3,verticalScrollbarSize:7,handleMouseWheel:!0,useShadows:!0}));const r=this.scrollableElement.getDomNode();r.style.position="",this.styleScrollElement(r,o),this._register((0,d.ko)(s,a.B.Change,e=>{d.fs.stop(e,!0);let t=this.scrollableElement.getScrollPosition().scrollTop;this.scrollableElement.setScrollPosition({scrollTop:t-e.translationY})})),this._register((0,d.ko)(r,d.Bx.MOUSE_UP,e=>{e.preventDefault()}));const l=(0,d.zk)(e);s.style.maxHeight=`${Math.max(10,l.innerHeight-e.getBoundingClientRect().top-35)}px`,t=t.filter((e,o)=>{var s;return(null==(s=i.submenuIds)?void 0:s.has(e.id))?(console.warn(`Found submenu cycle: ${e.id}`),!1):(!(e instanceof b.wv)||o!==t.length-1&&0!==o&&!(t[o-1]instanceof b.wv))&&!0}),this.push(t,{icon:!0,label:!0,isMenu:!0}),e.appendChild(this.scrollableElement.getDomNode()),this.scrollableElement.scanDomNode(),this.viewItems.filter(e=>!(e instanceof N)).forEach((e,t,i)=>{e.updatePositionInSet(t+1,i.length)})}initializeOrUpdateStyleSheet(e,t){this.styleSheet||((0,d.Cl)(e)?this.styleSheet=(0,d.li)(e):(E.globalStyleSheet||(E.globalStyleSheet=(0,d.li)()),this.styleSheet=E.globalStyleSheet)),this.styleSheet.textContent=function(e,t){let i=`
.monaco-menu {
	font-size: 13px;
	border-radius: 5px;
	min-width: 160px;
}

${F(f.W.menuSelection)}
${F(f.W.menuSubmenu)}

.monaco-menu .monaco-action-bar {
	text-align: right;
	overflow: hidden;
	white-space: nowrap;
}

.monaco-menu .monaco-action-bar .actions-container {
	display: flex;
	margin: 0 auto;
	padding: 0;
	width: 100%;
	justify-content: flex-end;
}

.monaco-menu .monaco-action-bar.vertical .actions-container {
	display: inline-block;
}

.monaco-menu .monaco-action-bar.reverse .actions-container {
	flex-direction: row-reverse;
}

.monaco-menu .monaco-action-bar .action-item {
	cursor: pointer;
	display: inline-block;
	transition: transform 50ms ease;
	position: relative;  /* DO NOT REMOVE - this is the key to preventing the ghosting icon bug in Chrome 42 */
}

.monaco-menu .monaco-action-bar .action-item.disabled {
	cursor: default;
}

.monaco-menu .monaco-action-bar .action-item .icon,
.monaco-menu .monaco-action-bar .action-item .codicon {
	display: inline-block;
}

.monaco-menu .monaco-action-bar .action-item .codicon {
	display: flex;
	align-items: center;
}

.monaco-menu .monaco-action-bar .action-label {
	font-size: 11px;
	margin-right: 4px;
}

.monaco-menu .monaco-action-bar .action-item.disabled .action-label,
.monaco-menu .monaco-action-bar .action-item.disabled .action-label:hover {
	color: var(--vscode-disabledForeground);
}

/* Vertical actions */

.monaco-menu .monaco-action-bar.vertical {
	text-align: left;
}

.monaco-menu .monaco-action-bar.vertical .action-item {
	display: block;
}

.monaco-menu .monaco-action-bar.vertical .action-label.separator {
	display: block;
	border-bottom: 1px solid var(--vscode-menu-separatorBackground);
	padding-top: 1px;
	padding: 30px;
}

.monaco-menu .secondary-actions .monaco-action-bar .action-label {
	margin-left: 6px;
}

/* Action Items */
.monaco-menu .monaco-action-bar .action-item.select-container {
	overflow: hidden; /* somehow the dropdown overflows its container, we prevent it here to not push */
	flex: 1;
	max-width: 170px;
	min-width: 60px;
	display: flex;
	align-items: center;
	justify-content: center;
	margin-right: 10px;
}

.monaco-menu .monaco-action-bar.vertical {
	margin-left: 0;
	overflow: visible;
}

.monaco-menu .monaco-action-bar.vertical .actions-container {
	display: block;
}

.monaco-menu .monaco-action-bar.vertical .action-item {
	padding: 0;
	transform: none;
	display: flex;
}

.monaco-menu .monaco-action-bar.vertical .action-item.active {
	transform: none;
}

.monaco-menu .monaco-action-bar.vertical .action-menu-item {
	flex: 1 1 auto;
	display: flex;
	height: 2em;
	align-items: center;
	position: relative;
	margin: 0 4px;
	border-radius: 4px;
}

.monaco-menu .monaco-action-bar.vertical .action-menu-item:hover .keybinding,
.monaco-menu .monaco-action-bar.vertical .action-menu-item:focus .keybinding {
	opacity: unset;
}

.monaco-menu .monaco-action-bar.vertical .action-label {
	flex: 1 1 auto;
	text-decoration: none;
	padding: 0 1em;
	background: none;
	font-size: 12px;
	line-height: 1;
}

.monaco-menu .monaco-action-bar.vertical .keybinding,
.monaco-menu .monaco-action-bar.vertical .submenu-indicator {
	display: inline-block;
	flex: 2 1 auto;
	padding: 0 1em;
	text-align: right;
	font-size: 12px;
	line-height: 1;
}

.monaco-menu .monaco-action-bar.vertical .submenu-indicator {
	height: 100%;
}

.monaco-menu .monaco-action-bar.vertical .submenu-indicator.codicon {
	font-size: 16px !important;
	display: flex;
	align-items: center;
}

.monaco-menu .monaco-action-bar.vertical .submenu-indicator.codicon::before {
	margin-left: auto;
	margin-right: -20px;
}

.monaco-menu .monaco-action-bar.vertical .action-item.disabled .keybinding,
.monaco-menu .monaco-action-bar.vertical .action-item.disabled .submenu-indicator {
	opacity: 0.4;
}

.monaco-menu .monaco-action-bar.vertical .action-label:not(.separator) {
	display: inline-block;
	box-sizing: border-box;
	margin: 0;
}

.monaco-menu .monaco-action-bar.vertical .action-item {
	position: static;
	overflow: visible;
}

.monaco-menu .monaco-action-bar.vertical .action-item .monaco-submenu {
	position: absolute;
}

.monaco-menu .monaco-action-bar.vertical .action-label.separator {
	width: 100%;
	height: 0px !important;
	opacity: 1;
}

.monaco-menu .monaco-action-bar.vertical .action-label.separator.text {
	padding: 0.7em 1em 0.1em 1em;
	font-weight: bold;
	opacity: 1;
}

.monaco-menu .monaco-action-bar.vertical .action-label:hover {
	color: inherit;
}

.monaco-menu .monaco-action-bar.vertical .menu-item-check {
	position: absolute;
	visibility: hidden;
	width: 1em;
	height: 100%;
}

.monaco-menu .monaco-action-bar.vertical .action-menu-item.checked .menu-item-check {
	visibility: visible;
	display: flex;
	align-items: center;
	justify-content: center;
}

/* Context Menu */

.context-view.monaco-menu-container {
	outline: 0;
	border: none;
	animation: fadeIn 0.083s linear;
	-webkit-app-region: no-drag;
}

.context-view.monaco-menu-container :focus,
.context-view.monaco-menu-container .monaco-action-bar.vertical:focus,
.context-view.monaco-menu-container .monaco-action-bar.vertical :focus {
	outline: 0;
}

.hc-black .context-view.monaco-menu-container,
.hc-light .context-view.monaco-menu-container,
:host-context(.hc-black) .context-view.monaco-menu-container,
:host-context(.hc-light) .context-view.monaco-menu-container {
	box-shadow: none;
}

.hc-black .monaco-menu .monaco-action-bar.vertical .action-item.focused,
.hc-light .monaco-menu .monaco-action-bar.vertical .action-item.focused,
:host-context(.hc-black) .monaco-menu .monaco-action-bar.vertical .action-item.focused,
:host-context(.hc-light) .monaco-menu .monaco-action-bar.vertical .action-item.focused {
	background: none;
}

/* Vertical Action Bar Styles */

.monaco-menu .monaco-action-bar.vertical {
	padding: 4px 0;
}

.monaco-menu .monaco-action-bar.vertical .action-menu-item {
	height: 2em;
}

.monaco-menu .monaco-action-bar.vertical .action-label:not(.separator),
.monaco-menu .monaco-action-bar.vertical .keybinding {
	font-size: inherit;
	padding: 0 2em;
	max-height: 100%;
}

.monaco-menu .monaco-action-bar.vertical .menu-item-check {
	font-size: inherit;
	width: 2em;
}

.monaco-menu .monaco-action-bar.vertical .action-label.separator {
	font-size: inherit;
	margin: 5px 0 !important;
	padding: 0;
	border-radius: 0;
}

.linux .monaco-menu .monaco-action-bar.vertical .action-label.separator,
:host-context(.linux) .monaco-menu .monaco-action-bar.vertical .action-label.separator {
	margin-left: 0;
	margin-right: 0;
}

.monaco-menu .monaco-action-bar.vertical .submenu-indicator {
	font-size: 60%;
	padding: 0 1.8em;
}

.linux .monaco-menu .monaco-action-bar.vertical .submenu-indicator,
:host-context(.linux) .monaco-menu .monaco-action-bar.vertical .submenu-indicator {
	height: 100%;
	mask-size: 10px 10px;
	-webkit-mask-size: 10px 10px;
}

.monaco-menu .action-item {
	cursor: default;
}`;if(t){i+=`
			/* Arrows */
			.monaco-scrollable-element > .scrollbar > .scra {
				cursor: pointer;
				font-size: 11px !important;
			}

			.monaco-scrollable-element > .visible {
				opacity: 1;

				/* Background rule added for IE9 - to allow clicks on dom node */
				background:rgba(0,0,0,0);

				transition: opacity 100ms linear;
			}
			.monaco-scrollable-element > .invisible {
				opacity: 0;
				pointer-events: none;
			}
			.monaco-scrollable-element > .invisible.fade {
				transition: opacity 800ms linear;
			}

			/* Scrollable Content Inset Shadow */
			.monaco-scrollable-element > .shadow {
				position: absolute;
				display: none;
			}
			.monaco-scrollable-element > .shadow.top {
				display: block;
				top: 0;
				left: 3px;
				height: 3px;
				width: 100%;
			}
			.monaco-scrollable-element > .shadow.left {
				display: block;
				top: 3px;
				left: 0;
				height: 100%;
				width: 3px;
			}
			.monaco-scrollable-element > .shadow.top-left-corner {
				display: block;
				top: 0;
				left: 0;
				height: 3px;
				width: 3px;
			}
		`;let t=e.scrollbarShadow;t&&(i+=`
				.monaco-scrollable-element > .shadow.top {
					box-shadow: ${t} 0 6px 6px -6px inset;
				}

				.monaco-scrollable-element > .shadow.left {
					box-shadow: ${t} 6px 0 6px -6px inset;
				}

				.monaco-scrollable-element > .shadow.top.left {
					box-shadow: ${t} 6px 6px 6px -6px inset;
				}
			`);let o=e.scrollbarSliderBackground;o&&(i+=`
				.monaco-scrollable-element > .scrollbar > .slider {
					background: ${o};
				}
			`);let s=e.scrollbarSliderHoverBackground;s&&(i+=`
				.monaco-scrollable-element > .scrollbar > .slider:hover {
					background: ${s};
				}
			`);let n=e.scrollbarSliderActiveBackground;n&&(i+=`
				.monaco-scrollable-element > .scrollbar > .slider.active {
					background: ${n};
				}
			`)}return i}(t,(0,d.Cl)(e))}styleScrollElement(e,t){var i,o;let s=null!=(i=t.foregroundColor)?i:"",n=null!=(o=t.backgroundColor)?o:"",r=t.borderColor?`1px solid ${t.borderColor}`:"",l=t.shadowColor?`0 2px 8px ${t.shadowColor}`:"";e.style.outline=r,e.style.borderRadius="5px",e.style.color=s,e.style.backgroundColor=n,e.style.boxShadow=l}getContainer(){return this.scrollableElement.getDomNode()}get onScroll(){return this.scrollableElement.onScroll}focusItemByElement(e){let t=this.focusedItem;this.setFocusedItem(e),t!==this.focusedItem&&this.updateFocus()}setFocusedItem(e){for(let t=0;t<this.actionsList.children.length;t++)if(e===this.actionsList.children[t]){this.focusedItem=t;break}}updateFocus(e){super.updateFocus(e,!0,!0),void 0!==this.focusedItem&&this.scrollableElement.setScrollPosition({scrollTop:Math.round(this.menuElement.scrollTop)})}doGetActionViewItem(e,t,i){if(e instanceof b.wv)return new N(t.context,e,{icon:!0},this.menuStyles);if(e instanceof b.YH){let o=new I(e,e.actions,i,{...t,submenuIds:new Set([...t.submenuIds||[],e.id])},this.menuStyles);if(t.enableMnemonics){let e=o.getMnemonic();if(e&&o.isEnabled()){let t=[];this.mnemonics.has(e)&&(t=this.mnemonics.get(e)),t.push(o),this.mnemonics.set(e,t)}}return o}{let i={enableMnemonics:t.enableMnemonics,useEventAsContext:t.useEventAsContext};if(t.getKeyBinding){let o=t.getKeyBinding(e);if(o){let e=o.getLabel();e&&(i.keybinding=e)}}let o=new B(t.context,e,i,this.menuStyles);if(t.enableMnemonics){let e=o.getMnemonic();if(e&&o.isEnabled()){let t=[];this.mnemonics.has(e)&&(t=this.mnemonics.get(e)),t.push(o),this.mnemonics.set(e,t)}}return o}}}class B extends m.EH{constructor(e,t,i,o){if(i.isMenu=!0,super(t,t,i),this.menuStyle=o,this.options=i,this.options.icon=void 0!==i.icon&&i.icon,this.options.label=void 0===i.label||i.label,this.cssClass="",this.options.label&&i.enableMnemonics){const e=this.action.label;if(e){const t=x.exec(e);t&&(this.mnemonic=(t[1]?t[1]:t[3]).toLocaleLowerCase())}}this.runOnceToEnableMouseUp=new v.uC(()=>{this.element&&(this._register((0,d.ko)(this.element,d.Bx.MOUSE_UP,e=>{(d.fs.stop(e,!0),l.gm)?new c.P((0,d.zk)(this.element),e).rightButton||this.onClick(e):setTimeout(()=>{this.onClick(e)},0)})),this._register((0,d.ko)(this.element,d.Bx.CONTEXT_MENU,e=>{d.fs.stop(e,!0)})))},100),this._register(this.runOnceToEnableMouseUp)}render(e){super.render(e),this.element&&(this.container=e,this.item=(0,d.BC)(this.element,(0,d.$)("a.action-menu-item")),this._action.id===b.wv.ID?this.item.setAttribute("role","presentation"):(this.item.setAttribute("role","menuitem"),this.mnemonic&&this.item.setAttribute("aria-keyshortcuts",`${this.mnemonic}`)),this.check=(0,d.BC)(this.item,(0,d.$)("span.menu-item-check"+y.L.asCSSSelector(f.W.menuSelection))),this.check.setAttribute("role","none"),this.label=(0,d.BC)(this.item,(0,d.$)("span.action-label")),this.options.label&&this.options.keybinding&&((0,d.BC)(this.item,(0,d.$)("span.keybinding")).textContent=this.options.keybinding),this.runOnceToEnableMouseUp.schedule(),this.updateClass(),this.updateLabel(),this.updateTooltip(),this.updateEnabled(),this.updateChecked(),this.applyStyle())}blur(){super.blur(),this.applyStyle()}focus(){var e;super.focus(),null==(e=this.item)||e.focus(),this.applyStyle()}updatePositionInSet(e,t){this.item&&(this.item.setAttribute("aria-posinset",`${e}`),this.item.setAttribute("aria-setsize",`${t}`))}updateLabel(){var e;if(this.label&&this.options.label){(0,d.w_)(this.label);let t=(0,A.pS)(this.action.label);if(t){let i=function(e){let t=x.exec(e);if(!t)return e;let i=!t[1];return e.replace(x,i?"$2$3":"").trim()}(t);this.options.enableMnemonics||(t=i),this.label.setAttribute("aria-label",i.replace(/&&/g,"&"));let o=x.exec(t);if(o){t=S.ih(t),k.lastIndex=0;let i=k.exec(t);for(;i&&i[1];)i=k.exec(t);i?this.label.append(S.NB(t.substr(0,i.index).replace(/&amp;&amp;/g,"&amp;")," "),(0,d.$)("u",{"aria-hidden":"true"},i[3]),S.BO(t.substr(i.index+i[0].length).replace(/&amp;&amp;/g,"&amp;")," ")):this.label.innerText=t.replace(/&amp;&amp;/g,"&amp;").trim(),null==(e=this.item)||e.setAttribute("aria-keyshortcuts",(o[1]?o[1]:o[3]).toLocaleLowerCase())}else this.label.innerText=t.replace(/&&/g,"&").trim()}}}updateTooltip(){}updateClass(){this.cssClass&&this.item&&this.item.classList.remove(...this.cssClass.split(" ")),this.options.icon&&this.label?(this.cssClass=this.action.class||"",this.label.classList.add("icon"),this.cssClass&&this.label.classList.add(...this.cssClass.split(" ")),this.updateEnabled()):this.label&&this.label.classList.remove("icon")}updateEnabled(){this.action.enabled?(this.element&&(this.element.classList.remove("disabled"),this.element.removeAttribute("aria-disabled")),this.item&&(this.item.classList.remove("disabled"),this.item.removeAttribute("aria-disabled"),this.item.tabIndex=0)):(this.element&&(this.element.classList.add("disabled"),this.element.setAttribute("aria-disabled","true")),this.item&&(this.item.classList.add("disabled"),this.item.setAttribute("aria-disabled","true")))}updateChecked(){if(!this.item)return;let e=this.action.checked;this.item.classList.toggle("checked",!!e),void 0!==e?(this.item.setAttribute("role","menuitemcheckbox"),this.item.setAttribute("aria-checked",e?"true":"false")):(this.item.setAttribute("role","menuitem"),this.item.setAttribute("aria-checked",""))}getMnemonic(){return this.mnemonic}applyStyle(){let e=this.element&&this.element.classList.contains("focused"),t=e&&this.menuStyle.selectionForegroundColor?this.menuStyle.selectionForegroundColor:this.menuStyle.foregroundColor,i=e&&this.menuStyle.selectionBackgroundColor?this.menuStyle.selectionBackgroundColor:void 0,o=e&&this.menuStyle.selectionBorderColor?`1px solid ${this.menuStyle.selectionBorderColor}`:"",s=e&&this.menuStyle.selectionBorderColor?"-1px":"";this.item&&(this.item.style.color=null!=t?t:"",this.item.style.backgroundColor=null!=i?i:"",this.item.style.outline=o,this.item.style.outlineOffset=s),this.check&&(this.check.style.color=null!=t?t:"")}}class I extends B{constructor(e,t,i,o,s){super(e,e,o,s),this.submenuActions=t,this.parentData=i,this.submenuOptions=o,this.mysubmenu=null,this.submenuDisposables=this._register(new C.Cm),this.mouseOver=!1,this.expandDirection=o&&void 0!==o.expandDirection?o.expandDirection:{horizontal:n.Right,vertical:r.Below},this.showScheduler=new v.uC(()=>{this.mouseOver&&(this.cleanupExistingSubmenu(!1),this.createSubmenu(!1))},250),this.hideScheduler=new v.uC(()=>{this.element&&!(0,d.QX)((0,d.bq)(),this.element)&&this.parentData.submenu===this.mysubmenu&&(this.parentData.parent.focus(!1),this.cleanupExistingSubmenu(!0))},750)}render(e){super.render(e),this.element&&(this.item&&(this.item.classList.add("monaco-submenu-item"),this.item.tabIndex=0,this.item.setAttribute("aria-haspopup","true"),this.updateAriaExpanded("false"),this.submenuIndicator=(0,d.BC)(this.item,(0,d.$)("span.submenu-indicator"+y.L.asCSSSelector(f.W.menuSubmenu))),this.submenuIndicator.setAttribute("aria-hidden","true")),this._register((0,d.ko)(this.element,d.Bx.KEY_UP,e=>{let t=new h.Z(e);(t.equals(17)||t.equals(3))&&(d.fs.stop(e,!0),this.createSubmenu(!0))})),this._register((0,d.ko)(this.element,d.Bx.KEY_DOWN,e=>{let t=new h.Z(e);(0,d.bq)()===this.item&&(t.equals(17)||t.equals(3))&&d.fs.stop(e,!0)})),this._register((0,d.ko)(this.element,d.Bx.MOUSE_OVER,e=>{this.mouseOver||(this.mouseOver=!0,this.showScheduler.schedule())})),this._register((0,d.ko)(this.element,d.Bx.MOUSE_LEAVE,e=>{this.mouseOver=!1})),this._register((0,d.ko)(this.element,d.Bx.FOCUS_OUT,e=>{this.element&&!(0,d.QX)((0,d.bq)(),this.element)&&this.hideScheduler.schedule()})),this._register(this.parentData.parent.onScroll(()=>{this.parentData.submenu===this.mysubmenu&&(this.parentData.parent.focus(!1),this.cleanupExistingSubmenu(!0))})))}updateEnabled(){}onClick(e){d.fs.stop(e,!0),this.cleanupExistingSubmenu(!1),this.createSubmenu(!0)}cleanupExistingSubmenu(e){if(this.parentData.submenu&&(e||this.parentData.submenu!==this.mysubmenu)){try{this.parentData.submenu.dispose()}catch(e){}this.parentData.submenu=void 0,this.updateAriaExpanded("false"),this.submenuContainer&&(this.submenuDisposables.clear(),this.submenuContainer=void 0)}}calculateSubmenuMenuLayout(e,t,i,o){let s={top:0,left:0};return s.left=(0,p.Zp)(e.width,t.width,{position:+(o.horizontal!==n.Right),offset:i.left,size:i.width}),s.left>=i.left&&s.left<i.left+i.width&&(i.left+10+t.width<=e.width&&(s.left=i.left+10),i.top+=10,i.height=0),s.top=(0,p.Zp)(e.height,t.height,{position:0,offset:i.top,size:0}),s.top+t.height===i.top&&s.top+i.height+t.height<=e.height&&(s.top+=i.height),s}createSubmenu(e=!0){if(this.element)if(this.parentData.submenu)this.parentData.submenu.focus(!1);else{this.updateAriaExpanded("true"),this.submenuContainer=(0,d.BC)(this.element,(0,d.$)("div.monaco-submenu")),this.submenuContainer.classList.add("menubar-menu-items-holder","context-view");let t=parseFloat((0,d.zk)(this.parentData.parent.domNode).getComputedStyle(this.parentData.parent.domNode).paddingTop||"0")||0;this.submenuContainer.style.zIndex="1",this.submenuContainer.style.position="fixed",this.submenuContainer.style.top="0",this.submenuContainer.style.left="0",this.parentData.submenu=new E(this.submenuContainer,this.submenuActions.length?this.submenuActions:[new b.HJ],this.submenuOptions,this.menuStyle);let i=this.element.getBoundingClientRect(),o={top:i.top-t,left:i.left,height:i.height+2*t,width:i.width},s=this.submenuContainer.getBoundingClientRect(),n=(0,d.zk)(this.element),{top:r,left:l}=this.calculateSubmenuMenuLayout(new d.fg(n.innerWidth,n.innerHeight),d.fg.lift(s),o,this.expandDirection);this.submenuContainer.style.left=`${l-s.left}px`,this.submenuContainer.style.top=`${r-s.top}px`,this.submenuDisposables.add((0,d.ko)(this.submenuContainer,d.Bx.KEY_UP,e=>{new h.Z(e).equals(15)&&(d.fs.stop(e,!0),this.parentData.parent.focus(),this.cleanupExistingSubmenu(!0))})),this.submenuDisposables.add((0,d.ko)(this.submenuContainer,d.Bx.KEY_DOWN,e=>{new h.Z(e).equals(15)&&d.fs.stop(e,!0)})),this.submenuDisposables.add(this.parentData.submenu.onDidCancel(()=>{this.parentData.parent.focus(),this.cleanupExistingSubmenu(!0)})),this.parentData.submenu.focus(e),this.mysubmenu=this.parentData.submenu}}updateAriaExpanded(e){var t;this.item&&(null==(t=this.item)||t.setAttribute("aria-expanded",e))}applyStyle(){super.applyStyle();let e=this.element&&this.element.classList.contains("focused")&&this.menuStyle.selectionForegroundColor?this.menuStyle.selectionForegroundColor:this.menuStyle.foregroundColor;this.submenuIndicator&&(this.submenuIndicator.style.color=null!=e?e:"")}dispose(){super.dispose(),this.hideScheduler.dispose(),this.mysubmenu&&(this.mysubmenu.dispose(),this.mysubmenu=null),this.submenuContainer&&(this.submenuContainer=void 0)}}class N extends m.Z4{constructor(e,t,i,o){super(e,t,i),this.menuStyles=o}render(e){super.render(e),this.label&&(this.label.style.borderBottomColor=this.menuStyles.separatorColor?`${this.menuStyles.separatorColor}`:"")}}function F(e){let t=(0,w.J)()[e.id];return`.codicon-${e.id}:before { content: '\\${t.toString(16)}'; }`}i.d(t,{W1:()=>E})},767119(e,t,i){var o=i(785072),s=i.n(o),n=i(697825),r=i.n(n),l=i(777659),a=i.n(l),d=i(655056),h=i.n(d),c=i(510540),u=i.n(c),m=i(341113),p=i.n(m),g=i(767340),b={};b.styleTagTransform=p(),b.setAttributes=h(),b.insert=a().bind(null,"head"),b.domAPI=r(),b.insertStyleElement=u(),s()(g.A,b),g.A&&g.A.locals&&g.A.locals}}]);
//# sourceMappingURL=27878-72479628a0bc0e65-4993d560f6569e76.js.map
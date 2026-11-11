performance.mark("js-parse-end:46424-5d18dbe7a2f6e418.js");
"use strict";(globalThis.rspackChunk_github_ui_github_ui=globalThis.rspackChunk_github_ui_github_ui||[]).push([[46424],{946835(e,t,i){var o=i(571354),r=i.n(o),s=i(576314),n=i.n(s)()(r());n.push([e.id,`/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

.monaco-editor .rendered-markdown kbd {
	background-color: var(--vscode-keybindingLabel-background);
	color: var(--vscode-keybindingLabel-foreground);
	border-style: solid;
	border-width: 1px;
	border-radius: 3px;
	border-color: var(--vscode-keybindingLabel-border);
	border-bottom-color: var(--vscode-keybindingLabel-bottomBorder);
	box-shadow: inset 0 -1px 0 var(--vscode-widget-shadow);
	vertical-align: middle;
	padding: 1px 3px;
}

.rendered-markdown li:has(input[type=checkbox]) {
	list-style-type: none;
}
`,"",{version:3,sources:["webpack://./node_modules/monaco-editor/esm/vs/editor/browser/widget/markdownRenderer/browser/renderedMarkdown.css"],names:[],mappings:"AAAA;;;+FAG+F;;AAE/F;CACC,0DAA0D;CAC1D,+CAA+C;CAC/C,mBAAmB;CACnB,iBAAiB;CACjB,kBAAkB;CAClB,kDAAkD;CAClD,+DAA+D;CAC/D,sDAAsD;CACtD,sBAAsB;CACtB,gBAAgB;AACjB;;AAEA;CACC,qBAAqB;AACtB",sourcesContent:["/*---------------------------------------------------------------------------------------------\n *  Copyright (c) Microsoft Corporation. All rights reserved.\n *  Licensed under the MIT License. See License.txt in the project root for license information.\n *--------------------------------------------------------------------------------------------*/\n\n.monaco-editor .rendered-markdown kbd {\n	background-color: var(--vscode-keybindingLabel-background);\n	color: var(--vscode-keybindingLabel-foreground);\n	border-style: solid;\n	border-width: 1px;\n	border-radius: 3px;\n	border-color: var(--vscode-keybindingLabel-border);\n	border-bottom-color: var(--vscode-keybindingLabel-bottomBorder);\n	box-shadow: inset 0 -1px 0 var(--vscode-widget-shadow);\n	vertical-align: middle;\n	padding: 1px 3px;\n}\n\n.rendered-markdown li:has(input[type=checkbox]) {\n	list-style-type: none;\n}\n"],sourceRoot:""}]),i.d(t,{},{A:n})},846514(e,t,i){var o=i(571354),r=i.n(o),s=i(576314),n=i.n(s)()(r());n.push([e.id,`/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

.monaco-component.multiDiffEditor {
	background: var(--vscode-multiDiffEditor-background);
	overflow-y: hidden;

	.active {
		--vscode-multiDiffEditor-border: var(--vscode-focusBorder);
	}

	.multiDiffEntry {
		display: flex;
		flex-direction: column;
		flex: 1;
		overflow: hidden;


		.collapse-button {
			margin: 0 5px;
			cursor: pointer;

			a {
				display: block;
			}
		}

		.header {
			z-index: 1000;
			background: var(--vscode-editor-background);

			&:not(.collapsed) .header-content {
				border-bottom: 1px solid var(--vscode-sideBarSectionHeader-border);
			}

			.header-content {
				margin: 8px 0px 0px 0px;
				padding: 4px 5px;

				border-top: 1px solid var(--vscode-multiDiffEditor-border);

				display: flex;
				align-items: center;

				color: var(--vscode-foreground);
				background: var(--vscode-multiDiffEditor-headerBackground);

				&.shadow {
					box-shadow: var(--vscode-scrollbar-shadow) 0px 6px 6px -6px;
				}

				.file-path {
					display: flex;
					flex: 1;
					min-width: 0;

					.title {
						font-size: 14px;
						line-height: 22px;

						&.original {
							flex: 1;
							min-width: 0;
							text-overflow: ellipsis;
						}
					}

					.status {
						font-weight: 600;
						opacity: 0.75;
						margin: 0px 10px;
						line-height: 22px;

						/*
							TODO@hediet: move colors from git extension to core!
						&.renamed {
							color: v ar(--vscode-gitDecoration-renamedResourceForeground);
						}

						&.deleted {
							color: v ar(--vscode-gitDecoration-deletedResourceForeground);
						}

						&.added {
							color: v ar(--vscode-gitDecoration-addedResourceForeground);
						}
						*/
					}
				}

				.actions {
					padding: 0 8px;
				}
			}


		}

		.editorParent {
			flex: 1;
			display: flex;
			flex-direction: column;

			border-bottom: 1px solid var(--vscode-multiDiffEditor-border);
			overflow: hidden;
		}

		.editorContainer {
			flex: 1;
		}
	}
}
`,"",{version:3,sources:["webpack://./node_modules/monaco-editor/esm/vs/editor/browser/widget/multiDiffEditor/style.css"],names:[],mappings:"AAAA;;;+FAG+F;;AAE/F;CACC,oDAAoD;CACpD,kBAAkB;;CAElB;EACC,0DAA0D;CAC3D;;CAEA;EACC,aAAa;EACb,sBAAsB;EACtB,OAAO;EACP,gBAAgB;;;EAGhB;GACC,aAAa;GACb,eAAe;;GAEf;IACC,cAAc;GACf;EACD;;EAEA;GACC,aAAa;GACb,2CAA2C;;GAE3C;IACC,kEAAkE;GACnE;;GAEA;IACC,uBAAuB;IACvB,gBAAgB;;IAEhB,0DAA0D;;IAE1D,aAAa;IACb,mBAAmB;;IAEnB,+BAA+B;IAC/B,0DAA0D;;IAE1D;KACC,2DAA2D;IAC5D;;IAEA;KACC,aAAa;KACb,OAAO;KACP,YAAY;;KAEZ;MACC,eAAe;MACf,iBAAiB;;MAEjB;OACC,OAAO;OACP,YAAY;OACZ,uBAAuB;MACxB;KACD;;KAEA;MACC,gBAAgB;MAChB,aAAa;MACb,gBAAgB;MAChB,iBAAiB;;MAEjB;;;;;;;;;;;;;OAaC;KACF;IACD;;IAEA;KACC,cAAc;IACf;GACD;;;EAGD;;EAEA;GACC,OAAO;GACP,aAAa;GACb,sBAAsB;;GAEtB,6DAA6D;GAC7D,gBAAgB;EACjB;;EAEA;GACC,OAAO;EACR;CACD;AACD",sourcesContent:["/*---------------------------------------------------------------------------------------------\n *  Copyright (c) Microsoft Corporation. All rights reserved.\n *  Licensed under the MIT License. See License.txt in the project root for license information.\n *--------------------------------------------------------------------------------------------*/\n\n.monaco-component.multiDiffEditor {\n	background: var(--vscode-multiDiffEditor-background);\n	overflow-y: hidden;\n\n	.active {\n		--vscode-multiDiffEditor-border: var(--vscode-focusBorder);\n	}\n\n	.multiDiffEntry {\n		display: flex;\n		flex-direction: column;\n		flex: 1;\n		overflow: hidden;\n\n\n		.collapse-button {\n			margin: 0 5px;\n			cursor: pointer;\n\n			a {\n				display: block;\n			}\n		}\n\n		.header {\n			z-index: 1000;\n			background: var(--vscode-editor-background);\n\n			&:not(.collapsed) .header-content {\n				border-bottom: 1px solid var(--vscode-sideBarSectionHeader-border);\n			}\n\n			.header-content {\n				margin: 8px 0px 0px 0px;\n				padding: 4px 5px;\n\n				border-top: 1px solid var(--vscode-multiDiffEditor-border);\n\n				display: flex;\n				align-items: center;\n\n				color: var(--vscode-foreground);\n				background: var(--vscode-multiDiffEditor-headerBackground);\n\n				&.shadow {\n					box-shadow: var(--vscode-scrollbar-shadow) 0px 6px 6px -6px;\n				}\n\n				.file-path {\n					display: flex;\n					flex: 1;\n					min-width: 0;\n\n					.title {\n						font-size: 14px;\n						line-height: 22px;\n\n						&.original {\n							flex: 1;\n							min-width: 0;\n							text-overflow: ellipsis;\n						}\n					}\n\n					.status {\n						font-weight: 600;\n						opacity: 0.75;\n						margin: 0px 10px;\n						line-height: 22px;\n\n						/*\n							TODO@hediet: move colors from git extension to core!\n						&.renamed {\n							color: v ar(--vscode-gitDecoration-renamedResourceForeground);\n						}\n\n						&.deleted {\n							color: v ar(--vscode-gitDecoration-deletedResourceForeground);\n						}\n\n						&.added {\n							color: v ar(--vscode-gitDecoration-addedResourceForeground);\n						}\n						*/\n					}\n				}\n\n				.actions {\n					padding: 0 8px;\n				}\n			}\n\n\n		}\n\n		.editorParent {\n			flex: 1;\n			display: flex;\n			flex-direction: column;\n\n			border-bottom: 1px solid var(--vscode-multiDiffEditor-border);\n			overflow: hidden;\n		}\n\n		.editorContainer {\n			flex: 1;\n		}\n	}\n}\n"],sourceRoot:""}]),i.d(t,{},{A:n})},734129(e,t,i){i.d(t,{T:()=>B,i:()=>M});var o,r=i(827067),s=i(813021),n=i(494327),d=i(2106),l=i(310998),a=i(785072),h=i.n(a),c=i(697825),g=i.n(c),u=i(777659),m=i.n(u),f=i(655056),p=i.n(f),_=i(510540),v=i.n(_),A=i(341113),b=i.n(A),C=i(946835),w={};w.styleTagTransform=b(),w.setAttributes=p(),w.insert=m().bind(null,"head"),w.domAPI=g(),w.insertStyleElement=v(),h()(C.A,w),C.A&&C.A.locals&&C.A.locals;var y=i(225837),x=i(677922),D=i(154957),E=i(1458),k=i(854435),S=function(e,t){return function(i,o){t(i,o,e)}};let B=o=class{constructor(e,t,i){this._options=e,this._languageService=t,this._openerService=i,this._onDidRenderAsync=new d.vl,this.onDidRenderAsync=this._onDidRenderAsync.event}dispose(){this._onDidRenderAsync.dispose()}render(e,t,i){if(!e)return{element:document.createElement("span"),dispose:()=>{}};let o=new l.Cm,s=o.add((0,r.Gc)(e,{...this._getRenderOptions(e,o),...t},i));return s.element.classList.add("rendered-markdown"),{element:s.element,dispose:()=>o.dispose()}}_getRenderOptions(e,t){return{codeBlockRenderer:async(e,t)=>{var i,r,s;let n;e?n=this._languageService.getLanguageIdByLanguageName(e):this._options.editor&&(n=null==(i=this._options.editor.getModel())?void 0:i.getLanguageId()),n||(n=D.vH);let d=await (0,E.Yj)(this._languageService,t,n),l=document.createElement("span");if(l.innerHTML=null!=(s=null==(r=o._ttpTokenizer)?void 0:r.createHTML(d))?s:d,this._options.editor){let e=this._options.editor.getOption(50);(0,y.M)(l,e)}else this._options.codeBlockFontFamily&&(l.style.fontFamily=this._options.codeBlockFontFamily);return void 0!==this._options.codeBlockFontSize&&(l.style.fontSize=this._options.codeBlockFontSize),l},asyncRenderCallback:()=>this._onDidRenderAsync.fire(),actionHandler:{callback:t=>M(this._openerService,t,e.isTrusted),disposables:t}}}};async function M(e,t,i){try{var o;return await e.open(t,{fromUserGesture:!0,allowContributedOpeners:!0,allowCommands:(o=i,!0===o||!!(o&&Array.isArray(o.enabledCommands))&&o.enabledCommands)})}catch(e){return(0,n.dz)(e),!1}}B._ttpTokenizer=(0,s.H)("tokenizeToString",{createHTML:e=>e}),B=o=function(e,t,i,o){var r,s=arguments.length,n=s<3?t:null===o?o=Object.getOwnPropertyDescriptor(t,i):o;if("object"==typeof Reflect&&"function"==typeof Reflect.decorate)n=Reflect.decorate(e,t,i,o);else for(var d=e.length-1;d>=0;d--)(r=e[d])&&(n=(s<3?r(n):s>3?r(t,i,n):r(t,i))||n);return s>3&&n&&Object.defineProperty(t,i,n),n}([S(1,x.L),S(2,k.C)],B)},395707(e,t,i){i.d(t,{c:()=>X});var o,r,s=i(310998),n=i(724288),d=i(502744),l=i(614333),a=i(82208),h=i(413338),c=i(597393),g=i(494327),u=i(834442),m=i(994513),f=i(785072),p=i.n(f),_=i(697825),v=i.n(_),A=i(777659),b=i.n(A),C=i(655056),w=i.n(C),y=i(510540),x=i.n(y),D=i(341113),E=i.n(D),k=i(846514),S={};S.styleTagTransform=E(),S.setAttributes=w(),S.insert=b().bind(null,"head"),S.domAPI=v(),S.insertStyleElement=x(),p()(k.A,S),k.A&&k.A.locals&&k.A.locals;var B=i(172532),M=i(93702),L=i(538122),I=i(309325),O=i(182399),R=i(30657),F=i(710387),T=i(126048),j=i(822623),H=i(465508),P=i(358067),W=i(716551),G=i(244395);class U{constructor(e,t){this.viewModel=e,this.deltaScrollVertical=t}getId(){return this.viewModel}}let Y=class extends s.jG{constructor(e,t,i,o){super(),this._container=e,this._overflowWidgetsDomNode=t,this._workbenchUIElementFactory=i,this._instantiationService=o,this._viewModel=(0,u.FY)(this,void 0),this._collapsed=(0,n.un)(this,e=>{var t;return null==(t=this._viewModel.read(e))?void 0:t.collapsed.read(e)}),this._editorContentHeight=(0,u.FY)(this,500),this.contentHeight=(0,n.un)(this,e=>(this._collapsed.read(e)?0:this._editorContentHeight.read(e))+this._outerEditorHeight),this._modifiedContentWidth=(0,u.FY)(this,0),this._modifiedWidth=(0,u.FY)(this,0),this._originalContentWidth=(0,u.FY)(this,0),this._originalWidth=(0,u.FY)(this,0),this.maxScroll=(0,n.un)(this,e=>{let t=this._modifiedContentWidth.read(e)-this._modifiedWidth.read(e),i=this._originalContentWidth.read(e)-this._originalWidth.read(e);return t>i?{maxScroll:t,width:this._modifiedWidth.read(e)}:{maxScroll:i,width:this._originalWidth.read(e)}}),this._elements=(0,l.h)("div.multiDiffEntry",[(0,l.h)("div.header@header",[(0,l.h)("div.header-content",[(0,l.h)("div.collapse-button@collapseButton"),(0,l.h)("div.file-path",[(0,l.h)("div.title.modified.show-file-icons@primaryPath",[]),(0,l.h)("div.status.deleted@status",["R"]),(0,l.h)("div.title.original.show-file-icons@secondaryPath",[])]),(0,l.h)("div.actions@actions")])]),(0,l.h)("div.editorParent",[(0,l.h)("div.editorContainer@editor")])]),this.editor=this._register(this._instantiationService.createInstance(j.T,this._elements.editor,{overflowWidgetsDomNode:this._overflowWidgetsDomNode},{})),this.isModifedFocused=K(this.editor.getModifiedEditor()),this.isOriginalFocused=K(this.editor.getOriginalEditor()),this.isFocused=(0,n.un)(this,e=>this.isModifedFocused.read(e)||this.isOriginalFocused.read(e)),this._resourceLabel=this._workbenchUIElementFactory.createResourceLabel?this._register(this._workbenchUIElementFactory.createResourceLabel(this._elements.primaryPath)):void 0,this._resourceLabel2=this._workbenchUIElementFactory.createResourceLabel?this._register(this._workbenchUIElementFactory.createResourceLabel(this._elements.secondaryPath)):void 0,this._dataStore=new s.Cm,this._headerHeight=40,this._lastScrollTop=-1,this._isSettingScrollTop=!1;const r=new F.$(this._elements.collapseButton,{});this._register((0,n.fm)(e=>{r.element.className="",r.icon=this._collapsed.read(e)?T.W.chevronRight:T.W.chevronDown})),this._register(r.onDidClick(()=>{var e;null==(e=this._viewModel.get())||e.collapsed.set(!this._collapsed.get(),void 0)})),this._register((0,n.fm)(e=>{this._elements.editor.style.display=this._collapsed.read(e)?"none":"block"})),this._register(this.editor.getModifiedEditor().onDidLayoutChange(e=>{let t=this.editor.getModifiedEditor().getLayoutInfo().contentWidth;this._modifiedWidth.set(t,void 0)})),this._register(this.editor.getOriginalEditor().onDidLayoutChange(e=>{let t=this.editor.getOriginalEditor().getLayoutInfo().contentWidth;this._originalWidth.set(t,void 0)})),this._register(this.editor.onDidContentSizeChange(e=>{(0,u.YY)(t=>{this._editorContentHeight.set(e.contentHeight,t),this._modifiedContentWidth.set(this.editor.getModifiedEditor().getContentWidth(),t),this._originalContentWidth.set(this.editor.getOriginalEditor().getContentWidth(),t)})})),this._register(this.editor.getOriginalEditor().onDidScrollChange(e=>{if(this._isSettingScrollTop||!e.scrollTopChanged||!this._data)return;let t=e.scrollTop-this._lastScrollTop;this._data.deltaScrollVertical(t)})),this._register((0,n.fm)(e=>{var t;let i=null==(t=this._viewModel.read(e))?void 0:t.isActive.read(e);this._elements.root.classList.toggle("active",i)})),this._container.appendChild(this._elements.root),this._outerEditorHeight=this._headerHeight,this._register(this._instantiationService.createInstance(H.m,this._elements.actions,P.D8.MultiDiffEditorFileToolbar,{actionRunner:this._register(new W.I(()=>{var e;return null==(e=this._viewModel.get())?void 0:e.modifiedUri})),menuOptions:{shouldForwardArgs:!0},toolbarOptions:{primaryGroup:e=>e.startsWith("navigation")},actionViewItemProvider:(e,t)=>(0,G.rN)(o,e,t)}))}setScrollLeft(e){this._modifiedContentWidth.get()-this._modifiedWidth.get()>this._originalContentWidth.get()-this._originalWidth.get()?this.editor.getModifiedEditor().setScrollLeft(e):this.editor.getOriginalEditor().setScrollLeft(e)}setData(e){function t(e){return{...e,scrollBeyondLastLine:!1,hideUnchangedRegions:{enabled:!0},scrollbar:{vertical:"hidden",horizontal:"hidden",handleMouseWheel:!1,useShadows:!1},renderOverviewRuler:!1,fixedOverflowWidgets:!0,overviewRulerBorder:!1}}this._data=e;let i=e.viewModel.entry.value;i.onOptionsDidChange&&this._dataStore.add(i.onOptionsDidChange(()=>{var e;this.editor.updateOptions(t(null!=(e=i.options)?e:{}))})),(0,u.YY)(o=>{var r,s,n,d;null==(r=this._resourceLabel)||r.setUri(null!=(s=e.viewModel.modifiedUri)?s:e.viewModel.originalUri,{strikethrough:void 0===e.viewModel.modifiedUri});let l=!1,a=!1,h=!1,c="";e.viewModel.modifiedUri&&e.viewModel.originalUri&&e.viewModel.modifiedUri.path!==e.viewModel.originalUri.path?(c="R",l=!0):e.viewModel.modifiedUri?e.viewModel.originalUri||(c="A",h=!0):(c="D",a=!0),this._elements.status.classList.toggle("renamed",l),this._elements.status.classList.toggle("deleted",a),this._elements.status.classList.toggle("added",h),this._elements.status.innerText=c,null==(n=this._resourceLabel2)||n.setUri(l?e.viewModel.originalUri:void 0,{strikethrough:!0}),this._dataStore.clear(),this._viewModel.set(e.viewModel,o),this.editor.setModel(e.viewModel.diffEditorViewModel,o),this.editor.updateOptions(t(null!=(d=i.options)?d:{}))})}render(e,t,i,o){this._elements.root.style.visibility="visible",this._elements.root.style.top=`${e.start}px`,this._elements.root.style.height=`${e.length}px`,this._elements.root.style.width=`${t}px`,this._elements.root.style.position="absolute";let r=e.length-this._headerHeight,s=Math.max(0,Math.min(o.start-e.start,r));this._elements.header.style.transform=`translateY(${s}px)`,(0,u.YY)(i=>{this.editor.layout({width:t-16-2,height:e.length-this._outerEditorHeight})});try{this._isSettingScrollTop=!0,this._lastScrollTop=i,this.editor.getOriginalEditor().setScrollTop(i)}finally{this._isSettingScrollTop=!1}this._elements.header.classList.toggle("shadow",s>0||i>0),this._elements.header.classList.toggle("collapsed",s===r)}hide(){this._elements.root.style.top="-100000px",this._elements.root.style.visibility="hidden"}};function K(e){return(0,n.y0)(t=>{let i=new s.Cm;return i.add(e.onDidFocusEditorWidget(()=>t(!0))),i.add(e.onDidBlurEditorWidget(()=>t(!1))),i},()=>e.hasTextFocus())}Y=function(e,t,i,o){var r,s=arguments.length,n=s<3?t:null===o?o=Object.getOwnPropertyDescriptor(t,i):o;if("object"==typeof Reflect&&"function"==typeof Reflect.decorate)n=Reflect.decorate(e,t,i,o);else for(var d=e.length-1;d>=0;d--)(r=e[d])&&(n=(s<3?r(n):s>3?r(t,i,n):r(t,i))||n);return s>3&&n&&Object.defineProperty(t,i,n),n}([(o=O._Y,function(e,t){o(e,t,3)})],Y);class z{constructor(e){this._create=e,this._unused=new Set,this._used=new Set,this._itemData=new Map}getUnusedObj(e){var t;let i;if(0===this._unused.size)i=this._create(e),this._itemData.set(i,e);else{let o=[...this._unused.values()];i=null!=(t=o.find(t=>this._itemData.get(t).getId()===e.getId()))?t:o[0],this._unused.delete(i),this._itemData.set(i,e),i.setData(e)}return this._used.add(i),{object:i,dispose:()=>{this._used.delete(i),this._unused.size>5?i.dispose():this._unused.add(i)}}}dispose(){for(let e of this._used)e.dispose();for(let e of this._unused)e.dispose();this._used.clear(),this._unused.clear()}}var N=function(e,t){return function(i,o){t(i,o,e)}};let V=class extends s.jG{constructor(e,t,i,o,r,f){super(),this._element=e,this._dimension=t,this._viewModel=i,this._workbenchUIElementFactory=o,this._parentContextKeyService=r,this._parentInstantiationService=f,this._elements=(0,l.h)("div.monaco-component.multiDiffEditor",[(0,l.h)("div@content",{style:{overflow:"hidden"}}),(0,l.h)("div.monaco-editor@overflowWidgetsDomNode",{})]),this._sizeObserver=this._register(new d.pN(this._element,void 0)),this._objectPool=this._register(new z(e=>{let t=this._instantiationService.createInstance(Y,this._elements.content,this._elements.overflowWidgetsDomNode,this._workbenchUIElementFactory);return t.setData(e),t})),this._scrollable=this._register(new m.yE({forceIntegerValues:!1,scheduleAtNextAnimationFrame:e=>(0,l.PG)((0,l.zk)(this._element),e),smoothScrollDuration:100})),this._scrollableElement=this._register(new a.oO(this._elements.root,{vertical:1,horizontal:1,useShadows:!1},this._scrollable)),this.scrollTop=(0,n.y0)(this._scrollableElement.onScroll,()=>this._scrollableElement.getScrollPosition().scrollTop),this.scrollLeft=(0,n.y0)(this._scrollableElement.onScroll,()=>this._scrollableElement.getScrollPosition().scrollLeft),this._viewItemsInfo=(0,n.rm)(this,(e,t)=>{let i=this._viewModel.read(e);if(!i)return{items:[],getItem:e=>{throw new g.D7}};let o=i.items.read(e),r=new Map;return{items:o.map(e=>{var i;let o=t.add(new $(e,this._objectPool,this.scrollLeft,e=>{this._scrollableElement.setScrollPosition({scrollTop:this._scrollableElement.getScrollPosition().scrollTop+e})})),s=null==(i=this._lastDocStates)?void 0:i[o.getKey()];return s&&(0,u.Rn)(e=>{o.setViewState(s,e)}),r.set(e,o),o}),getItem:e=>r.get(e)}}),this._viewItems=this._viewItemsInfo.map(this,e=>e.items),this._spaceBetweenPx=0,this._totalHeight=this._viewItems.map(this,(e,t)=>e.reduce((e,i)=>e+i.contentHeight.read(t)+this._spaceBetweenPx,0)),this._contextKeyService=this._register(this._parentContextKeyService.createScoped(this._element)),this._instantiationService=this._parentInstantiationService.createChild(new R.a([I.fN,this._contextKeyService])),this._lastDocStates={},this._contextKeyService.createKey(L.R.inMultiDiffEditor.key,!0),this._register((0,n.yC)((e,t)=>{let i=this._viewModel.read(e);if(i&&i.contextKeys)for(let[e,o]of Object.entries(i.contextKeys)){let i=this._contextKeyService.createKey(e,void 0);i.set(o),t.add((0,s.s)(()=>i.reset()))}}));const p=this._parentContextKeyService.createKey(L.R.multiDiffEditorAllCollapsed.key,!1);this._register((0,n.fm)(e=>{let t=this._viewModel.read(e);if(t){let i=t.items.read(e).every(t=>t.collapsed.read(e));p.set(i)}})),this._register((0,n.fm)(e=>{let t=this._dimension.read(e);this._sizeObserver.observe(t)})),this._elements.content.style.position="relative",this._register((0,n.fm)(e=>{let t=this._sizeObserver.height.read(e);this._elements.root.style.height=`${t}px`;let i=this._totalHeight.read(e);this._elements.content.style.height=`${i}px`;let o=this._sizeObserver.width.read(e),r=o,s=this._viewItems.read(e),n=(0,c.Cn)(s,(0,h.VE)(t=>t.maxScroll.read(e).maxScroll,h.U9));n&&(r=o+n.maxScroll.read(e).maxScroll),this._scrollableElement.setScrollDimensions({width:o,height:t,scrollHeight:i,scrollWidth:r})})),e.replaceChildren(this._scrollableElement.getDomNode()),this._register((0,s.s)(()=>{e.replaceChildren()})),this._register(this._register((0,n.fm)(e=>{(0,u.YY)(t=>{this.render(e)})})))}render(e){let t=this.scrollTop.read(e),i=0,o=0,r=0,s=this._sizeObserver.height.read(e),n=B.L.ofStartAndLength(t,s),d=this._sizeObserver.width.read(e);for(let l of this._viewItems.read(e)){let a=l.contentHeight.read(e),h=Math.min(a,s),c=B.L.ofStartAndLength(o,h),g=B.L.ofStartAndLength(r,a);if(g.isBefore(n))i-=a-h,l.hide();else if(g.isAfter(n))l.hide();else{let e=Math.max(0,Math.min(n.start-g.start,a-h));i-=e;let o=B.L.ofStartAndLength(t+i,s);l.render(c,e,d,o)}o+=h+this._spaceBetweenPx,r+=a+this._spaceBetweenPx}this._elements.content.style.transform=`translateY(${-(t+i)}px)`}};V=function(e,t,i,o){var r,s=arguments.length,n=s<3?t:null===o?o=Object.getOwnPropertyDescriptor(t,i):o;if("object"==typeof Reflect&&"function"==typeof Reflect.decorate)n=Reflect.decorate(e,t,i,o);else for(var d=e.length-1;d>=0;d--)(r=e[d])&&(n=(s<3?r(n):s>3?r(t,i,n):r(t,i))||n);return s>3&&n&&Object.defineProperty(t,i,n),n}([N(4,I.fN),N(5,O._Y)],V);class $ extends s.jG{constructor(e,t,i,o){super(),this.viewModel=e,this._objectPool=t,this._scrollLeft=i,this._deltaScrollVertical=o,this._templateRef=this._register((0,u.X2)(this,void 0)),this.contentHeight=(0,n.un)(this,e=>{var t,i,o;return null!=(o=null==(i=null==(t=this._templateRef.read(e))?void 0:t.object.contentHeight)?void 0:i.read(e))?o:this.viewModel.lastTemplateData.read(e).contentHeight}),this.maxScroll=(0,n.un)(this,e=>{var t,i;return null!=(i=null==(t=this._templateRef.read(e))?void 0:t.object.maxScroll.read(e))?i:{maxScroll:0,scrollWidth:0}}),this.template=(0,n.un)(this,e=>{var t;return null==(t=this._templateRef.read(e))?void 0:t.object}),this._isHidden=(0,n.FY)(this,!1),this._isFocused=(0,n.un)(this,e=>{var t,i;return null!=(i=null==(t=this.template.read(e))?void 0:t.isFocused.read(e))&&i}),this.viewModel.setIsFocused(this._isFocused,void 0),this._register((0,n.fm)(e=>{var t;let i=this._scrollLeft.read(e);null==(t=this._templateRef.read(e))||t.object.setScrollLeft(i)})),this._register((0,n.fm)(e=>{let t=this._templateRef.read(e);t&&this._isHidden.read(e)&&(t.object.isFocused.read(e)||this._clear())}))}dispose(){this._clear(),super.dispose()}toString(){var e;return`VirtualViewItem(${null==(e=this.viewModel.entry.value.modified)?void 0:e.uri.toString()})`}getKey(){return this.viewModel.getKey()}setViewState(e,t){var i;this.viewModel.collapsed.set(e.collapsed,t),this._updateTemplateData(t);let o=this.viewModel.lastTemplateData.get(),r=null==(i=e.selections)?void 0:i.map(M.L.liftSelection);this.viewModel.lastTemplateData.set({...o,selections:r},t);let s=this._templateRef.get();s&&r&&s.object.editor.setSelections(r)}_updateTemplateData(e){var t;let i=this._templateRef.get();i&&this.viewModel.lastTemplateData.set({contentHeight:i.object.contentHeight.get(),selections:null!=(t=i.object.editor.getSelections())?t:void 0},e)}_clear(){let e=this._templateRef.get();e&&(0,u.Rn)(t=>{this._updateTemplateData(t),e.object.hide(),this._templateRef.set(void 0,t)})}hide(){this._isHidden.set(!0,void 0)}render(e,t,i,o){this._isHidden.set(!1,void 0);let r=this._templateRef.get();if(!r){r=this._objectPool.getUnusedObj(new U(this.viewModel,this._deltaScrollVertical)),this._templateRef.set(r,void 0);let e=this.viewModel.lastTemplateData.get().selections;e&&r.object.editor.setSelections(e)}r.object.render(e,i,t,o)}}var q=i(3765),Z=i(912672);(0,Z.x1A)("multiDiffEditor.headerBackground",{dark:"#262626",light:"tab.inactiveBackground",hcDark:"tab.inactiveBackground",hcLight:"tab.inactiveBackground"},(0,q.kg)("multiDiffEditor.headerBackground","The background color of the diff editor's header")),(0,Z.x1A)("multiDiffEditor.background",{dark:"editorBackground",light:"editorBackground",hcDark:"editorBackground",hcLight:"editorBackground"},(0,q.kg)("multiDiffEditor.background","The background color of the multi file diff editor")),(0,Z.x1A)("multiDiffEditor.border",{dark:"sideBarSectionHeader.border",light:"#cccccc",hcDark:"sideBarSectionHeader.border",hcLight:"#cccccc"},(0,q.kg)("multiDiffEditor.border","The border color of the multi file diff editor"));let X=class extends s.jG{constructor(e,t,i){super(),this._element=e,this._workbenchUIElementFactory=t,this._instantiationService=i,this._dimension=(0,n.FY)(this,void 0),this._viewModel=(0,n.FY)(this,void 0),this._widgetImpl=(0,n.rm)(this,(e,t)=>((0,d.b6)(Y,e),t.add(this._instantiationService.createInstance((0,d.b6)(V,e),this._element,this._dimension,this._viewModel,this._workbenchUIElementFactory)))),this._register((0,n.OI)(this._widgetImpl))}};X=function(e,t,i,o){var r,s=arguments.length,n=s<3?t:null===o?o=Object.getOwnPropertyDescriptor(t,i):o;if("object"==typeof Reflect&&"function"==typeof Reflect.decorate)n=Reflect.decorate(e,t,i,o);else for(var d=e.length-1;d>=0;d--)(r=e[d])&&(n=(s<3?r(n):s>3?r(t,i,n):r(t,i))||n);return s>3&&n&&Object.defineProperty(t,i,n),n}([(r=O._Y,function(e,t){r(e,t,2)})],X)},716551(e,t,i){var o=i(427969);class r extends o.LN{constructor(e){super(),this._getContext=e}runAction(e,t){let i=this._getContext();return super.runAction(e,i)}}i.d(t,{I:()=>r})}}]);
//# sourceMappingURL=46424-5d18dbe7a2f6e418-fc1e2cc088efcb72.js.map
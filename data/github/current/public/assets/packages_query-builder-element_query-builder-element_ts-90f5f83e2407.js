"use strict";(globalThis.webpackChunk_github_ui_github_ui=globalThis.webpackChunk_github_ui_github_ui||[]).push([["packages_query-builder-element_query-builder-element_ts"],{76999:(t,e,i)=>{i.d(e,{XX:()=>s.XX,_3:()=>s._3,qy:()=>s.qy});var s=i(31143)},73855:(t,e,i)=>{i.d(e,{CN:()=>SearchItem,P$:()=>QueryEvent,VJ:()=>h,dS:()=>FetchDataEvent,k8:()=>r,m4:()=>n,nM:()=>l,o7:()=>a,qi:()=>FilterItem,yk:()=>o});var s=i(50467);let a={DIRECTORY:"Search in this directory",ORG:"Search in this organization",OWNER:"Search in this owner",REPO:"Search in this repository",GITHUB:"Search all of GitHub",GENERAL:"Submit search",COMMAND:"Run command",COPILOT_CHAT:"Start a new Copilot thread",COPILOT_SEARCH:"Search with Copilot",EXPLORE:"Learn More",DEFAULT:"Jump to"},r="Autocomplete";let FilterItem=class FilterItem extends Event{constructor({filter:t,value:e,name:i="",description:a="",inlineDescription:r=!1,priority:l=1/0,icon:n,avatar:o,action:h}){super("filter-item"),(0,s._)(this,"name",void 0),(0,s._)(this,"filter",void 0),(0,s._)(this,"value",void 0),(0,s._)(this,"description",void 0),(0,s._)(this,"inlineDescription",!1),(0,s._)(this,"action",void 0),(0,s._)(this,"priority",void 0),(0,s._)(this,"icon",void 0),(0,s._)(this,"avatar",void 0),this.filter=t,this.value=e,this.name=i,this.description=a,this.inlineDescription=r,this.priority=l,this.icon=n,this.avatar=o,this.action=h}};function l(t){return t instanceof Object}let n={Apps:"apps",Archived:"archived",Book:"book",Bookmark:"bookmark",Branch:"branch",Calendar:"calendar",Circle:"circle",Code:"code",CodeReview:"code-review",CodeSquare:"code-square",Comment:"comment",CommentDiscussion:"comment-discussion",Copilot:"copilot",CopilotError:"copilot-error",Codespaces:"codespaces",CreditCard:"credit-card",Default:"default",DeviceDesktop:"device-desktop",DeviceMobile:"device-mobile",Discussion:"discussion",Draft:"draft",FileCode:"file-code",Filter:"filter",Forbidden:"forbidden",Gift:"gift",Globe:"globe",Heart:"heart",History:"history",Issue:"issue",IssueOpened:"issue-opened",IssueClosed:"issueClosed",Iterations:"iterations",Mention:"mention",Merged:"merged",Milestone:"milestone",No:"no",Not:"not",Organization:"organization",Package:"package",Pencil:"pencil",Person:"person",Play:"play",PlusCircle:"plus-circle",Project:"project",PullRequest:"pullRequest",Question:"question",Reaction:"reaction",Repo:"repo",Rocket:"rocket",Search:"search",Server:"server",ShieldCheck:"shield-check",SingleSelect:"single-select",Sort:"sort",Tag:"tag",Team:"team",Telescope:"telescope",Trash:"trash",Workflow:"workflow"},o={Entity:"--color-prettylights-syntax-entity",Constant:"--color-prettylights-syntax-constant",Keyword:"--color-prettylights-syntax-keyword",Variable:"--color-prettylights-syntax-variable",String:"--color-prettylights-syntax-string"};let SearchItem=class SearchItem extends Event{constructor({id:t,priority:e,value:i,action:a,description:r="",icon:l,scope:n="DEFAULT",prefixText:o,prefixColor:h,isFallbackSuggestion:u,isUpdate:c}){super(c?"update-item":"search-item"),(0,s._)(this,"id",void 0),(0,s._)(this,"priority",void 0),(0,s._)(this,"value",void 0),(0,s._)(this,"action",void 0),(0,s._)(this,"description",void 0),(0,s._)(this,"icon",void 0),(0,s._)(this,"scope",void 0),(0,s._)(this,"prefixText",void 0),(0,s._)(this,"prefixColor",void 0),(0,s._)(this,"isFallbackSuggestion",void 0),this.id=t,this.priority=e,this.value=i,this.prefixText=o,this.prefixColor=h,this.action=a,this.description=r,this.icon=l,this.scope=n,this.isFallbackSuggestion=u||!1}};let h={Normal:"normal",Entity:"entity",Constant:"constant",FilterValue:"filter-value"};let FetchDataEvent=class FetchDataEvent extends Event{constructor(t){super("fetch-data"),(0,s._)(this,"fetchPromise",void 0),this.fetchPromise=t}};let QueryEvent=class QueryEvent extends Event{toString(){return this.rawQuery}constructor(t,e,i){super("query"),(0,s._)(this,"parsedQuery",void 0),(0,s._)(this,"rawQuery",void 0),(0,s._)(this,"parsedMetadata",void 0),this.parsedQuery=t,this.rawQuery=e,this.parsedMetadata=i}};Event},94643:(t,e,i)=>{i.d(e,{CN:()=>y.CN,MK:()=>QueryBuilderElement,dS:()=>y.dS,m4:()=>y.m4,qi:()=>y.qi});var s=i(35750),a=i(18150),r=i(85242),l=i(88243),n=i(16213),o=i(50467),h=i(31635),u=i(39595),c=i(35908),d=i(76999),p=i(53419),y=i(73855);let FeedbackEvent=class FeedbackEvent extends Event{constructor(t,e,i){super("query-builder-feedback",{bubbles:!0,cancelable:!0}),(0,o._)(this,"key",void 0),(0,o._)(this,"text",void 0),(0,o._)(this,"data",void 0),this.key=t,this.text=e,this.data=i}};let v=(t,e)=>t.priority-e.priority;var m=new WeakMap,_=new WeakMap,f=new WeakMap,g=new WeakMap,b=new WeakMap,$=new WeakMap,w=new WeakMap,L=new WeakMap,I=new WeakMap,C=new WeakMap,A=new WeakMap,k=new WeakMap,q=new WeakMap,E=new WeakMap,S=new WeakMap,x=new WeakMap,W=new WeakMap,F=new WeakMap,M=new WeakMap,B=new WeakMap,P=new WeakMap,T=new WeakMap,Q=new WeakMap,R=new WeakSet,V=new WeakSet,D=new WeakSet,O=new WeakSet,N=new WeakSet,z=new WeakSet,j=new WeakSet,J=new WeakSet,U=new WeakSet,X=new WeakSet,H=new WeakSet,K=new WeakSet,G=new WeakSet;let QueryBuilderElement=class QueryBuilderElement extends HTMLElement{get input(){return(0,u.FB)(this,"input")}get styledInputContent(){return(0,u.FB)(this,"styledInputContent")}get styledInputContainer(){return(0,u.FB)(this,"styledInputContainer")}get styledInput(){return(0,u.FB)(this,"styledInput")}get overlay(){return(0,u.FB)(this,"overlay")}get sizer(){return(0,u.FB)(this,"sizer")}get clearButton(){return(0,u.FB)(this,"clearButton")}get resultsList(){return(0,u.FB)(this,"resultsList")}get screenReaderFeedback(){return(0,u.FB)(this,"screenReaderFeedback")}get query(){return this.input.value}get i18n(){return{suggestion:"suggestion",suggestions:"suggestions",clear_search:"Input cleared."}}navigate(t){let e=t?.target?.closest("a")?.getAttribute("href");e&&((0,p.BI)("query-builder-element.click",{url:e}),this.dispatchEvent(new CustomEvent("query-builder:navigate",{bubbles:!0,detail:{url:e}})))}get closed(){return this.overlay&&this.overlay.hasAttribute("hidden")}set closed(t){if(t)this.closed||(this.overlay&&(this.overlay.hidden=!0),this.input.setAttribute("aria-expanded","false"),(0,s._)(this,m)?.clearSelection());else{if(!this.closed)return;this.overlay&&(this.overlay.hidden=!1),this.input.setAttribute("aria-expanded","true")}}show(){this.closed=!1,this.overlay?.scrollIntoView?.({behavior:"smooth",block:"nearest"})}hide(){"false"===this.resultsList.getAttribute("data-persist-list")&&(this.closed=!0)}initialize(t,e){for(let i of(this.parser=t,(0,r._)(this,P,!0),(0,r._)(this,M,!0),e))this.attachProvider(i);(0,r._)(this,M,!1),(0,r._)(this,g,e.reduce((t,e)=>({...t,[e.value]:e}),{}))}detachElementDefinitionReadyForProviders(){this.removeEventListener("query-builder:ready-to-request-provider",this.elementDefinitionReadyForProviders)}connectedCallback(){(0,s._)(this,$)?.abort();let{signal:t}=(0,r._)(this,$,new AbortController);t.addEventListener("abort",()=>{(0,r._)(this,g,{})}),(0,r._)(this,q,this.input.getAttribute("id")),this.hasAttribute("defer-request-providers")||(document.addEventListener("query-builder:ready-to-request-provider",this.elementDefinitionReadyForProviders,!0),this.readyForRequestProviders())}readyForRequestProviders(){(0,l._)(this,G,tu).call(this)>0&&(0,s._)(this,B)||((0,r._)(this,m,(0,s._)(this,m)||new c.A(this.input,this.resultsList,{tabInsertsSuggestions:!1})),this.requestProviders())}async requestProviders(){(0,r._)(this,B,!0),await Promise.resolve(),(0,r._)(this,M,!0),this.dispatchEvent(new Event("query-builder:request-provider",{bubbles:!0})),(0,r._)(this,M,!1),(0,r._)(this,S,new Map);let t=this.parseInputValue();this.styleInputText(t),this.toggleClearButtonVisibility()}parseInputValue(){return this.parsedMetadata=this.parser.parse(this.input.value,this.input.selectionStart||0),this.parser.flatten(this.parsedMetadata)}attachProvider(t){if(!(0,s._)(this,$))return;let{signal:e}=(0,s._)(this,$);if(!(0,s._)(this,M))throw Error("Can't attach providers after the query builder has been connected");(0,s._)(this,g)[t.value]||((0,s._)(this,g)[t.value]=t,"filter"===t.type?((0,s._)(this,b).add(t.value),t.addEventListener("filter-item",e=>{(0,s._)(this,T).call(this,(0,s._)(this,k),t),(0,s._)(this,k).get(t)?.push(e),(0,l._)(this,R,Y).call(this)},{signal:e}),t.addEventListener("show",()=>{(0,s._)(this,A).add(t),(0,l._)(this,R,Y).call(this)},{signal:e}),t.addEventListener("fetch-data",async t=>{let e=new Promise(t=>setTimeout(t,(0,s._)(this,W)));(0,r._)(this,F,Promise.race([Promise.all([(0,s._)(this,F),t.fetchPromise]),e]));let i=(0,s._)(this,F);try{await i}catch(t){if("AbortError"!==t.name)throw(0,r._)(this,F,!1),t}i===(0,s._)(this,F)&&((0,r._)(this,F,!1),(0,l._)(this,R,Y).call(this),this.updateVisibility())},{signal:e})):(t.addEventListener("fetch-data",async e=>{(0,s._)(this,C).delete(t),await e.fetchPromise,(0,s._)(this,L).set(t,(0,s._)(this,I).get(t)||[]),(0,s._)(this,I).delete(t),(0,l._)(this,R,Y).call(this)}),t.addEventListener("search-item",e=>{(0,s._)(this,T).call(this,(0,s._)(this,L),t),(0,s._)(this,I).has(t)?(0,s._)(this,I).get(t)?.push(e):((0,s._)(this,C).has(t)&&((0,s._)(this,L).set(t,[]),(0,s._)(this,C).delete(t)),(0,s._)(this,L).get(t)?.push(e),(0,l._)(this,R,Y).call(this))},{signal:e}),t.addEventListener("update-item",e=>{let i=(0,s._)(this,L).get(t);if(!i)return;let a=i.findIndex(t=>t.id===e.id);a<0||(i[a]=e,(0,l._)(this,R,Y).call(this))},{signal:e})))}disconnectedCallback(){(0,s._)(this,$)?.abort()}comboboxCommit(t){let e=t.target,i=e?.getAttribute("data-type"),s=e?.getAttribute("data-value")||"",a=e?.getAttribute("data-replace-query-with")||"",r=parseInt(e?.getAttribute("data-move-caret-to")||"0")||0,l=this.parseInputValue();if("url-result"===i);else if("filter-result"===i)l.pop(),l.push({type:"filter",filter:s,value:""});else if("command-result"===i){let t=e.getAttribute("data-command-name")||"",i=JSON.parse(e.getAttribute("data-command-payload")||"{}");this.dispatchEvent(new CustomEvent(t,{detail:i}))}else if("query-result"===i)if(a)this.input.value=a,this.input.focus(),l=void 0;else{let t=this.parser.flatten(this.parser.parse(s,0));l.push(...t),l.push({type:"text",value:""})}else"filter-item"===i&&(a?(this.input.value=a,this.input.focus(),l=void 0):this.addSelectedItemToFilter(s,l));if(this.parseQuery(l),a){let t=-1===r?this.input.value.length:r;this.input.setSelectionRange(t,t)}this.input.removeAttribute("aria-activedescendant")}addSelectedItemToFilter(t,e){let i=/\s/.test(t),s=e.pop();if(s?.type==="filter"){let a=s.value.split(",");a.pop(),a.push(i?`"${t}"`:t),e.push({type:"filter",filter:s?.filter,value:a.join(",")}),e.push({type:"text",value:""})}else s&&e.push(s)}async inputChange(){await this.parseQuery()}inputBlur(){if(clearTimeout(this.focusTimeout),(0,s._)(this,_))return void(0,r._)(this,_,!1);this.styledInput.classList.remove((0,s._)(this,E)),this.input.removeAttribute("aria-activedescendant"),this.hide()}resultsMousedown(){(0,r._)(this,_,!0)}async inputFocus(){this.styledInput.classList.add((0,s._)(this,E)),this.readyForRequestProviders(),(0,s._)(this,m).start();let t=this.input.value;this.lastParsedQuery&&this.lastParsedQuery===this.input.value||await this.parseQuery(),this.closed&&this.input.value===t&&this.input.setSelectionRange(0,this.input.value.length),this.focusTimeout?clearTimeout(this.focusTimeout):this.focusTimeout=setTimeout(()=>{this.input.focus()},this.FOCUS_TIMEOUT_VALUE)}moveCaretToEndOfInput(){this.input.setSelectionRange(this.input.value.length,this.input.value.length)}hasFocus(){return this.styledInput.classList.contains((0,s._)(this,E))}inputKeydown(t){let e=t.key;if("Escape"===e)this.hide();else if("Enter"===e){let e=this.resultsList.querySelector('[aria-selected="true"], [data-combobox-option-default="true"]');if(!e||"true"===e.getAttribute("aria-disabled"))return;let i=e.querySelector("a");i&&(t.ctrlKey||t.metaKey?window.open(i.getAttribute("href")||"","_blank"):i.click())}}inputSubmit(){this.hide()}clearButtonFocus(t){let e=t.relatedTarget;e&&e===this.input&&this.show()}clearButtonBlur(){this.hide()}toggleClearButtonVisibility(){if(this.clearButton)if(""!==this.input.value){if(!1===this.clearButton.hidden)return;this.clearButton.hidden=!1}else this.clearButton.hidden=!0}updateVisibility(){this.hasFocus()&&((0,s._)(this,k).size>0||(0,s._)(this,L).size>0||(0,s._)(this,A).size>0?this.show():(0,s._)(this,F)||this.hide())}getLeadingVisual(t,e){if(e){let t="org"===e.type?"avatar avatar-1 avatar-small":"avatar avatar-1 avatar-small circle";return(0,d.qy)`<img src="${e.url}" alt="" role="presentation" class="${t}" />`}if(t&&(0,y.nM)(t))return(0,d.qy)([t.html]);let i=document.getElementById(`${t}-icon`);return(0,d.qy)([i?.innerHTML])}updateScreenReaderFeedback(t){let e=new FeedbackEvent("NEW_RESULTS",t,{});this.dispatchEvent(e),this.screenReaderFeedback.textContent=e.text}async clear(){this.dispatchEvent(new CustomEvent("query-builder:clear",{bubbles:!0,cancelable:!0}))&&await this.clearInput()}async clearInput({focusInput:t=!0}={}){await this.parseQuery([],t),(0,r._)(this,f,!0)}async parseQuery(t,e=!0){(0,s._)(this,w)?.abort();let{signal:i}=(0,r._)(this,w,new AbortController);if(t){let e=t.map(t=>"filter"===t.type?`${t.filter}:${t.value}`:t.value).join((0,s._)(this,P)?"":" "),i=Object.getOwnPropertyDescriptor(Object.getPrototypeOf(this.input),"value")?.set;i?i?.call(this.input,e):this.input.value=e,this.input.dispatchEvent(new Event("change",{bubbles:!0}))}else t=this.parseInputValue();if(this.lastParsedQuery=this.input.value,await new Promise(t=>requestAnimationFrame(t)),i.aborted||(this.styleInputText(t),e&&this.input.focus(),await new Promise(t=>setTimeout(t,100)),i.aborted))return;for(let t of(0,s._)(this,L).keys())(0,s._)(this,C).add(t);(0,s._)(this,k).clear(),(0,s._)(this,A).clear();let a=new y.P$(t,this.input.value,this.parsedMetadata);this.dispatchEvent(a);let n=!1;for(let t of(0,s._)(this,C).keys())(0,s._)(this,L).delete(t),(0,s._)(this,C).delete(t),n=!0;n&&(0,l._)(this,R,Y).call(this),this.updateVisibility()}styleInputText(t){(0,l._)(this,H,to).call(this,this.input.value);let e=document.createDocumentFragment();for(let i of t){let t=document.createElement("span"),a=document.createElement("span");a.textContent=" ";let r=!(0,s._)(this,P);if("filter"===i.type){let{filter:e,value:s}=i,l=document.createElement("span");t.setAttribute("data-type","filter-expression"),l.setAttribute("data-type","filter"),l.textContent=e;let n=document.createElement("span");n.textContent=this.filterKey;let o=document.createElement("span");o.setAttribute("data-type","filter-value"),o.textContent=s,t.appendChild(l),t.appendChild(n),t.appendChild(o),r&&t.appendChild(a)}else r?t.textContent=`${i.value} `:t.textContent=i.value,i.style===y.VJ.Constant?t.classList.add("qb-constant"):i.style===y.VJ.Entity?t.classList.add("qb-entity"):i.style===y.VJ.FilterValue&&t.classList.add("qb-filter-value");e.append(t),(0,l._)(this,K,th).call(this)}this.styledInputContent.replaceChildren(e)}constructor(...t){super(...t),(0,n._)(this,R),(0,n._)(this,V),(0,n._)(this,D),(0,n._)(this,O),(0,n._)(this,N),(0,n._)(this,z),(0,n._)(this,j),(0,n._)(this,J),(0,n._)(this,U),(0,n._)(this,X),(0,n._)(this,H),(0,n._)(this,K),(0,n._)(this,G),(0,a._)(this,m,{writable:!0,value:void 0}),(0,a._)(this,_,{writable:!0,value:!1}),(0,a._)(this,f,{writable:!0,value:!1}),(0,a._)(this,g,{writable:!0,value:{}}),(0,a._)(this,b,{writable:!0,value:new Set}),(0,a._)(this,$,{writable:!0,value:null}),(0,a._)(this,w,{writable:!0,value:null}),(0,a._)(this,L,{writable:!0,value:new Map}),(0,a._)(this,I,{writable:!0,value:new Map}),(0,a._)(this,C,{writable:!0,value:new Set}),(0,a._)(this,A,{writable:!0,value:new Set}),(0,a._)(this,k,{writable:!0,value:new Map}),(0,a._)(this,q,{writable:!0,value:void 0}),(0,a._)(this,E,{writable:!0,value:"QueryBuilder-focus"}),(0,a._)(this,S,{writable:!0,value:new Map}),(0,a._)(this,x,{writable:!0,value:150}),(0,a._)(this,W,{writable:!0,value:3e3}),(0,a._)(this,F,{writable:!0,value:!1}),(0,a._)(this,M,{writable:!0,value:!1}),(0,a._)(this,B,{writable:!0,value:!1}),(0,o._)(this,"parser",{parse:(0,l._)(this,X,tn).bind(this),flatten:t=>t}),(0,o._)(this,"parsedMetadata",void 0),(0,o._)(this,"renderSingularItemNames",!1),(0,a._)(this,P,{writable:!0,value:!1}),(0,o._)(this,"lastParsedQuery",void 0),(0,o._)(this,"FOCUS_TIMEOUT_VALUE",100),(0,o._)(this,"minWidth",300),(0,o._)(this,"elementDefinitionReadyForProviders",t=>{t.detail.id===(0,s._)(this,q)&&(this.readyForRequestProviders(),t.stopImmediatePropagation())}),(0,a._)(this,T,{writable:!0,value:(t,e)=>{t.has(e)||t.set(e,[])}}),(0,a._)(this,Q,{writable:!0,value:!1})}};function Y(){(0,s._)(this,Q)||((0,r._)(this,Q,!0),this.toggleClearButtonVisibility(),(0,r._)(this,Q,!1),(0,l._)(this,O,te).call(this))}function Z(){if(0!==(0,s._)(this,A).size)return(0,d.qy)`<li role="presentation" class="ActionList-sectionDivider">
      <h3 role="presentation" class="ActionList-sectionDivider-title p-2 text-left" aria-hidden="true">
        Suggested filters
      </h3>
      <ul role="presentation">
        ${[...(0,s._)(this,A)].sort(v).map(t=>(0,l._)(this,J,tr).call(this,t))}
      </ul>
    </li>`}function tt(t,e=!1){let i=[],a=this.parseInputValue().at(-1);if("filter"===t.type?t.manuallyDetermineFilterEligibility?i=(0,s._)(this,k).get(t)?.sort(v).map(t=>(0,l._)(this,U,tl).call(this,t))||[]:a?.type==="filter"&&(i=(0,s._)(this,k).get(t)?.filter(t=>t.filter===a.filter).sort(v).map(t=>(0,l._)(this,U,tl).call(this,t))||[]):i=[...(0,s._)(this,L).get(t)||[]].filter(t=>t.isFallbackSuggestion===e).sort(v).map(t=>(0,l._)(this,z,ts).call(this,t)),i.length)if(""===t.name)return(0,d.qy)`<li role="presentation" class="ActionList-sectionDivider">
        <ul role="presentation">
          ${i}
        </ul>
      </li>`;else return(0,d.qy)`<li role="presentation" class="ActionList-sectionDivider">
        <h3
          role="presentation"
          class="ActionList-sectionDivider-title QueryBuilder-sectionTitle p-2 text-left"
          aria-hidden="true"
        >
          ${t.name}
        </h3>
        <ul role="presentation">
          ${i}
        </ul>
      </li>`}function te(){let t,e=Object.values((0,s._)(this,g)).sort((t,e)=>t.priority-e.priority).map(t=>(0,l._)(this,D,tt).call(this,t)).filter(t=>void 0!==t);(0,s._)(this,F)||0!==e.length||(e=Object.values((0,s._)(this,g)).sort((t,e)=>t.priority-e.priority).map(t=>(0,l._)(this,D,tt).call(this,t,!0)).filter(t=>void 0!==t));let i=(0,l._)(this,V,Z).call(this);i&&e.push(i),0===e.length?(0,s._)(this,F)||(this.resultsList.textContent="",(0,d.XX)((0,d.qy)``,this.resultsList)):(0,d.XX)((0,d.qy)`${e.map((t,i)=>i===e.length-1?t:(0,d.qy)`${t}
                <li aria-hidden="true" class="ActionList-sectionDivider"></li>`)}`,this.resultsList);let a=this.resultsList.querySelectorAll('[role="option"]').length,n=1===a?this.i18n.suggestion:this.i18n.suggestions;t=`${a} ${n}.`,(0,s._)(this,f)&&(t=`${this.i18n.clear_search} ${t}`,(0,r._)(this,f,!1)),this.screenReaderFeedback.textContent===t&&(t+="\xa0"),setTimeout(()=>this.updateScreenReaderFeedback(t),(0,s._)(this,x))}function ti(t){if(t)return t.replace(/\s/g,"-").toLowerCase()}function ts({value:t,prefixText:e,prefixColor:i,target:a,action:r,description:n,icon:o,scope:h}){if("url"in r){let u="GENERAL"===h?`${y.o7[h]}`:`jump to this ${a.singularItemName}`,c=n?`, ${n}`:"",p=`${e?`${e} `:""}${t}${c}, ${u}`,v=null;return e&&(v=(0,d.qy)`
          <span>
            <div class="d-inline-flex position-relative">
              <div
                class="position-absolute rounded-1 flex-items-stretch height-full width-full"
                style="opacity: 0.1; background-color: var(${i})"
              ></div>
              <div class="px-1" style="color: var(${i})">${e}</div>
            </div>
            ${(0,l._)(this,j,ta).call(this,t)}
          </span>
        `),(0,d.qy)`<li
        role="option"
        class="ActionListItem"
        data-type="url-result"
        id="${(0,s._)(this,q)||"search-item"}-result-${(0,l._)(this,N,ti).call(this,t)}"
        data-value="${t}"
        aria-label="${p}"
      >
        <a
          href="${r.url}"
          data-action="click:query-builder#navigate"
          tabindex="-1"
          class="QueryBuilder-ListItem-link ActionListContent ActionListContent--visual16 QueryBuilder-ListItem"
        >
          ${o?(0,d.qy)`<span
                id="${(0,s._)(this,q)||"search-item"}-result-${(0,l._)(this,N,ti).call(this,t)}--leading"
                class="ActionListItem-visual ActionListItem-visual--leading"
              >
                ${this.getLeadingVisual(o)}
              </span>`:null}
          <span class="ActionListItem-descriptionWrap">
            <span class="ActionListItem-label text-normal"> ${v||(0,l._)(this,j,ta).call(this,t)} </span>
            ${n?(0,d.qy)`<span class="ActionListItem-description">${n}</span>`:null}
          </span>

          <span aria-hidden="true" class="ActionListItem-description QueryBuilder-ListItem-trailing"
            >${y.o7[h]}</span
          >
        </a>
      </li>`}if("commandName"in r){let e=y.o7[h]||y.o7.COMMAND,i=n?`, ${n}`:"",a=`${t}${i}, ${e}`;return(0,d.qy)`<li
        role="option"
        class="ActionListItem"
        data-type="command-result"
        id="${(0,s._)(this,q)||"search-item"}-result-${(0,l._)(this,N,ti).call(this,t)}"
        data-value="${t}"
        data-command-name="${r.commandName}"
        data-command-payload="${JSON.stringify(r.data)}"
        aria-label="${a}"
      >
        <span class="ActionListContent ActionListContent--visual16 QueryBuilder-ListItem">
          ${o?(0,d.qy)`<span
                id="${(0,s._)(this,q)||"search-item"}-result-${(0,l._)(this,N,ti).call(this,t)}--leading"
                class="ActionListItem-visual ActionListItem-visual--leading"
              >
                ${this.getLeadingVisual(o)}
              </span>`:null}
          <span class="ActionListItem-descriptionWrap">
            <span class="ActionListItem-label text-normal"> ${(0,l._)(this,j,ta).call(this,t)} </span>
            ${n?(0,d.qy)`<span class="ActionListItem-description">${n}</span>`:null}
          </span>

          <span aria-hidden="true" class="ActionListItem-description QueryBuilder-ListItem-trailing"
            >${e}</span
          >
        </span>
      </li>`}{let e="",i=0;"replaceQueryWith"in r&&(e=r.replaceQueryWith,i=r.moveCaretTo);let a="query"in r?y.o7[h]:y.k8;return(0,d.qy)` <li
        role="option"
        class="ActionListItem"
        data-type="query-result"
        data-value="${t}"
        aria-label="${t}${n?`, ${n}`:""}"
        data-replace-query-with="${e}"
        data-move-caret-to="${i}"
        id="${(0,s._)(this,q)||"search-item"}-result-${(0,l._)(this,N,ti).call(this,t)}"
      >
        <span class="ActionListContent ActionListContent--visual16 QueryBuilder-ListItem">
          ${o?(0,d.qy)`<span
                id="${(0,s._)(this,q)||"search-item"}-result-${(0,l._)(this,N,ti).call(this,t)}--leading"
                class="ActionListItem-visual ActionListItem-visual--leading"
              >
                ${this.getLeadingVisual(o)}
              </span>`:null}
          <span class="ActionListItem-descriptionWrap">
            <span class="ActionListItem-label text-normal">${(0,l._)(this,j,ta).call(this,t)}</span>
            ${n?(0,d.qy)`<span class="ActionListItem-description">${n}</span>`:null}
          </span>

          ${(0,s._)(this,L).size>0?(0,d.qy)`<span aria-hidden="true" class="ActionListItem-description QueryBuilder-ListItem-trailing"
                >${a}</span
              >`:(0,d.qy)``}
        </span>
      </li>`}}function ta(t){let e=this.parser.flatten(this.parser.parse(t,0)),i=!(0,s._)(this,P),a=[];for(let t of e)if("filter"===t.type)a.push((0,d.qy)`<span>${t.filter}:</span
            ><span data-type="filter-value">${t.value}${i?" ":""}</span>`);else{let e="";t.style===y.VJ.Constant?e="qb-constant":t.style===y.VJ.Entity?e="qb-entity":t.style===y.VJ.FilterValue&&(e="qb-filter-value"),a.push((0,d.qy)`<span class="${e}">${t.value}${i?" ":""}</span>`)}return a}function tr({singularItemName:t,icon:e,description:i,value:a}){let r=i?`, ${i}`:"",n=`${this.renderSingularItemNames?t:a}${r}`;return(0,d.qy)` <li
      role="option"
      class="ActionListItem"
      data-type="filter-result"
      data-value="${a}"
      id="${(0,s._)(this,q)||"filter"}-result-${(0,l._)(this,N,ti).call(this,a)}"
      aria-label="${n}, filter"
    >
      <span class="ActionListContent ActionListContent--visual16 QueryBuilder-ListItem">
        ${e?(0,d.qy)`<span
              id="${(0,s._)(this,q)||"filter"}-result-${(0,l._)(this,N,ti).call(this,a)}--leading"
              class="ActionListItem-visual ActionListItem-visual--leading"
            >
              ${this.getLeadingVisual(e)}
            </span>`:null}
        <span class="ActionListItem-descriptionWrap">
          <span class="ActionListItem-label text-normal">
            ${this.renderSingularItemNames?t:`${a}:`}
          </span>
          ${i?(0,d.qy)`<span class="ActionListItem-description">${i}</span>`:null}
        </span>

        ${(0,s._)(this,L).size>0?(0,d.qy)`<span aria-hidden="true" class="ActionListItem-description QueryBuilder-ListItem-trailing"
              >${y.k8}</span
            >`:(0,d.qy)``}
      </span>
    </li>`}function tl({name:t,value:e,target:i,icon:a,avatar:r,description:n,inlineDescription:o,action:h}){let u=t&&t.length>0?t:e,c=n?`, ${n}`:"",p=i.singularItemName?`${u}${c}, autocomplete this ${i.singularItemName}`:`${u}${c}, ${i.name}`,v="",m=0;return h&&"replaceQueryWith"in h&&(v=h.replaceQueryWith,m=h.moveCaretTo),(0,d.qy)` <li
      role="option"
      class="ActionListItem"
      data-type="filter-item"
      data-replace-query-with="${v}"
      data-move-caret-to="${m}"
      data-value="${e}"
      id="${(0,s._)(this,q)||"filter-item"}-result-${(0,l._)(this,N,ti).call(this,e)}"
      aria-label="${p}"
    >
      <span class="ActionListContent ActionListContent--visual16 QueryBuilder-ListItem">
        ${a?(0,d.qy)`<span
              id="${(0,s._)(this,q)||"filter-item"}-result-${(0,l._)(this,N,ti).call(this,e)}--leading"
              class="ActionListItem-visual ActionListItem-visual--leading"
            >
              ${this.getLeadingVisual(a,r)}
            </span>`:null}
        <span class="${o?"ActionListItem-descriptionWrap-inline":"ActionListItem-descriptionWrap"}">
          <span class="ActionListItem-label text-normal">${u}</span>
          ${n?(0,d.qy)`<span class="ActionListItem-description">${n}</span>`:null}
        </span>

        ${(0,s._)(this,L).size>0?(0,d.qy)`<span aria-hidden="true" class="ActionListItem-description QueryBuilder-ListItem-trailing"
              >${y.k8}</span
            >`:(0,d.qy)``}
      </span>
    </li>`}function tn(t){let e=(0,s._)(this,S).get(t);if(e)return e.slice();{let e=[];for(let i of t.split(/\s(?=(?:[^"]*"[^"]*")*[^"]*$)/g)){let t=i.indexOf(this.filterKey);if(t>0){let a=i.substring(0,t),r=i.substring(t+1);e.push((0,s._)(this,b).has(a)?{type:"filter",filter:a,value:r}:{type:"text",value:i})}else e.push({type:"text",value:i})}return(0,s._)(this,S).set(t,[...e]),e}}function to(t){if(this.sizer.textContent="",null!==this.input.selectionStart&&this.input.selectionStart===this.input.selectionEnd){let e=this.input.selectionStart,i=document.createElement("span");this.sizer.append(t.substring(0,e),i,t.substring(e))}else this.sizer.textContent=t}function th(){let t=this.minWidth;requestAnimationFrame(()=>{let e=this.sizer.querySelector("span");e&&(e.offsetLeft<this.styledInputContainer.scrollLeft?this.styledInputContainer.scrollLeft=e.offsetLeft-t:e.offsetLeft>this.styledInputContainer.scrollLeft+this.styledInputContainer.clientWidth&&(this.styledInputContainer.scrollLeft=e.offsetLeft-this.styledInputContainer.clientWidth+t));let i=Math.max(this.sizer.scrollWidth+2,2*(""===this.input.value),t);this.input.style.width=`${i}px`})}function tu(){return Object.keys((0,s._)(this,g)).length}(0,h.Cg)([u.CF],QueryBuilderElement.prototype,"filterKey",void 0),(0,h.Cg)([u.CF],QueryBuilderElement.prototype,"minWidth",void 0),QueryBuilderElement=(0,h.Cg)([u.p_],QueryBuilderElement)}}]);
//# sourceMappingURL=packages_query-builder-element_query-builder-element_ts-a6a220906468.js.map
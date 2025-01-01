"use strict";(globalThis.webpackChunk=globalThis.webpackChunk||[]).push([["app_assets_modules_github_filter-input_ts"],{3810:(e,t,i)=>{i.d(t,{W:()=>BaseFilterElement});var s=i(17688),r=i(58120),a=i(97797),n=i(91052),l=i(97325),o=i(39595),u=i(85247),h=i(99418),c=i(26559);function g(e,t,i){return t in e?Object.defineProperty(e,t,{value:i,enumerable:!0,configurable:!0,writable:!0}):e[t]=i,e}function d(e,t,i,s){var r,a=arguments.length,n=a<3?t:null===s?s=Object.getOwnPropertyDescriptor(t,i):s;if("object"==typeof Reflect&&"function"==typeof Reflect.decorate)n=Reflect.decorate(e,t,i,s);else for(var l=e.length-1;l>=0;l--)(r=e[l])&&(n=(a<3?r(n):a>3?r(t,i,n):r(t,i))||n);return a>3&&n&&Object.defineProperty(t,i,n),n}let p=new Map;let BaseFilterElement=class BaseFilterElement extends HTMLElement{async cachedJSON(e){let t=await fetch(e,{headers:{...(0,c.kt)(),Accept:"application/json"}});if(!t.ok){let e=Error(),i=t.statusText?` ${t.statusText}`:"";throw e.message=`HTTP ${t.status}${i}`,e}return t.json()}fetchQualifierSuggestions(){let e="data-suggestable-qualifiers",t=this.searchInput.getAttribute(e);if(null===t)throw Error(`
        ${e} is missing from ${this.searchInput.getAttribute("data-target")}.
        Either add it or override fetchQualifierSuggestions.
      `);return JSON.parse(t)}negatableQualifiers(){return JSON.parse(this.searchInput.getAttribute("data-negatable-qualifiers")||"[]")}removeNegationFromQualifierIfSupported(e){if(!e.startsWith("-"))return e;let[t,...i]=e.split(":"),s=t.substring(1);return this.negatableQualifiers().includes(s)&&(t=s),e.includes(":")&&(t+=":"),i?.length>0?`${t}${i.join(":")}`:t}fetchSuggestionsForQualifier(e){e=this.removeNegationFromQualifierIfSupported(e);let t=`data-suggestable-${e}`,i=`data-suggestable-${e}-path`;if(this.searchInput.hasAttribute(t))return JSON.parse(this.searchInput.getAttribute(t)||"[]");if(!this.searchInput.hasAttribute(i))return Promise.resolve([]);{let e=this.searchInput.getAttribute(i);if(!e)throw Error(`${i} not set`);return this.cachedJSON(e)}}hideFilterSuggestions(){(0,r.LU)(this.searchForm),this.autocompleteDropdown.hidden=!0,this.searchInput.removeAttribute("aria-activedescendant")}updateFilterSuggestionResults(){let e,t;let i=this.searchInput.value,s=(i.slice(0,this.searchInput.selectionEnd).match(/\S+?(:(?:"[^"]*"|[^\s:])+?)?$/)||[""])[0].replace(/"/g,"");this.autocompleteDropdown.hidden=!1,s.includes(":")?[e,...t]=s.split(":"):e=s,null!=t?this.renderValueSuggestions(e,t.join(":")):this.renderQualifierSuggestions(e),i.trim().length>0&&(!this.invalidSearchTerms()||this.showSubmissionOptionIfInvalidSearchTerms)&&!this.searchMatchesDefault()?(this.clearButton&&(this.clearButton.hidden=!1),(0,r.XC)(this.searchForm)):(this.clearButton&&(this.clearButton.hidden=!0),(0,r.Yf)(this.searchForm))}handleSelectedSuggestionResultEvent(e){let t=e.target;if(t.classList.contains("js-filter-input-support-url"))return;if(t.hasAttribute("data-search")){(0,l.k_)(this.searchForm);return}let i=t.getAttribute("data-value")||"";":"!==i[i.length-1]&&(i+=" ");let s=this.searchInput.value.slice(0,this.searchInput.selectionEnd),r=s.match(/(\S+)$/)?.pop()||"",n=this.searchInput.value.slice(this.searchInput.selectionEnd),o=" "!==n[0]?" ":"";if(r){r.startsWith("-")&&!i.startsWith("-")&&(i=`-${i}`);let e=i.indexOf(":"),t=-1!==e?i.slice(0,e):i,s=-1!==e?i.slice(e+1):"";if(s.slice(0,-1).includes(" ")&&(s=`"${s.slice(0,-1)}" `),r.includes(",")){let e=r.split(",");e.pop(),e.push(s),i=e.join(",")}else i=`${t}:${s}`}let u=s.replace(/\S+$/,"");this.searchInput.value=u+i+o+n,e.preventDefault(),this.searchInput.focus();let h=u.length+i.length;this.searchInput.setSelectionRange(h,h),(0,a.h)(this.searchInput,"input")}handleFormKeydownEvent(e){"Enter"!==e.detail.hotkey||this.autocompleteResults.querySelector(".js-filter-loading")||this.autocompleteResults.querySelector(".js-navigation-item.navigation-focus")||(0,l.k_)(this.searchForm)}clear(){this.searchInput.value=this.getDefaultSearch(),0===this.getInitialValue().trim().length?this.updateFilterSuggestionResults():(0,l.k_)(this.searchForm)}renderQualifierSuggestions(e){this.showAllQualifiersIfNoneMatch?this.renderMatchingOrAllQualifierSuggestions(e):this.renderMatchingQualifierSuggestions(e)}handleSuggestionNavigation(e){null!=e.target&&this.searchInput.setAttribute("aria-activedescendant",e.target.id)}renderMatchingOrAllQualifierSuggestions(e){let t=this.fetchQualifierSuggestions(),i=this.filterSuggestionsList(t,e,{fuzzy:this.fuzzyMatchQualifiers}).then(e=>0===e.length?t:e);this.renderSuggestionDropdown(i)}renderMatchingQualifierSuggestions(e){let t=this.filterSuggestionsList(this.fetchQualifierSuggestions(),e,{fuzzy:this.fuzzyMatchQualifiers});this.renderSuggestionDropdown(t)}renderValueSuggestions(e,t){let i=this.fetchMatchingSuggestions(e,t);this.renderSuggestionDropdown(i)}async fetchMatchingSuggestions(e,t){let i=this.fetchSuggestionsForQualifier(e),s=t.split(",").pop()||"";return(await this.filterSuggestionsList(i,s,{fuzzy:this.fuzzyMatchValues})).map(t=>({value:`${e}:${t.value}`,description:t.description}))}async filterSuggestionsList(e,t,{fuzzy:i}={fuzzy:!0}){let s=await e,r=t.trim().toLowerCase();return r&&0!==r.length?(r.startsWith("-")&&(r=r.slice(1)),s.filter(e=>i?e.value.toLowerCase().includes(r):e.value.toLowerCase().startsWith(r))):s}renderSuggestionDropdown(e){(0,s.XX)((0,s.qy)`
        <div role="listbox" aria-label="${this.suggestionsTitle}">
          ${this.renderSearchWarningIfRequired()}
          ${this.shouldRenderSubmissionOption()?this.renderSearchSuggestion():""}
          ${(0,u.T)(this.renderSuggestionList(e),this.renderLoadingItem())}
        </div>
      `,this.autocompleteResults),this.postDropdownRender()}renderSearchWarningIfRequired(){let e;let t=this.searchInput.getAttribute("data-search-warning-container"),i=t?document.querySelector(t):null,a=this.invalidSearchTerms();if(!a||0===a.length)return i&&(i.hidden=!0),"";let n=this.getFilterSupportURL();e=n?(0,s.qy)`<a
        class="js-navigation-item js-navigation-open js-filter-input-support-url px-1"
        href="${n}"
        role="link"
        tabindex="0"
        target="_blank"
      >
        Learn more about filters.
      </a>`:"";let l=(0,s.qy)`Sorry, we don't support the <span class="text-bold">${h.default.sanitize(a)}</span> filter yet. ${e}`;return i?((0,s.XX)(l,i),i.hidden=!1,(0,r.XC)(i),""):(0,s.qy)`
      <div
        class="color-bg-attention color-fg-muted ml-n2 mr-n2 mt-n1 py-1 px-2 js-search-warning-container"
        role="alert"
      >
        ${l}
      </div>
    `}getFilterSupportURL(){return this.searchInput.getAttribute("data-filter-support-url")}postDropdownRender(){}renderSearchSuggestion(){let e=this.searchInput.value.trim();return 0===e.length||/:\s|:$/g.test(e)&&!/(?:\w+:){2,}/g.test(e)?(0,s.qy)``:(0,s.qy)`
      <div
        id="${this.getComponentTagName()}-search-submit-option"
        class="border-bottom-0 rounded-2 py-1 px-2 mx-0 mb-1 js-navigation-item"
        data-action="navigation:focus:${this.getComponentTagName()}#handleSuggestionNavigation"
        data-search="true"
        role="option"
      >
        <span class="text-bold">${e}</span> - submit
      </div>
    `}invalidSearchTerms(){let e=this.fetchQualifierSuggestions().map(e=>e.value),t=new RegExp(/[^\s:]+:/),i=new RegExp(/"(?:\\"|.)*?"/),s=RegExp(`${t.source}(?:${i.source}|[^\\s]*)`),r=new RegExp(/[^\s]+/),a=RegExp(`${s.source}|${r.source}`,"g"),n=(this.searchInput.value.match(a)||[]).filter(t=>{let i=(t=this.removeNegationFromQualifierIfSupported(t)).indexOf(":");if(-1===i)return this.unqualifiedSearchTermsAlwaysValid?null:!e.some(e=>e.startsWith(t));{let s=t.substr(0,i+1);return!e.some(e=>e===s)}});return 0===n.length?null:n.join(" ")}searchMatchesDefault(){let e=this.searchInput.value.trim().split(" ").sort(),t=this.getDefaultSearch().trim().split(" ").sort();return e.length===t.length&&e.every((e,i)=>e===t[i])}getInitialValue(){return this.getDataAttributeOrThrow("data-initial-value")}getComponentTagName(){return this.tagName.toLowerCase()}getDefaultSearch(){return this.getDataAttributeOrThrow("data-default-value")}getDataAttributeOrThrow(e){let t=this.searchInput.getAttribute(e);if(null===t)throw Error(`${e} is missing from search input`);return t}renderSuggestionsTitle(){return(0,s.qy)`<p
      class="h6 width-full text-normal border-bottom color-bg-default color-fg-muted py-2 mb-2"
      aria-hidden="true"
    >
      ${this.suggestionsTitle}
    </p>`}async renderSuggestionList(e){let t=(await e).map((e,t)=>(0,s.qy)`
        <div
          class="border-bottom-0 rounded-2 py-1 px-2 mx-0 mb-1 js-navigation-item"
          data-value="${e.value}"
          data-action="navigation:focus:${this.getComponentTagName()}#handleSuggestionNavigation"
          aria-label="${e.value} ${e.description}"
          id="${this.getComponentTagName()}-suggestion-${t}"
          role="option"
        >
          <span class="text-bold">${e.value}</span>${this.spaceBetweenValueAndDescription?" ":""}<span
            class="autocomplete-text-qualifier color-fg-muted"
            >&nbsp;${e.description}</span
          >
          ${e.isAlpha&&this.alphaTag} ${e.isBeta&&this.betaTag}
          ${e.isNew?this.newTag:""}
        </div>
      `);return t.length&&t.unshift(this.renderSuggestionsTitle()),t}renderLoadingItem(){return(0,s.qy)`
      ${this.renderSuggestionsTitle()}
      <span class="js-filter-loading">loading...</span>
    `}handleSearchBlur(){this.hideFilterSuggestions(),this.selectorOfElementToActivateOnBlur&&(0,r.Yf)(document.querySelector(this.selectorOfElementToActivateOnBlur))}inputKey(e){"Escape"===e.key&&this.handleSearchBlur()}shouldRenderSubmissionOption(){return this.showSubmissionOptionIfInvalidSearchTerms||!this.invalidSearchTerms()}static tagFn(e){return(0,s.qy)`<span class="lh-condensed px-1 rounded-2 border color-border-success">${e}</span>`}constructor(...e){super(...e),g(this,"showAllQualifiersIfNoneMatch",!0),g(this,"fuzzyMatchQualifiers",!1),g(this,"fuzzyMatchValues",!0),g(this,"showSubmissionOptionIfInvalidSearchTerms",!1),g(this,"suggestionsTitle","Available filters"),g(this,"spaceBetweenValueAndDescription",!0),g(this,"selectorOfElementToActivateOnBlur",null),g(this,"unqualifiedSearchTermsAlwaysValid",!0),g(this,"alphaTag",BaseFilterElement.tagFn("Alpha")),g(this,"betaTag",BaseFilterElement.tagFn("Beta")),g(this,"newTag",(0,s.qy)`<span class="Label ml-1 Label--accent color-bg-default float-right">New</span>`)}};d([o.aC],BaseFilterElement.prototype,"autocompleteDropdown",void 0),d([o.aC],BaseFilterElement.prototype,"autocompleteResults",void 0),d([o.aC],BaseFilterElement.prototype,"clearButton",void 0),d([o.aC],BaseFilterElement.prototype,"searchForm",void 0),d([o.aC],BaseFilterElement.prototype,"searchInput",void 0),d([(0,n.A)({cache:p})],BaseFilterElement.prototype,"cachedJSON",null)}}]);
//# sourceMappingURL=app_assets_modules_github_filter-input_ts-da000cd80574.js.map
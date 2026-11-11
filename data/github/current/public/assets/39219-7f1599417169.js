(globalThis.webpackChunk_github_ui_github_ui=globalThis.webpackChunk_github_ui_github_ui||[]).push([[39219],{10201:(e,t,r)=>{"use strict";r.r(t),r.d(t,{Fragment:()=>n.Fragment,jsx:()=>c,jsxAttr:()=>h,jsxDEV:()=>c,jsxEscape:()=>function e(t){if(null==t||"boolean"==typeof t||"function"==typeof t)return null;if("object"==typeof t){if(void 0===t.constructor)return t;if(l(t)){for(var r=0;r<t.length;r++)t[r]=e(t[r]);return t}}return i(""+t)},jsxTemplate:()=>d,jsxs:()=>c});var n=r(27791),o=/["&<]/;function i(e){if(0===e.length||!1===o.test(e))return e;for(var t=0,r=0,n="",i="";r<e.length;r++){switch(e.charCodeAt(r)){case 34:i="&quot;";break;case 38:i="&amp;";break;case 60:i="&lt;";break;default:continue}r!==t&&(n+=e.slice(t,r)),n+=i,t=r+1}return r!==t&&(n+=e.slice(t,r)),n}var a=/acit|ex(?:s|g|n|p|$)|rph|grid|ows|mnc|ntw|ine[ch]|zoo|^ord|itera/i,s=0,l=Array.isArray;function c(e,t,r,o,i,a){t||(t={});var l,c,d=t;if("ref"in d)for(c in d={},t)"ref"==c?l=t[c]:d[c]=t[c];var u={type:e,props:d,key:r,ref:l,__k:null,__:null,__b:0,__e:null,__c:null,constructor:void 0,__v:--s,__i:-1,__u:0,__source:i,__self:a};if("function"==typeof e&&(l=e.defaultProps))for(c in l)void 0===d[c]&&(d[c]=l[c]);return n.options.vnode&&n.options.vnode(u),u}function d(e){var t=c(n.Fragment,{tpl:e,exprs:[].slice.call(arguments,1)});return t.key=t.__v,t}var u={},p=/[A-Z]/g;function h(e,t){if(n.options.attr){var r=n.options.attr(e,t);if("string"==typeof r)return r}if("ref"===e||"key"===e)return"";if("style"===e&&"object"==typeof t){var o="";for(var s in t){var l=t[s];if(null!=l&&""!==l){var c="-"==s[0]?s:u[s]||(u[s]=s.replace(p,"-$&").toLowerCase()),d=";";"number"!=typeof l||c.startsWith("--")||a.test(c)||(d="px;"),o=o+c+":"+l+d}}return e+'="'+o+'"'}return null==t||!1===t||"function"==typeof t||"object"==typeof t?"":!0===t?e:e+'="'+i(t)+'"'}},17402:(e,t,r)=>{"use strict";r.r(t),r.d(t,{Children:()=>w,Component:()=>n.Component,Fragment:()=>n.Fragment,PureComponent:()=>h,StrictMode:()=>en,Suspense:()=>_,SuspenseList:()=>C,__SECRET_INTERNALS_DO_NOT_USE_OR_YOU_WILL_BE_FIRED:()=>V,cloneElement:()=>Z,createContext:()=>n.createContext,createElement:()=>n.createElement,createFactory:()=>q,createPortal:()=>E,createRef:()=>n.createRef,default:()=>ei,findDOMNode:()=>ee,flushSync:()=>er,forwardRef:()=>x,hydrate:()=>P,isElement:()=>eo,isFragment:()=>J,isMemo:()=>K,isValidElement:()=>G,lazy:()=>j,memo:()=>m,render:()=>O,startTransition:()=>c,unmountComponentAtNode:()=>Q,unstable_batchedUpdates:()=>et,useCallback:()=>o.useCallback,useContext:()=>o.useContext,useDebugValue:()=>o.useDebugValue,useDeferredValue:()=>d,useEffect:()=>o.useEffect,useErrorBoundary:()=>o.useErrorBoundary,useId:()=>o.useId,useImperativeHandle:()=>o.useImperativeHandle,useInsertionEffect:()=>p,useLayoutEffect:()=>o.useLayoutEffect,useMemo:()=>o.useMemo,useReducer:()=>o.useReducer,useRef:()=>o.useRef,useState:()=>o.useState,useSyncExternalStore:()=>s,useTransition:()=>u,version:()=>X});var n=r(27791),o=r(45994);function i(e,t){for(var r in t)e[r]=t[r];return e}function a(e,t){for(var r in e)if("__source"!==r&&!(r in t))return!0;for(var n in t)if("__source"!==n&&e[n]!==t[n])return!0;return!1}function s(e,t){var r=t(),n=(0,o.useState)({t:{__:r,u:t}}),i=n[0].t,a=n[1];return(0,o.useLayoutEffect)(function(){i.__=r,i.u=t,l(i)&&a({t:i})},[e,r,t]),(0,o.useEffect)(function(){return l(i)&&a({t:i}),e(function(){l(i)&&a({t:i})})},[e]),r}function l(e){var t=e.u,r=e.__;try{var n=t();return(r!==n||0===r&&1/r!=1/n)&&(r==r||n==n)}catch(e){return!0}}function c(e){e()}function d(e){return e}function u(){return[!1,c]}var p=o.useLayoutEffect;function h(e,t){this.props=e,this.context=t}function m(e,t){function r(e){var r=this.props.ref,n=r==e.ref;return!n&&r&&(r.call?r(null):r.current=null),t?!t(this.props,e)||!n:a(this.props,e)}function o(t){return this.shouldComponentUpdate=r,(0,n.createElement)(e,t)}return o.displayName="Memo("+(e.displayName||e.name)+")",o.prototype.isReactComponent=!0,o.__f=!0,o}(h.prototype=new n.Component).isPureReactComponent=!0,h.prototype.shouldComponentUpdate=function(e,t){return a(this.props,e)||a(this.state,t)};var f=n.options.__b;n.options.__b=function(e){e.type&&e.type.__f&&e.ref&&(e.props.ref=e.ref,e.ref=null),f&&f(e)};var g="undefined"!=typeof Symbol&&Symbol.for&&Symbol.for("react.forward_ref")||3911;function x(e){function t(t){var r=i({},t);return delete r.ref,e(r,t.ref||null)}return t.$$typeof=g,t.render=t,t.prototype.isReactComponent=t.__f=!0,t.displayName="ForwardRef("+(e.displayName||e.name)+")",t}var b=function(e,t){return null==e?null:(0,n.toChildArray)((0,n.toChildArray)(e).map(t))},w={map:b,forEach:b,count:function(e){return e?(0,n.toChildArray)(e).length:0},only:function(e){var t=(0,n.toChildArray)(e);if(1!==t.length)throw"Children.only";return t[0]},toArray:n.toChildArray},v=n.options.__e;n.options.__e=function(e,t,r,n){if(e.then){for(var o,i=t;i=i.__;)if((o=i.__c)&&o.__c)return null==t.__e&&(t.__e=r.__e,t.__k=r.__k),o.__c(e,t)}v(e,t,r,n)};var y=n.options.unmount;function _(){this.__u=0,this.o=null,this.__b=null}function k(e){var t=e.__.__c;return t&&t.__a&&t.__a(e)}function j(e){var t,r,o;function i(i){if(t||(t=e()).then(function(e){r=e.default||e},function(e){o=e}),o)throw o;if(!r)throw t;return(0,n.createElement)(r,i)}return i.displayName="Lazy",i.__f=!0,i}function C(){this.i=null,this.l=null}n.options.unmount=function(e){var t=e.__c;t&&t.__R&&t.__R(),t&&32&e.__u&&(e.type=null),y&&y(e)},(_.prototype=new n.Component).__c=function(e,t){var r=t.__c,n=this;null==n.o&&(n.o=[]),n.o.push(r);var o=k(n.__v),i=!1,a=function(){i||(i=!0,r.__R=null,o?o(s):s())};r.__R=a;var s=function(){if(!--n.__u){if(n.state.__a){var e,t=n.state.__a;n.__v.__k[0]=function e(t,r,n){return t&&n&&(t.__v=null,t.__k=t.__k&&t.__k.map(function(t){return e(t,r,n)}),t.__c&&t.__c.__P===r&&(t.__e&&n.appendChild(t.__e),t.__c.__e=!0,t.__c.__P=n)),t}(t,t.__c.__P,t.__c.__O)}for(n.setState({__a:n.__b=null});e=n.o.pop();)e.forceUpdate()}};n.__u++||32&t.__u||n.setState({__a:n.__b=n.__v.__k[0]}),e.then(a,a)},_.prototype.componentWillUnmount=function(){this.o=[]},_.prototype.render=function(e,t){if(this.__b){if(this.__v.__k){var r=document.createElement("div"),o=this.__v.__k[0].__c;this.__v.__k[0]=function e(t,r,n){return t&&(t.__c&&t.__c.__H&&(t.__c.__H.__.forEach(function(e){"function"==typeof e.__c&&e.__c()}),t.__c.__H=null),null!=(t=i({},t)).__c&&(t.__c.__P===n&&(t.__c.__P=r),t.__c=null),t.__k=t.__k&&t.__k.map(function(t){return e(t,r,n)})),t}(this.__b,r,o.__O=o.__P)}this.__b=null}var a=t.__a&&(0,n.createElement)(n.Fragment,null,e.fallback);return a&&(a.__u&=-33),[(0,n.createElement)(n.Fragment,null,t.__a?null:e.children),a]};var S=function(e,t,r){if(++r[1]===r[0]&&e.l.delete(t),e.props.revealOrder&&("t"!==e.props.revealOrder[0]||!e.l.size))for(r=e.i;r;){for(;r.length>3;)r.pop()();if(r[1]<r[0])break;e.i=r=r[2]}};function N(e){return this.getChildContext=function(){return e.context},e.children}function T(e){var t=this,r=e.h;t.componentWillUnmount=function(){(0,n.render)(null,t.v),t.v=null,t.h=null},t.h&&t.h!==r&&t.componentWillUnmount(),t.v||(t.h=r,t.v={nodeType:1,parentNode:r,childNodes:[],contains:function(){return!0},appendChild:function(e){this.childNodes.push(e),t.h.appendChild(e)},insertBefore:function(e,r){this.childNodes.push(e),t.h.insertBefore(e,r)},removeChild:function(e){this.childNodes.splice(this.childNodes.indexOf(e)>>>1,1),t.h.removeChild(e)}}),(0,n.render)((0,n.createElement)(N,{context:t.context},e.__v),t.v)}function E(e,t){var r=(0,n.createElement)(T,{__v:e,h:t});return r.containerInfo=t,r}(C.prototype=new n.Component).__a=function(e){var t=this,r=k(t.__v),n=t.l.get(e);return n[0]++,function(o){var i=function(){t.props.revealOrder?(n.push(o),S(t,e,n)):o()};r?r(i):i()}},C.prototype.render=function(e){this.i=null,this.l=new Map;var t=(0,n.toChildArray)(e.children);e.revealOrder&&"b"===e.revealOrder[0]&&t.reverse();for(var r=t.length;r--;)this.l.set(t[r],this.i=[1,0,this.i]);return e.children},C.prototype.componentDidUpdate=C.prototype.componentDidMount=function(){var e=this;this.l.forEach(function(t,r){S(e,r,t)})};var z="undefined"!=typeof Symbol&&Symbol.for&&Symbol.for("react.element")||60103,R=/^(?:accent|alignment|arabic|baseline|cap|clip(?!PathU)|color|dominant|fill|flood|font|glyph(?!R)|horiz|image(!S)|letter|lighting|marker(?!H|W|U)|overline|paint|pointer|shape|stop|strikethrough|stroke|text(?!L)|transform|underline|unicode|units|v|vector|vert|word|writing|x(?!C))[A-Z]/,F=/^on(Ani|Tra|Tou|BeforeInp|Compo)/,M=/[A-Z0-9]/g,A="undefined"!=typeof document;function O(e,t,r){return null==t.__k&&(t.textContent=""),(0,n.render)(e,t),"function"==typeof r&&r(),e?e.__c:null}function P(e,t,r){return(0,n.hydrate)(e,t),"function"==typeof r&&r(),e?e.__c:null}n.Component.prototype.isReactComponent={},["componentWillMount","componentWillReceiveProps","componentWillUpdate"].forEach(function(e){Object.defineProperty(n.Component.prototype,e,{configurable:!0,get:function(){return this["UNSAFE_"+e]},set:function(t){Object.defineProperty(this,e,{configurable:!0,writable:!0,value:t})}})});var D=n.options.event;function I(){}function $(){return this.cancelBubble}function L(){return this.defaultPrevented}n.options.event=function(e){return D&&(e=D(e)),e.persist=I,e.isPropagationStopped=$,e.isDefaultPrevented=L,e.nativeEvent=e};var H,U={enumerable:!1,configurable:!0,get:function(){return this.class}},Y=n.options.vnode;n.options.vnode=function(e){"string"==typeof e.type&&function(e){var t=e.props,r=e.type,o={},i=-1===r.indexOf("-");for(var a in t){var s=t[a];if(!("value"===a&&"defaultValue"in t&&null==s||A&&"children"===a&&"noscript"===r||"class"===a||"className"===a)){var l,c=a.toLowerCase();"defaultValue"===a&&"value"in t&&null==t.value?a="value":"download"===a&&!0===s?s="":"translate"===c&&"no"===s?s=!1:"o"===c[0]&&"n"===c[1]?"ondoubleclick"===c?a="ondblclick":"onchange"!==c||"input"!==r&&"textarea"!==r||(l=t.type,("undefined"!=typeof Symbol&&"symbol"==typeof Symbol()?/fil|che|rad/:/fil|che|ra/).test(l))?"onfocus"===c?a="onfocusin":"onblur"===c?a="onfocusout":F.test(a)&&(a=c):c=a="oninput":i&&R.test(a)?a=a.replace(M,"-$&").toLowerCase():null===s&&(s=void 0),"oninput"===c&&o[a=c]&&(a="oninputCapture"),o[a]=s}}"select"==r&&o.multiple&&Array.isArray(o.value)&&(o.value=(0,n.toChildArray)(t.children).forEach(function(e){e.props.selected=-1!=o.value.indexOf(e.props.value)})),"select"==r&&null!=o.defaultValue&&(o.value=(0,n.toChildArray)(t.children).forEach(function(e){e.props.selected=o.multiple?-1!=o.defaultValue.indexOf(e.props.value):o.defaultValue==e.props.value})),t.class&&!t.className?(o.class=t.class,Object.defineProperty(o,"className",U)):(t.className&&!t.class||t.class&&t.className)&&(o.class=o.className=t.className),e.props=o}(e),e.$$typeof=z,Y&&Y(e)};var B=n.options.__r;n.options.__r=function(e){B&&B(e),H=e.__c};var W=n.options.diffed;n.options.diffed=function(e){W&&W(e);var t=e.props,r=e.__e;null!=r&&"textarea"===e.type&&"value"in t&&t.value!==r.value&&(r.value=null==t.value?"":t.value),H=null};var V={ReactCurrentDispatcher:{current:{readContext:function(e){return H.__n[e.__c].props.value},useCallback:o.useCallback,useContext:o.useContext,useDebugValue:o.useDebugValue,useDeferredValue:d,useEffect:o.useEffect,useId:o.useId,useImperativeHandle:o.useImperativeHandle,useInsertionEffect:p,useLayoutEffect:o.useLayoutEffect,useMemo:o.useMemo,useReducer:o.useReducer,useRef:o.useRef,useState:o.useState,useSyncExternalStore:s,useTransition:u}}},X="18.3.1";function q(e){return n.createElement.bind(null,e)}function G(e){return!!e&&e.$$typeof===z}function J(e){return G(e)&&e.type===n.Fragment}function K(e){return!!e&&!!e.displayName&&("string"==typeof e.displayName||e.displayName instanceof String)&&e.displayName.startsWith("Memo(")}function Z(e){return G(e)?n.cloneElement.apply(null,arguments):e}function Q(e){return!!e.__k&&((0,n.render)(null,e),!0)}function ee(e){return e&&(e.base||1===e.nodeType&&e)||null}var et=function(e,t){return e(t)},er=function(e,t){return e(t)},en=n.Fragment,eo=G,ei={useState:o.useState,useId:o.useId,useReducer:o.useReducer,useEffect:o.useEffect,useLayoutEffect:o.useLayoutEffect,useInsertionEffect:p,useTransition:u,useDeferredValue:d,useSyncExternalStore:s,startTransition:c,useRef:o.useRef,useImperativeHandle:o.useImperativeHandle,useMemo:o.useMemo,useCallback:o.useCallback,useContext:o.useContext,useDebugValue:o.useDebugValue,version:"18.3.1",Children:w,render:O,hydrate:P,unmountComponentAtNode:Q,createPortal:E,createElement:n.createElement,createContext:n.createContext,createFactory:q,cloneElement:Z,createRef:n.createRef,Fragment:n.Fragment,isValidElement:G,isElement:eo,isFragment:J,isMemo:K,findDOMNode:ee,Component:n.Component,PureComponent:h,memo:m,forwardRef:x,flushSync:er,unstable_batchedUpdates:et,StrictMode:en,Suspense:_,SuspenseList:C,lazy:j,__SECRET_INTERNALS_DO_NOT_USE_OR_YOU_WILL_BE_FIRED:V}},27791:(e,t,r)=>{"use strict";r.r(t),r.d(t,{Component:()=>S,Fragment:()=>C,cloneElement:()=>L,createContext:()=>H,createElement:()=>_,createRef:()=>j,h:()=>_,hydrate:()=>$,isValidElement:()=>a,options:()=>o,render:()=>I,toChildArray:()=>function e(t,r){return r=r||[],null==t||"boolean"==typeof t||(w(t)?t.some(function(t){e(t,r)}):r.push(t)),r}});var n,o,i,a,s,l,c,d,u,p,h,m,f,g={},x=[],b=/acit|ex(?:s|g|n|p|$)|rph|grid|ows|mnc|ntw|ine[ch]|zoo|^ord|itera/i,w=Array.isArray;function v(e,t){for(var r in t)e[r]=t[r];return e}function y(e){e&&e.parentNode&&e.parentNode.removeChild(e)}function _(e,t,r){var o,i,a,s={};for(a in t)"key"==a?o=t[a]:"ref"==a?i=t[a]:s[a]=t[a];if(arguments.length>2&&(s.children=arguments.length>3?n.call(arguments,2):r),"function"==typeof e&&null!=e.defaultProps)for(a in e.defaultProps)void 0===s[a]&&(s[a]=e.defaultProps[a]);return k(e,s,o,i,null)}function k(e,t,r,n,a){var s={type:e,props:t,key:r,ref:n,__k:null,__:null,__b:0,__e:null,__c:null,constructor:void 0,__v:null==a?++i:a,__i:-1,__u:0};return null==a&&null!=o.vnode&&o.vnode(s),s}function j(){return{current:null}}function C(e){return e.children}function S(e,t){this.props=e,this.context=t}function N(e,t){if(null==t)return e.__?N(e.__,e.__i+1):null;for(var r;t<e.__k.length;t++)if(null!=(r=e.__k[t])&&null!=r.__e)return r.__e;return"function"==typeof e.type?N(e):null}function T(e){(!e.__d&&(e.__d=!0)&&s.push(e)&&!E.__r++||l!==o.debounceRendering)&&((l=o.debounceRendering)||c)(E)}function E(){var e,t,r,n,i,a,l,c;for(s.sort(d);e=s.shift();)e.__d&&(t=s.length,n=void 0,a=(i=(r=e).__v).__e,l=[],c=[],r.__P&&((n=v({},i)).__v=i.__v+1,o.vnode&&o.vnode(n),A(r.__P,n,i,r.__n,r.__P.namespaceURI,32&i.__u?[a]:null,l,null==a?N(i):a,!!(32&i.__u),c),n.__v=i.__v,n.__.__k[n.__i]=n,O(l,n,c),n.__e!=a&&function e(t){var r,n;if(null!=(t=t.__)&&null!=t.__c){for(t.__e=t.__c.base=null,r=0;r<t.__k.length;r++)if(null!=(n=t.__k[r])&&null!=n.__e){t.__e=t.__c.base=n.__e;break}return e(t)}}(n)),s.length>t&&s.sort(d));E.__r=0}function z(e,t,r,n,i,a,s,l,c,d,u){var p,h,m,f,b,v,_=n&&n.__k||x,j=t.length;for(c=function(e,t,r,n,i){var a,s,l,c,d,u=r.length,p=u,h=0;for(e.__k=Array(i),a=0;a<i;a++)null!=(s=t[a])&&"boolean"!=typeof s&&"function"!=typeof s?(c=a+h,(s=e.__k[a]="string"==typeof s||"number"==typeof s||"bigint"==typeof s||s.constructor==String?k(null,s,null,null,null):w(s)?k(C,{children:s},null,null,null):void 0===s.constructor&&s.__b>0?k(s.type,s.props,s.key,s.ref?s.ref:null,s.__v):s).__=e,s.__b=e.__b+1,l=null,-1!==(d=s.__i=function(e,t,r,n){var o,i,a=e.key,s=e.type,l=t[r];if(null===l||l&&a==l.key&&s===l.type&&0==(2&l.__u))return r;if(n>+(null!=l&&0==(2&l.__u)))for(o=r-1,i=r+1;o>=0||i<t.length;){if(o>=0){if((l=t[o])&&0==(2&l.__u)&&a==l.key&&s===l.type)return o;o--}if(i<t.length){if((l=t[i])&&0==(2&l.__u)&&a==l.key&&s===l.type)return i;i++}}return -1}(s,r,c,p))&&(p--,(l=r[d])&&(l.__u|=2)),null==l||null===l.__v?(-1==d&&h--,"function"!=typeof s.type&&(s.__u|=4)):d!=c&&(d==c-1?h--:d==c+1?h++:(d>c?h--:h++,s.__u|=4))):e.__k[a]=null;if(p)for(a=0;a<u;a++)null!=(l=r[a])&&0==(2&l.__u)&&(l.__e==n&&(n=N(l)),function e(t,r,n){var i,a;if(o.unmount&&o.unmount(t),(i=t.ref)&&(i.current&&i.current!==t.__e||P(i,null,r)),null!=(i=t.__c)){if(i.componentWillUnmount)try{i.componentWillUnmount()}catch(e){o.__e(e,r)}i.base=i.__P=null}if(i=t.__k)for(a=0;a<i.length;a++)i[a]&&e(i[a],r,n||"function"!=typeof t.type);n||y(t.__e),t.__c=t.__=t.__e=void 0}(l,l));return n}(r,t,_,c,j),p=0;p<j;p++)null!=(m=r.__k[p])&&(h=-1===m.__i?g:_[m.__i]||g,m.__i=p,v=A(e,m,h,i,a,s,l,c,d,u),f=m.__e,m.ref&&h.ref!=m.ref&&(h.ref&&P(h.ref,null,m),u.push(m.ref,m.__c||f,m)),null==b&&null!=f&&(b=f),4&m.__u||h.__k===m.__k?c=function e(t,r,n){var o,i;if("function"==typeof t.type){for(o=t.__k,i=0;o&&i<o.length;i++)o[i]&&(o[i].__=t,r=e(o[i],r,n));return r}t.__e!=r&&(r&&t.type&&!n.contains(r)&&(r=N(t)),n.insertBefore(t.__e,r||null),r=t.__e);do r=r&&r.nextSibling;while(null!=r&&8==r.nodeType)return r}(m,c,e):"function"==typeof m.type&&void 0!==v?c=v:f&&(c=f.nextSibling),m.__u&=-7);return r.__e=b,c}function R(e,t,r){"-"==t[0]?e.setProperty(t,null==r?"":r):e[t]=null==r?"":"number"!=typeof r||b.test(t)?r:r+"px"}function F(e,t,r,n,o){var i;e:if("style"==t)if("string"==typeof r)e.style.cssText=r;else{if("string"==typeof n&&(e.style.cssText=n=""),n)for(t in n)r&&t in r||R(e.style,t,"");if(r)for(t in r)n&&r[t]===n[t]||R(e.style,t,r[t])}else if("o"==t[0]&&"n"==t[1])i=t!=(t=t.replace(u,"$1")),t=t.toLowerCase()in e||"onFocusOut"==t||"onFocusIn"==t?t.toLowerCase().slice(2):t.slice(2),e.l||(e.l={}),e.l[t+i]=r,r?n?r.u=n.u:(r.u=p,e.addEventListener(t,i?m:h,i)):e.removeEventListener(t,i?m:h,i);else{if("http://www.w3.org/2000/svg"==o)t=t.replace(/xlink(H|:h)/,"h").replace(/sName$/,"s");else if("width"!=t&&"height"!=t&&"href"!=t&&"list"!=t&&"form"!=t&&"tabIndex"!=t&&"download"!=t&&"rowSpan"!=t&&"colSpan"!=t&&"role"!=t&&"popover"!=t&&t in e)try{e[t]=null==r?"":r;break e}catch(e){}"function"==typeof r||(null==r||!1===r&&"-"!=t[4]?e.removeAttribute(t):e.setAttribute(t,"popover"==t&&1==r?"":r))}}function M(e){return function(t){if(this.l){var r=this.l[t.type+e];if(null==t.t)t.t=p++;else if(t.t<r.u)return;return r(o.event?o.event(t):t)}}}function A(e,t,r,i,a,s,l,c,d,u){var p,h,m,f,x,b,_,k,j,T,E,R,M,A,O,P,I,$=t.type;if(void 0!==t.constructor)return null;128&r.__u&&(d=!!(32&r.__u),s=[c=t.__e=r.__e]),(p=o.__b)&&p(t);e:if("function"==typeof $)try{if(k=t.props,j="prototype"in $&&$.prototype.render,T=(p=$.contextType)&&i[p.__c],E=p?T?T.props.value:p.__:i,r.__c?_=(h=t.__c=r.__c).__=h.__E:(j?t.__c=h=new $(k,E):(t.__c=h=new S(k,E),h.constructor=$,h.render=D),T&&T.sub(h),h.props=k,h.state||(h.state={}),h.context=E,h.__n=i,m=h.__d=!0,h.__h=[],h._sb=[]),j&&null==h.__s&&(h.__s=h.state),j&&null!=$.getDerivedStateFromProps&&(h.__s==h.state&&(h.__s=v({},h.__s)),v(h.__s,$.getDerivedStateFromProps(k,h.__s))),f=h.props,x=h.state,h.__v=t,m)j&&null==$.getDerivedStateFromProps&&null!=h.componentWillMount&&h.componentWillMount(),j&&null!=h.componentDidMount&&h.__h.push(h.componentDidMount);else{if(j&&null==$.getDerivedStateFromProps&&k!==f&&null!=h.componentWillReceiveProps&&h.componentWillReceiveProps(k,E),!h.__e&&(null!=h.shouldComponentUpdate&&!1===h.shouldComponentUpdate(k,h.__s,E)||t.__v==r.__v)){for(t.__v!=r.__v&&(h.props=k,h.state=h.__s,h.__d=!1),t.__e=r.__e,t.__k=r.__k,t.__k.some(function(e){e&&(e.__=t)}),R=0;R<h._sb.length;R++)h.__h.push(h._sb[R]);h._sb=[],h.__h.length&&l.push(h);break e}null!=h.componentWillUpdate&&h.componentWillUpdate(k,h.__s,E),j&&null!=h.componentDidUpdate&&h.__h.push(function(){h.componentDidUpdate(f,x,b)})}if(h.context=E,h.props=k,h.__P=e,h.__e=!1,M=o.__r,A=0,j){for(h.state=h.__s,h.__d=!1,M&&M(t),p=h.render(h.props,h.state,h.context),O=0;O<h._sb.length;O++)h.__h.push(h._sb[O]);h._sb=[]}else do h.__d=!1,M&&M(t),p=h.render(h.props,h.state,h.context),h.state=h.__s;while(h.__d&&++A<25)h.state=h.__s,null!=h.getChildContext&&(i=v(v({},i),h.getChildContext())),j&&!m&&null!=h.getSnapshotBeforeUpdate&&(b=h.getSnapshotBeforeUpdate(f,x)),c=z(e,w(P=null!=p&&p.type===C&&null==p.key?p.props.children:p)?P:[P],t,r,i,a,s,l,c,d,u),h.base=t.__e,t.__u&=-161,h.__h.length&&l.push(h),_&&(h.__E=h.__=null)}catch(e){if(t.__v=null,d||null!=s)if(e.then){for(t.__u|=d?160:128;c&&8==c.nodeType&&c.nextSibling;)c=c.nextSibling;s[s.indexOf(c)]=null,t.__e=c}else for(I=s.length;I--;)y(s[I]);else t.__e=r.__e,t.__k=r.__k;o.__e(e,t,r)}else null==s&&t.__v==r.__v?(t.__k=r.__k,t.__e=r.__e):c=t.__e=function(e,t,r,i,a,s,l,c,d){var u,p,h,m,f,x,b,v=r.props,_=t.props,k=t.type;if("svg"==k?a="http://www.w3.org/2000/svg":"math"==k?a="http://www.w3.org/1998/Math/MathML":a||(a="http://www.w3.org/1999/xhtml"),null!=s){for(u=0;u<s.length;u++)if((f=s[u])&&"setAttribute"in f==!!k&&(k?f.localName==k:3==f.nodeType)){e=f,s[u]=null;break}}if(null==e){if(null==k)return document.createTextNode(_);e=document.createElementNS(a,k,_.is&&_),c&&(o.__m&&o.__m(t,s),c=!1),s=null}if(null===k)v===_||c&&e.data===_||(e.data=_);else{if(s=s&&n.call(e.childNodes),v=r.props||g,!c&&null!=s)for(v={},u=0;u<e.attributes.length;u++)v[(f=e.attributes[u]).name]=f.value;for(u in v)if(f=v[u],"children"==u);else if("dangerouslySetInnerHTML"==u)h=f;else if(!(u in _)){if("value"==u&&"defaultValue"in _||"checked"==u&&"defaultChecked"in _)continue;F(e,u,null,f,a)}for(u in _)f=_[u],"children"==u?m=f:"dangerouslySetInnerHTML"==u?p=f:"value"==u?x=f:"checked"==u?b=f:c&&"function"!=typeof f||v[u]===f||F(e,u,f,v[u],a);if(p)c||h&&(p.__html===h.__html||p.__html===e.innerHTML)||(e.innerHTML=p.__html),t.__k=[];else if(h&&(e.innerHTML=""),z(e,w(m)?m:[m],t,r,i,"foreignObject"==k?"http://www.w3.org/1999/xhtml":a,s,l,s?s[0]:r.__k&&N(r,0),c,d),null!=s)for(u=s.length;u--;)y(s[u]);c||(u="value","progress"==k&&null==x?e.removeAttribute("value"):void 0===x||x===e[u]&&("progress"!=k||x)&&("option"!=k||x===v[u])||F(e,u,x,v[u],a),u="checked",void 0!==b&&b!==e[u]&&F(e,u,b,v[u],a))}return e}(r.__e,t,r,i,a,s,l,d,u);return(p=o.diffed)&&p(t),128&t.__u?void 0:c}function O(e,t,r){for(var n=0;n<r.length;n++)P(r[n],r[++n],r[++n]);o.__c&&o.__c(t,e),e.some(function(t){try{e=t.__h,t.__h=[],e.some(function(e){e.call(t)})}catch(e){o.__e(e,t.__v)}})}function P(e,t,r){try{if("function"==typeof e){var n="function"==typeof e.__u;n&&e.__u(),n&&null==t||(e.__u=e(t))}else e.current=t}catch(e){o.__e(e,r)}}function D(e,t,r){return this.constructor(e,r)}function I(e,t,r){var i,a,s,l;t==document&&(t=document.documentElement),o.__&&o.__(e,t),a=(i="function"==typeof r)?null:r&&r.__k||t.__k,s=[],l=[],A(t,e=(!i&&r||t).__k=_(C,null,[e]),a||g,g,t.namespaceURI,!i&&r?[r]:a?null:t.firstChild?n.call(t.childNodes):null,s,!i&&r?r:a?a.__e:t.firstChild,i,l),O(s,e,l)}function $(e,t){I(e,t,$)}function L(e,t,r){var o,i,a,s,l=v({},e.props);for(a in e.type&&e.type.defaultProps&&(s=e.type.defaultProps),t)"key"==a?o=t[a]:"ref"==a?i=t[a]:l[a]=void 0===t[a]&&void 0!==s?s[a]:t[a];return arguments.length>2&&(l.children=arguments.length>3?n.call(arguments,2):r),k(e.type,l,o||e.key,i||e.ref,null)}function H(e,t){var r={__c:t="__cC"+f++,__:e,Consumer:function(e,t){return e.children(t)},Provider:function(e){var r,n;return this.getChildContext||(r=new Set,(n={})[t]=this,this.getChildContext=function(){return n},this.componentWillUnmount=function(){r=null},this.shouldComponentUpdate=function(e){this.props.value!==e.value&&r.forEach(function(e){e.__e=!0,T(e)})},this.sub=function(e){r.add(e);var t=e.componentWillUnmount;e.componentWillUnmount=function(){r&&r.delete(e),t&&t.call(e)}}),e.children}};return r.Provider.__=r.Consumer.contextType=r}n=x.slice,o={__e:function(e,t,r,n){for(var o,i,a;t=t.__;)if((o=t.__c)&&!o.__)try{if((i=o.constructor)&&null!=i.getDerivedStateFromError&&(o.setState(i.getDerivedStateFromError(e)),a=o.__d),null!=o.componentDidCatch&&(o.componentDidCatch(e,n||{}),a=o.__d),a)return o.__E=o}catch(t){e=t}throw e}},i=0,a=function(e){return null!=e&&null==e.constructor},S.prototype.setState=function(e,t){var r;r=null!=this.__s&&this.__s!==this.state?this.__s:this.__s=v({},this.state),"function"==typeof e&&(e=e(v({},r),this.props)),e&&v(r,e),null!=e&&this.__v&&(t&&this._sb.push(t),T(this))},S.prototype.forceUpdate=function(e){this.__v&&(this.__e=!0,e&&this.__h.push(e),T(this))},S.prototype.render=C,s=[],c="function"==typeof Promise?Promise.prototype.then.bind(Promise.resolve()):setTimeout,d=function(e,t){return e.__v.__b-t.__v.__b},E.__r=0,u=/(PointerCapture)$|Capture$/i,p=0,h=M(!1),m=M(!0),f=0},39219:(e,t,r)=>{"use strict";let n,o,i,a;var s,l,c,d,u,p=Object.create,h=Object.defineProperty,m=Object.getOwnPropertyDescriptor,f=Object.getOwnPropertyNames,g=Object.getPrototypeOf,x=Object.prototype.hasOwnProperty,b=(e,t,r,n)=>{if(t&&"object"==typeof t||"function"==typeof t)for(let o of f(t))x.call(e,o)||o===r||h(e,o,{get:()=>t[o],enumerable:!(n=m(t,o))||n.enumerable});return e},w={},v={ReactScanInternals:()=>iC,Store:()=>ij,getIsProduction:()=>iR,getOptions:()=>iE,getReport:()=>iN,ignoreScan:()=>i$,ignoredProps:()=>iI,onRender:()=>iD,scan:()=>iO,setOptions:()=>iT,start:()=>iF,useScan:()=>iP};for(var y in v)h(w,y,{get:v[y],enumerable:!0});e.exports=b(h({},"__esModule",{value:!0}),w),Array.prototype.toSorted||Object.defineProperty(Array.prototype,"toSorted",{value:function(e){return[...this].sort(e)},writable:!0,configurable:!0}),r(62224);var _=r(61704),k=r(62224),j=r(62224),C=r(61704),S=r(62224);function N(e,t){return t-e}r(27791),r(62224);var T=e=>{let t="",r=new Map;for(let t of e){let{forget:e,time:n,aggregatedCount:o,name:i}=t;r.has(o)||r.set(o,[]);let a=r.get(o);a&&a.push({name:i,forget:e,time:n??0})}let n=Array.from(r.keys()).sort(N),o=[],i=0;for(let e of n){let t=r.get(e);if(!t)continue;let n=function(e){let t=e[0].name,r=Math.min(4,e.length);for(let n=1;n<r;n++)t+=`, ${e[n].name}`;return t}(t),a=function(e){let t=e[0].time;for(let r=1,n=e.length;r<n;r++)t+=e[r].time;return t}(t),s=function(e){for(let t=0,r=e.length;t<r;t++)if(e[t].forget)return!0;return!1}(t);i+=a,t.length>4&&(n+="\u2026"),e>1&&(n+=` \xd7 ${e}`),s&&(n=`\u2728${n}`),o.push(n)}return(t=o.join(", ")).length?(t.length>40&&(t=`${t.slice(0,40)}\u2026`),i>=.01&&(t+=` (${Number(i.toFixed(2))}ms)`),t):null};function E(e,t){return e===t||e!=e&&t!=t}var z=e=>{let t=e.createOscillator(),r=e.createGain();t.connect(r),r.connect(e.destination);let n=[392,600],o=.3/n.length;n.forEach((r,n)=>{t.frequency.setValueAtTime(r,e.currentTime+n*o)}),t.type="sine",r.gain.setValueAtTime(.12,e.currentTime),r.gain.setTargetAtTime(0,e.currentTime+.21,.05),t.start(),t.stop(e.currentTime+.3)},R={mount:1,update:2,unmount:4},F=r(62224),M=r(62224),A=r(61704),O=r(27791),P=r(45994),D=r(17402),I=r(10201),$=(0,D.forwardRef)(({size:e=15,name:t,fill:r="currentColor",stroke:n="currentColor",className:o,externalURL:i="",style:a},s)=>{let l=Array.isArray(e)?e[0]:e,c=Array.isArray(e)?e[1]||e[0]:e,d=`${i}#${t}`;return(0,I.jsxs)("svg",{ref:s,width:`${l}px`,height:`${c}px`,fill:r,stroke:n,className:o,style:{...a,minWidth:`${l}px`,maxWidth:`${l}px`,minHeight:`${c}px`,maxHeight:`${c}px`},children:[(0,I.jsx)("title",{children:t}),(0,I.jsx)("use",{href:d})]})}),L=r(61704),H="react-scan-widget-settings-v2",U="undefined"!=typeof window,Y=r(62224),B=(e,t)=>{if(0===e.length)return t.classGroupId;let r=e[0],n=t.nextPart.get(r),o=n?B(e.slice(1),n):void 0;if(o)return o;if(0===t.validators.length)return;let i=e.join("-");return t.validators.find(({validator:e})=>e(i))?.classGroupId},W=/^\[(.+)\]$/,V=(e,t,r,n)=>{e.forEach(e=>{if("string"==typeof e){(""===e?t:X(t,e)).classGroupId=r;return}"function"==typeof e?q(e)?V(e(n),t,r,n):t.validators.push({validator:e,classGroupId:r}):Object.entries(e).forEach(([e,o])=>{V(o,X(t,e),r,n)})})},X=(e,t)=>{let r=e;return t.split("-").forEach(e=>{r.nextPart.has(e)||r.nextPart.set(e,{nextPart:new Map,validators:[]}),r=r.nextPart.get(e)}),r},q=e=>e.isThemeGetter,G=(e,t)=>t?e.map(([e,r])=>[e,r.map(e=>"string"==typeof e?t+e:"object"==typeof e?Object.fromEntries(Object.entries(e).map(([e,r])=>[t+e,r])):e)]):e,J=e=>{if(e.length<=1)return e;let t=[],r=[];return e.forEach(e=>{"["===e[0]?(t.push(...r.sort(),e),r=[]):r.push(e)}),t.push(...r.sort()),t},K=/\s+/;function Z(){let e,t,r=0,n="";for(;r<arguments.length;)(e=arguments[r++])&&(t=Q(e))&&(n&&(n+=" "),n+=t);return n}var Q=e=>{let t;if("string"==typeof e)return e;let r="";for(let n=0;n<e.length;n++)e[n]&&(t=Q(e[n]))&&(r&&(r+=" "),r+=t);return r},ee=e=>{let t=t=>t[e]||[];return t.isThemeGetter=!0,t},et=/^\[(?:([a-z-]+):)?(.+)\]$/i,er=/^\d+\/\d+$/,en=new Set(["px","full","screen"]),eo=/^(\d+(\.\d+)?)?(xs|sm|md|lg|xl)$/,ei=/\d+(%|px|r?em|[sdl]?v([hwib]|min|max)|pt|pc|in|cm|mm|cap|ch|ex|r?lh|cq(w|h|i|b|min|max))|\b(calc|min|max|clamp)\(.+\)|^0$/,ea=/^(rgba?|hsla?|hwb|(ok)?(lab|lch))\(.+\)$/,es=/^(inset_)?-?((\d+)?\.?(\d+)[a-z]+|0)_-?((\d+)?\.?(\d+)[a-z]+|0)/,el=/^(url|image|image-set|cross-fade|element|(repeating-)?(linear|radial|conic)-gradient)\(.+\)$/,ec=e=>eu(e)||en.has(e)||er.test(e),ed=e=>ej(e,"length",eC),eu=e=>!!e&&!Number.isNaN(Number(e)),ep=e=>ej(e,"number",eu),eh=e=>!!e&&Number.isInteger(Number(e)),em=e=>e.endsWith("%")&&eu(e.slice(0,-1)),ef=e=>et.test(e),eg=e=>eo.test(e),ex=new Set(["length","size","percentage"]),eb=e=>ej(e,ex,eS),ew=e=>ej(e,"position",eS),ev=new Set(["image","url"]),ey=e=>ej(e,ev,eT),e_=e=>ej(e,"",eN),ek=()=>!0,ej=(e,t,r)=>{let n=et.exec(e);return!!n&&(n[1]?"string"==typeof t?n[1]===t:t.has(n[1]):r(n[2]))},eC=e=>ei.test(e)&&!ea.test(e),eS=()=>!1,eN=e=>es.test(e),eT=e=>el.test(e),eE=function(e,...t){let r,n,o,i=function(s){let l;return n=(r={cache:(e=>{if(e<1)return{get:()=>void 0,set:()=>{}};let t=0,r=new Map,n=new Map,o=(o,i)=>{r.set(o,i),++t>e&&(t=0,n=r,r=new Map)};return{get(e){let t=r.get(e);return void 0!==t?t:void 0!==(t=n.get(e))?(o(e,t),t):void 0},set(e,t){r.has(e)?r.set(e,t):o(e,t)}}})((l=t.reduce((e,t)=>t(e),e())).cacheSize),parseClassName:(e=>{let{separator:t,experimentalParseClassName:r}=e,n=1===t.length,o=t[0],i=t.length,a=e=>{let r,a=[],s=0,l=0;for(let c=0;c<e.length;c++){let d=e[c];if(0===s){if(d===o&&(n||e.slice(c,c+i)===t)){a.push(e.slice(l,c)),l=c+i;continue}if("/"===d){r=c;continue}}"["===d?s++:"]"===d&&s--}let c=0===a.length?e:e.substring(l),d=c.startsWith("!"),u=d?c.substring(1):c;return{modifiers:a,hasImportantModifier:d,baseClassName:u,maybePostfixModifierPosition:r&&r>l?r-l:void 0}};return r?e=>r({className:e,parseClassName:a}):a})(l),...(e=>{let t=(e=>{let{theme:t,prefix:r}=e,n={nextPart:new Map,validators:[]};return G(Object.entries(e.classGroups),r).forEach(([e,r])=>{V(r,n,e,t)}),n})(e),{conflictingClassGroups:r,conflictingClassGroupModifiers:n}=e;return{getClassGroupId:e=>{let r=e.split("-");return""===r[0]&&1!==r.length&&r.shift(),B(r,t)||(e=>{if(W.test(e)){let t=W.exec(e)[1],r=t?.substring(0,t.indexOf(":"));if(r)return"arbitrary.."+r}})(e)},getConflictingClassGroupIds:(e,t)=>{let o=r[e]||[];return t&&n[e]?[...o,...n[e]]:o}}})(l)}).cache.get,o=r.cache.set,i=a,a(s)};function a(e){let t=n(e);if(t)return t;let i=((e,t)=>{let{parseClassName:r,getClassGroupId:n,getConflictingClassGroupIds:o}=t,i=[],a=e.trim().split(K),s="";for(let e=a.length-1;e>=0;e-=1){let t=a[e],{modifiers:l,hasImportantModifier:c,baseClassName:d,maybePostfixModifierPosition:u}=r(t),p=!!u,h=n(p?d.substring(0,u):d);if(!h){if(!p||!(h=n(d))){s=t+(s.length>0?" "+s:s);continue}p=!1}let m=J(l).join(":"),f=c?m+"!":m,g=f+h;if(i.includes(g))continue;i.push(g);let x=o(h,p);for(let e=0;e<x.length;++e){let t=x[e];i.push(f+t)}s=t+(s.length>0?" "+s:s)}return s})(e,r);return o(e,i),i}return function(){return i(Z.apply(null,arguments))}}(()=>{let e=ee("colors"),t=ee("spacing"),r=ee("blur"),n=ee("brightness"),o=ee("borderColor"),i=ee("borderRadius"),a=ee("borderSpacing"),s=ee("borderWidth"),l=ee("contrast"),c=ee("grayscale"),d=ee("hueRotate"),u=ee("invert"),p=ee("gap"),h=ee("gradientColorStops"),m=ee("gradientColorStopPositions"),f=ee("inset"),g=ee("margin"),x=ee("opacity"),b=ee("padding"),w=ee("saturate"),v=ee("scale"),y=ee("sepia"),_=ee("skew"),k=ee("space"),j=ee("translate"),C=()=>["auto","contain","none"],S=()=>["auto","hidden","clip","visible","scroll"],N=()=>["auto",ef,t],T=()=>[ef,t],E=()=>["",ec,ed],z=()=>["auto",eu,ef],R=()=>["bottom","center","left","left-bottom","left-top","right","right-bottom","right-top","top"],F=()=>["solid","dashed","dotted","double","none"],M=()=>["normal","multiply","screen","overlay","darken","lighten","color-dodge","color-burn","hard-light","soft-light","difference","exclusion","hue","saturation","color","luminosity"],A=()=>["start","end","center","between","around","evenly","stretch"],O=()=>["","0",ef],P=()=>["auto","avoid","all","avoid-page","page","left","right","column"],D=()=>[eu,ef];return{cacheSize:500,separator:":",theme:{colors:[ek],spacing:[ec,ed],blur:["none","",eg,ef],brightness:D(),borderColor:[e],borderRadius:["none","","full",eg,ef],borderSpacing:T(),borderWidth:E(),contrast:D(),grayscale:O(),hueRotate:D(),invert:O(),gap:T(),gradientColorStops:[e],gradientColorStopPositions:[em,ed],inset:N(),margin:N(),opacity:D(),padding:T(),saturate:D(),scale:D(),sepia:O(),skew:D(),space:T(),translate:T()},classGroups:{aspect:[{aspect:["auto","square","video",ef]}],container:["container"],columns:[{columns:[eg]}],"break-after":[{"break-after":P()}],"break-before":[{"break-before":P()}],"break-inside":[{"break-inside":["auto","avoid","avoid-page","avoid-column"]}],"box-decoration":[{"box-decoration":["slice","clone"]}],box:[{box:["border","content"]}],display:["block","inline-block","inline","flex","inline-flex","table","inline-table","table-caption","table-cell","table-column","table-column-group","table-footer-group","table-header-group","table-row-group","table-row","flow-root","grid","inline-grid","contents","list-item","hidden"],float:[{float:["right","left","none","start","end"]}],clear:[{clear:["left","right","both","none","start","end"]}],isolation:["isolate","isolation-auto"],"object-fit":[{object:["contain","cover","fill","none","scale-down"]}],"object-position":[{object:[...R(),ef]}],overflow:[{overflow:S()}],"overflow-x":[{"overflow-x":S()}],"overflow-y":[{"overflow-y":S()}],overscroll:[{overscroll:C()}],"overscroll-x":[{"overscroll-x":C()}],"overscroll-y":[{"overscroll-y":C()}],position:["static","fixed","absolute","relative","sticky"],inset:[{inset:[f]}],"inset-x":[{"inset-x":[f]}],"inset-y":[{"inset-y":[f]}],start:[{start:[f]}],end:[{end:[f]}],top:[{top:[f]}],right:[{right:[f]}],bottom:[{bottom:[f]}],left:[{left:[f]}],visibility:["visible","invisible","collapse"],z:[{z:["auto",eh,ef]}],basis:[{basis:N()}],"flex-direction":[{flex:["row","row-reverse","col","col-reverse"]}],"flex-wrap":[{flex:["wrap","wrap-reverse","nowrap"]}],flex:[{flex:["1","auto","initial","none",ef]}],grow:[{grow:O()}],shrink:[{shrink:O()}],order:[{order:["first","last","none",eh,ef]}],"grid-cols":[{"grid-cols":[ek]}],"col-start-end":[{col:["auto",{span:["full",eh,ef]},ef]}],"col-start":[{"col-start":z()}],"col-end":[{"col-end":z()}],"grid-rows":[{"grid-rows":[ek]}],"row-start-end":[{row:["auto",{span:[eh,ef]},ef]}],"row-start":[{"row-start":z()}],"row-end":[{"row-end":z()}],"grid-flow":[{"grid-flow":["row","col","dense","row-dense","col-dense"]}],"auto-cols":[{"auto-cols":["auto","min","max","fr",ef]}],"auto-rows":[{"auto-rows":["auto","min","max","fr",ef]}],gap:[{gap:[p]}],"gap-x":[{"gap-x":[p]}],"gap-y":[{"gap-y":[p]}],"justify-content":[{justify:["normal",...A()]}],"justify-items":[{"justify-items":["start","end","center","stretch"]}],"justify-self":[{"justify-self":["auto","start","end","center","stretch"]}],"align-content":[{content:["normal",...A(),"baseline"]}],"align-items":[{items:["start","end","center","baseline","stretch"]}],"align-self":[{self:["auto","start","end","center","stretch","baseline"]}],"place-content":[{"place-content":[...A(),"baseline"]}],"place-items":[{"place-items":["start","end","center","baseline","stretch"]}],"place-self":[{"place-self":["auto","start","end","center","stretch"]}],p:[{p:[b]}],px:[{px:[b]}],py:[{py:[b]}],ps:[{ps:[b]}],pe:[{pe:[b]}],pt:[{pt:[b]}],pr:[{pr:[b]}],pb:[{pb:[b]}],pl:[{pl:[b]}],m:[{m:[g]}],mx:[{mx:[g]}],my:[{my:[g]}],ms:[{ms:[g]}],me:[{me:[g]}],mt:[{mt:[g]}],mr:[{mr:[g]}],mb:[{mb:[g]}],ml:[{ml:[g]}],"space-x":[{"space-x":[k]}],"space-x-reverse":["space-x-reverse"],"space-y":[{"space-y":[k]}],"space-y-reverse":["space-y-reverse"],w:[{w:["auto","min","max","fit","svw","lvw","dvw",ef,t]}],"min-w":[{"min-w":[ef,t,"min","max","fit"]}],"max-w":[{"max-w":[ef,t,"none","full","min","max","fit","prose",{screen:[eg]},eg]}],h:[{h:[ef,t,"auto","min","max","fit","svh","lvh","dvh"]}],"min-h":[{"min-h":[ef,t,"min","max","fit","svh","lvh","dvh"]}],"max-h":[{"max-h":[ef,t,"min","max","fit","svh","lvh","dvh"]}],size:[{size:[ef,t,"auto","min","max","fit"]}],"font-size":[{text:["base",eg,ed]}],"font-smoothing":["antialiased","subpixel-antialiased"],"font-style":["italic","not-italic"],"font-weight":[{font:["thin","extralight","light","normal","medium","semibold","bold","extrabold","black",ep]}],"font-family":[{font:[ek]}],"fvn-normal":["normal-nums"],"fvn-ordinal":["ordinal"],"fvn-slashed-zero":["slashed-zero"],"fvn-figure":["lining-nums","oldstyle-nums"],"fvn-spacing":["proportional-nums","tabular-nums"],"fvn-fraction":["diagonal-fractions","stacked-fractions"],tracking:[{tracking:["tighter","tight","normal","wide","wider","widest",ef]}],"line-clamp":[{"line-clamp":["none",eu,ep]}],leading:[{leading:["none","tight","snug","normal","relaxed","loose",ec,ef]}],"list-image":[{"list-image":["none",ef]}],"list-style-type":[{list:["none","disc","decimal",ef]}],"list-style-position":[{list:["inside","outside"]}],"placeholder-color":[{placeholder:[e]}],"placeholder-opacity":[{"placeholder-opacity":[x]}],"text-alignment":[{text:["left","center","right","justify","start","end"]}],"text-color":[{text:[e]}],"text-opacity":[{"text-opacity":[x]}],"text-decoration":["underline","overline","line-through","no-underline"],"text-decoration-style":[{decoration:[...F(),"wavy"]}],"text-decoration-thickness":[{decoration:["auto","from-font",ec,ed]}],"underline-offset":[{"underline-offset":["auto",ec,ef]}],"text-decoration-color":[{decoration:[e]}],"text-transform":["uppercase","lowercase","capitalize","normal-case"],"text-overflow":["truncate","text-ellipsis","text-clip"],"text-wrap":[{text:["wrap","nowrap","balance","pretty"]}],indent:[{indent:T()}],"vertical-align":[{align:["baseline","top","middle","bottom","text-top","text-bottom","sub","super",ef]}],whitespace:[{whitespace:["normal","nowrap","pre","pre-line","pre-wrap","break-spaces"]}],break:[{break:["normal","words","all","keep"]}],hyphens:[{hyphens:["none","manual","auto"]}],content:[{content:["none",ef]}],"bg-attachment":[{bg:["fixed","local","scroll"]}],"bg-clip":[{"bg-clip":["border","padding","content","text"]}],"bg-opacity":[{"bg-opacity":[x]}],"bg-origin":[{"bg-origin":["border","padding","content"]}],"bg-position":[{bg:[...R(),ew]}],"bg-repeat":[{bg:["no-repeat",{repeat:["","x","y","round","space"]}]}],"bg-size":[{bg:["auto","cover","contain",eb]}],"bg-image":[{bg:["none",{"gradient-to":["t","tr","r","br","b","bl","l","tl"]},ey]}],"bg-color":[{bg:[e]}],"gradient-from-pos":[{from:[m]}],"gradient-via-pos":[{via:[m]}],"gradient-to-pos":[{to:[m]}],"gradient-from":[{from:[h]}],"gradient-via":[{via:[h]}],"gradient-to":[{to:[h]}],rounded:[{rounded:[i]}],"rounded-s":[{"rounded-s":[i]}],"rounded-e":[{"rounded-e":[i]}],"rounded-t":[{"rounded-t":[i]}],"rounded-r":[{"rounded-r":[i]}],"rounded-b":[{"rounded-b":[i]}],"rounded-l":[{"rounded-l":[i]}],"rounded-ss":[{"rounded-ss":[i]}],"rounded-se":[{"rounded-se":[i]}],"rounded-ee":[{"rounded-ee":[i]}],"rounded-es":[{"rounded-es":[i]}],"rounded-tl":[{"rounded-tl":[i]}],"rounded-tr":[{"rounded-tr":[i]}],"rounded-br":[{"rounded-br":[i]}],"rounded-bl":[{"rounded-bl":[i]}],"border-w":[{border:[s]}],"border-w-x":[{"border-x":[s]}],"border-w-y":[{"border-y":[s]}],"border-w-s":[{"border-s":[s]}],"border-w-e":[{"border-e":[s]}],"border-w-t":[{"border-t":[s]}],"border-w-r":[{"border-r":[s]}],"border-w-b":[{"border-b":[s]}],"border-w-l":[{"border-l":[s]}],"border-opacity":[{"border-opacity":[x]}],"border-style":[{border:[...F(),"hidden"]}],"divide-x":[{"divide-x":[s]}],"divide-x-reverse":["divide-x-reverse"],"divide-y":[{"divide-y":[s]}],"divide-y-reverse":["divide-y-reverse"],"divide-opacity":[{"divide-opacity":[x]}],"divide-style":[{divide:F()}],"border-color":[{border:[o]}],"border-color-x":[{"border-x":[o]}],"border-color-y":[{"border-y":[o]}],"border-color-s":[{"border-s":[o]}],"border-color-e":[{"border-e":[o]}],"border-color-t":[{"border-t":[o]}],"border-color-r":[{"border-r":[o]}],"border-color-b":[{"border-b":[o]}],"border-color-l":[{"border-l":[o]}],"divide-color":[{divide:[o]}],"outline-style":[{outline:["",...F()]}],"outline-offset":[{"outline-offset":[ec,ef]}],"outline-w":[{outline:[ec,ed]}],"outline-color":[{outline:[e]}],"ring-w":[{ring:E()}],"ring-w-inset":["ring-inset"],"ring-color":[{ring:[e]}],"ring-opacity":[{"ring-opacity":[x]}],"ring-offset-w":[{"ring-offset":[ec,ed]}],"ring-offset-color":[{"ring-offset":[e]}],shadow:[{shadow:["","inner","none",eg,e_]}],"shadow-color":[{shadow:[ek]}],opacity:[{opacity:[x]}],"mix-blend":[{"mix-blend":[...M(),"plus-lighter","plus-darker"]}],"bg-blend":[{"bg-blend":M()}],filter:[{filter:["","none"]}],blur:[{blur:[r]}],brightness:[{brightness:[n]}],contrast:[{contrast:[l]}],"drop-shadow":[{"drop-shadow":["","none",eg,ef]}],grayscale:[{grayscale:[c]}],"hue-rotate":[{"hue-rotate":[d]}],invert:[{invert:[u]}],saturate:[{saturate:[w]}],sepia:[{sepia:[y]}],"backdrop-filter":[{"backdrop-filter":["","none"]}],"backdrop-blur":[{"backdrop-blur":[r]}],"backdrop-brightness":[{"backdrop-brightness":[n]}],"backdrop-contrast":[{"backdrop-contrast":[l]}],"backdrop-grayscale":[{"backdrop-grayscale":[c]}],"backdrop-hue-rotate":[{"backdrop-hue-rotate":[d]}],"backdrop-invert":[{"backdrop-invert":[u]}],"backdrop-opacity":[{"backdrop-opacity":[x]}],"backdrop-saturate":[{"backdrop-saturate":[w]}],"backdrop-sepia":[{"backdrop-sepia":[y]}],"border-collapse":[{border:["collapse","separate"]}],"border-spacing":[{"border-spacing":[a]}],"border-spacing-x":[{"border-spacing-x":[a]}],"border-spacing-y":[{"border-spacing-y":[a]}],"table-layout":[{table:["auto","fixed"]}],caption:[{caption:["top","bottom"]}],transition:[{transition:["none","all","","colors","opacity","shadow","transform",ef]}],duration:[{duration:D()}],ease:[{ease:["linear","in","out","in-out",ef]}],delay:[{delay:D()}],animate:[{animate:["none","spin","ping","pulse","bounce",ef]}],transform:[{transform:["","gpu","none"]}],scale:[{scale:[v]}],"scale-x":[{"scale-x":[v]}],"scale-y":[{"scale-y":[v]}],rotate:[{rotate:[eh,ef]}],"translate-x":[{"translate-x":[j]}],"translate-y":[{"translate-y":[j]}],"skew-x":[{"skew-x":[_]}],"skew-y":[{"skew-y":[_]}],"transform-origin":[{origin:["center","top","top-right","right","bottom-right","bottom","bottom-left","left","top-left",ef]}],accent:[{accent:["auto",e]}],appearance:[{appearance:["none","auto"]}],cursor:[{cursor:["auto","default","pointer","wait","text","move","help","not-allowed","none","context-menu","progress","cell","crosshair","vertical-text","alias","copy","no-drop","grab","grabbing","all-scroll","col-resize","row-resize","n-resize","e-resize","s-resize","w-resize","ne-resize","nw-resize","se-resize","sw-resize","ew-resize","ns-resize","nesw-resize","nwse-resize","zoom-in","zoom-out",ef]}],"caret-color":[{caret:[e]}],"pointer-events":[{"pointer-events":["none","auto"]}],resize:[{resize:["none","y","x",""]}],"scroll-behavior":[{scroll:["auto","smooth"]}],"scroll-m":[{"scroll-m":T()}],"scroll-mx":[{"scroll-mx":T()}],"scroll-my":[{"scroll-my":T()}],"scroll-ms":[{"scroll-ms":T()}],"scroll-me":[{"scroll-me":T()}],"scroll-mt":[{"scroll-mt":T()}],"scroll-mr":[{"scroll-mr":T()}],"scroll-mb":[{"scroll-mb":T()}],"scroll-ml":[{"scroll-ml":T()}],"scroll-p":[{"scroll-p":T()}],"scroll-px":[{"scroll-px":T()}],"scroll-py":[{"scroll-py":T()}],"scroll-ps":[{"scroll-ps":T()}],"scroll-pe":[{"scroll-pe":T()}],"scroll-pt":[{"scroll-pt":T()}],"scroll-pr":[{"scroll-pr":T()}],"scroll-pb":[{"scroll-pb":T()}],"scroll-pl":[{"scroll-pl":T()}],"snap-align":[{snap:["start","end","center","align-none"]}],"snap-stop":[{snap:["normal","always"]}],"snap-type":[{snap:["none","x","y","both"]}],"snap-strictness":[{snap:["mandatory","proximity"]}],touch:[{touch:["auto","none","manipulation"]}],"touch-x":[{"touch-pan":["x","left","right"]}],"touch-y":[{"touch-pan":["y","up","down"]}],"touch-pz":["touch-pinch-zoom"],select:[{select:["none","text","all","auto"]}],"will-change":[{"will-change":["auto","scroll","contents","transform",ef]}],fill:[{fill:[e,"none"]}],"stroke-w":[{stroke:[ec,ed,ep]}],stroke:[{stroke:[e,"none"]}],sr:["sr-only","not-sr-only"],"forced-color-adjust":[{"forced-color-adjust":["auto","none"]}]},conflictingClassGroups:{overflow:["overflow-x","overflow-y"],overscroll:["overscroll-x","overscroll-y"],inset:["inset-x","inset-y","start","end","top","right","bottom","left"],"inset-x":["right","left"],"inset-y":["top","bottom"],flex:["basis","grow","shrink"],gap:["gap-x","gap-y"],p:["px","py","ps","pe","pt","pr","pb","pl"],px:["pr","pl"],py:["pt","pb"],m:["mx","my","ms","me","mt","mr","mb","ml"],mx:["mr","ml"],my:["mt","mb"],size:["w","h"],"font-size":["leading"],"fvn-normal":["fvn-ordinal","fvn-slashed-zero","fvn-figure","fvn-spacing","fvn-fraction"],"fvn-ordinal":["fvn-normal"],"fvn-slashed-zero":["fvn-normal"],"fvn-figure":["fvn-normal"],"fvn-spacing":["fvn-normal"],"fvn-fraction":["fvn-normal"],"line-clamp":["display","overflow"],rounded:["rounded-s","rounded-e","rounded-t","rounded-r","rounded-b","rounded-l","rounded-ss","rounded-se","rounded-ee","rounded-es","rounded-tl","rounded-tr","rounded-br","rounded-bl"],"rounded-s":["rounded-ss","rounded-es"],"rounded-e":["rounded-se","rounded-ee"],"rounded-t":["rounded-tl","rounded-tr"],"rounded-r":["rounded-tr","rounded-br"],"rounded-b":["rounded-br","rounded-bl"],"rounded-l":["rounded-tl","rounded-bl"],"border-spacing":["border-spacing-x","border-spacing-y"],"border-w":["border-w-s","border-w-e","border-w-t","border-w-r","border-w-b","border-w-l"],"border-w-x":["border-w-r","border-w-l"],"border-w-y":["border-w-t","border-w-b"],"border-color":["border-color-s","border-color-e","border-color-t","border-color-r","border-color-b","border-color-l"],"border-color-x":["border-color-r","border-color-l"],"border-color-y":["border-color-t","border-color-b"],"scroll-m":["scroll-mx","scroll-my","scroll-ms","scroll-me","scroll-mt","scroll-mr","scroll-mb","scroll-ml"],"scroll-mx":["scroll-mr","scroll-ml"],"scroll-my":["scroll-mt","scroll-mb"],"scroll-p":["scroll-px","scroll-py","scroll-ps","scroll-pe","scroll-pt","scroll-pr","scroll-pb","scroll-pl"],"scroll-px":["scroll-pr","scroll-pl"],"scroll-py":["scroll-pt","scroll-pb"],touch:["touch-x","touch-y","touch-pz"],"touch-x":["touch"],"touch-y":["touch"],"touch-pz":["touch"]},conflictingClassGroupModifiers:{"font-size":["leading"]}}}),ez=(...e)=>eE(function(){for(var e,t,r=0,n="",o=arguments.length;r<o;r++)(e=arguments[r])&&(t=function e(t){var r,n,o="";if("string"==typeof t||"number"==typeof t)o+=t;else if("object"==typeof t)if(Array.isArray(t)){var i=t.length;for(r=0;r<i;r++)t[r]&&(n=e(t[r]))&&(o&&(o+=" "),o+=n)}else for(n in t)t[n]&&(o&&(o+=" "),o+=n);return o}(e))&&(n&&(n+=" "),n+=t);return n}(e));"undefined"!=typeof navigator&&navigator.userAgent.includes("Firefox");var eR=(e,t)=>{let r=0;return n=>{let o=Date.now();if(o-r>=t)return r=o,e(n)}},eF=e=>{if(!U)return null;try{let t=localStorage.getItem(e);return t?JSON.parse(t):null}catch{return null}},eM=(e,t)=>{if(U)try{window.localStorage.setItem(e,JSON.stringify(t))}catch{}},eA=e=>{if(!e)return{name:"Unknown",wrappers:[],wrapperTypes:[]};let{tag:t,type:r,elementType:n}=e,o=(0,Y.getDisplayName)(r),i=[],a=[];if((0,Y.hasMemoCache)(e)||t===Y.SimpleMemoComponentTag||t===Y.MemoComponentTag||r?.$$typeof===Symbol.for("react.memo")||n?.$$typeof===Symbol.for("react.memo")){let t=(0,Y.hasMemoCache)(e);a.push({type:"memo",title:t?"This component has been auto-memoized by the React Compiler.":"Memoized component that skips re-renders if props are the same",compiler:t})}if(24===t&&a.push({type:"lazy",title:"Lazily loaded component that supports code splitting"}),t===Y.SuspenseComponentTag&&a.push({type:"suspense",title:"Component that can suspend while content is loading"}),12===t&&a.push({type:"profiler",title:"Component that measures rendering performance"}),"string"==typeof o){let e=/^(\w+)\((.*)\)$/,t=o;for(;e.test(t);){let r=t.match(e);if(r?.[1]&&r?.[2])i.unshift(r[1]),t=r[2];else break}o=t}return{name:o||"Unknown",wrappers:i,wrapperTypes:a}},eO=(0,L.signal)(!1),eP=(0,L.signal)(null),eD={corner:"bottom-right",dimensions:{isFullWidth:!1,isFullHeight:!1,width:550,height:350,position:{x:24,y:24}},lastDimensions:{isFullWidth:!1,isFullHeight:!1,width:550,height:350,position:{x:24,y:24}},componentsTree:{width:240}},eI=(0,L.signal)((n=eF(H))?{corner:n.corner??eD.corner,dimensions:{isFullWidth:!1,isFullHeight:!1,width:550,height:350,position:n.dimensions.position??eD.dimensions.position},lastDimensions:n.dimensions??eD.dimensions,componentsTree:n.componentsTree??eD.componentsTree}:(eM(H,{corner:eD.corner,dimensions:eD.dimensions,lastDimensions:eD.lastDimensions,componentsTree:eD.componentsTree}),eD)),e$=()=>{if(!U)return;let{dimensions:e}=eI.value,{width:t,height:r,position:n}=e;eI.value={...eI.value,dimensions:{isFullWidth:t>=window.innerWidth-48,isFullHeight:r>=window.innerHeight-48,width:t,height:r,position:n}}},eL=(0,L.signal)({view:"none"}),eH=r(27791);function eU(){return!1}function eY(e){function t(t){return this.shouldComponentUpdate=eU,(0,eH.createElement)(e,t)}return t.displayName=`Memo(${e.displayName||e.name})`,t.prototype.isReactComponent=!0,t._forwarded=!0,t}var eB=r(45994),eW=r(45994);eF("react-scann-pinned");var eV=r(61704),eX=new WeakMap,eq={activeFlashes:new Map,create(e){let t,r,n,o=e.querySelector(".react-scan-flash-overlay"),i=o instanceof HTMLElement?o:((t=document.createElement("div")).className="react-scan-flash-overlay",e.appendChild(t),r=(()=>{e.querySelector(".react-scan-flash-overlay")&&this.create(e)}).bind(null,e),document.addEventListener("scroll",r,{passive:!0,capture:!0}),n=()=>{document.removeEventListener("scroll",r,{capture:!0})},this.activeFlashes.set(e,{element:e,overlay:t,scrollCleanup:n}),t),a=eX.get(i);a&&(clearTimeout(a),eX.delete(i)),requestAnimationFrame(()=>{i.style.transition="none",i.style.opacity="0.9";let t=setTimeout(()=>{i.style.transition="opacity 150ms ease-out",i.style.opacity="0";let t=setTimeout(()=>{i.parentNode&&i.parentNode.removeChild(i);let t=this.activeFlashes.get(e);t?.scrollCleanup&&t.scrollCleanup(),this.activeFlashes.delete(e),eX.delete(i)},150);eX.set(i,t)},300);eX.set(i,t)})},cleanup(e){let t=this.activeFlashes.get(e);if(t){let r=eX.get(t.overlay);r&&(clearTimeout(r),eX.delete(t.overlay)),t.overlay.parentNode&&t.overlay.parentNode.removeChild(t.overlay),t.scrollCleanup&&t.scrollCleanup(),this.activeFlashes.delete(e)}},cleanupAll(){for(let[,e]of this.activeFlashes)this.cleanup(e.element)}},eG={updates:[],currentFiber:null,totalUpdates:0,windowOffset:0,currentIndex:0,isViewingHistory:!1,latestFiber:null,isVisible:!1,playbackSpeed:1},eJ=(0,eV.signal)(eG),eK=(0,eV.signal)(0),eZ=[],eQ=null,e0=r(61704),e1=(0,e0.signal)({query:"",matches:[],currentMatchIndex:-1}),e2=(0,e0.signal)(!1),e4=r(10201),e5=(e,t=0,r=null)=>e.reduce((e,n,o)=>{let i=n.element?(e=>{let t=[],r=e;for(;r;){let e=r.elementType,n="function"==typeof e?e.displayName||e.name:"string"==typeof e?e:"Unknown",o=void 0!==r.index?`[${r.index}]`:"";t.unshift(`${n}${o}`),r=r.return??null}return t.join("::")})(n.fiber):`${r}-${o}`,a=n.fiber?.type?r_(n.fiber):void 0,s={...n,depth:t,nodeId:i,parentId:r,fiber:n.fiber,renderData:a};return e.push(s),n.children?.length&&e.push(...e5(n.children,t+1,i)),e},[]),e3=["memo","forwardRef","lazy","suspense"],e6=e=>{let t=e.match(/\[(.*?)\]/);if(!t)return null;let r=[];for(let e of t[1].split(",")){let t=e.trim().toLowerCase();t&&r.push(t)}return r},e8=(e,t)=>{if(0===e.length)return!0;if(!t.length)return!1;for(let r of e){let e=!1;for(let n of t)if(n.type.toLowerCase().includes(r)){e=!0;break}if(!e)return!1}return!0},e7=e=>e>0?e<.1-Number.EPSILON?"< 0.1":e<1e3?Number(e.toFixed(1)).toString():`${(e/1e3).toFixed(1)}k`:"0",e9=({node:e,nodeIndex:t,hasChildren:r,isCollapsed:n,handleTreeNodeClick:o,handleTreeNodeToggle:i,searchValue:a})=>{let s=(0,eB.useRef)(null),l=(0,eB.useRef)(e.renderData?.renderCount??0),{highlightedText:c,typeHighlight:d}=(0,eB.useMemo)(()=>{let{query:t,matches:r}=a,n=r.some(t=>t.nodeId===e.nodeId),o=e6(t)||[],i=t?t.replace(/\[.*?\]/,"").trim():"";if(!t||!n)return{highlightedText:(0,e4.jsx)("span",{className:"truncate",children:e.label}),typeHighlight:!1};let s=!0;if(o.length>0)if(e.fiber){let{wrapperTypes:t}=eA(e.fiber);s=e8(o,t)}else s=!1;let l=(0,e4.jsx)("span",{className:"truncate",children:e.label});if(i)try{if(i.startsWith("/")&&i.endsWith("/")){let t=i.slice(1,-1),r=RegExp(`(${t})`,"i"),n=e.label.split(r);l=(0,e4.jsx)("span",{className:"tree-node-search-highlight",children:n.map((t,o)=>r.test(t)?(0,e4.jsx)("span",{className:ez("regex",{start:r.test(t)&&0===o,middle:r.test(t)&&o%2==1,end:r.test(t)&&o===n.length-1,"!ml-0":1===o}),children:t},`${e.nodeId}-${t}`):t)})}else{let t=e.label.toLowerCase(),r=i.toLowerCase(),n=t.indexOf(r);n>=0&&(l=(0,e4.jsxs)("span",{className:"tree-node-search-highlight",children:[e.label.slice(0,n),(0,e4.jsx)("span",{className:"single",children:e.label.slice(n,n+i.length)}),e.label.slice(n+i.length)]}))}}catch{}return{highlightedText:l,typeHighlight:s&&o.length>0}},[e.label,e.nodeId,e.fiber,a]);(0,eB.useEffect)(()=>{let t=e.renderData?.renderCount,r=s.current;r&&l.current&&t&&l.current!==t&&(r.classList.remove("count-flash"),r.offsetWidth,r.classList.add("count-flash"),l.current=t)},[e.renderData?.renderCount]);let u=(0,eB.useMemo)(()=>{if(!e.renderData)return null;let{selfTime:t,totalTime:r,renderCount:n}=e.renderData;return n?(0,e4.jsx)("span",{className:ez("flex items-center gap-x-0.5 ml-1.5","text-[10px] text-neutral-400"),children:(0,e4.jsxs)("span",{ref:s,title:`Self time: ${e7(t)}ms
Total time: ${e7(r)}ms`,className:"count-badge",children:["\xd7",n]})}):null},[e.renderData]),p=(0,eB.useMemo)(()=>{if(!e.fiber)return null;let{wrapperTypes:t}=eA(e.fiber),r=t[0];return(0,e4.jsxs)("span",{className:ez("flex items-center gap-x-1","text-[10px] text-neutral-400 tracking-wide","overflow-hidden"),children:[r&&(0,e4.jsxs)(e4.Fragment,{children:[(0,e4.jsx)("span",{title:r?.title,className:ez("rounded py-[1px] px-1","bg-neutral-700 text-neutral-300","truncate","memo"===r.type&&"bg-[#8e61e3] text-white",d&&"bg-yellow-300 text-black"),children:r.type},r.type),r.compiler&&(0,e4.jsx)("span",{className:"text-yellow-300 ml-1",children:"\u2728"})]}),t.length>1&&`\xd7${t.length}`,u]})},[e.fiber,d,u]);return(0,e4.jsxs)("button",{type:"button",title:e.title,"data-index":t,className:ez("flex items-center gap-x-1","pl-1 pr-2","w-full h-7","text-left","rounded","cursor-pointer select-none"),onClick:o,children:[(0,e4.jsx)("button",{type:"button","data-index":t,onClick:i,className:ez("w-6 h-6 flex items-center justify-center","text-left"),children:r&&(0,e4.jsx)($,{name:"icon-chevron-right",size:12,className:ez("transition-transform",!n&&"rotate-90")})}),c,p]})},te=()=>{let e=(0,eB.useRef)(null),t=(0,eB.useRef)(null),r=(0,eB.useRef)(null),n=(0,eB.useRef)(null),o=(0,eB.useRef)(null),i=(0,eB.useRef)(0),a=(0,eB.useRef)(!1),s=(0,eB.useRef)(!1),l=(0,eB.useRef)(null),[c,d]=(0,eB.useState)([]),[u,p]=(0,eB.useState)(new Set),[h,m]=(0,eB.useState)(void 0),[f,g]=(0,eB.useState)(e1.value),x=(0,eB.useMemo)(()=>{let e=[],t=new Map(c.map(e=>[e.nodeId,e]));for(let r of c){let n=!0,o=r;for(;o.parentId;){let e=t.get(o.parentId);if(!e)break;if(u.has(e.nodeId)){n=!1;break}o=e}n&&e.push(r)}return e},[u,c]),{virtualItems:b,totalSize:w}=(e=>{let{count:t,getScrollElement:r,estimateSize:n,overscan:o=5}=e,[i,a]=(0,eW.useState)(0),[s,l]=(0,eW.useState)(0),c=(0,eW.useRef)(),d=(0,eW.useRef)(null),u=(0,eW.useRef)(null),p=n(),h=(0,eW.useCallback)(e=>{d.current&&l(e?.[0]?.contentRect.height??d.current.getBoundingClientRect().height)},[]),m=(0,eW.useCallback)(()=>{null!==u.current&&cancelAnimationFrame(u.current),u.current=requestAnimationFrame(()=>{h(),u.current=null})},[h]);(0,eW.useEffect)(()=>{let e=r();if(!e)return;d.current=e;let t=()=>{d.current&&a(d.current.scrollTop)};h(),c.current||(c.current=new ResizeObserver(()=>{m()})),c.current.observe(e),e.addEventListener("scroll",t,{passive:!0});let n=new MutationObserver(m);return n.observe(e,{attributes:!0,childList:!0,subtree:!0}),()=>{e.removeEventListener("scroll",t),c.current&&c.current.disconnect(),n.disconnect(),null!==u.current&&cancelAnimationFrame(u.current)}},[r,h,m]);let f=(0,eW.useMemo)(()=>{let e=Math.floor(i/p);return{start:Math.max(0,e-o),end:Math.min(t,e+Math.ceil(s/p)+o)}},[i,p,s,t,o]);return{virtualItems:(0,eW.useMemo)(()=>{let e=[];for(let t=f.start;t<f.end;t++)e.push({key:t,index:t,start:t*p});return e},[f,p]),totalSize:t*p,scrollTop:i,containerHeight:s}})({count:x.length,getScrollElement:()=>e.current,estimateSize:()=>28,overscan:5}),v=(0,eB.useCallback)(t=>{a.current=!0,n.current?.blur(),e2.value=!0;let{parentCompositeFiber:r}=tU(t);if(!r)return;ij.inspectState.value={kind:"focused",focusedDomElement:t,fiber:r};let o=x.findIndex(e=>e.element===t);if(-1!==o){m(o);let t=28*o,r=e.current;if(r){let e=r.clientHeight,n=r.scrollTop;(t<n||t+28>n+e)&&r.scrollTo({top:Math.max(0,t-e/2),behavior:"instant"})}}},[x]),y=(0,eB.useCallback)(e=>{let t=Number(e.currentTarget.dataset.index);if(Number.isNaN(t))return;let r=x[t].element;r&&v(r)},[x,v]),_=(0,eB.useCallback)(e=>{p(t=>{let r=new Set(t);return r.has(e)?r.delete(e):r.add(e),r})},[]),k=(0,eB.useCallback)(e=>{e.stopPropagation();let t=Number(e.target.dataset.index);Number.isNaN(t)||_(x[t].nodeId)},[x,_]),j=(0,eB.useCallback)(t=>{r.current?.classList.remove("!border-red-500");let n=[];if(!t){e1.value={query:t,matches:n,currentMatchIndex:-1};return}if(t.includes("[")&&!t.includes("]")&&t.length>t.indexOf("[")+1)return void r.current?.classList.add("!border-red-500");let o=e6(t)||[];if(t.includes("[")&&!(e=>{if(0===e.length)return!1;for(let t of e){let e=!1;for(let r of e3)if(r.toLowerCase().includes(t)){e=!0;break}if(!e)return!1}return!0})(o))return void r.current?.classList.add("!border-red-500");let i=t.replace(/\[.*?\]/,"").trim(),a=/^\/.*\/$/.test(i),s=e=>!1;if(i.startsWith("/")&&!a&&i.length>1)return void r.current?.classList.add("!border-red-500");if(a)try{let e=i.slice(1,-1),t=RegExp(e,"i");s=e=>t.test(e)}catch{r.current?.classList.add("!border-red-500");return}else if(i){let e=i.toLowerCase();s=t=>t.toLowerCase().includes(e)}for(let e of c){let t=!0;if(i&&(t=s(e.label)),t&&o.length>0)if(e.fiber){let{wrapperTypes:r}=eA(e.fiber);t=e8(o,r)}else t=!1;t&&n.push(e)}if(e1.value={query:t,matches:n,currentMatchIndex:n.length>0?0:-1},n.length>0){let t=n[0],r=x.findIndex(e=>e.nodeId===t.nodeId);if(-1!==r){let t=e.current;if(t){let e=t.clientHeight;t.scrollTo({top:Math.max(0,28*r-e/2),behavior:"instant"})}}}},[c,x]),C=(0,eB.useCallback)(e=>{let t=e.currentTarget;t&&j(t.value)},[j]),S=(0,eB.useCallback)(t=>{let{matches:r,currentMatchIndex:n}=e1.value;if(0===r.length)return;let o="next"===t?(n+1)%r.length:(n-1+r.length)%r.length;e1.value={...e1.value,currentMatchIndex:o};let i=r[o],a=x.findIndex(e=>e.nodeId===i.nodeId);if(-1!==a){m(a);let t=28*a,r=e.current;if(r){let e=r.clientHeight;r.scrollTo({top:Math.max(0,t-e/2),behavior:"instant"})}}},[x]),N=(0,eB.useCallback)(r=>{if(t.current&&(t.current.style.width=`${r}px`),e.current){e.current.style.width=`${r}px`;let t=((e,t)=>{if(t<=0)return 24;let r=Math.max(0,e-240);return r<24?0:Math.max(0,Math.min(24,Math.min(.3*r,24*t)/t))})(r,i.current);e.current.style.setProperty("--indentation-size",`${t}px`)}},[]),T=(0,eB.useCallback)(e=>{if(!l.current)return;let t=Math.floor(eI.value.dimensions.width-120);l.current.classList.remove("cursor-ew-resize","cursor-w-resize","cursor-e-resize"),e<=240?l.current.classList.add("cursor-w-resize"):e>=t?l.current.classList.add("cursor-e-resize"):l.current.classList.add("cursor-ew-resize")},[]),E=(0,eB.useCallback)(t=>{if(t.preventDefault(),t.stopPropagation(),!e.current)return;e.current.style.setProperty("pointer-events","none"),s.current=!0;let r=t.clientX,n=e.current.offsetWidth,o=Math.floor(eI.value.dimensions.width-120);T(n);let i=e=>{let t=n+(r-e.clientX);T(t),N(Math.min(o,Math.max(240,t)))},a=()=>{e.current&&(e.current.style.removeProperty("pointer-events"),document.removeEventListener("pointermove",i),document.removeEventListener("pointerup",a),eI.value={...eI.value,componentsTree:{...eI.value.componentsTree,width:e.current.offsetWidth}},eM(H,eI.value),s.current=!1)};document.addEventListener("pointermove",i),document.addEventListener("pointerup",a)},[N,T]);(0,eB.useEffect)(()=>{if(e.current)return T(e.current.offsetWidth),eI.subscribe(()=>{e.current&&T(e.current.offsetWidth)})},[T]);let z=(0,eB.useCallback)(()=>{a.current=!1},[]);return(0,eB.useEffect)(()=>{let t=!0,r=()=>{let r=o.current;if(!r)return;let n=(e=>{let t=new Map,r=[];for(let{element:r,name:n,fiber:o}of e){if(!r)continue;let e=n,{name:i,wrappers:a}=eA(o);i&&(e=a.length>0?`${a.join("(")}(${i})${")".repeat(a.length)}`:i),t.set(r,{label:i||n,title:e,children:[],element:r,fiber:o})}for(let{element:n,depth:o}of e){if(!n)continue;let e=t.get(n);if(e)if(0===o)r.push(e);else{let r=n.parentElement;for(;r;){let n=t.get(r);if(n){n.children=n.children||[],n.children.push(e);break}r=r.parentElement}}}return r})(tX());if(n.length>0){let o=e5(n);if(i.current=o.reduce((e,t)=>Math.max(e,t.depth),0),N(eI.value.componentsTree.width),d(o),t){t=!1;let n=o.findIndex(e=>e.element===r);if(-1!==n){let t=28*n,r=e.current;r&&setTimeout(()=>{r.scrollTo({top:t,behavior:"instant"})},96)}}}},n=ij.inspectState.subscribe(e=>{"focused"===e.kind&&(e2.value||(j(""),o.current=e.focusedDomElement,r()))}),a=0,l=eK.subscribe(()=>{"focused"===ij.inspectState.value.kind&&(cancelAnimationFrame(a),s.current||(a=requestAnimationFrame(()=>{e2.value=!1,r()})))});return()=>{n(),l(),e1.value={query:"",matches:[],currentMatchIndex:-1}}},[]),(0,eB.useEffect)(()=>{let e=e=>{if(a.current&&h)switch(e.key){case"ArrowUp":if(e.preventDefault(),e.stopPropagation(),h>0){let e=x[h-1];e?.element&&v(e.element)}return;case"ArrowDown":if(e.preventDefault(),e.stopPropagation(),h<x.length-1){let e=x[h+1];e?.element&&v(e.element)}return;case"ArrowLeft":case"ArrowRight":{e.preventDefault(),e.stopPropagation();let t=x[h];t?.nodeId&&_(t.nodeId);return}}};return document.addEventListener("keydown",e),()=>{document.removeEventListener("keydown",e)}},[h,x,v,_]),(0,eB.useEffect)(()=>e1.subscribe(g),[]),(0,eB.useEffect)(()=>eI.subscribe(e=>{t.current?.style.setProperty("transition","width 0.1s"),N(e.componentsTree.width),setTimeout(()=>{t.current?.style.removeProperty("transition")},500)}),[]),(0,e4.jsxs)("div",{className:"react-scan-components-tree flex",children:[(0,e4.jsx)("div",{ref:l,onPointerDown:E,className:"relative resize-v-line",children:(0,e4.jsx)("span",{children:(0,e4.jsx)($,{name:"icon-ellipsis",size:18})})}),(0,e4.jsxs)("div",{ref:t,className:"flex flex-col h-full",children:[(0,e4.jsx)("div",{className:"p-2 border-b border-[#1e1e1e]",children:(0,e4.jsxs)("div",{ref:r,title:`Search components by:

\u2022 Name (e.g., "Button") \u2014 Case insensitive, matches any part

\u2022 Regular Expression (e.g., "/^Button/") \u2014 Use forward slashes

\u2022 Wrapper Type (e.g., "[memo,forwardRef]"):
   - Available types: memo, forwardRef, lazy, suspense
   - Matches any part of type name (e.g., "mo" matches "memo")
   - Use commas for multiple types

\u2022 Combined Search:
   - Mix name/regex with type: "button [for]"
   - Will match components satisfying both conditions

\u2022 Navigation:
   - Enter \u2192 Next match
   - Shift + Enter \u2192 Previous match
   - Cmd/Ctrl + Enter \u2192 Select and focus match
`,className:ez("relative","flex items-center gap-x-1 px-2","rounded","border border-transparent","focus-within:border-[#454545]","bg-[#1e1e1e] text-neutral-300","transition-colors","whitespace-nowrap","overflow-hidden"),children:[(0,e4.jsx)($,{name:"icon-search",size:12,className:" text-neutral-500"}),(0,e4.jsx)("div",{className:"relative flex-1 h-7 overflow-hidden",children:(0,e4.jsx)("input",{ref:n,type:"text",value:e1.value.query,onClick:e=>{e.stopPropagation(),e.currentTarget.focus()},onPointerDown:e=>{e.stopPropagation()},onKeyDown:e=>{"Escape"===e.key&&e.currentTarget.blur(),e1.value.matches.length&&("Enter"===e.key&&e.shiftKey?S("prev"):"Enter"===e.key&&(e.metaKey||e.ctrlKey?(e.preventDefault(),e.stopPropagation(),v(e1.value.matches[e1.value.currentMatchIndex].element),e.currentTarget.focus()):S("next")))},onChange:C,className:"absolute inset-y-0 inset-x-1",placeholder:"Component name, /regex/, or [type]"})}),e1.value.query?(0,e4.jsxs)(e4.Fragment,{children:[(0,e4.jsxs)("span",{className:"flex items-center gap-x-0.5 text-xs text-neutral-500",children:[e1.value.currentMatchIndex+1,"|",e1.value.matches.length]}),!!e1.value.matches.length&&(0,e4.jsxs)(e4.Fragment,{children:[(0,e4.jsx)("button",{type:"button",onClick:e=>{e.stopPropagation(),S("prev")},className:"button rounded w-4 h-4 flex items-center justify-center text-neutral-400 hover:text-neutral-300",children:(0,e4.jsx)($,{name:"icon-chevron-right",className:"-rotate-90",size:12})}),(0,e4.jsx)("button",{type:"button",onClick:e=>{e.stopPropagation(),S("next")},className:"button rounded w-4 h-4 flex items-center justify-center text-neutral-400 hover:text-neutral-300",children:(0,e4.jsx)($,{name:"icon-chevron-right",className:"rotate-90",size:12})})]}),(0,e4.jsx)("button",{type:"button",onClick:e=>{e.stopPropagation(),j("")},className:"button rounded w-4 h-4 flex items-center justify-center text-neutral-400 hover:text-neutral-300",children:(0,e4.jsx)($,{name:"icon-close",size:12})})]}):!!c.length&&(0,e4.jsx)("span",{className:"text-xs text-neutral-500",children:c.length})]})}),(0,e4.jsx)("div",{className:"flex-1 overflow-hidden",children:(0,e4.jsx)("div",{ref:e,onPointerLeave:z,className:"tree h-full overflow-auto will-change-transform",children:(0,e4.jsx)("div",{className:"relative w-full",style:{height:w},children:b.map(e=>{let t=x[e.index];if(!t)return null;let r="focused"===ij.inspectState.value.kind&&t.element===ij.inspectState.value.focusedDomElement,n=e.index===h;return(0,e4.jsx)("div",{className:ez("absolute left-0 w-full overflow-hidden","text-neutral-400 hover:text-neutral-300","bg-transparent hover:bg-[#5f3f9a]/20",(r||n)&&"text-neutral-300 bg-[#5f3f9a]/40 hover:bg-[#5f3f9a]/40"),style:{top:e.start,height:28},children:(0,e4.jsx)("div",{className:"w-full h-full",style:{paddingLeft:`calc(${t.depth} * var(--indentation-size))`},children:(0,e4.jsx)(e9,{node:t,nodeIndex:e.index,hasChildren:!!t.children?.length,isCollapsed:u.has(t.nodeId),handleTreeNodeClick:y,handleTreeNodeToggle:k,searchValue:f})})},t.nodeId)})})})})]})]})},tt=r(17402),tr=r(45994),tn=r(17402),to=r(45994),ti=r(10201),ta=(0,tn.memo)(({text:e,children:t,onCopy:r,className:n,iconSize:o=14})=>{let[i,a]=(0,to.useState)(!1);(0,to.useEffect)(()=>{if(i){let e=setTimeout(()=>a(!1),600);return()=>{clearTimeout(e)}}},[i]);let s=(0,to.useCallback)(t=>{t.preventDefault(),t.stopPropagation(),navigator.clipboard.writeText(e).then(()=>{a(!0),r?.(!0,e)},()=>{r?.(!1,e)})},[e,r]),l=(0,ti.jsx)("button",{onClick:s,type:"button",className:ez("z-10","flex items-center justify-center","hover:text-dev-pink-400","transition-colors duration-200 ease-in-out","cursor-pointer",`size-[${o}px]`,n),children:(0,ti.jsx)($,{name:`icon-${i?"check":"copy"}`,size:[o],className:ez(i&&"text-green-500")})});return t?t({ClipboardIcon:l,onClick:s}):l}),ts=r(45994),tl=r(10201),tc=({length:e,expanded:t,onToggle:r,isNegative:n})=>(0,tl.jsxs)("div",{className:"flex items-center gap-1",children:[(0,tl.jsx)("button",{type:"button",onClick:r,className:"flex items-center p-0 opacity-50",children:(0,tl.jsx)($,{name:"icon-chevron-right",size:12,className:ez("transition-[color,transform]",n?"text-[#f87171]":"text-[#4ade80]",t&&"rotate-90")})}),(0,tl.jsxs)("span",{children:["Array(",e,")"]})]}),td=({value:e,path:t,isNegative:r})=>{let[n,o]=(0,ts.useState)(!1);if(null===e||"object"!=typeof e||e instanceof Date)return(0,tl.jsxs)("div",{className:"flex items-center gap-1",children:[(0,tl.jsxs)("span",{className:"text-gray-500",children:[t,":"]}),(0,tl.jsx)("span",{className:"truncate",children:tZ(e)})]});let i=Object.entries(e);return(0,tl.jsxs)("div",{className:"flex flex-col",children:[(0,tl.jsxs)("div",{className:"flex items-center gap-1",children:[(0,tl.jsx)("button",{type:"button",onClick:()=>o(!n),className:"flex items-center p-0 opacity-50",children:(0,tl.jsx)($,{name:"icon-chevron-right",size:12,className:ez("transition-[color,transform]",r?"text-[#f87171]":"text-[#4ade80]",n&&"rotate-90")})}),(0,tl.jsxs)("span",{className:"text-gray-500",children:[t,":"]}),!n&&(0,tl.jsx)("span",{className:"truncate",children:e instanceof Date?tZ(e):`{${Object.keys(e).join(", ")}}`})]}),n&&(0,tl.jsx)("div",{className:"pl-5 border-l border-[#333] mt-0.5 ml-1 flex flex-col gap-0.5",children:i.map(([e,t])=>(0,tl.jsx)(td,{value:t,path:e,isNegative:r},e))})]})},tu=({value:e,expanded:t,onToggle:r,isNegative:n})=>{let{value:o,error:i}=tQ(e);return i?(0,tl.jsx)("span",{className:"text-gray-500 font-italic",children:i}):null===o||"object"!=typeof o||o instanceof Promise?(0,tl.jsx)("span",{children:tZ(o)}):Array.isArray(o)?(0,tl.jsxs)("div",{className:"flex flex-col gap-1 relative",children:[(0,tl.jsx)(tc,{length:o.length,expanded:t,onToggle:r,isNegative:n}),t&&(0,tl.jsx)("div",{className:"pl-2 border-l border-[#333] mt-0.5 ml-1 flex flex-col gap-0.5",children:o.map((e,t)=>(0,tl.jsx)(td,{value:e,path:t.toString(),isNegative:n},t.toString()))}),(0,tl.jsx)(ta,{text:tq(o),className:"absolute top-0.5 right-0.5 opacity-0 transition-opacity group-hover:opacity-100 self-end",children:({ClipboardIcon:e})=>(0,tl.jsx)(tl.Fragment,{children:e})})]}):(0,tl.jsxs)("div",{className:"flex items-start gap-1 relative",children:[(0,tl.jsx)("button",{type:"button",onClick:r,className:ez("flex items-center","p-0 mt-0.5 mr-1","opacity-50"),children:(0,tl.jsx)($,{name:"icon-chevron-right",size:12,className:ez("transition-[color,transform]",n?"text-[#f87171]":"text-[#4ade80]",t&&"rotate-90")})}),(0,tl.jsx)("div",{className:"flex-1",children:t?(0,tl.jsx)("div",{className:"pl-2 border-l border-[#333] mt-0.5 ml-1 flex flex-col gap-0.5",children:Object.entries(o).map(([e,t])=>(0,tl.jsx)(td,{value:t,path:e,isNegative:n},e))}):(0,tl.jsx)("span",{children:tZ(o)})}),(0,tl.jsx)(ta,{text:tq(o),className:"absolute top-0.5 right-0.5 opacity-0 transition-opacity group-hover:opacity-100 self-end",children:({ClipboardIcon:e})=>(0,tl.jsx)(tl.Fragment,{children:e})})]})},tp=r(45994),th=r(62224);(0,r(61704).signal)({fiber:null,fiberProps:{current:[],changes:new Set},fiberState:{current:[],changes:new Set},fiberContext:{current:[],changes:new Set}});var tm=e=>{switch(e.kind){case"initialized":return e.changes.currentValue;case"partially-initialized":return e.value}},tf=(e,t)=>{for(let r of e){let e=t.get(r.name);if(e){t.set(e.name,{count:e.count+1,currentValue:r.value,id:e.name,lastUpdated:Date.now(),name:e.name,previousValue:r.prevValue});continue}t.set(r.name,{count:1,currentValue:r.value,id:r.name,lastUpdated:Date.now(),name:r.name,previousValue:r.prevValue})}},tg=(e,t)=>{let r=new Map;return e.forEach((e,t)=>{r.set(t,e)}),t.forEach((e,t)=>{let n=r.get(t);n?r.set(t,{count:n.count+e.count,currentValue:e.currentValue,id:e.id,lastUpdated:e.lastUpdated,name:e.name,previousValue:e.previousValue}):r.set(t,e)}),r},tx=e=>Array.from(e.propsChanges.values()).reduce((e,t)=>e+t.count,0)+Array.from(e.stateChanges.values()).reduce((e,t)=>e+t.count,0)+Array.from(e.contextChanges.values()).filter(e=>"initialized"===e.kind).reduce((e,t)=>e+t.changes.count,0),tb=r(62224),tw=r(10201),tv=e=>{if(null==e||"function"==typeof e||"object"!=typeof e)return{value:e};if(t0(e))return{value:"Promise"};try{let t=Object.getPrototypeOf(e);if(t===Promise.prototype||t?.constructor?.name==="Promise")return{value:"Promise"};return{value:e}}catch{return{value:null,error:"Error accessing value"}}},ty=(0,tt.memo)(()=>{let[e,t]=(0,tr.useState)(!0),r=(e=>{let t=(0,tp.useRef)({queue:[]}),[r,n]=(0,tp.useState)({propsChanges:new Map,stateChanges:new Map,contextChanges:new Map}),o="focused"===ij.inspectState.value.kind?ij.inspectState.value.fiber:null,i=o?(0,th.getFiberId)(o):null;return(0,tp.useEffect)(()=>{let r=setInterval(()=>{0!==t.current.queue.length&&(n(r=>{var n;let o,i,a=(n=t.current.queue,o={contextChanges:new Map,propsChanges:new Map,stateChanges:new Map},n.forEach(e=>{for(let t of e.contextChanges){let e=o.contextChanges.get(t.contextType);if(e){if(E(tm(e),t.value))continue;if("partially-initialized"===e.kind){o.contextChanges.set(t.contextType,{kind:"initialized",changes:{count:1,currentValue:t.value,id:t.contextType.toString(),lastUpdated:Date.now(),name:t.name,previousValue:e.value}});continue}o.contextChanges.set(t.contextType,{kind:"initialized",changes:{count:e.changes.count+1,currentValue:t.value,id:t.contextType.toString(),lastUpdated:Date.now(),name:t.name,previousValue:e.changes.currentValue}});continue}o.contextChanges.set(t.contextType,{kind:"partially-initialized",id:t.contextType.toString(),lastUpdated:Date.now(),name:t.name,value:t.value})}tf(e.stateChanges,o.stateChanges),tf(e.propsChanges,o.propsChanges)}),o),s=(i=new Map,r.contextChanges.forEach((e,t)=>{i.set(t,e)}),a.contextChanges.forEach((e,t)=>{let r=i.get(t);if(!r)return void i.set(t,e);if(tm(e)!==tm(r))switch(r.kind){case"initialized":switch(e.kind){case"initialized":return void i.set(t,{kind:"initialized",changes:{...e.changes,count:e.changes.count+r.changes.count+1,currentValue:e.changes.currentValue,previousValue:e.changes.previousValue}});case"partially-initialized":return void i.set(t,{kind:"initialized",changes:{count:r.changes.count+1,currentValue:e.value,id:e.id,lastUpdated:e.lastUpdated,name:e.name,previousValue:r.changes.currentValue}})}case"partially-initialized":switch(e.kind){case"initialized":return void i.set(t,{kind:"initialized",changes:{count:e.changes.count+1,currentValue:e.changes.currentValue,id:e.changes.id,lastUpdated:e.changes.lastUpdated,name:e.changes.name,previousValue:r.value}});case"partially-initialized":return void i.set(t,{kind:"initialized",changes:{count:1,currentValue:e.value,id:e.id,lastUpdated:e.lastUpdated,name:e.name,previousValue:r.value}})}}}),{contextChanges:i,propsChanges:tg(r.propsChanges,a.propsChanges),stateChanges:tg(r.stateChanges,a.stateChanges)}),l=tx(r),c=tx(s);return e?.onChangeUpdate?.(c-l),s}),t.current.queue=[])},50);return()=>{clearInterval(r)}},[o]),(0,tp.useEffect)(()=>{if(!i)return;let e=e=>{t.current?.queue.push(e)},r=ij.changesListeners.get(i);return r||(r=[],ij.changesListeners.set(i,r)),r.push(e),()=>{n({propsChanges:new Map,stateChanges:new Map,contextChanges:new Map}),t.current.queue=[],ij.changesListeners.set(i,ij.changesListeners.get(i)?.filter(t=>t!==e)??[])}},[i]),(0,tp.useEffect)(()=>()=>{n({propsChanges:new Map,stateChanges:new Map,contextChanges:new Map}),t.current.queue=[]},[i]),r})(),[n,o]=(0,tr.useState)(!1),i=tx(r)>0;(0,tr.useEffect)(()=>{if(!n&&i){let e=setTimeout(()=>{o(!0),requestAnimationFrame(()=>{t(!0)})},0);return()=>clearTimeout(e)}},[n,i]);let a=new Map(Array.from(r.contextChanges.entries()).filter(([,e])=>"initialized"===e.kind).map(([e,t])=>[e,"partially-initialized"===t.kind?null:t.changes])),s="focused"===ij.inspectState.value.kind?ij.inspectState.value.fiber:null;if(s)return(0,tw.jsxs)(tw.Fragment,{children:[(0,tw.jsx)(tk,{}),(0,tw.jsxs)("div",{className:"overflow-hidden h-full flex flex-col gap-y-2",children:[(0,tw.jsxs)("div",{className:"flex flex-col gap-2 px-3 pt-2",children:[(0,tw.jsxs)("span",{className:"text-sm font-medium text-[#888]",children:["Why did"," ",(0,tw.jsx)("span",{className:"text-[#A855F7]",children:(0,tb.getDisplayName)(s)})," ","render?"]}),!i&&(0,tw.jsxs)("div",{className:"text-sm text-[#737373] bg-[#1E1E1E] rounded-md p-4 flex flex-col gap-4",children:[(0,tw.jsx)("div",{children:"No changes detected since selecting"}),(0,tw.jsx)("div",{children:"The props, state, and context changes within your component will be reported here"})]})]}),(0,tw.jsxs)("div",{className:ez("flex flex-col gap-y-2 pl-3 relative overflow-y-auto h-full"),children:[(0,tw.jsx)(tC,{changes:r.propsChanges,title:"Changed Props",isExpanded:e}),(0,tw.jsx)(tC,{renderName:e=>t_(e,(0,tb.getDisplayName)((0,tb.getType)(s))??"Unknown Component"),changes:r.stateChanges,title:"Changed State",isExpanded:e}),(0,tw.jsx)(tC,{changes:a,title:"Changed Context",isExpanded:e})]})]})]})}),t_=(e,t)=>{if(Number.isNaN(Number(e)))return e;let r=Number.parseInt(e);return(0,tw.jsxs)("span",{className:"truncate",children:[(0,tw.jsxs)("span",{className:"text-white",children:[r,(e=>{let t=e%100;if(t>=11&&t<=13)return"th";switch(e%10){case 1:return"st";case 2:return"nd";case 3:return"rd";default:return"th"}})(r)," hook"," "]}),(0,tw.jsxs)("span",{style:{color:"#666"},children:["called in ",(0,tw.jsx)("i",{className:"text-[#A855F7] truncate",children:t})]})]})},tk=(0,tt.memo)(()=>{let e=(0,tr.useRef)(null),t=(0,tr.useRef)(null),r=(0,tr.useRef)(null),n=(0,tr.useRef)({isPropsChanged:!1,isStateChanged:!1,isContextChanged:!1});return(0,tr.useEffect)(()=>{let o=eR(()=>{let n=[];for(let o of(e.current?.dataset.flash==="true"&&n.push(e.current),t.current?.dataset.flash==="true"&&n.push(t.current),r.current?.dataset.flash==="true"&&n.push(r.current),n))o.classList.remove("count-flash-white"),o.offsetWidth,o.classList.add("count-flash-white")},400);return eJ.subscribe(i=>{if(!e.current||!t.current||!r.current)return;let{currentIndex:a,updates:s}=i,l=s[a];l&&0!==a&&(o(),n.current={isPropsChanged:(l.props?.changes?.size??0)>0,isStateChanged:(l.state?.changes?.size??0)>0,isContextChanged:(l.context?.changes?.size??0)>0},"true"!==e.current.dataset.flash&&(e.current.dataset.flash=n.current.isPropsChanged.toString()),"true"!==t.current.dataset.flash&&(t.current.dataset.flash=n.current.isStateChanged.toString()),"true"!==r.current.dataset.flash&&(r.current.dataset.flash=n.current.isContextChanged.toString()))})},[]),(0,tw.jsx)("button",{type:"button",className:ez("react-section-header","overflow-hidden","max-h-0","transition-[max-height]"),children:(0,tw.jsx)("div",{className:ez("flex-1 react-scan-expandable"),children:(0,tw.jsx)("div",{className:"overflow-hidden",children:(0,tw.jsxs)("div",{className:"flex items-center whitespace-nowrap",children:[(0,tw.jsx)("div",{className:"flex items-center gap-x-2",children:"What changed?"}),(0,tw.jsxs)("div",{className:ez("ml-auto","change-scope","transition-opacity duration-300 delay-150"),children:[(0,tw.jsx)("div",{ref:e,children:"props"}),(0,tw.jsx)("div",{ref:t,children:"state"}),(0,tw.jsx)("div",{ref:r,children:"context"})]})]})})})})}),tj=e=>e,tC=(0,tt.memo)(({title:e,changes:t,renderName:r=tj})=>{let[n,o]=(0,tr.useState)(new Set),[i,a]=(0,tr.useState)(new Set),s=Array.from(t.entries());return 0===t.size?null:(0,tw.jsxs)("div",{children:[(0,tw.jsx)("div",{className:"text-xs text-[#888] mb-1.5",children:e}),(0,tw.jsx)("div",{className:"flex flex-col gap-2",children:s.map(([t,s])=>{let l=i.has(String(t)),{value:c,error:d}=tv(s.previousValue),{value:u,error:p}=tv(s.currentValue),h=tG(c,u);return(0,tw.jsxs)("div",{children:[(0,tw.jsx)("button",{onClick:()=>{a(e=>{let r=new Set(e);return r.has(String(t))?r.delete(String(t)):r.add(String(t)),r})},className:"flex items-center gap-2 w-full bg-transparent border-none p-0 cursor-pointer text-white text-xs",children:(0,tw.jsxs)("div",{className:"flex items-center gap-1.5 flex-1",children:[(0,tw.jsx)($,{name:"icon-chevron-right",size:12,className:ez("text-[#666] transition-transform duration-200 ease-[cubic-bezier(0.25,0.1,0.25,1)]",{"rotate-90":l})}),(0,tw.jsxs)("div",{className:"whitespace-pre-wrap break-words text-left font-medium flex items-center gap-x-1.5",children:[r(s.name),(0,tw.jsx)(tE,{count:s.count,isFunction:"function"==typeof s.currentValue,showWarning:0===h.changes.length,forceFlash:!0})]})]})}),(0,tw.jsx)("div",{className:ez("react-scan-expandable",{"react-scan-expanded":l}),children:(0,tw.jsx)("div",{className:"pl-3 text-xs font-mono border-l-1 border-[#333]",children:(0,tw.jsx)("div",{className:"flex flex-col gap-0.5",children:d||p?(0,tw.jsx)(tS,{currError:p,prevError:d}):h.changes.length>0?(0,tw.jsx)(tN,{change:s,diff:h,expandedFns:n,renderName:r,setExpandedFns:o,title:e}):(0,tw.jsx)(tT,{currValue:u,entryKey:t,expandedFns:n,prevValue:c,setExpandedFns:o})})})})]},t)})})]})}),tS=({prevError:e,currError:t})=>(0,tw.jsxs)(tw.Fragment,{children:[e&&(0,tw.jsx)("div",{className:"text-[#f87171] bg-[#2a1515] pr-1.5 py-[3px] rounded italic",children:e}),t&&(0,tw.jsx)("div",{className:"text-[#4ade80] bg-[#1a2a1a] pr-1.5 py-[3px] rounded italic mt-0.5",children:t})]}),tN=({diff:e,title:t,renderName:r,change:n,expandedFns:o,setExpandedFns:i})=>e.changes.map((a,s)=>{let l,{value:c,error:d}=tv(a.prevValue),{value:u,error:p}=tv(a.currentValue),h="function"==typeof c||"function"==typeof u;return"Props"===t&&(l=a.path.length>0?`${r(String(n.name))}.${tJ(a.path)}`:void 0),"State"===t&&a.path.length>0&&(l=`state.${tJ(a.path)}`),l||(l=tJ(a.path)),(0,tw.jsxs)("div",{className:ez("flex flex-col gap-y-1",s<e.changes.length-1&&"mb-4"),children:[l&&(0,tw.jsx)("div",{className:"text-[#666] text-[10px]",children:l}),(0,tw.jsxs)("button",{type:"button",className:ez("group","flex items-start","py-[3px] px-1.5","text-left text-[#f87171] bg-[#2a1515]","rounded","overflow-hidden break-all",h&&"cursor-pointer"),onClick:h?()=>{let e=`${tJ(a.path)}-prev`;i(t=>{let r=new Set(t);return r.has(e)?r.delete(e):r.add(e),r})}:void 0,children:[(0,tw.jsx)("span",{className:"w-3 flex items-center justify-center opacity-50",children:"-"}),(0,tw.jsx)("span",{className:"flex-1 whitespace-nowrap font-mono",children:d?(0,tw.jsx)("span",{className:"italic text-[#f87171]",children:d}):h?(0,tw.jsxs)("div",{className:"flex gap-1 items-start flex-col",children:[(0,tw.jsxs)("div",{className:"flex gap-1 items-start w-full",children:[(0,tw.jsx)("span",{className:"flex-1 max-h-40",children:tK(c,o.has(`${tJ(a.path)}-prev`))}),"function"==typeof c&&(0,tw.jsx)(ta,{text:c.toString(),className:"opacity-0 transition-opacity group-hover:opacity-100",children:({ClipboardIcon:e})=>(0,tw.jsx)(tw.Fragment,{children:e})})]}),c?.toString()===u?.toString()&&(0,tw.jsx)("div",{className:"text-[10px] text-[#666] italic",children:"Function reference changed"})]}):(0,tw.jsx)(tu,{value:c,expanded:o.has(`${tJ(a.path)}-prev`),onToggle:()=>{let e=`${tJ(a.path)}-prev`;i(t=>{let r=new Set(t);return r.has(e)?r.delete(e):r.add(e),r})},isNegative:!0})})]}),(0,tw.jsxs)("button",{type:"button",className:ez("group","flex items-start","py-[3px] px-1.5","text-left text-[#4ade80] bg-[#1a2a1a]","rounded","overflow-hidden break-all",h&&"cursor-pointer"),onClick:h?()=>{let e=`${tJ(a.path)}-current`;i(t=>{let r=new Set(t);return r.has(e)?r.delete(e):r.add(e),r})}:void 0,children:[(0,tw.jsx)("span",{className:"w-3 flex items-center justify-center opacity-50",children:"+"}),(0,tw.jsx)("span",{className:"flex-1 whitespace-pre-wrap font-mono",children:p?(0,tw.jsx)("span",{className:"italic text-[#4ade80]",children:p}):h?(0,tw.jsxs)("div",{className:"flex gap-1 items-start flex-col",children:[(0,tw.jsxs)("div",{className:"flex gap-1 items-start w-full",children:[(0,tw.jsx)("span",{className:"flex-1",children:tK(u,o.has(`${tJ(a.path)}-current`))}),"function"==typeof u&&(0,tw.jsx)(ta,{text:u.toString(),className:"opacity-0 transition-opacity group-hover:opacity-100",children:({ClipboardIcon:e})=>(0,tw.jsx)(tw.Fragment,{children:e})})]}),c?.toString()===u?.toString()&&(0,tw.jsx)("div",{className:"text-[10px] text-[#666] italic",children:"Function reference changed"})]}):(0,tw.jsx)(tu,{value:u,expanded:o.has(`${tJ(a.path)}-current`),onToggle:()=>{let e=`${tJ(a.path)}-current`;i(t=>{let r=new Set(t);return r.has(e)?r.delete(e):r.add(e),r})},isNegative:!1})})]})]},`${l}-${n.name}-${s}`)}),tT=({prevValue:e,currValue:t,entryKey:r,expandedFns:n,setExpandedFns:o})=>(0,tw.jsxs)(tw.Fragment,{children:[(0,tw.jsxs)("div",{className:"group flex gap-0.5 items-start text-[#f87171] bg-[#2a1515] py-[3px] px-1.5 rounded",children:[(0,tw.jsx)("span",{className:"w-3 flex items-center justify-center opacity-50",children:"-"}),(0,tw.jsx)("span",{className:"flex-1 overflow-hidden whitespace-pre-wrap font-mono",children:(0,tw.jsx)(tu,{value:e,expanded:n.has(`${String(r)}-prev`),onToggle:()=>{let e=`${String(r)}-prev`;o(t=>{let r=new Set(t);return r.has(e)?r.delete(e):r.add(e),r})},isNegative:!0})})]}),(0,tw.jsxs)("div",{className:"group flex gap-0.5 items-start text-[#4ade80] bg-[#1a2a1a] py-[3px] px-1.5 rounded mt-0.5",children:[(0,tw.jsx)("span",{className:"w-3 flex items-center justify-center opacity-50",children:"+"}),(0,tw.jsx)("span",{className:"flex-1 overflow-hidden whitespace-pre-wrap font-mono",children:(0,tw.jsx)(tu,{value:t,expanded:n.has(`${String(r)}-current`),onToggle:()=>{let e=`${String(r)}-current`;o(t=>{let r=new Set(t);return r.has(e)?r.delete(e):r.add(e),r})},isNegative:!1})})]}),"object"==typeof t&&null!==t&&(0,tw.jsxs)("div",{className:"text-[#666] text-[10px] italic mt-1 flex items-center gap-x-1",children:[(0,tw.jsx)($,{name:"icon-triangle-alert",className:"text-yellow-500 mb-px",size:14}),(0,tw.jsx)("span",{children:"Reference changed but objects are structurally the same"})]})]}),tE=({count:e,forceFlash:t,isFunction:r,showWarning:n})=>{let o=(0,tr.useRef)(!0),i=(0,tr.useRef)(null),a=(0,tr.useRef)(e);return(0,tr.useEffect)(()=>{let t=i.current;t&&a.current!==e&&(t.classList.remove("count-flash"),t.offsetWidth,t.classList.add("count-flash"),a.current=e)},[e]),(0,tr.useEffect)(()=>{if(o.current){o.current=!1;return}if(t){let e=setTimeout(()=>{i.current?.classList.add("count-flash-white"),e=setTimeout(()=>{i.current?.classList.remove("count-flash-white")},300)},500);return()=>{clearTimeout(e)}}},[t]),(0,tw.jsxs)("div",{ref:i,className:"count-badge",children:[n&&(0,tw.jsx)($,{name:"icon-triangle-alert",className:"text-yellow-500 mb-px",size:14}),r&&(0,tw.jsx)($,{name:"icon-function",className:"text-[#A855F7] mb-px",size:14}),"x",e]})},tz=r(10201),tR={lastRendered:new Map,expandedPaths:new Set,cleanup:()=>{tR.lastRendered.clear(),tR.expandedPaths.clear(),eq.cleanupAll(),t7(),eQ&&(clearTimeout(eQ),eQ=null),eZ=[],eJ.value=eG}},tF=class extends O.Component{constructor(){super(...arguments),this.state={hasError:!1,error:null},this.handleReset=()=>{this.setState({hasError:!1,error:null}),tR.cleanup()}}static getDerivedStateFromError(e){return{hasError:!0,error:e}}render(){return this.state.hasError?(0,tz.jsxs)("div",{className:"p-4 bg-red-950/50 h-screen backdrop-blur-sm",children:[(0,tz.jsxs)("div",{className:"flex items-center gap-2 mb-3 text-red-400 font-medium",children:[(0,tz.jsx)($,{name:"icon-flame",className:"text-red-500",size:16}),"Something went wrong in the inspector"]}),(0,tz.jsx)("div",{className:"p-3 bg-black/40 rounded font-mono text-xs text-red-300 mb-4 break-words",children:this.state.error?.message||JSON.stringify(this.state.error)}),(0,tz.jsx)("button",{type:"button",onClick:this.handleReset,className:"px-4 py-2 bg-red-500 hover:bg-red-600 text-white rounded-md text-sm font-medium transition-colors flex items-center justify-center gap-2",children:"Reset Inspector"})]}):this.props.children}},tM=(0,A.computed)(()=>ez("react-scan-inspector","flex-1","opacity-0","overflow-y-auto overflow-x-hidden","transition-opacity delay-0","pointer-events-none",!eO.value&&"opacity-100 delay-300 pointer-events-auto")),tA=eY(()=>{let e=(0,P.useRef)(null),t=t=>{if(!t)return;e.current=t;let{data:r,shouldUpdate:n}=ro(t);if(n){var o={timestamp:Date.now(),fiberInfo:t1(t),props:r.fiberProps,state:r.fiberState,context:r.fiberContext,stateNames:t8(t)},i=t;if(eZ.push({update:o,fiber:i}),!eQ){let e=()=>{(()=>{let e;if(0===eZ.length)return;let t=[...eZ],{updates:r,totalUpdates:n,currentIndex:o,isViewingHistory:i}=eJ.value,a=[...r],s=n;for(let{update:e}of t)a.length>=1e3&&a.shift(),a.push(e),s++;let l=Math.max(0,s-1e3);e=i?o===n-1?a.length-1:0===o?0:0===l?o:o-1:a.length-1;let c=t[t.length-1];eJ.value={...eJ.value,latestFiber:c.fiber,updates:a,totalUpdates:s,windowOffset:l,currentIndex:e,isViewingHistory:i},eZ=eZ.slice(t.length)})(),eQ=null,eZ.length>0&&(eQ=setTimeout(e,96))};eQ=setTimeout(e,96)}}};return(0,A.useSignalEffect)(()=>{let r=ij.inspectState.value;(0,A.untracked)(()=>{if("focused"!==r.kind||!r.focusedDomElement){e.current=null,tR.cleanup();return}"focused"===r.kind&&(eO.value=!1);let{parentCompositeFiber:n}=tY(r.focusedDomElement,r.fiber);if(!n){ij.inspectState.value={kind:"inspect-off"},eL.value={view:"none"};return}e.current?.type!==n.type&&(e.current=n,tR.cleanup(),t(n))})}),(0,A.useSignalEffect)(()=>{eK.value,(0,A.untracked)(()=>{let r=ij.inspectState.value;if("focused"!==r.kind||!r.focusedDomElement){e.current=null,tR.cleanup();return}let{parentCompositeFiber:n}=tY(r.focusedDomElement,r.fiber);if(!n){ij.inspectState.value={kind:"inspect-off"},eL.value={view:"none"};return}t(n),r.focusedDomElement.isConnected||(e.current=null,tR.cleanup(),ij.inspectState.value={kind:"inspecting",hoveredDomElement:null})})}),(0,P.useEffect)(()=>()=>{tR.cleanup()},[]),(0,tz.jsx)(tF,{children:(0,tz.jsx)("div",{className:tM,children:(0,tz.jsx)("div",{className:"w-full h-full",children:(0,tz.jsx)(ty,{})})})})}),tO=eY(()=>"focused"!==ij.inspectState.value.kind?null:(0,tz.jsxs)(tF,{children:[(0,tz.jsx)(tA,{}),(0,tz.jsx)(te,{})]})),tP=e=>{if("__REACT_DEVTOOLS_GLOBAL_HOOK__"in window){let t=window.__REACT_DEVTOOLS_GLOBAL_HOOK__;if(!t?.renderers)return null;for(let[,r]of Array.from(t.renderers))try{let t=r.findFiberByHostInstance?.(e);if(t)return t}catch{}}if("_reactRootContainer"in e){let t=e._reactRootContainer;return t?._internalRoot?.current?.child??null}for(let t in e)if(t.startsWith("__reactInternalInstance$")||t.startsWith("__reactFiber"))return e[t];return null},tD=e=>{let t=e;for(;t;){if(t.stateNode instanceof Element)return t.stateNode;if(!t.child)break;t=t.child}for(;t;){if(t.stateNode instanceof Element)return t.stateNode;if(!t.return)break;t=t.return}return null},tI=e=>{if(!e)return null;try{let t=tP(e);if(!t)return null;let r=t$(t);return r?r[0]:null}catch{return null}},t$=e=>{let t=e,r=null;for(;t;){if((0,M.isCompositeFiber)(t))return[t,r];(0,M.isHostFiber)(t)&&!r&&(r=t),t=t.return}return null},tL=(e,t)=>!!(0,M.traverseFiber)(t,t=>t===e),tH=async e=>{let t,r=tI(e);if(!r)return null;let n=tD(r);if(!n)return null;let o=(await (t=[n],new Promise(e=>{let r=new Map,n=new IntersectionObserver(t=>{for(let e of t){let t=e.target,n=e.boundingClientRect;r.set(t,n)}n.disconnect(),e(r)});for(let e of t)n.observe(e)}))).get(n);return o||null},tU=e=>{let t=tI(e);if(!t||!tD(t))return{};let r=t$(t);if(!r)return{};let[n]=r;return{parentCompositeFiber:n}},tY=(e,t)=>{if(!e.isConnected)return{};let r=t??tI(e);if(!r)return{};let n=r,o=null,i=null;for(;n;){if(!n.stateNode){n=n.return;continue}if(iC.instrumentation?.fiberRoots.has(n.stateNode)){o=n,i=n.stateNode.current;break}n=n.return}if(!o||!i||!(r=tL(r,i)?r:r.alternate??r)||!tD(r))return{};let a=t$(r)?.[0];return a?{parentCompositeFiber:tL(a,i)?a:a.alternate??a}:{}},tB=e=>{let t=e.memoizedProps??{},r=e.alternate?.memoizedProps??{},n=[];for(let e in t){if("children"===e)continue;let o=t[e],i=r[e];E(o,i)||n.push({name:e,value:o,prevValue:i,type:1})}return n},tW=new Set(["HTML","HEAD","META","TITLE","BASE","SCRIPT","SCRIPT","STYLE","LINK","NOSCRIPT","SOURCE","TRACK","EMBED","OBJECT","PARAM","TEMPLATE","PORTAL","SLOT","AREA","XML","DOCTYPE","COMMENT"]),tV=(e,t=!0)=>{if(e.stateNode&&"nodeType"in e.stateNode){let r=e.stateNode;return t&&r.tagName&&tW.has(r.tagName.toLowerCase())?null:r}let r=e.child;for(;r;){let e=tV(r,t);if(e)return e;r=r.sibling}return null},tX=(e=document.body)=>{let t=[],r=(e,n=0)=>{let o=(e=>{if(!e)return null;let{parentCompositeFiber:t}=tU(e);return t&&tV(t)===e?e:null})(e);if(o){let{parentCompositeFiber:e}=tU(o);if(!e)return;t.push({element:o,depth:n,name:(0,M.getDisplayName)(e.type)??"Unknown",fiber:e})}for(let t of Array.from(e.children))r(t,o?n+1:n)};return r(e),t},tq=e=>{try{if(null===e)return"null";if(void 0===e)return"undefined";if(t0(e))return"Promise";if("function"==typeof e){let t=e.toString();try{return t.replace(/\s+/g," ").replace(/{\s+/g,`{
  `).replace(/;\s+/g,`;
  `).replace(/}\s*$/g,`
}`).replace(/\(\s+/g,"(").replace(/\s+\)/g,")").replace(/,\s+/g,", ")}catch{return t}}switch(!0){case e instanceof Date:return e.toISOString();case e instanceof RegExp:return e.toString();case e instanceof Error:return`${e.name}: ${e.message}`;case e instanceof Map:return JSON.stringify(Array.from(e.entries()),null,2);case e instanceof Set:return JSON.stringify(Array.from(e),null,2);case e instanceof DataView:return JSON.stringify(Array.from(new Uint8Array(e.buffer)),null,2);case e instanceof ArrayBuffer:return JSON.stringify(Array.from(new Uint8Array(e)),null,2);case ArrayBuffer.isView(e)&&"length"in e:return JSON.stringify(Array.from(e),null,2);case Array.isArray(e):case"object"==typeof e:return JSON.stringify(e,null,2);default:return String(e)}}catch{return String(e)}},tG=(e,t,r=[],n=new WeakSet)=>{if(e===t)return{type:"primitive",changes:[],hasDeepChanges:!1};if("function"==typeof e&&"function"==typeof t){let n=((e,t)=>{try{if("function"!=typeof e||"function"!=typeof t)return!1;return e.toString()===t.toString()}catch{return!1}})(e,t);return{type:"primitive",changes:[{path:r,prevValue:e,currentValue:t,sameFunction:n}],hasDeepChanges:!n}}if(null===e||null===t||void 0===e||void 0===t||"object"!=typeof e||"object"!=typeof t)return{type:"primitive",changes:[{path:r,prevValue:e,currentValue:t}],hasDeepChanges:!0};if(n.has(e)||n.has(t))return{type:"object",changes:[{path:r,prevValue:"[Circular]",currentValue:"[Circular]"}],hasDeepChanges:!1};n.add(e),n.add(t);let o=new Set([...Object.keys(e),...Object.keys(t)]),i=[],a=!1;for(let s of o){let o=e[s],l=t[s];if(o!==l)if("object"==typeof o&&"object"==typeof l&&null!==o&&null!==l){let e=tG(o,l,[...r,s],n);i.push(...e.changes),e.hasDeepChanges&&(a=!0)}else i.push({path:[...r,s],prevValue:o,currentValue:l}),a=!0}return{type:"object",changes:i,hasDeepChanges:a}},tJ=e=>0===e.length?"":e.reduce((e,t,r)=>/^\d+$/.test(t)?`${e}[${t}]`:0===r?t:`${e}.${t}`,""),tK=(e,t=!1)=>{try{let r=e.toString(),n=r.match(/(?:function\s*)?(?:\(([^)]*)\)|([^=>\s]+))\s*=>?/);if(!n)return"\u0192";let o=(n[1]||n[2]||"").replace(/\s+/g,"");if(!t)return`\u0192 (${o}) => ...`;return function(e){let t=e.replace(/\s+/g," ").trim(),r=[],n="";for(let e=0;e<t.length;e++){let o=t[e];if("="===o&&">"===t[e+1]){n.trim()&&r.push(n.trim()),r.push("=>"),n="",e++;continue}/[(){}[\];,<>:\?!]/.test(o)?(n.trim()&&r.push(n.trim()),r.push(o),n=""):/\s/.test(o)?(n.trim()&&r.push(n.trim()),n=""):n+=o}n.trim()&&r.push(n.trim());let o=[];for(let e=0;e<r.length;e++){let t=r[e],n=r[e+1];"("===t&&")"===n||"["===t&&"]"===n||"{"===t&&"}"===n||"<"===t&&">"===n?(o.push(t+n),e++):o.push(t)}let i=new Set,a=new Set;function s(e,t,r){let n=0;for(let i=r;i<o.length;i++){let r=o[i];if(r===e)n++;else if(r===t&&0==--n)return i}return -1}for(let e=0;e<o.length;e++)if("("===o[e]){let t=s("(",")",e);if(-1!==t&&"=>"===o[t+1])for(let r=e;r<=t;r++)i.add(r)}for(let e=1;e<o.length;e++){let t=o[e-1],r=o[e];if(/^[a-zA-Z0-9_$]+$/.test(t)&&"<"===r){let t=s("<",">",e);if(-1!==t)for(let r=e;r<=t;r++)a.add(r)}}let l=0,c=[],d="";function u(){d.trim()&&c.push(d.replace(/\s+$/,"")),d=""}function p(){u(),d="  ".repeat(l)}let h=[];function m(){return h.length?h[h.length-1]:null}function f(e,t=!1){d.trim()?t||/^[),;:\].}>]$/.test(e)?d+=e:d+=` ${e}`:d+=e}for(let e=0;e<o.length;e++){let t=o[e],r=o[e+1]||"";if(["(","{","[","<"].includes(t))f(t),h.push(t),"{"===t?(l++,p()):("("===t||"["===t||"<"===t)&&(i.has(e)&&"("===t||a.has(e)&&"<"===t||r!==({"(":")","[":"]","<":">"})[t]&&"()"!==r&&"[]"!==r&&"<>"!==r&&(l++,p()));else if([")","}","]",">"].includes(t)){let r=m();")"===t&&"("===r||"]"===t&&"["===r||">"===t&&"<"===r?i.has(e)&&")"===t||a.has(e)&&">"===t||(l=Math.max(l-1,0),p()):"}"===t&&"{"===r&&(l=Math.max(l-1,0),p()),h.pop(),f(t),"}"===t&&p()}else if(/^\(\)|\[\]|\{\}|\<\>$/.test(t))f(t);else if("=>"===t)f(t);else if(";"===t)f(t,!0),p();else if(","===t){f(t,!0);let r=m();!(i.has(e)&&"("===r)&&!(a.has(e)&&"<"===r)&&r&&["{","[","(","<"].includes(r)&&p()}else f(t)}return u(),c.join(`
`).replace(/\n\s*\n+/g,`
`).trim()}(r)}catch{return"\u0192"}},tZ=e=>{if(null===e)return"null";if(void 0===e)return"undefined";if("string"==typeof e)return`"${e.length>150?`${e.slice(0,20)}...`:e}"`;if("number"==typeof e||"boolean"==typeof e)return String(e);if("function"==typeof e)return tK(e);if(Array.isArray(e))return`Array(${e.length})`;if(e instanceof Map)return`Map(${e.size})`;if(e instanceof Set)return`Set(${e.size})`;if(e instanceof Date)return e.toISOString();if(e instanceof RegExp)return e.toString();if(e instanceof Error)return`${e.name}: ${e.message}`;if("object"==typeof e){let t=Object.keys(e);return`{${t.length>2?`${t.slice(0,2).join(", ")}, ...`:t.join(", ")}}`}return String(e)},tQ=e=>{if(null==e||"function"==typeof e||"object"!=typeof e)return{value:e};if(e instanceof Promise)return{value:"Promise"};try{let t=Object.getPrototypeOf(e);if(t===Promise.prototype||t?.constructor?.name==="Promise")return{value:"Promise"};return{value:e}}catch{return{value:null,error:"Error accessing value"}}},t0=e=>!!e&&(e instanceof Promise||"object"==typeof e&&"then"in e),t1=e=>{let t=(0,M.getTimings)(e);return{displayName:(0,M.getDisplayName)(e)||"Unknown",type:e.type,key:e.key,id:e.index,selfTime:t?.selfTime??null,totalTime:t?.totalTime??null}},t2=new Map,t4=new Map,t5=new Map,t3=null,t6=/\[(?<name>\w+),\s*set\w+\]/g,t8=e=>{let t=e.type?.toString?.()||"";return t?Array.from(t.matchAll(t6),e=>e.groups?.name??""):[]},t7=()=>{t2.clear(),t4.clear(),t5.clear(),t3=null},t9=(e,t,r,n)=>{let o=e.get(t),i=e===t2||e===t5,a=!E(r,n);if(!o)return e.set(t,{count:a&&i?1:0,currentValue:r,previousValue:n,lastUpdated:Date.now()}),{hasChanged:a,count:a&&i?1:+!i};if(!E(o.currentValue,r)){let n=o.count+1;return e.set(t,{count:n,currentValue:r,previousValue:o.currentValue,lastUpdated:Date.now()}),{hasChanged:!0,count:n}}return{hasChanged:!1,count:o.count}},re=e=>{if(!e)return{};if(e.tag===F.FunctionComponentTag||e.tag===F.ForwardRefTag||e.tag===F.SimpleMemoComponentTag||e.tag===F.MemoComponentTag){let t=e.memoizedState,r={},n=0;for(;t;)t.queue&&void 0!==t.memoizedState&&(r[n]=t.memoizedState),t=t.next,n++;return r}return e.tag===F.ClassComponentTag&&e.memoizedState||{}},rt=e=>{let t=e.memoizedProps||{},r=e.alternate?.memoizedProps||{},n={},o={};for(let e of Object.keys(t))e in t&&(n[e]=t[e],o[e]=r[e]);return{current:n,prev:o,changes:tB(e).map(e=>({name:e.name,value:e.value,prevValue:e.prevValue}))}},rr=e=>{let t=re(e),r=e.alternate?re(e.alternate):{},n=[];for(let[o,i]of Object.entries(t)){let t=e.tag===F.ClassComponentTag?o:Number(o);e.alternate&&!E(r[o],i)&&n.push({name:t,value:i,prevValue:r[o]})}return{current:t,prev:r,changes:n}},rn=e=>{let t=ra(e),r=e.alternate?ra(e.alternate):new Map,n={},o={},i=[],a=new Set;for(let[e,s]of t){let t=s.displayName;if(a.has(e))continue;a.add(e),n[t]=s.value;let l=r.get(e);l&&(o[t]=l.value,E(l.value,s.value)||i.push({name:t,value:s.value,prevValue:l.value,contextType:e}))}return{current:n,prev:o,changes:i}},ro=e=>{let t,r=()=>({current:[],changes:new Set,changesCounts:new Map});if(!e)return{data:{fiberProps:r(),fiberState:r(),fiberContext:r()},shouldUpdate:!1};let n=!1,o=(t=e.type!==t3,t3=e.type,t),i=r();if(e.memoizedProps){let{current:t,changes:r}=rt(e);for(let[e,r]of Object.entries(t))i.current.push({name:e,value:t0(r)?{type:"promise",displayValue:"Promise"}:r});for(let e of r){let{hasChanged:t,count:r}=t9(t2,e.name,e.value,e.prevValue);t&&(n=!0,i.changes.add(e.name),i.changesCounts.set(e.name,r))}}let a=r(),{current:s,changes:l}=rr(e);for(let[t,r]of Object.entries(s)){let n=e.tag===F.ClassComponentTag?t:Number(t);a.current.push({name:n,value:r})}for(let e of l){let{hasChanged:t,count:r}=t9(t4,e.name,e.value,e.prevValue);t&&(n=!0,a.changes.add(e.name),a.changesCounts.set(e.name,r))}let c=r(),{current:d,changes:u}=rn(e);for(let[e,t]of Object.entries(d))c.current.push({name:e,value:t});if(!o)for(let e of u){let{hasChanged:t,count:r}=t9(t5,e.name,e.value,e.prevValue);t&&(n=!0,c.changes.add(e.name),c.changesCounts.set(e.name,r))}return n||o||(i.changes.clear(),a.changes.clear(),c.changes.clear()),{data:{fiberProps:i,fiberState:a,fiberContext:c},shouldUpdate:n||o}},ri=new WeakMap,ra=e=>{if(!e)return new Map;let t=ri.get(e);if(t)return t;let r=new Map,n=e;for(;n;){let e=n.dependencies;if(e?.firstContext){let t=e.firstContext;for(;t;){let e=t.memoizedValue,n=t.context?.displayName;if(r.has(e)||r.set(t.context,{value:e,displayName:n??"UnnamedContext",contextType:null}),t===t.next)break;t=t.next}}n=n.return}return ri.set(e,r),r},rs=e=>{let t=()=>({current:[],changes:new Set,changesCounts:new Map});if(!e)return{fiberProps:t(),fiberState:t(),fiberContext:t()};let r=t();if(e.memoizedProps){let{current:t,changes:n}=rt(e);for(let[e,n]of Object.entries(t))r.current.push({name:e,value:t0(n)?{type:"promise",displayValue:"Promise"}:n});for(let e of n)r.changes.add(e.name),r.changesCounts.set(e.name,1)}let n=t();if(e.memoizedState){let{current:t,changes:r}=rr(e);for(let[e,r]of Object.entries(t))n.current.push({name:e,value:t0(r)?{type:"promise",displayValue:"Promise"}:r});for(let e of r)n.changes.add(e.name),n.changesCounts.set(e.name,1)}let o=t(),{current:i,changes:a}=rn(e);for(let[e,t]of Object.entries(i))o.current.push({name:e,value:t0(t)?{type:"promise",displayValue:"Promise"}:t});for(let e of a)o.changes.add(e.name),o.changesCounts.set(e.name,1);return{fiberProps:r,fiberState:n,fiberContext:o}},rl=0,rc=performance.now(),rd=0,ru=!1,rp=()=>{rd++;let e=performance.now();e-rc>=1e3&&(rl=rd,rd=0,rc=e),requestAnimationFrame(rp)},rh=()=>(ru||(ru=!0,rp(),rl=60),rl),rm=0,rf=new WeakMap;function rg(e,t){var r;let n;if(!e||!t)return;let o=e.memoizedValue,i={type:4,name:e.context.displayName??"Context.Provider",value:o,contextType:(r=e.context,(n=rf.get(r))||(rm++,rf.set(r,rm),rm))};this.push(i)}var rx=new Map,rb=!1,rw=()=>Array.from(rx.values()),rv=new WeakMap;function ry(e){return String((0,S.getFiberId)(e))}function r_(e){let t=ry(e),r=rv.get((0,S.getType)(e));if(r)return r.get(t)}var rk=(e,t)=>Math.floor(e+(t-e)*.1),rj="115,97,230";function rC(e,t){return t[0]-e[0]}function rS([e,t]){let r=`${t.slice(0,4).join(", ")} \xd7${e}`;return r.length>40&&(r=`${r.slice(0,40)}\u2026`),r}var rN=e=>{let t=new Map;for(let{name:r,count:n}of e)t.set(r,(t.get(r)||0)+n);let r=new Map;for(let[e,n]of t){let t=r.get(n);t?t.push(e):r.set(n,[e])}let n=[...r.entries()].sort(rC),o=rS(n[0]);for(let e=1,t=n.length;e<t;e++)o+=", "+rS(n[e]);return o.length>40?`${o.slice(0,40)}\u2026`:o},rT=e=>{let t=0;for(let r of e)t+=r.width*r.height;return t},rE=(e,t)=>{for(let{id:r,name:n,count:o,x:i,y:a,width:s,height:l,didCommit:c}of t){let t={id:r,name:n,count:o,x:i,y:a,width:s,height:l,frame:0,targetX:i,targetY:a,targetWidth:s,targetHeight:l,didCommit:c},d=String(t.id),u=e.get(d);u?(u.count++,u.frame=0,u.targetX=i,u.targetY=a,u.targetWidth=s,u.targetHeight=l,u.didCommit=c):e.set(d,t)}},rz=(e,t,r)=>{for(let n of e.values()){let e=n.x-t,o=n.y-r;n.targetX=e,n.targetY=o}},rR=`"use strict";(()=>{var D="Menlo,Consolas,Monaco,Liberation Mono,Lucida Console,monospace";var M=(t,i)=>Math.floor(t+(i-t)*.1);var _="115,97,230";function F(t,i){return i[0]-t[0]}function I(t){return[...t.entries()].sort(F)}function $([t,i]){let o=\`\${i.slice(0,4).join(", ")} \\xD7\${t}\`;return o.length>40&&(o=\`\${o.slice(0,40)}\\u2026\`),o}var S=t=>{let i=new Map;for(let{name:e,count:u}of t)i.set(e,(i.get(e)||0)+u);let o=new Map;for(let[e,u]of i){let A=o.get(u);A?A.push(e):o.set(u,[e])}let h=I(o),s=$(h[0]);for(let e=1,u=h.length;e<u;e++)s+=", "+$(h[e]);return s.length>40?\`\${s.slice(0,40)}\\u2026\`:s},X=t=>{let i=0;for(let o of t)i+=o.width*o.height;return i};var N=(t,i)=>{let o=t.getContext("2d",{alpha:!0});return o&&o.scale(i,i),o},Y=(t,i,o,h)=>{t.clearRect(0,0,i.width/o,i.height/o);let s=new Map,e=new Map;for(let n of h.values()){let{x:r,y:c,width:a,height:g,targetX:l,targetY:d,targetWidth:f,targetHeight:p,frame:O}=n;l!==r&&(n.x=M(r,l)),d!==c&&(n.y=M(c,d)),f!==a&&(n.width=M(a,f)),p!==g&&(n.height=M(g,p));let w=\`\${l??r},\${d??c}\`,y=\`\${w},\${f??a},\${p??g}\`,v=s.get(w);v?v.push(n):s.set(w,[n]);let E=1-O/45;n.frame++;let x=e.get(y)||{x:r,y:c,width:a,height:g,alpha:E};E>x.alpha&&(x.alpha=E),e.set(y,x)}for(let{x:n,y:r,width:c,height:a,alpha:g}of e.values())t.strokeStyle=\`rgba(\${_},\${g})\`,t.lineWidth=1,t.beginPath(),t.rect(n,r,c,a),t.stroke(),t.fillStyle=\`rgba(\${_},\${g*.1})\`,t.fill();t.font=\`11px \${D}\`;let u=new Map;t.textRendering="optimizeSpeed";for(let n of s.values()){let r=n[0],{x:c,y:a,frame:g}=r,l=1-g/45,d=S(n),{width:f}=t.measureText(d),p=11;u.set(\`\${c},\${a},\${f},\${d}\`,{text:d,width:f,height:p,alpha:l,x:c,y:a,outlines:n});let O=a-p-4;if(O<0&&(O=0),g>45)for(let w of n)h.delete(String(w.id))}let A=Array.from(u.entries()).sort(([n,r],[c,a])=>X(a.outlines)-X(r.outlines));for(let[n,r]of A)if(u.has(n))for(let[c,a]of u.entries()){if(n===c)continue;let{x:g,y:l,width:d,height:f}=r,{x:p,y:O,width:w,height:y}=a;g+d>p&&p+w>g&&l+f>O&&O+y>l&&(r.text=S(r.outlines.concat(a.outlines)),r.width=t.measureText(r.text).width,u.delete(c))}for(let n of u.values()){let{x:r,y:c,alpha:a,width:g,height:l,text:d}=n,f=c-l-4;f<0&&(f=0),t.fillStyle=\`rgba(\${_},\${a})\`,t.fillRect(r,f,g+4,l+4),t.fillStyle=\`rgba(255,255,255,\${a})\`,t.fillText(d,r+2,f+l)}return h.size>0};var m=null,L=null,b=1,T=new Map,C=null,R=()=>{if(!L||!m)return;Y(L,m,b,T)?C=requestAnimationFrame(R):C=null};self.onmessage=t=>{let{type:i}=t.data;if(i==="init"&&(m=t.data.canvas,b=t.data.dpr,m&&(m.width=t.data.width,m.height=t.data.height,L=N(m,b))),!(!m||!L)){if(i==="resize"){b=t.data.dpr,m.width=t.data.width*b,m.height=t.data.height*b,L.resetTransform(),L.scale(b,b),R();return}if(i==="draw-outlines"){let{data:o,names:h}=t.data,s=new Float32Array(o);for(let e=0;e<s.length;e+=7){let u=s[e+2],A=s[e+3],n=s[e+4],r=s[e+5],c=s[e+6],a={id:s[e],name:h[e/7],count:s[e+1],x:u,y:A,width:n,height:r,frame:0,targetX:u,targetY:A,targetWidth:n,targetHeight:r,didCommit:c},g=String(a.id),l=T.get(g);l?(l.count++,l.frame=0,l.targetX=u,l.targetY=A,l.targetWidth=n,l.targetHeight=r,l.didCommit=c):T.set(g,a)}C||(C=requestAnimationFrame(R));return}if(i==="scroll"){let{deltaX:o,deltaY:h}=t.data;for(let s of T.values()){let e=s.x-o,u=s.y-h;s.targetX=e,s.targetY=u}}}};})();
`,rF=null,rM=null,rA=null,rO=1,rP=null,rD=new Map,rI=new Map,r$=new Set,rL=e=>{let t,r,n,o,i=e[0];if(1===e.length)return i;for(let i=0,a=e.length;i<a;i++){let a=e[i];t=null==t?a.x:Math.min(t,a.x),r=null==r?a.y:Math.min(r,a.y),n=null==n?a.x+a.width:Math.max(n,a.x+a.width),o=null==o?a.y+a.height:Math.max(o,a.y+a.height)}return null==t||null==r||null==n||null==o?e[0]:new DOMRect(t,r,n-t,o-r)};function rH(e,t){let r=[];for(let t of e){let e=t.target;this.seenElements.has(e)||(this.seenElements.add(e),r.push(t))}r.length>0&&this.resolveNext&&(this.resolveNext(r),this.resolveNext=null),this.seenElements.size===this.uniqueElements.size&&(t.disconnect(),this.done=!0,this.resolveNext&&this.resolveNext([]))}var rU=async function*(e){let t={uniqueElements:new Set(e),seenElements:new Set,resolveNext:null,done:!1},r=new IntersectionObserver(rH.bind(t));for(let e of t.uniqueElements)r.observe(e);for(;!t.done;){let e=await new Promise(e=>{t.resolveNext=e});e.length>0&&(yield e)}},rY="undefined"!=typeof SharedArrayBuffer?SharedArrayBuffer:ArrayBuffer,rB=async()=>{let e=[];for(let t of r$){let r=rI.get(t);if(r)for(let t=0;t<r.elements.length;t++)r.elements[t]instanceof Element&&e.push(r.elements[t])}let t=new Map;for await(let r of rU(e)){for(let e of r){let r=e.target,n=e.intersectionRect;e.isIntersecting&&n.width&&n.height&&t.set(r,n)}let e=[],n=[],o=[];for(let r of r$){let i=rI.get(r);if(!i)continue;let a=[];for(let e=0;e<i.elements.length;e++){let r=i.elements[e],n=t.get(r);n&&a.push(n)}a.length&&(e.push(i),n.push(rL(a)),o.push((0,j.getFiberId)(r)))}if(e.length>0){let t,r=new rY(7*e.length*4),i=new Float32Array(r),a=Array(e.length);for(let r=0,s=e.length;r<s;r++){let s=e[r],l=o[r],{x:c,y:d,width:u,height:p}=n[r],{count:h,name:m,didCommit:f}=s;if(rF){let e=7*r;i[e]=l,i[e+1]=h,i[e+2]=c,i[e+3]=d,i[e+4]=u,i[e+5]=p,i[e+6]=f,a[r]=m}else(t||=Array(e.length))[r]={id:l,name:m,count:h,x:c,y:d,width:u,height:p,didCommit:f}}rF?rF.postMessage({type:"draw-outlines",data:r,names:a}):rM&&rA&&t&&(rE(rD,t),rP||(rP=requestAnimationFrame(rW)))}}for(let e of r$)rI.delete(e),r$.delete(e)},rW=()=>{rA&&rM&&(rP=((e,t,r,n)=>{e.clearRect(0,0,t.width/r,t.height/r);let o=new Map,i=new Map;for(let e of n.values()){let{x:t,y:r,width:n,height:a,targetX:s,targetY:l,targetWidth:c,targetHeight:d,frame:u}=e;s!==t&&(e.x=rk(t,s)),l!==r&&(e.y=rk(r,l)),c!==n&&(e.width=rk(n,c)),d!==a&&(e.height=rk(a,d));let p=`${s??t},${l??r}`,h=`${p},${c??n},${d??a}`,m=o.get(p);m?m.push(e):o.set(p,[e]);let f=1-u/45;e.frame++;let g=i.get(h)||{x:t,y:r,width:n,height:a,alpha:f};f>g.alpha&&(g.alpha=f),i.set(h,g)}for(let{x:t,y:r,width:n,height:o,alpha:a}of i.values())e.strokeStyle=`rgba(${rj},${a})`,e.lineWidth=1,e.beginPath(),e.rect(t,r,n,o),e.stroke(),e.fillStyle=`rgba(${rj},${.1*a})`,e.fill();e.font="11px Menlo,Consolas,Monaco,Liberation Mono,Lucida Console,monospace";let a=new Map;for(let t of(e.textRendering="optimizeSpeed",o.values())){let{x:r,y:o,frame:i}=t[0],s=1-i/45,l=rN(t),{width:c}=e.measureText(l);a.set(`${r},${o},${c},${l}`,{text:l,width:c,height:11,alpha:s,x:r,y:o,outlines:t});let d=o-11-4;if(d<0&&(d=0),i>45)for(let e of t)n.delete(String(e.id))}for(let[t,r]of Array.from(a.entries()).sort(([e,t],[r,n])=>rT(n.outlines)-rT(t.outlines)))if(a.has(t))for(let[n,o]of a.entries()){if(t===n)continue;let{x:i,y:s,width:l,height:c}=r,{x:d,y:u,width:p,height:h}=o;i+l>d&&d+p>i&&s+c>u&&u+h>s&&(r.text=rN(r.outlines.concat(o.outlines)),r.width=e.measureText(r.text).width,a.delete(n))}for(let t of a.values()){let{x:r,y:n,alpha:o,width:i,height:a,text:s}=t,l=n-a-4;l<0&&(l=0),e.fillStyle=`rgba(${rj},${o})`,e.fillRect(r,l,i+4,a+4),e.fillStyle=`rgba(255,255,255,${o})`,e.fillText(s,r+2,l+a)}return n.size>0})(rA,rM,rO,rD)?requestAnimationFrame(rW):null)},rV="undefined"!=typeof OffscreenCanvas&&"undefined"!=typeof Worker,rX=()=>Math.min(window.devicePixelRatio||1,2),rq=!1,rG=e=>!iI.has(e.memoizedProps),rJ=`*, ::before, ::after {
  --tw-border-spacing-x: 0;
  --tw-border-spacing-y: 0;
  --tw-translate-x: 0;
  --tw-translate-y: 0;
  --tw-rotate: 0;
  --tw-skew-x: 0;
  --tw-skew-y: 0;
  --tw-scale-x: 1;
  --tw-scale-y: 1;
  --tw-pan-x:  ;
  --tw-pan-y:  ;
  --tw-pinch-zoom:  ;
  --tw-scroll-snap-strictness: proximity;
  --tw-gradient-from-position:  ;
  --tw-gradient-via-position:  ;
  --tw-gradient-to-position:  ;
  --tw-ordinal:  ;
  --tw-slashed-zero:  ;
  --tw-numeric-figure:  ;
  --tw-numeric-spacing:  ;
  --tw-numeric-fraction:  ;
  --tw-ring-inset:  ;
  --tw-ring-offset-width: 0px;
  --tw-ring-offset-color: #fff;
  --tw-ring-color: rgb(59 130 246 / 0.5);
  --tw-ring-offset-shadow: 0 0 #0000;
  --tw-ring-shadow: 0 0 #0000;
  --tw-shadow: 0 0 #0000;
  --tw-shadow-colored: 0 0 #0000;
  --tw-blur:  ;
  --tw-brightness:  ;
  --tw-contrast:  ;
  --tw-grayscale:  ;
  --tw-hue-rotate:  ;
  --tw-invert:  ;
  --tw-saturate:  ;
  --tw-sepia:  ;
  --tw-drop-shadow:  ;
  --tw-backdrop-blur:  ;
  --tw-backdrop-brightness:  ;
  --tw-backdrop-contrast:  ;
  --tw-backdrop-grayscale:  ;
  --tw-backdrop-hue-rotate:  ;
  --tw-backdrop-invert:  ;
  --tw-backdrop-opacity:  ;
  --tw-backdrop-saturate:  ;
  --tw-backdrop-sepia:  ;
  --tw-contain-size:  ;
  --tw-contain-layout:  ;
  --tw-contain-paint:  ;
  --tw-contain-style:  ;
}

::backdrop {
  --tw-border-spacing-x: 0;
  --tw-border-spacing-y: 0;
  --tw-translate-x: 0;
  --tw-translate-y: 0;
  --tw-rotate: 0;
  --tw-skew-x: 0;
  --tw-skew-y: 0;
  --tw-scale-x: 1;
  --tw-scale-y: 1;
  --tw-pan-x:  ;
  --tw-pan-y:  ;
  --tw-pinch-zoom:  ;
  --tw-scroll-snap-strictness: proximity;
  --tw-gradient-from-position:  ;
  --tw-gradient-via-position:  ;
  --tw-gradient-to-position:  ;
  --tw-ordinal:  ;
  --tw-slashed-zero:  ;
  --tw-numeric-figure:  ;
  --tw-numeric-spacing:  ;
  --tw-numeric-fraction:  ;
  --tw-ring-inset:  ;
  --tw-ring-offset-width: 0px;
  --tw-ring-offset-color: #fff;
  --tw-ring-color: rgb(59 130 246 / 0.5);
  --tw-ring-offset-shadow: 0 0 #0000;
  --tw-ring-shadow: 0 0 #0000;
  --tw-shadow: 0 0 #0000;
  --tw-shadow-colored: 0 0 #0000;
  --tw-blur:  ;
  --tw-brightness:  ;
  --tw-contrast:  ;
  --tw-grayscale:  ;
  --tw-hue-rotate:  ;
  --tw-invert:  ;
  --tw-saturate:  ;
  --tw-sepia:  ;
  --tw-drop-shadow:  ;
  --tw-backdrop-blur:  ;
  --tw-backdrop-brightness:  ;
  --tw-backdrop-contrast:  ;
  --tw-backdrop-grayscale:  ;
  --tw-backdrop-hue-rotate:  ;
  --tw-backdrop-invert:  ;
  --tw-backdrop-opacity:  ;
  --tw-backdrop-saturate:  ;
  --tw-backdrop-sepia:  ;
  --tw-contain-size:  ;
  --tw-contain-layout:  ;
  --tw-contain-paint:  ;
  --tw-contain-style:  ;
}/*
! tailwindcss v3.4.17 | MIT License | https://tailwindcss.com
*//*
1. Prevent padding and border from affecting element width. (https://github.com/mozdevs/cssremedy/issues/4)
2. Allow adding a border to an element by just adding a border-width. (https://github.com/tailwindcss/tailwindcss/pull/116)
*/

*,
::before,
::after {
  box-sizing: border-box; /* 1 */
  border-width: 0; /* 2 */
  border-style: solid; /* 2 */
  border-color: #e5e7eb; /* 2 */
}

::before,
::after {
  --tw-content: '';
}

/*
1. Use a consistent sensible line-height in all browsers.
2. Prevent adjustments of font size after orientation changes in iOS.
3. Use a more readable tab size.
4. Use the user's configured \`sans\` font-family by default.
5. Use the user's configured \`sans\` font-feature-settings by default.
6. Use the user's configured \`sans\` font-variation-settings by default.
7. Disable tap highlights on iOS
*/

html,
:host {
  line-height: 1.5; /* 1 */
  -webkit-text-size-adjust: 100%; /* 2 */
  -moz-tab-size: 4; /* 3 */
  -o-tab-size: 4;
     tab-size: 4; /* 3 */
  font-family: ui-sans-serif, system-ui, sans-serif, "Apple Color Emoji", "Segoe UI Emoji", "Segoe UI Symbol", "Noto Color Emoji"; /* 4 */
  font-feature-settings: normal; /* 5 */
  font-variation-settings: normal; /* 6 */
  -webkit-tap-highlight-color: transparent; /* 7 */
}

/*
1. Remove the margin in all browsers.
2. Inherit line-height from \`html\` so users can set them as a class directly on the \`html\` element.
*/

body {
  margin: 0; /* 1 */
  line-height: inherit; /* 2 */
}

/*
1. Add the correct height in Firefox.
2. Correct the inheritance of border color in Firefox. (https://bugzilla.mozilla.org/show_bug.cgi?id=190655)
3. Ensure horizontal rules are visible by default.
*/

hr {
  height: 0; /* 1 */
  color: inherit; /* 2 */
  border-top-width: 1px; /* 3 */
}

/*
Add the correct text decoration in Chrome, Edge, and Safari.
*/

abbr:where([title]) {
  -webkit-text-decoration: underline dotted;
          text-decoration: underline dotted;
}

/*
Remove the default font size and weight for headings.
*/

h1,
h2,
h3,
h4,
h5,
h6 {
  font-size: inherit;
  font-weight: inherit;
}

/*
Reset links to optimize for opt-in styling instead of opt-out.
*/

a {
  color: inherit;
  text-decoration: inherit;
}

/*
Add the correct font weight in Edge and Safari.
*/

b,
strong {
  font-weight: bolder;
}

/*
1. Use the user's configured \`mono\` font-family by default.
2. Use the user's configured \`mono\` font-feature-settings by default.
3. Use the user's configured \`mono\` font-variation-settings by default.
4. Correct the odd \`em\` font sizing in all browsers.
*/

code,
kbd,
samp,
pre {
  font-family: Menlo, Consolas, Monaco, Liberation Mono, Lucida Console, monospace; /* 1 */
  font-feature-settings: normal; /* 2 */
  font-variation-settings: normal; /* 3 */
  font-size: 1em; /* 4 */
}

/*
Add the correct font size in all browsers.
*/

small {
  font-size: 80%;
}

/*
Prevent \`sub\` and \`sup\` elements from affecting the line height in all browsers.
*/

sub,
sup {
  font-size: 75%;
  line-height: 0;
  position: relative;
  vertical-align: baseline;
}

sub {
  bottom: -0.25em;
}

sup {
  top: -0.5em;
}

/*
1. Remove text indentation from table contents in Chrome and Safari. (https://bugs.chromium.org/p/chromium/issues/detail?id=999088, https://bugs.webkit.org/show_bug.cgi?id=201297)
2. Correct table border color inheritance in all Chrome and Safari. (https://bugs.chromium.org/p/chromium/issues/detail?id=935729, https://bugs.webkit.org/show_bug.cgi?id=195016)
3. Remove gaps between table borders by default.
*/

table {
  text-indent: 0; /* 1 */
  border-color: inherit; /* 2 */
  border-collapse: collapse; /* 3 */
}

/*
1. Change the font styles in all browsers.
2. Remove the margin in Firefox and Safari.
3. Remove default padding in all browsers.
*/

button,
input,
optgroup,
select,
textarea {
  font-family: inherit; /* 1 */
  font-feature-settings: inherit; /* 1 */
  font-variation-settings: inherit; /* 1 */
  font-size: 100%; /* 1 */
  font-weight: inherit; /* 1 */
  line-height: inherit; /* 1 */
  letter-spacing: inherit; /* 1 */
  color: inherit; /* 1 */
  margin: 0; /* 2 */
  padding: 0; /* 3 */
}

/*
Remove the inheritance of text transform in Edge and Firefox.
*/

button,
select {
  text-transform: none;
}

/*
1. Correct the inability to style clickable types in iOS and Safari.
2. Remove default button styles.
*/

button,
input:where([type='button']),
input:where([type='reset']),
input:where([type='submit']) {
  -webkit-appearance: button; /* 1 */
  background-color: transparent; /* 2 */
  background-image: none; /* 2 */
}

/*
Use the modern Firefox focus style for all focusable elements.
*/

:-moz-focusring {
  outline: auto;
}

/*
Remove the additional \`:invalid\` styles in Firefox. (https://github.com/mozilla/gecko-dev/blob/2f9eacd9d3d995c937b4251a5557d95d494c9be1/layout/style/res/forms.css#L728-L737)
*/

:-moz-ui-invalid {
  box-shadow: none;
}

/*
Add the correct vertical alignment in Chrome and Firefox.
*/

progress {
  vertical-align: baseline;
}

/*
Correct the cursor style of increment and decrement buttons in Safari.
*/

::-webkit-inner-spin-button,
::-webkit-outer-spin-button {
  height: auto;
}

/*
1. Correct the odd appearance in Chrome and Safari.
2. Correct the outline style in Safari.
*/

[type='search'] {
  -webkit-appearance: textfield; /* 1 */
  outline-offset: -2px; /* 2 */
}

/*
Remove the inner padding in Chrome and Safari on macOS.
*/

::-webkit-search-decoration {
  -webkit-appearance: none;
}

/*
1. Correct the inability to style clickable types in iOS and Safari.
2. Change font properties to \`inherit\` in Safari.
*/

::-webkit-file-upload-button {
  -webkit-appearance: button; /* 1 */
  font: inherit; /* 2 */
}

/*
Add the correct display in Chrome and Safari.
*/

summary {
  display: list-item;
}

/*
Removes the default spacing and border for appropriate elements.
*/

blockquote,
dl,
dd,
h1,
h2,
h3,
h4,
h5,
h6,
hr,
figure,
p,
pre {
  margin: 0;
}

fieldset {
  margin: 0;
  padding: 0;
}

legend {
  padding: 0;
}

ol,
ul,
menu {
  list-style: none;
  margin: 0;
  padding: 0;
}

/*
Reset default styling for dialogs.
*/
dialog {
  padding: 0;
}

/*
Prevent resizing textareas horizontally by default.
*/

textarea {
  resize: vertical;
}

/*
1. Reset the default placeholder opacity in Firefox. (https://github.com/tailwindlabs/tailwindcss/issues/3300)
2. Set the default placeholder color to the user's configured gray 400 color.
*/

input::-moz-placeholder, textarea::-moz-placeholder {
  opacity: 1; /* 1 */
  color: #9ca3af; /* 2 */
}

input::placeholder,
textarea::placeholder {
  opacity: 1; /* 1 */
  color: #9ca3af; /* 2 */
}

/*
Set the default cursor for buttons.
*/

button,
[role="button"] {
  cursor: pointer;
}

/*
Make sure disabled buttons don't get the pointer cursor.
*/
:disabled {
  cursor: default;
}

/*
1. Make replaced elements \`display: block\` by default. (https://github.com/mozdevs/cssremedy/issues/14)
2. Add \`vertical-align: middle\` to align replaced elements more sensibly by default. (https://github.com/jensimmons/cssremedy/issues/14#issuecomment-634934210)
   This can trigger a poorly considered lint error in some tools but is included by design.
*/

img,
svg,
video,
canvas,
audio,
iframe,
embed,
object {
  display: block; /* 1 */
  vertical-align: middle; /* 2 */
}

/*
Constrain images and videos to the parent width and preserve their intrinsic aspect ratio. (https://github.com/mozdevs/cssremedy/issues/14)
*/

img,
video {
  max-width: 100%;
  height: auto;
}

/* Make elements with the HTML hidden attribute stay hidden by default */
[hidden]:where(:not([hidden="until-found"])) {
  display: none;
}
.\\!container {
  width: 100% !important;
}
.container {
  width: 100%;
}
@media (min-width: 640px) {

  .\\!container {
    max-width: 640px !important;
  }

  .container {
    max-width: 640px;
  }
}
@media (min-width: 768px) {

  .\\!container {
    max-width: 768px !important;
  }

  .container {
    max-width: 768px;
  }
}
@media (min-width: 1024px) {

  .\\!container {
    max-width: 1024px !important;
  }

  .container {
    max-width: 1024px;
  }
}
@media (min-width: 1280px) {

  .\\!container {
    max-width: 1280px !important;
  }

  .container {
    max-width: 1280px;
  }
}
@media (min-width: 1536px) {

  .\\!container {
    max-width: 1536px !important;
  }

  .container {
    max-width: 1536px;
  }
}
.pointer-events-none {
  pointer-events: none;
}
.pointer-events-auto {
  pointer-events: auto;
}
.visible {
  visibility: visible;
}
.static {
  position: static;
}
.fixed {
  position: fixed;
}
.absolute {
  position: absolute;
}
.relative {
  position: relative;
}
.sticky {
  position: sticky;
}
.inset-0 {
  inset: 0px;
}
.inset-x-1 {
  left: 4px;
  right: 4px;
}
.inset-y-0 {
  top: 0px;
  bottom: 0px;
}
.-right-1 {
  right: -4px;
}
.-right-2\\.5 {
  right: -10px;
}
.-top-1 {
  top: -4px;
}
.-top-2\\.5 {
  top: -10px;
}
.bottom-0 {
  bottom: 0px;
}
.bottom-4 {
  bottom: 16px;
}
.left-0 {
  left: 0px;
}
.left-3 {
  left: 12px;
}
.right-0 {
  right: 0px;
}
.right-0\\.5 {
  right: 2px;
}
.right-2 {
  right: 8px;
}
.right-4 {
  right: 16px;
}
.top-0 {
  top: 0px;
}
.top-0\\.5 {
  top: 2px;
}
.top-1\\/2 {
  top: 50%;
}
.top-2 {
  top: 8px;
}
.z-10 {
  z-index: 10;
}
.z-100 {
  z-index: 100;
}
.z-50 {
  z-index: 50;
}
.z-\\[124124124124\\] {
  z-index: 124124124124;
}
.z-\\[214748365\\] {
  z-index: 214748365;
}
.z-\\[214748367\\] {
  z-index: 214748367;
}
.m-\\[2px\\] {
  margin: 2px;
}
.mx-0\\.5 {
  margin-left: 2px;
  margin-right: 2px;
}
.\\!ml-0 {
  margin-left: 0px !important;
}
.mb-1\\.5 {
  margin-bottom: 6px;
}
.mb-2 {
  margin-bottom: 8px;
}
.mb-3 {
  margin-bottom: 12px;
}
.mb-4 {
  margin-bottom: 16px;
}
.mb-px {
  margin-bottom: 1px;
}
.ml-1 {
  margin-left: 4px;
}
.ml-1\\.5 {
  margin-left: 6px;
}
.ml-auto {
  margin-left: auto;
}
.mr-0\\.5 {
  margin-right: 2px;
}
.mr-1 {
  margin-right: 4px;
}
.mr-1\\.5 {
  margin-right: 6px;
}
.mr-16 {
  margin-right: 64px;
}
.mr-auto {
  margin-right: auto;
}
.mt-0\\.5 {
  margin-top: 2px;
}
.mt-1 {
  margin-top: 4px;
}
.mt-4 {
  margin-top: 16px;
}
.block {
  display: block;
}
.inline {
  display: inline;
}
.flex {
  display: flex;
}
.table {
  display: table;
}
.hidden {
  display: none;
}
.aspect-square {
  aspect-ratio: 1 / 1;
}
.h-1 {
  height: 4px;
}
.h-1\\.5 {
  height: 6px;
}
.h-10 {
  height: 40px;
}
.h-12 {
  height: 48px;
}
.h-4 {
  height: 16px;
}
.h-4\\/5 {
  height: 80%;
}
.h-6 {
  height: 24px;
}
.h-7 {
  height: 28px;
}
.h-8 {
  height: 32px;
}
.h-\\[150px\\] {
  height: 150px;
}
.h-\\[235px\\] {
  height: 235px;
}
.h-\\[28px\\] {
  height: 28px;
}
.h-\\[48px\\] {
  height: 48px;
}
.h-\\[50px\\] {
  height: 50px;
}
.h-\\[calc\\(100\\%-150px\\)\\] {
  height: calc(100% - 150px);
}
.h-\\[calc\\(100\\%-200px\\)\\] {
  height: calc(100% - 200px);
}
.h-\\[calc\\(100\\%-25px\\)\\] {
  height: calc(100% - 25px);
}
.h-\\[calc\\(100\\%-40px\\)\\] {
  height: calc(100% - 40px);
}
.h-\\[calc\\(100\\%-48px\\)\\] {
  height: calc(100% - 48px);
}
.h-fit {
  height: -moz-fit-content;
  height: fit-content;
}
.h-full {
  height: 100%;
}
.h-screen {
  height: 100vh;
}
.max-h-0 {
  max-height: 0px;
}
.max-h-40 {
  max-height: 160px;
}
.max-h-9 {
  max-height: 36px;
}
.min-h-9 {
  min-height: 36px;
}
.min-h-\\[48px\\] {
  min-height: 48px;
}
.min-h-fit {
  min-height: -moz-fit-content;
  min-height: fit-content;
}
.w-1 {
  width: 4px;
}
.w-1\\/2 {
  width: 50%;
}
.w-1\\/3 {
  width: 33.333333%;
}
.w-2\\/4 {
  width: 50%;
}
.w-3 {
  width: 12px;
}
.w-4 {
  width: 16px;
}
.w-4\\/5 {
  width: 80%;
}
.w-6 {
  width: 24px;
}
.w-80 {
  width: 320px;
}
.w-\\[20px\\] {
  width: 20px;
}
.w-\\[72px\\] {
  width: 72px;
}
.w-\\[90\\%\\] {
  width: 90%;
}
.w-\\[calc\\(100\\%-200px\\)\\] {
  width: calc(100% - 200px);
}
.w-fit {
  width: -moz-fit-content;
  width: fit-content;
}
.w-full {
  width: 100%;
}
.w-px {
  width: 1px;
}
.w-screen {
  width: 100vw;
}
.min-w-0 {
  min-width: 0px;
}
.min-w-\\[200px\\] {
  min-width: 200px;
}
.min-w-fit {
  min-width: -moz-fit-content;
  min-width: fit-content;
}
.max-w-md {
  max-width: 448px;
}
.flex-1 {
  flex: 1 1 0%;
}
.shrink-0 {
  flex-shrink: 0;
}
.grow {
  flex-grow: 1;
}
.-translate-y-1\\/2 {
  --tw-translate-y: -50%;
  transform: translate(var(--tw-translate-x), var(--tw-translate-y)) rotate(var(--tw-rotate)) skewX(var(--tw-skew-x)) skewY(var(--tw-skew-y)) scaleX(var(--tw-scale-x)) scaleY(var(--tw-scale-y));
}
.-translate-y-\\[200\\%\\] {
  --tw-translate-y: -200%;
  transform: translate(var(--tw-translate-x), var(--tw-translate-y)) rotate(var(--tw-rotate)) skewX(var(--tw-skew-x)) skewY(var(--tw-skew-y)) scaleX(var(--tw-scale-x)) scaleY(var(--tw-scale-y));
}
.translate-y-0 {
  --tw-translate-y: 0px;
  transform: translate(var(--tw-translate-x), var(--tw-translate-y)) rotate(var(--tw-rotate)) skewX(var(--tw-skew-x)) skewY(var(--tw-skew-y)) scaleX(var(--tw-scale-x)) scaleY(var(--tw-scale-y));
}
.translate-y-1 {
  --tw-translate-y: 4px;
  transform: translate(var(--tw-translate-x), var(--tw-translate-y)) rotate(var(--tw-rotate)) skewX(var(--tw-skew-x)) skewY(var(--tw-skew-y)) scaleX(var(--tw-scale-x)) scaleY(var(--tw-scale-y));
}
.-rotate-90 {
  --tw-rotate: -90deg;
  transform: translate(var(--tw-translate-x), var(--tw-translate-y)) rotate(var(--tw-rotate)) skewX(var(--tw-skew-x)) skewY(var(--tw-skew-y)) scaleX(var(--tw-scale-x)) scaleY(var(--tw-scale-y));
}
.rotate-0 {
  --tw-rotate: 0deg;
  transform: translate(var(--tw-translate-x), var(--tw-translate-y)) rotate(var(--tw-rotate)) skewX(var(--tw-skew-x)) skewY(var(--tw-skew-y)) scaleX(var(--tw-scale-x)) scaleY(var(--tw-scale-y));
}
.rotate-90 {
  --tw-rotate: 90deg;
  transform: translate(var(--tw-translate-x), var(--tw-translate-y)) rotate(var(--tw-rotate)) skewX(var(--tw-skew-x)) skewY(var(--tw-skew-y)) scaleX(var(--tw-scale-x)) scaleY(var(--tw-scale-y));
}
.scale-110 {
  --tw-scale-x: 1.1;
  --tw-scale-y: 1.1;
  transform: translate(var(--tw-translate-x), var(--tw-translate-y)) rotate(var(--tw-rotate)) skewX(var(--tw-skew-x)) skewY(var(--tw-skew-y)) scaleX(var(--tw-scale-x)) scaleY(var(--tw-scale-y));
}
.transform {
  transform: translate(var(--tw-translate-x), var(--tw-translate-y)) rotate(var(--tw-rotate)) skewX(var(--tw-skew-x)) skewY(var(--tw-skew-y)) scaleX(var(--tw-scale-x)) scaleY(var(--tw-scale-y));
}
@keyframes fadeIn {

  0% {
    opacity: 0;
  }

  100% {
    opacity: 1;
  }
}
.animate-fade-in {
  animation: fadeIn ease-in forwards;
}
.cursor-default {
  cursor: default;
}
.cursor-e-resize {
  cursor: e-resize;
}
.cursor-ew-resize {
  cursor: ew-resize;
}
.cursor-move {
  cursor: move;
}
.cursor-nesw-resize {
  cursor: nesw-resize;
}
.cursor-ns-resize {
  cursor: ns-resize;
}
.cursor-nwse-resize {
  cursor: nwse-resize;
}
.cursor-pointer {
  cursor: pointer;
}
.cursor-w-resize {
  cursor: w-resize;
}
.select-none {
  -webkit-user-select: none;
     -moz-user-select: none;
          user-select: none;
}
.resize {
  resize: both;
}
.appearance-none {
  -webkit-appearance: none;
     -moz-appearance: none;
          appearance: none;
}
.flex-col {
  flex-direction: column;
}
.items-start {
  align-items: flex-start;
}
.items-end {
  align-items: flex-end;
}
.items-center {
  align-items: center;
}
.items-stretch {
  align-items: stretch;
}
.justify-start {
  justify-content: flex-start;
}
.justify-end {
  justify-content: flex-end;
}
.justify-center {
  justify-content: center;
}
.justify-between {
  justify-content: space-between;
}
.gap-0\\.5 {
  gap: 2px;
}
.gap-1 {
  gap: 4px;
}
.gap-1\\.5 {
  gap: 6px;
}
.gap-2 {
  gap: 8px;
}
.gap-4 {
  gap: 16px;
}
.gap-x-0\\.5 {
  -moz-column-gap: 2px;
       column-gap: 2px;
}
.gap-x-1 {
  -moz-column-gap: 4px;
       column-gap: 4px;
}
.gap-x-1\\.5 {
  -moz-column-gap: 6px;
       column-gap: 6px;
}
.gap-x-2 {
  -moz-column-gap: 8px;
       column-gap: 8px;
}
.gap-x-3 {
  -moz-column-gap: 12px;
       column-gap: 12px;
}
.gap-x-4 {
  -moz-column-gap: 16px;
       column-gap: 16px;
}
.gap-y-0\\.5 {
  row-gap: 2px;
}
.gap-y-1 {
  row-gap: 4px;
}
.gap-y-2 {
  row-gap: 8px;
}
.gap-y-4 {
  row-gap: 16px;
}
.space-y-1\\.5 > :not([hidden]) ~ :not([hidden]) {
  --tw-space-y-reverse: 0;
  margin-top: calc(6px * calc(1 - var(--tw-space-y-reverse)));
  margin-bottom: calc(6px * var(--tw-space-y-reverse));
}
.divide-y > :not([hidden]) ~ :not([hidden]) {
  --tw-divide-y-reverse: 0;
  border-top-width: calc(1px * calc(1 - var(--tw-divide-y-reverse)));
  border-bottom-width: calc(1px * var(--tw-divide-y-reverse));
}
.divide-zinc-800 > :not([hidden]) ~ :not([hidden]) {
  --tw-divide-opacity: 1;
  border-color: rgb(39 39 42 / var(--tw-divide-opacity, 1));
}
.place-self-center {
  place-self: center;
}
.self-end {
  align-self: flex-end;
}
.overflow-auto {
  overflow: auto;
}
.overflow-hidden {
  overflow: hidden;
}
.\\!overflow-visible {
  overflow: visible !important;
}
.overflow-x-auto {
  overflow-x: auto;
}
.overflow-y-auto {
  overflow-y: auto;
}
.overflow-x-hidden {
  overflow-x: hidden;
}
.truncate {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.whitespace-nowrap {
  white-space: nowrap;
}
.whitespace-pre-wrap {
  white-space: pre-wrap;
}
.text-wrap {
  text-wrap: wrap;
}
.break-words {
  overflow-wrap: break-word;
}
.break-all {
  word-break: break-all;
}
.rounded {
  border-radius: 4px;
}
.rounded-full {
  border-radius: 9999px;
}
.rounded-lg {
  border-radius: 8px;
}
.rounded-md {
  border-radius: 6px;
}
.rounded-sm {
  border-radius: 2px;
}
.rounded-l-md {
  border-top-left-radius: 6px;
  border-bottom-left-radius: 6px;
}
.rounded-l-sm {
  border-top-left-radius: 2px;
  border-bottom-left-radius: 2px;
}
.rounded-r-md {
  border-top-right-radius: 6px;
  border-bottom-right-radius: 6px;
}
.rounded-r-sm {
  border-top-right-radius: 2px;
  border-bottom-right-radius: 2px;
}
.rounded-t-lg {
  border-top-left-radius: 8px;
  border-top-right-radius: 8px;
}
.rounded-t-sm {
  border-top-left-radius: 2px;
  border-top-right-radius: 2px;
}
.border {
  border-width: 1px;
}
.border-4 {
  border-width: 4px;
}
.border-b {
  border-bottom-width: 1px;
}
.border-l {
  border-left-width: 1px;
}
.border-l-0 {
  border-left-width: 0px;
}
.border-l-1 {
  border-left-width: 1px;
}
.border-r {
  border-right-width: 1px;
}
.border-t {
  border-top-width: 1px;
}
.border-none {
  border-style: none;
}
.\\!border-red-500 {
  --tw-border-opacity: 1 !important;
  border-color: rgb(239 68 68 / var(--tw-border-opacity, 1)) !important;
}
.border-\\[\\#1e1e1e\\] {
  --tw-border-opacity: 1;
  border-color: rgb(30 30 30 / var(--tw-border-opacity, 1));
}
.border-\\[\\#222\\] {
  --tw-border-opacity: 1;
  border-color: rgb(34 34 34 / var(--tw-border-opacity, 1));
}
.border-\\[\\#27272A\\] {
  --tw-border-opacity: 1;
  border-color: rgb(39 39 42 / var(--tw-border-opacity, 1));
}
.border-\\[\\#333\\] {
  --tw-border-opacity: 1;
  border-color: rgb(51 51 51 / var(--tw-border-opacity, 1));
}
.border-transparent {
  border-color: transparent;
}
.border-zinc-800 {
  --tw-border-opacity: 1;
  border-color: rgb(39 39 42 / var(--tw-border-opacity, 1));
}
.bg-\\[\\#0A0A0A\\] {
  --tw-bg-opacity: 1;
  background-color: rgb(10 10 10 / var(--tw-bg-opacity, 1));
}
.bg-\\[\\#141414\\] {
  --tw-bg-opacity: 1;
  background-color: rgb(20 20 20 / var(--tw-bg-opacity, 1));
}
.bg-\\[\\#18181B\\] {
  --tw-bg-opacity: 1;
  background-color: rgb(24 24 27 / var(--tw-bg-opacity, 1));
}
.bg-\\[\\#18181B\\]\\/50 {
  background-color: rgb(24 24 27 / 0.5);
}
.bg-\\[\\#1D3A66\\] {
  --tw-bg-opacity: 1;
  background-color: rgb(29 58 102 / var(--tw-bg-opacity, 1));
}
.bg-\\[\\#1E1E1E\\] {
  --tw-bg-opacity: 1;
  background-color: rgb(30 30 30 / var(--tw-bg-opacity, 1));
}
.bg-\\[\\#1a2a1a\\] {
  --tw-bg-opacity: 1;
  background-color: rgb(26 42 26 / var(--tw-bg-opacity, 1));
}
.bg-\\[\\#1e1e1e\\] {
  --tw-bg-opacity: 1;
  background-color: rgb(30 30 30 / var(--tw-bg-opacity, 1));
}
.bg-\\[\\#214379d4\\] {
  background-color: #214379d4;
}
.bg-\\[\\#27272A\\] {
  --tw-bg-opacity: 1;
  background-color: rgb(39 39 42 / var(--tw-bg-opacity, 1));
}
.bg-\\[\\#2a1515\\] {
  --tw-bg-opacity: 1;
  background-color: rgb(42 21 21 / var(--tw-bg-opacity, 1));
}
.bg-\\[\\#412162\\] {
  --tw-bg-opacity: 1;
  background-color: rgb(65 33 98 / var(--tw-bg-opacity, 1));
}
.bg-\\[\\#44444a\\] {
  --tw-bg-opacity: 1;
  background-color: rgb(68 68 74 / var(--tw-bg-opacity, 1));
}
.bg-\\[\\#4b4b4b\\] {
  --tw-bg-opacity: 1;
  background-color: rgb(75 75 75 / var(--tw-bg-opacity, 1));
}
.bg-\\[\\#5f3f9a\\] {
  --tw-bg-opacity: 1;
  background-color: rgb(95 63 154 / var(--tw-bg-opacity, 1));
}
.bg-\\[\\#5f3f9a\\]\\/40 {
  background-color: rgb(95 63 154 / 0.4);
}
.bg-\\[\\#6a369e\\] {
  --tw-bg-opacity: 1;
  background-color: rgb(106 54 158 / var(--tw-bg-opacity, 1));
}
.bg-\\[\\#7521c8\\] {
  --tw-bg-opacity: 1;
  background-color: rgb(117 33 200 / var(--tw-bg-opacity, 1));
}
.bg-\\[\\#8e61e3\\] {
  --tw-bg-opacity: 1;
  background-color: rgb(142 97 227 / var(--tw-bg-opacity, 1));
}
.bg-\\[\\#EFD81A\\] {
  --tw-bg-opacity: 1;
  background-color: rgb(239 216 26 / var(--tw-bg-opacity, 1));
}
.bg-\\[\\#b77116\\] {
  --tw-bg-opacity: 1;
  background-color: rgb(183 113 22 / var(--tw-bg-opacity, 1));
}
.bg-\\[\\#b94040\\] {
  --tw-bg-opacity: 1;
  background-color: rgb(185 64 64 / var(--tw-bg-opacity, 1));
}
.bg-\\[\\#d36cff\\] {
  --tw-bg-opacity: 1;
  background-color: rgb(211 108 255 / var(--tw-bg-opacity, 1));
}
.bg-\\[\\#efd81a6b\\] {
  background-color: #efd81a6b;
}
.bg-black {
  --tw-bg-opacity: 1;
  background-color: rgb(0 0 0 / var(--tw-bg-opacity, 1));
}
.bg-black\\/40 {
  background-color: rgb(0 0 0 / 0.4);
}
.bg-gray-200 {
  --tw-bg-opacity: 1;
  background-color: rgb(229 231 235 / var(--tw-bg-opacity, 1));
}
.bg-green-500\\/50 {
  background-color: rgb(34 197 94 / 0.5);
}
.bg-green-500\\/60 {
  background-color: rgb(34 197 94 / 0.6);
}
.bg-neutral-700 {
  --tw-bg-opacity: 1;
  background-color: rgb(64 64 64 / var(--tw-bg-opacity, 1));
}
.bg-purple-500 {
  --tw-bg-opacity: 1;
  background-color: rgb(168 85 247 / var(--tw-bg-opacity, 1));
}
.bg-purple-500\\/90 {
  background-color: rgb(168 85 247 / 0.9);
}
.bg-purple-800 {
  --tw-bg-opacity: 1;
  background-color: rgb(107 33 168 / var(--tw-bg-opacity, 1));
}
.bg-red-500 {
  --tw-bg-opacity: 1;
  background-color: rgb(239 68 68 / var(--tw-bg-opacity, 1));
}
.bg-red-500\\/90 {
  background-color: rgb(239 68 68 / 0.9);
}
.bg-red-950\\/50 {
  background-color: rgb(69 10 10 / 0.5);
}
.bg-transparent {
  background-color: transparent;
}
.bg-white {
  --tw-bg-opacity: 1;
  background-color: rgb(255 255 255 / var(--tw-bg-opacity, 1));
}
.bg-yellow-300 {
  --tw-bg-opacity: 1;
  background-color: rgb(253 224 71 / var(--tw-bg-opacity, 1));
}
.bg-zinc-800 {
  --tw-bg-opacity: 1;
  background-color: rgb(39 39 42 / var(--tw-bg-opacity, 1));
}
.bg-zinc-900\\/30 {
  background-color: rgb(24 24 27 / 0.3);
}
.bg-zinc-900\\/50 {
  background-color: rgb(24 24 27 / 0.5);
}
.p-0 {
  padding: 0px;
}
.p-1 {
  padding: 4px;
}
.p-2 {
  padding: 8px;
}
.p-3 {
  padding: 12px;
}
.p-4 {
  padding: 16px;
}
.p-5 {
  padding: 20px;
}
.p-6 {
  padding: 24px;
}
.px-1 {
  padding-left: 4px;
  padding-right: 4px;
}
.px-1\\.5 {
  padding-left: 6px;
  padding-right: 6px;
}
.px-2 {
  padding-left: 8px;
  padding-right: 8px;
}
.px-2\\.5 {
  padding-left: 10px;
  padding-right: 10px;
}
.px-3 {
  padding-left: 12px;
  padding-right: 12px;
}
.px-4 {
  padding-left: 16px;
  padding-right: 16px;
}
.py-0\\.5 {
  padding-top: 2px;
  padding-bottom: 2px;
}
.py-1 {
  padding-top: 4px;
  padding-bottom: 4px;
}
.py-1\\.5 {
  padding-top: 6px;
  padding-bottom: 6px;
}
.py-2 {
  padding-top: 8px;
  padding-bottom: 8px;
}
.py-3 {
  padding-top: 12px;
  padding-bottom: 12px;
}
.py-4 {
  padding-top: 16px;
  padding-bottom: 16px;
}
.py-\\[1px\\] {
  padding-top: 1px;
  padding-bottom: 1px;
}
.py-\\[3px\\] {
  padding-top: 3px;
  padding-bottom: 3px;
}
.py-\\[5px\\] {
  padding-top: 5px;
  padding-bottom: 5px;
}
.pb-2 {
  padding-bottom: 8px;
}
.pl-1 {
  padding-left: 4px;
}
.pl-2 {
  padding-left: 8px;
}
.pl-2\\.5 {
  padding-left: 10px;
}
.pl-3 {
  padding-left: 12px;
}
.pl-5 {
  padding-left: 20px;
}
.pl-6 {
  padding-left: 24px;
}
.pr-1 {
  padding-right: 4px;
}
.pr-1\\.5 {
  padding-right: 6px;
}
.pr-2 {
  padding-right: 8px;
}
.pr-2\\.5 {
  padding-right: 10px;
}
.pt-0 {
  padding-top: 0px;
}
.pt-2 {
  padding-top: 8px;
}
.pt-5 {
  padding-top: 20px;
}
.text-left {
  text-align: left;
}
.font-mono {
  font-family: Menlo, Consolas, Monaco, Liberation Mono, Lucida Console, monospace;
}
.text-\\[10px\\] {
  font-size: 10px;
}
.text-\\[11px\\] {
  font-size: 11px;
}
.text-\\[13px\\] {
  font-size: 13px;
}
.text-\\[14px\\] {
  font-size: 14px;
}
.text-\\[17px\\] {
  font-size: 17px;
}
.text-\\[8px\\] {
  font-size: 8px;
}
.text-sm {
  font-size: 14px;
  line-height: 20px;
}
.text-xs {
  font-size: 12px;
  line-height: 16px;
}
.font-bold {
  font-weight: 700;
}
.font-medium {
  font-weight: 500;
}
.font-semibold {
  font-weight: 600;
}
.uppercase {
  text-transform: uppercase;
}
.lowercase {
  text-transform: lowercase;
}
.capitalize {
  text-transform: capitalize;
}
.italic {
  font-style: italic;
}
.leading-6 {
  line-height: 24px;
}
.leading-none {
  line-height: 1;
}
.tracking-wide {
  letter-spacing: 0.025em;
}
.text-\\[\\#4ade80\\] {
  --tw-text-opacity: 1;
  color: rgb(74 222 128 / var(--tw-text-opacity, 1));
}
.text-\\[\\#5a5a5a\\] {
  --tw-text-opacity: 1;
  color: rgb(90 90 90 / var(--tw-text-opacity, 1));
}
.text-\\[\\#65656D\\] {
  --tw-text-opacity: 1;
  color: rgb(101 101 109 / var(--tw-text-opacity, 1));
}
.text-\\[\\#666\\] {
  --tw-text-opacity: 1;
  color: rgb(102 102 102 / var(--tw-text-opacity, 1));
}
.text-\\[\\#6E6E77\\] {
  --tw-text-opacity: 1;
  color: rgb(110 110 119 / var(--tw-text-opacity, 1));
}
.text-\\[\\#6F6F78\\] {
  --tw-text-opacity: 1;
  color: rgb(111 111 120 / var(--tw-text-opacity, 1));
}
.text-\\[\\#7346a0\\] {
  --tw-text-opacity: 1;
  color: rgb(115 70 160 / var(--tw-text-opacity, 1));
}
.text-\\[\\#737373\\] {
  --tw-text-opacity: 1;
  color: rgb(115 115 115 / var(--tw-text-opacity, 1));
}
.text-\\[\\#888\\] {
  --tw-text-opacity: 1;
  color: rgb(136 136 136 / var(--tw-text-opacity, 1));
}
.text-\\[\\#8E61E3\\] {
  --tw-text-opacity: 1;
  color: rgb(142 97 227 / var(--tw-text-opacity, 1));
}
.text-\\[\\#999\\] {
  --tw-text-opacity: 1;
  color: rgb(153 153 153 / var(--tw-text-opacity, 1));
}
.text-\\[\\#A1A1AA\\] {
  --tw-text-opacity: 1;
  color: rgb(161 161 170 / var(--tw-text-opacity, 1));
}
.text-\\[\\#A855F7\\] {
  --tw-text-opacity: 1;
  color: rgb(168 85 247 / var(--tw-text-opacity, 1));
}
.text-\\[\\#E4E4E7\\] {
  --tw-text-opacity: 1;
  color: rgb(228 228 231 / var(--tw-text-opacity, 1));
}
.text-\\[\\#d36cff\\] {
  --tw-text-opacity: 1;
  color: rgb(211 108 255 / var(--tw-text-opacity, 1));
}
.text-\\[\\#f87171\\] {
  --tw-text-opacity: 1;
  color: rgb(248 113 113 / var(--tw-text-opacity, 1));
}
.text-black {
  --tw-text-opacity: 1;
  color: rgb(0 0 0 / var(--tw-text-opacity, 1));
}
.text-gray-100 {
  --tw-text-opacity: 1;
  color: rgb(243 244 246 / var(--tw-text-opacity, 1));
}
.text-gray-300 {
  --tw-text-opacity: 1;
  color: rgb(209 213 219 / var(--tw-text-opacity, 1));
}
.text-gray-400 {
  --tw-text-opacity: 1;
  color: rgb(156 163 175 / var(--tw-text-opacity, 1));
}
.text-gray-500 {
  --tw-text-opacity: 1;
  color: rgb(107 114 128 / var(--tw-text-opacity, 1));
}
.text-green-500 {
  --tw-text-opacity: 1;
  color: rgb(34 197 94 / var(--tw-text-opacity, 1));
}
.text-neutral-300 {
  --tw-text-opacity: 1;
  color: rgb(212 212 212 / var(--tw-text-opacity, 1));
}
.text-neutral-400 {
  --tw-text-opacity: 1;
  color: rgb(163 163 163 / var(--tw-text-opacity, 1));
}
.text-neutral-500 {
  --tw-text-opacity: 1;
  color: rgb(115 115 115 / var(--tw-text-opacity, 1));
}
.text-purple-400 {
  --tw-text-opacity: 1;
  color: rgb(192 132 252 / var(--tw-text-opacity, 1));
}
.text-red-300 {
  --tw-text-opacity: 1;
  color: rgb(252 165 165 / var(--tw-text-opacity, 1));
}
.text-red-400 {
  --tw-text-opacity: 1;
  color: rgb(248 113 113 / var(--tw-text-opacity, 1));
}
.text-red-500 {
  --tw-text-opacity: 1;
  color: rgb(239 68 68 / var(--tw-text-opacity, 1));
}
.text-white {
  --tw-text-opacity: 1;
  color: rgb(255 255 255 / var(--tw-text-opacity, 1));
}
.text-white\\/30 {
  color: rgb(255 255 255 / 0.3);
}
.text-white\\/70 {
  color: rgb(255 255 255 / 0.7);
}
.text-yellow-300 {
  --tw-text-opacity: 1;
  color: rgb(253 224 71 / var(--tw-text-opacity, 1));
}
.text-yellow-500 {
  --tw-text-opacity: 1;
  color: rgb(234 179 8 / var(--tw-text-opacity, 1));
}
.text-zinc-200 {
  --tw-text-opacity: 1;
  color: rgb(228 228 231 / var(--tw-text-opacity, 1));
}
.text-zinc-400 {
  --tw-text-opacity: 1;
  color: rgb(161 161 170 / var(--tw-text-opacity, 1));
}
.text-zinc-500 {
  --tw-text-opacity: 1;
  color: rgb(113 113 122 / var(--tw-text-opacity, 1));
}
.text-zinc-600 {
  --tw-text-opacity: 1;
  color: rgb(82 82 91 / var(--tw-text-opacity, 1));
}
.opacity-0 {
  opacity: 0;
}
.opacity-100 {
  opacity: 1;
}
.opacity-50 {
  opacity: 0.5;
}
.shadow-lg {
  --tw-shadow: 0 10px 15px -3px rgb(0 0 0 / 0.1), 0 4px 6px -4px rgb(0 0 0 / 0.1);
  --tw-shadow-colored: 0 10px 15px -3px var(--tw-shadow-color), 0 4px 6px -4px var(--tw-shadow-color);
  box-shadow: var(--tw-ring-offset-shadow, 0 0 #0000), var(--tw-ring-shadow, 0 0 #0000), var(--tw-shadow);
}
.outline {
  outline-style: solid;
}
.ring-1 {
  --tw-ring-offset-shadow: var(--tw-ring-inset) 0 0 0 var(--tw-ring-offset-width) var(--tw-ring-offset-color);
  --tw-ring-shadow: var(--tw-ring-inset) 0 0 0 calc(1px + var(--tw-ring-offset-width)) var(--tw-ring-color);
  box-shadow: var(--tw-ring-offset-shadow), var(--tw-ring-shadow), var(--tw-shadow, 0 0 #0000);
}
.ring-white\\/\\[0\\.08\\] {
  --tw-ring-color: rgb(255 255 255 / 0.08);
}
.blur {
  --tw-blur: blur(8px);
  filter: var(--tw-blur) var(--tw-brightness) var(--tw-contrast) var(--tw-grayscale) var(--tw-hue-rotate) var(--tw-invert) var(--tw-saturate) var(--tw-sepia) var(--tw-drop-shadow);
}
.\\!filter {
  filter: var(--tw-blur) var(--tw-brightness) var(--tw-contrast) var(--tw-grayscale) var(--tw-hue-rotate) var(--tw-invert) var(--tw-saturate) var(--tw-sepia) var(--tw-drop-shadow) !important;
}
.filter {
  filter: var(--tw-blur) var(--tw-brightness) var(--tw-contrast) var(--tw-grayscale) var(--tw-hue-rotate) var(--tw-invert) var(--tw-saturate) var(--tw-sepia) var(--tw-drop-shadow);
}
.backdrop-blur-sm {
  --tw-backdrop-blur: blur(4px);
  -webkit-backdrop-filter: var(--tw-backdrop-blur) var(--tw-backdrop-brightness) var(--tw-backdrop-contrast) var(--tw-backdrop-grayscale) var(--tw-backdrop-hue-rotate) var(--tw-backdrop-invert) var(--tw-backdrop-opacity) var(--tw-backdrop-saturate) var(--tw-backdrop-sepia);
  backdrop-filter: var(--tw-backdrop-blur) var(--tw-backdrop-brightness) var(--tw-backdrop-contrast) var(--tw-backdrop-grayscale) var(--tw-backdrop-hue-rotate) var(--tw-backdrop-invert) var(--tw-backdrop-opacity) var(--tw-backdrop-saturate) var(--tw-backdrop-sepia);
}
.transition {
  transition-property: color, background-color, border-color, text-decoration-color, fill, stroke, opacity, box-shadow, transform, filter, -webkit-backdrop-filter;
  transition-property: color, background-color, border-color, text-decoration-color, fill, stroke, opacity, box-shadow, transform, filter, backdrop-filter;
  transition-property: color, background-color, border-color, text-decoration-color, fill, stroke, opacity, box-shadow, transform, filter, backdrop-filter, -webkit-backdrop-filter;
  transition-timing-function: cubic-bezier(0.4, 0, 0.2, 1);
  transition-duration: 150ms;
}
.transition-\\[border-radius\\] {
  transition-property: border-radius;
  transition-timing-function: cubic-bezier(0.4, 0, 0.2, 1);
  transition-duration: 150ms;
}
.transition-\\[color\\2c transform\\] {
  transition-property: color,transform;
  transition-timing-function: cubic-bezier(0.4, 0, 0.2, 1);
  transition-duration: 150ms;
}
.transition-\\[max-height\\] {
  transition-property: max-height;
  transition-timing-function: cubic-bezier(0.4, 0, 0.2, 1);
  transition-duration: 150ms;
}
.transition-\\[opacity\\] {
  transition-property: opacity;
  transition-timing-function: cubic-bezier(0.4, 0, 0.2, 1);
  transition-duration: 150ms;
}
.transition-all {
  transition-property: all;
  transition-timing-function: cubic-bezier(0.4, 0, 0.2, 1);
  transition-duration: 150ms;
}
.transition-colors {
  transition-property: color, background-color, border-color, text-decoration-color, fill, stroke;
  transition-timing-function: cubic-bezier(0.4, 0, 0.2, 1);
  transition-duration: 150ms;
}
.transition-none {
  transition-property: none;
}
.transition-opacity {
  transition-property: opacity;
  transition-timing-function: cubic-bezier(0.4, 0, 0.2, 1);
  transition-duration: 150ms;
}
.transition-transform {
  transition-property: transform;
  transition-timing-function: cubic-bezier(0.4, 0, 0.2, 1);
  transition-duration: 150ms;
}
.delay-0 {
  transition-delay: 0s;
}
.delay-150 {
  transition-delay: 150ms;
}
.delay-300 {
  transition-delay: 300ms;
}
.\\!duration-0 {
  transition-duration: 0s !important;
}
.duration-0 {
  transition-duration: 0s;
}
.duration-200 {
  transition-duration: 200ms;
}
.duration-300 {
  transition-duration: 300ms;
}
.ease-\\[cubic-bezier\\(0\\.23\\2c 1\\2c 0\\.32\\2c 1\\)\\] {
  transition-timing-function: cubic-bezier(0.23,1,0.32,1);
}
.ease-\\[cubic-bezier\\(0\\.25\\2c 0\\.1\\2c 0\\.25\\2c 1\\)\\] {
  transition-timing-function: cubic-bezier(0.25,0.1,0.25,1);
}
.ease-in-out {
  transition-timing-function: cubic-bezier(0.4, 0, 0.2, 1);
}
.ease-out {
  transition-timing-function: cubic-bezier(0, 0, 0.2, 1);
}
.will-change-transform {
  will-change: transform;
}
.animation-duration-300 {
  animation-duration: .3s;
}
.animation-delay-300 {
  animation-delay: .3s;
}
.\\[touch-action\\:none\\] {
  touch-action: none;
}

* {
  outline: none !important;
  text-rendering: optimizeLegibility;
  -webkit-font-smoothing: antialiased;
  -moz-osx-font-smoothing: grayscale;
  backface-visibility: hidden;

  /* WebKit (Chrome, Safari, Edge) specific scrollbar styles */
  &::-webkit-scrollbar {
    width: 6px;
    height: 6px;
  }

  &::-webkit-scrollbar-track {
    border-radius: 10px;
    background: transparent;
  }

  &::-webkit-scrollbar-thumb {
    border-radius: 10px;
    background: rgba(255, 255, 255, 0.3);
  }

  &::-webkit-scrollbar-thumb:hover {
    background: rgba(255, 255, 255, .4);
  }

  &::-webkit-scrollbar-corner {
    background: transparent;
  }
}

@-moz-document url-prefix() {
  * {
    scrollbar-width: thin;
    scrollbar-color: rgba(255, 255, 255, 0.4) transparent;
    scrollbar-width: 6px;
  }
}


button:hover {
  background-image: none;
}


button {
  outline: 2px solid transparent;
  outline-offset: 2px;
  border-style: none;
  transition-property: color, background-color, border-color, text-decoration-color, fill, stroke;
  transition-timing-function: cubic-bezier(0.4, 0, 0.2, 1);
  transition-duration: 150ms;
  transition-timing-function: linear;
  cursor: pointer;
}

input {
  border-style: none;
  background-color: transparent;
  background-image: none;
  outline: 2px solid transparent;
  outline-offset: 2px;
}

input::-moz-placeholder {
  font-size: 12px;
  line-height: 16px;
  font-style: italic;
  --tw-text-opacity: 1;
  color: rgb(115 115 115 / var(--tw-text-opacity, 1));
}

input::placeholder {
  font-size: 12px;
  line-height: 16px;
  font-style: italic;
  --tw-text-opacity: 1;
  color: rgb(115 115 115 / var(--tw-text-opacity, 1));
}

input:-moz-placeholder-shown {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

input:placeholder-shown {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

svg {
  height: auto;
  width: auto;
  pointer-events: none;
}

/*
  Using CSS content with data attributes is more performant than:
  1. React re-renders with JSX text content
  2. Direct DOM manipulation methods:
     - element.textContent (creates/updates text nodes, triggers repaint)
     - element.innerText (triggers reflow by computing styles & layout)
     - element.innerHTML (heavy parsing, triggers reflow, security risks)
  3. Multiple data attributes with complex CSS concatenation

  This approach:
  - Avoids React reconciliation
  - Uses browser's native CSS engine (optimized content updates)
  - Minimizes main thread work
  - Reduces DOM operations
  - Avoids forced reflows (layout recalculation)
  - Only triggers necessary repaints
  - Keeps pseudo-element updates in render layer
*/
.with-data-text {
  overflow: hidden;
  &::before {
    content: attr(data-text);
  }
  &::before {
    display: block;
  }
  &::before {
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
}

#react-scan-toolbar {
  position: fixed;
  left: 0px;
  top: 0px;
  display: flex;
  flex-direction: column;
  border-radius: 8px;
  --tw-shadow: 0 10px 15px -3px rgb(0 0 0 / 0.1), 0 4px 6px -4px rgb(0 0 0 / 0.1);
  --tw-shadow-colored: 0 10px 15px -3px var(--tw-shadow-color), 0 4px 6px -4px var(--tw-shadow-color);
  box-shadow: var(--tw-ring-offset-shadow, 0 0 #0000), var(--tw-ring-shadow, 0 0 #0000), var(--tw-shadow);
  font-family: Menlo, Consolas, Monaco, Liberation Mono, Lucida Console, monospace;
  font-size: 13px;
  --tw-text-opacity: 1;
  color: rgb(255 255 255 / var(--tw-text-opacity, 1));
  --tw-bg-opacity: 1;
  background-color: rgb(0 0 0 / var(--tw-bg-opacity, 1));
  -webkit-user-select: none;
     -moz-user-select: none;
          user-select: none;
  cursor: move;
  opacity: 0;
  z-index: 2147483678;
}

@keyframes fadeIn {

  0% {
    opacity: 0;
  }

  100% {
    opacity: 1;
  }
}

#react-scan-toolbar {
  animation: fadeIn ease-in forwards;
  animation-duration: .3s;
  animation-delay: .3s;
  --tw-shadow: 0 4px 12px rgba(0,0,0,0.2);
  --tw-shadow-colored: 0 4px 12px var(--tw-shadow-color);
  box-shadow: var(--tw-ring-offset-shadow, 0 0 #0000), var(--tw-ring-shadow, 0 0 #0000), var(--tw-shadow);
  place-self: start;

  /* [CURSOR GENERATED] Anti-blur fixes:
   * We removed will-change-transform and replaced it with these properties
   * because will-change was causing stacking context issues and inconsistent
   * text rendering. The new properties work together to force proper
   * GPU acceleration without z-index side effects:
   */
  transform: translate3d(0, 0, 0);      /* Forces GPU acceleration without causing stacking issues */
  backface-visibility: hidden;          /* Prevents blurry text during transforms */
  perspective: 1000;                    /* Creates proper 3D context for crisp text */ /* Ensures consistent text rendering across browsers */
  transform-style: preserve-3d;
}

.button {
  &:hover {
    background: rgba(255, 255, 255, 0.1);
  }

  &:active {
    background: rgba(255, 255, 255, 0.15);
  }
}

.resize-line-wrapper {
  position: absolute;
  overflow: hidden;
}

.resize-line {
  position: absolute;
  inset: 0px;
  overflow: hidden;
  --tw-bg-opacity: 1;
  background-color: rgb(0 0 0 / var(--tw-bg-opacity, 1));
  transition-property: all;
  transition-timing-function: cubic-bezier(0.4, 0, 0.2, 1);
  transition-duration: 150ms;

  svg {
    position: absolute;
  }

  svg {
    top: 50%;
  }

  svg {
    left: 50%;
  }

  svg {
    --tw-translate-x: -50%;
    transform: translate(var(--tw-translate-x), var(--tw-translate-y)) rotate(var(--tw-rotate)) skewX(var(--tw-skew-x)) skewY(var(--tw-skew-y)) scaleX(var(--tw-scale-x)) scaleY(var(--tw-scale-y));
  }

  svg {
    --tw-translate-y: -50%;
    transform: translate(var(--tw-translate-x), var(--tw-translate-y)) rotate(var(--tw-rotate)) skewX(var(--tw-skew-x)) skewY(var(--tw-skew-y)) scaleX(var(--tw-scale-x)) scaleY(var(--tw-scale-y));
  }
}

.resize-right,
.resize-left {
  top: 0px;
  bottom: 0px;
  width: 24px;
  cursor: ew-resize;

  .resize-line-wrapper {
    top: 0px;
    bottom: 0px;
  }

  .resize-line-wrapper {
    width: 50%;
  }

  &:hover {
    .resize-line {
      --tw-translate-x: 0px;
      transform: translate(var(--tw-translate-x), var(--tw-translate-y)) rotate(var(--tw-rotate)) skewX(var(--tw-skew-x)) skewY(var(--tw-skew-y)) scaleX(var(--tw-scale-x)) scaleY(var(--tw-scale-y));
    }
  }
}
.resize-right {
  right: 0px;
  --tw-translate-x: 50%;
  transform: translate(var(--tw-translate-x), var(--tw-translate-y)) rotate(var(--tw-rotate)) skewX(var(--tw-skew-x)) skewY(var(--tw-skew-y)) scaleX(var(--tw-scale-x)) scaleY(var(--tw-scale-y));

  .resize-line-wrapper {
    right: 0px;
  }
  .resize-line {
    border-top-right-radius: 8px;
    border-bottom-right-radius: 8px;
  }
  .resize-line {
    --tw-translate-x: -100%;
    transform: translate(var(--tw-translate-x), var(--tw-translate-y)) rotate(var(--tw-rotate)) skewX(var(--tw-skew-x)) skewY(var(--tw-skew-y)) scaleX(var(--tw-scale-x)) scaleY(var(--tw-scale-y));
  }
}

.resize-left {
  left: 0px;
  --tw-translate-x: -50%;
  transform: translate(var(--tw-translate-x), var(--tw-translate-y)) rotate(var(--tw-rotate)) skewX(var(--tw-skew-x)) skewY(var(--tw-skew-y)) scaleX(var(--tw-scale-x)) scaleY(var(--tw-scale-y));

  .resize-line-wrapper {
    left: 0px;
  }
  .resize-line {
    border-top-left-radius: 8px;
    border-bottom-left-radius: 8px;
  }
  .resize-line {
    --tw-translate-x: 100%;
    transform: translate(var(--tw-translate-x), var(--tw-translate-y)) rotate(var(--tw-rotate)) skewX(var(--tw-skew-x)) skewY(var(--tw-skew-y)) scaleX(var(--tw-scale-x)) scaleY(var(--tw-scale-y));
  }
}

.resize-top,
.resize-bottom {
  left: 0px;
  right: 0px;
  height: 24px;
  cursor: ns-resize;

  .resize-line-wrapper {
    left: 0px;
    right: 0px;
  }

  .resize-line-wrapper {
    height: 50%;
  }

  &:hover {
    .resize-line {
      --tw-translate-y: 0px;
      transform: translate(var(--tw-translate-x), var(--tw-translate-y)) rotate(var(--tw-rotate)) skewX(var(--tw-skew-x)) skewY(var(--tw-skew-y)) scaleX(var(--tw-scale-x)) scaleY(var(--tw-scale-y));
    }
  }
}
.resize-top {
  top: 0px;
  --tw-translate-y: -50%;
  transform: translate(var(--tw-translate-x), var(--tw-translate-y)) rotate(var(--tw-rotate)) skewX(var(--tw-skew-x)) skewY(var(--tw-skew-y)) scaleX(var(--tw-scale-x)) scaleY(var(--tw-scale-y));

  .resize-line-wrapper {
    top: 0px;
  }
  .resize-line {
    border-top-left-radius: 8px;
    border-top-right-radius: 8px;
  }
  .resize-line {
    --tw-translate-y: 100%;
    transform: translate(var(--tw-translate-x), var(--tw-translate-y)) rotate(var(--tw-rotate)) skewX(var(--tw-skew-x)) skewY(var(--tw-skew-y)) scaleX(var(--tw-scale-x)) scaleY(var(--tw-scale-y));
  }
}

.resize-bottom {
  bottom: 0px;
  --tw-translate-y: 50%;
  transform: translate(var(--tw-translate-x), var(--tw-translate-y)) rotate(var(--tw-rotate)) skewX(var(--tw-skew-x)) skewY(var(--tw-skew-y)) scaleX(var(--tw-scale-x)) scaleY(var(--tw-scale-y));

  .resize-line-wrapper {
    bottom: 0px;
  }
  .resize-line {
    border-bottom-right-radius: 8px;
    border-bottom-left-radius: 8px;
  }
  .resize-line {
    --tw-translate-y: -100%;
    transform: translate(var(--tw-translate-x), var(--tw-translate-y)) rotate(var(--tw-rotate)) skewX(var(--tw-skew-x)) skewY(var(--tw-skew-y)) scaleX(var(--tw-scale-x)) scaleY(var(--tw-scale-y));
  }
}

.react-scan-header {
  display: flex;
  align-items: center;
  -moz-column-gap: 8px;
       column-gap: 8px;
  padding-left: 12px;
  padding-right: 8px;
  min-height: 36px;
  border-bottom-width: 1px;
  --tw-border-opacity: 1;
  border-color: rgb(34 34 34 / var(--tw-border-opacity, 1));
  overflow: hidden;
  white-space: nowrap;
}

.react-scan-replay-button,
.react-scan-close-button {
  display: flex;
  align-items: center;
  padding: 4px;
  min-width: -moz-fit-content;
  min-width: fit-content;
  border-radius: 4px;
  transition-property: all;
  transition-timing-function: cubic-bezier(0.4, 0, 0.2, 1);
  transition-duration: 300ms;
}

.react-scan-replay-button {
  position: relative;
  overflow: hidden;
  background-color: rgb(168 85 247 / 0.5) !important;

  &:hover {
    background-color: rgb(168 85 247 / 0.25);
  }

  &.disabled {
    opacity: 0.5;
  }

  &.disabled {
    pointer-events: none;
  }

  &:before {
    content: '';
  }

  &:before {
    position: absolute;
  }

  &:before {
    inset: 0px;
  }

  &:before {
    --tw-translate-x: -100%;
    transform: translate(var(--tw-translate-x), var(--tw-translate-y)) rotate(var(--tw-rotate)) skewX(var(--tw-skew-x)) skewY(var(--tw-skew-y)) scaleX(var(--tw-scale-x)) scaleY(var(--tw-scale-y));
  }

  &:before {
    animation: shimmer 2s infinite;
    background: linear-gradient(to right,
      transparent,
      rgba(142, 97, 227, 0.3),
      transparent);
  }
}

.react-scan-close-button {
  background-color: rgb(255 255 255 / 0.1);

  &:hover {
    background-color: rgb(255 255 255 / 0.15);
  }
}

@keyframes shimmer {
  100% {
    --tw-translate-x: 100%;
    transform: translate(var(--tw-translate-x), var(--tw-translate-y)) rotate(var(--tw-rotate)) skewX(var(--tw-skew-x)) skewY(var(--tw-skew-y)) scaleX(var(--tw-scale-x)) scaleY(var(--tw-scale-y));
  }
}

.react-section-header {
  position: sticky;
  z-index: 100;
  display: flex;
  align-items: center;
  -moz-column-gap: 8px;
       column-gap: 8px;
  padding-left: 12px;
  padding-right: 12px;
  height: 28px;
  width: 100%;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  --tw-text-opacity: 1;
  color: rgb(136 136 136 / var(--tw-text-opacity, 1));
  border-bottom-width: 1px;
  --tw-border-opacity: 1;
  border-color: rgb(34 34 34 / var(--tw-border-opacity, 1));
  --tw-bg-opacity: 1;
  background-color: rgb(10 10 10 / var(--tw-bg-opacity, 1));
}

.react-scan-section {
  display: flex;
  flex-direction: column;
  padding-left: 8px;
  padding-right: 8px;
  --tw-text-opacity: 1;
  color: rgb(136 136 136 / var(--tw-text-opacity, 1));
}

.react-scan-section::before {
  --tw-text-opacity: 1;
  color: rgb(107 114 128 / var(--tw-text-opacity, 1));
  --tw-content: attr(data-section);
  content: var(--tw-content);
}

.react-scan-section {
  font-size: 12px;
  line-height: 16px;

  > .react-scan-property {
    margin-left: -14px;
  }
}

.react-scan-property {
  position: relative;
  display: flex;
  flex-direction: column;
  padding-left: 32px;
  border-left-width: 1px;
  border-color: transparent;
  overflow: hidden;
}

.react-scan-property-content {
  display: flex;
  flex: 1 1 0%;
  flex-direction: column;
  min-height: 28px;
  max-width: 100%;
  overflow: hidden;
}

.react-scan-string {
  color: #9ecbff;
}

.react-scan-number {
  color: #79c7ff;
}

.react-scan-boolean {
  color: #56b6c2;
}

.react-scan-key {
  width: -moz-fit-content;
  width: fit-content;
  max-width: 240px;
  white-space: nowrap;
  --tw-text-opacity: 1;
  color: rgb(255 255 255 / var(--tw-text-opacity, 1));
}

.react-scan-input {
  --tw-text-opacity: 1;
  color: rgb(255 255 255 / var(--tw-text-opacity, 1));
  --tw-bg-opacity: 1;
  background-color: rgb(0 0 0 / var(--tw-bg-opacity, 1));
}

@keyframes blink {
  from {
    opacity: 1;
  }
  to {
    opacity: 0;
  }
}

.react-scan-arrow {
  position: absolute;
  top: 0px;
  left: 28px;
  display: flex;
  align-items: center;
  justify-content: center;
  cursor: pointer;
  height: 28px;
  width: 24px;
  --tw-translate-x: -100%;
  transform: translate(var(--tw-translate-x), var(--tw-translate-y)) rotate(var(--tw-rotate)) skewX(var(--tw-skew-x)) skewY(var(--tw-skew-y)) scaleX(var(--tw-scale-x)) scaleY(var(--tw-scale-y));
  z-index: 10;

  > svg {
    transition-property: transform;
    transition-timing-function: cubic-bezier(0.4, 0, 0.2, 1);
    transition-duration: 150ms;
  }
}

.react-scan-expandable {
  display: grid;
  grid-template-rows: 0fr;
  transition-property: all;
  transition-timing-function: cubic-bezier(0.4, 0, 0.2, 1);
  transition-duration: 75ms;

  &.react-scan-expanded {
    grid-template-rows: 1fr;
  }

  &.react-scan-expanded {
    transition-duration: 100ms;
  }
}

.react-scan-nested {
  position: relative;
  overflow: hidden;

  &:before {
    content: '';
  }

  &:before {
    position: absolute;
  }

  &:before {
    top: 0px;
  }

  &:before {
    left: 0px;
  }

  &:before {
    height: 100%;
  }

  &:before {
    width: 1px;
  }

  &:before {
    background-color: rgb(107 114 128 / 0.3);
  }
}

.react-scan-settings {
  position: absolute;
  inset: 0px;
  display: flex;
  flex-direction: column;
  gap: 16px;
  padding-top: 8px;
  padding-bottom: 8px;
  padding-left: 16px;
  padding-right: 16px;
  --tw-text-opacity: 1;
  color: rgb(136 136 136 / var(--tw-text-opacity, 1));

  >div {
    display: flex;
  }

  >div {
    align-items: center;
  }

  >div {
    justify-content: space-between;
  }

  >div {
    transition-property: color, background-color, border-color, text-decoration-color, fill, stroke;
    transition-timing-function: cubic-bezier(0.4, 0, 0.2, 1);
    transition-duration: 150ms;
  }

  >div {
    transition-duration: 300ms;
  }
}

.react-scan-preview-line {
  position: relative;
  display: flex;
  min-height: 28px;
  align-items: center;
  -moz-column-gap: 8px;
       column-gap: 8px;
}

.react-scan-flash-overlay {
  position: absolute;
  inset: 0px;
  opacity: 0;
  z-index: 50;
  pointer-events: none;
  transition-property: opacity;
  transition-timing-function: cubic-bezier(0.4, 0, 0.2, 1);
  transition-duration: 150ms;
  mix-blend-mode: multiply;
  background-color: rgb(168 85 247 / 0.9);
}

.react-scan-toggle {
  position: relative;
  display: inline-flex;
  height: 24px;
  width: 40px;

  input {
    position: absolute;
  }

  input {
    inset: 0px;
  }

  input {
    z-index: 20;
  }

  input {
    opacity: 0;
  }

  input {
    cursor: pointer;
  }

  input {
    height: 100%;
  }

  input {
    width: 100%;
  }

  input:checked {
    +div {
      --tw-bg-opacity: 1;
      background-color: rgb(95 63 154 / var(--tw-bg-opacity, 1));
    }
    +div {

      &::before {
        --tw-translate-x: 100%;
        transform: translate(var(--tw-translate-x), var(--tw-translate-y)) rotate(var(--tw-rotate)) skewX(var(--tw-skew-x)) skewY(var(--tw-skew-y)) scaleX(var(--tw-scale-x)) scaleY(var(--tw-scale-y));
      }

      &::before {
        left: auto;
      }

      &::before {
        --tw-border-opacity: 1;
        border-color: rgb(95 63 154 / var(--tw-border-opacity, 1));
      }
    }
  }

  >div {
    position: absolute;
  }

  >div {
    inset: 4px;
  }

  >div {
    --tw-bg-opacity: 1;
    background-color: rgb(64 64 64 / var(--tw-bg-opacity, 1));
  }

  >div {
    border-radius: 9999px;
  }

  >div {
    pointer-events: none;
  }

  >div {
    transition-property: color, background-color, border-color, text-decoration-color, fill, stroke;
    transition-timing-function: cubic-bezier(0.4, 0, 0.2, 1);
    transition-duration: 150ms;
  }

  >div {
    transition-duration: 300ms;
  }

  >div {

    &:before {
      --tw-content: '';
      content: var(--tw-content);
    }

    &:before {
      position: absolute;
    }

    &:before {
      top: 50%;
    }

    &:before {
      left: 0px;
    }

    &:before {
      --tw-translate-y: -50%;
      transform: translate(var(--tw-translate-x), var(--tw-translate-y)) rotate(var(--tw-rotate)) skewX(var(--tw-skew-x)) skewY(var(--tw-skew-y)) scaleX(var(--tw-scale-x)) scaleY(var(--tw-scale-y));
    }

    &:before {
      height: 16px;
    }

    &:before {
      width: 16px;
    }

    &:before {
      --tw-bg-opacity: 1;
      background-color: rgb(255 255 255 / var(--tw-bg-opacity, 1));
    }

    &:before {
      border-width: 2px;
    }

    &:before {
      --tw-border-opacity: 1;
      border-color: rgb(64 64 64 / var(--tw-border-opacity, 1));
    }

    &:before {
      border-radius: 9999px;
    }

    &:before {
      --tw-shadow: 0 1px 2px 0 rgb(0 0 0 / 0.05);
      --tw-shadow-colored: 0 1px 2px 0 var(--tw-shadow-color);
      box-shadow: var(--tw-ring-offset-shadow, 0 0 #0000), var(--tw-ring-shadow, 0 0 #0000), var(--tw-shadow);
    }

    &:before {
      transition-property: all;
      transition-timing-function: cubic-bezier(0.4, 0, 0.2, 1);
      transition-duration: 150ms;
    }

    &:before {
      transition-duration: 300ms;
    }
  }
}

.react-scan-flash-active {
  opacity: 0.4;
  transition-property: opacity;
  transition-timing-function: cubic-bezier(0.4, 0, 0.2, 1);
  transition-duration: 300ms;
}

.react-scan-inspector-overlay {
  display: flex;
  flex-direction: column;
  opacity: 0;
  transition-property: opacity;
  transition-timing-function: cubic-bezier(0.4, 0, 0.2, 1);
  transition-duration: 300ms;

  &.fade-out {
    opacity: 0;
  }

  &.fade-in {
    opacity: 1;
  }
}

.react-scan-what-changed {
  ul {
    list-style-type: disc;
  }
  ul {
    padding-left: 16px;
  }

  li {
    white-space: nowrap;
  }

  li {
    > div {
      display: flex;
    }
    > div {
      align-items: center;
    }
    > div {
      justify-content: space-between;
    }
    > div {
      -moz-column-gap: 8px;
           column-gap: 8px;
    }
  }
}

.count-badge {
  display: flex;
  align-items: center;
  -moz-column-gap: 8px;
       column-gap: 8px;
  padding-left: 6px;
  padding-right: 6px;
  padding-top: 2px;
  padding-bottom: 2px;
  border-radius: 4px;
  font-size: 12px;
  line-height: 16px;
  font-weight: 500;
  --tw-numeric-spacing: tabular-nums;
  font-variant-numeric: var(--tw-ordinal) var(--tw-slashed-zero) var(--tw-numeric-figure) var(--tw-numeric-spacing) var(--tw-numeric-fraction);
  --tw-text-opacity: 1;
  color: rgb(168 85 247 / var(--tw-text-opacity, 1));
  background-color: rgb(168 85 247 / 0.1);
  transform-origin: center;
  transition-property: all;
  transition-timing-function: cubic-bezier(0.4, 0, 0.2, 1);
  transition-delay: 150ms;
  transition-duration: 300ms;
}

@keyframes countFlash {

  0% {
    background-color: rgba(168, 85, 247, 0.3);
    transform: scale(1.05);
  }

  100% {
    background-color: rgba(168, 85, 247, 0.1);
    transform: scale(1);
  }
}

.count-flash {
  animation: countFlash .3s ease-out forwards;
}

@keyframes countFlashShake {

  0% {
    transform: translateX(0);
  }

  25% {
    transform: translateX(-5px);
  }

  50% {
    transform: translateX(5px) scale(1.1);
  }

  75% {
    transform: translateX(-5px);
  }

  100% {
    transform: translateX(0);
  }
}

.count-flash-white {
  animation: countFlashShake .3s ease-out forwards;
  transition-delay: 500ms !important;
}

.change-scope {
  display: flex;
  align-items: center;
  -moz-column-gap: 4px;
       column-gap: 4px;
  --tw-text-opacity: 1;
  color: rgb(102 102 102 / var(--tw-text-opacity, 1));
  font-size: 12px;
  line-height: 16px;
  font-family: Menlo, Consolas, Monaco, Liberation Mono, Lucida Console, monospace;

  > div {
    padding-left: 6px;
    padding-right: 6px;
  }

  > div {
    padding-top: 2px;
    padding-bottom: 2px;
  }

  > div {
    transform-origin: center;
  }

  > div {
    border-radius: 4px;
  }

  > div {
    font-size: 12px;
    line-height: 16px;
  }

  > div {
    font-weight: 500;
  }

  > div {
    --tw-numeric-spacing: tabular-nums;
    font-variant-numeric: var(--tw-ordinal) var(--tw-slashed-zero) var(--tw-numeric-figure) var(--tw-numeric-spacing) var(--tw-numeric-fraction);
  }

  > div {
    transform-origin: center;
  }

  > div {
    transition-property: all;
    transition-timing-function: cubic-bezier(0.4, 0, 0.2, 1);
    transition-duration: 150ms;
  }

  > div {
    transition-delay: 150ms;
  }

  > div {
    transition-duration: 300ms;
  }

  > div {

    &[data-flash="true"] {
      background-color: rgb(168 85 247 / 0.1);
    }

    &[data-flash="true"] {
      --tw-text-opacity: 1;
      color: rgb(168 85 247 / var(--tw-text-opacity, 1));
    }
  }
}

.react-scan-slider {
  position: relative;
  min-height: 24px;

  > input {
    position: absolute;
  }

  > input {
    inset: 0px;
  }

  > input {
    opacity: 0;
  }

  &:before {
    --tw-content: '';
    content: var(--tw-content);
  }

  &:before {
    position: absolute;
  }

  &:before {
    left: 0px;
    right: 0px;
  }

  &:before {
    top: 50%;
  }

  &:before {
    --tw-translate-y: -50%;
    transform: translate(var(--tw-translate-x), var(--tw-translate-y)) rotate(var(--tw-rotate)) skewX(var(--tw-skew-x)) skewY(var(--tw-skew-y)) scaleX(var(--tw-scale-x)) scaleY(var(--tw-scale-y));
  }

  &:before {
    height: 6px;
  }

  &:before {
    background-color: rgb(142 97 227 / 0.4);
  }

  &:before {
    border-radius: 8px;
  }

  &:before {
    pointer-events: none;
  }

  &:after {
    --tw-content: '';
    content: var(--tw-content);
  }

  &:after {
    position: absolute;
  }

  &:after {
    left: 0px;
    right: 0px;
  }

  &:after {
    top: -8px;
    bottom: -8px;
  }

  &:after {
    z-index: -10;
  }

  span {
    position: absolute;
  }

  span {
    left: 0px;
  }

  span {
    top: 50%;
  }

  span {
    --tw-translate-y: -50%;
    transform: translate(var(--tw-translate-x), var(--tw-translate-y)) rotate(var(--tw-rotate)) skewX(var(--tw-skew-x)) skewY(var(--tw-skew-y)) scaleX(var(--tw-scale-x)) scaleY(var(--tw-scale-y));
  }

  span {
    height: 10px;
  }

  span {
    width: 10px;
  }

  span {
    border-radius: 8px;
  }

  span {
    --tw-bg-opacity: 1;
    background-color: rgb(142 97 227 / var(--tw-bg-opacity, 1));
  }

  span {
    pointer-events: none;
  }

  span {
    transition-property: transform;
    transition-timing-function: cubic-bezier(0.4, 0, 0.2, 1);
    transition-duration: 150ms;
  }

  span {
    transition-duration: 75ms;
  }
}

.resize-v-line {
  display: flex;
  align-items: center;
  justify-content: center;
  min-width: 4px;
  max-width: 4px;
  height: 100%;
  width: 100%;
  transition-property: color, background-color, border-color, text-decoration-color, fill, stroke;
  transition-timing-function: cubic-bezier(0.4, 0, 0.2, 1);
  transition-duration: 150ms;

  &:hover,
  &:active {
    > span {
      --tw-bg-opacity: 1;
      background-color: rgb(34 34 34 / var(--tw-bg-opacity, 1));
    }

    svg {
      opacity: 1;
    }
  }

  &::before {
    --tw-content: "";
    content: var(--tw-content);
  }

  &::before {
    position: absolute;
  }

  &::before {
    inset: 0px;
  }

  &::before {
    left: 50%;
  }

  &::before {
    --tw-translate-x: -50%;
    transform: translate(var(--tw-translate-x), var(--tw-translate-y)) rotate(var(--tw-rotate)) skewX(var(--tw-skew-x)) skewY(var(--tw-skew-y)) scaleX(var(--tw-scale-x)) scaleY(var(--tw-scale-y));
  }

  &::before {
    width: 1px;
  }

  &::before {
    --tw-bg-opacity: 1;
    background-color: rgb(34 34 34 / var(--tw-bg-opacity, 1));
  }

  &::before {
    transition-property: color, background-color, border-color, text-decoration-color, fill, stroke;
    transition-timing-function: cubic-bezier(0.4, 0, 0.2, 1);
    transition-duration: 150ms;
  }

  > span {
    position: absolute;
  }

  > span {
    left: 50%;
  }

  > span {
    top: 50%;
  }

  > span {
    --tw-translate-x: -50%;
    transform: translate(var(--tw-translate-x), var(--tw-translate-y)) rotate(var(--tw-rotate)) skewX(var(--tw-skew-x)) skewY(var(--tw-skew-y)) scaleX(var(--tw-scale-x)) scaleY(var(--tw-scale-y));
  }

  > span {
    --tw-translate-y: -50%;
    transform: translate(var(--tw-translate-x), var(--tw-translate-y)) rotate(var(--tw-rotate)) skewX(var(--tw-skew-x)) skewY(var(--tw-skew-y)) scaleX(var(--tw-scale-x)) scaleY(var(--tw-scale-y));
  }

  > span {
    height: 18px;
  }

  > span {
    width: 6px;
  }

  > span {
    border-radius: 4px;
  }

  > span {
    transition-property: color, background-color, border-color, text-decoration-color, fill, stroke;
    transition-timing-function: cubic-bezier(0.4, 0, 0.2, 1);
    transition-duration: 150ms;
  }

  svg {
    position: absolute;
  }

  svg {
    left: 50%;
  }

  svg {
    top: 50%;
  }

  svg {
    --tw-translate-x: -50%;
    transform: translate(var(--tw-translate-x), var(--tw-translate-y)) rotate(var(--tw-rotate)) skewX(var(--tw-skew-x)) skewY(var(--tw-skew-y)) scaleX(var(--tw-scale-x)) scaleY(var(--tw-scale-y));
  }

  svg {
    --tw-translate-y: -50%;
    transform: translate(var(--tw-translate-x), var(--tw-translate-y)) rotate(var(--tw-rotate)) skewX(var(--tw-skew-x)) skewY(var(--tw-skew-y)) scaleX(var(--tw-scale-x)) scaleY(var(--tw-scale-y));
  }

  svg {
    --tw-rotate: 90deg;
    transform: translate(var(--tw-translate-x), var(--tw-translate-y)) rotate(var(--tw-rotate)) skewX(var(--tw-skew-x)) skewY(var(--tw-skew-y)) scaleX(var(--tw-scale-x)) scaleY(var(--tw-scale-y));
  }

  svg {
    --tw-text-opacity: 1;
    color: rgb(163 163 163 / var(--tw-text-opacity, 1));
  }

  svg {
    opacity: 0;
  }

  svg {
    transition-property: opacity;
    transition-timing-function: cubic-bezier(0.4, 0, 0.2, 1);
    transition-duration: 150ms;
  }

  svg {
    z-index: 50;
  }
}


.tree-node-search-highlight {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;

  span {
    padding-top: 1px;
    padding-bottom: 1px;
  }

  span {
    border-radius: 2px;
  }

  span {
    --tw-bg-opacity: 1;
    background-color: rgb(253 224 71 / var(--tw-bg-opacity, 1));
  }

  span {
    font-weight: 500;
  }

  span {
    --tw-text-opacity: 1;
    color: rgb(0 0 0 / var(--tw-text-opacity, 1));
  }

  .single {
    margin-right: 1px;
  }

  .single {
    padding-left: 2px;
    padding-right: 2px;
  }

  .regex {
    padding-left: 2px;
    padding-right: 2px;
  }

  .start {
    margin-left: 1px;
  }

  .start {
    border-top-left-radius: 2px;
    border-bottom-left-radius: 2px;
  }

  .end {
    margin-right: 1px;
  }

  .end {
    border-top-right-radius: 2px;
    border-bottom-right-radius: 2px;
  }

  .middle {
    margin-left: 1px;
    margin-right: 1px;
  }

  .middle {
    border-radius: 2px;
  }
}

.react-scan-toolbar-notification {
  position: absolute;
  left: 0px;
  right: 0px;
  display: flex;
  align-items: center;
  -moz-column-gap: 8px;
       column-gap: 8px;
  padding: 4px;
  padding-left: 8px;
  font-size: 10px;
  --tw-text-opacity: 1;
  color: rgb(212 212 212 / var(--tw-text-opacity, 1));
  background-color: rgb(0 0 0 / 0.9);
  transition-property: transform;
  transition-timing-function: cubic-bezier(0.4, 0, 0.2, 1);
  transition-duration: 150ms;

  &:before {
    --tw-content: '';
    content: var(--tw-content);
  }

  &:before {
    position: absolute;
  }

  &:before {
    left: 0px;
    right: 0px;
  }

  &:before {
    --tw-bg-opacity: 1;
    background-color: rgb(0 0 0 / var(--tw-bg-opacity, 1));
  }

  &:before {
    height: 8px;
  }

  &.position-top {
    top: 100%;
  }

  &.position-top {
    --tw-translate-y: -100%;
    transform: translate(var(--tw-translate-x), var(--tw-translate-y)) rotate(var(--tw-rotate)) skewX(var(--tw-skew-x)) skewY(var(--tw-skew-y)) scaleX(var(--tw-scale-x)) scaleY(var(--tw-scale-y));
  }

  &.position-top {
    border-bottom-right-radius: 8px;
    border-bottom-left-radius: 8px;
  }

  &.position-top {

    &::before {
      top: 0px;
    }

    &::before {
      --tw-translate-y: -100%;
      transform: translate(var(--tw-translate-x), var(--tw-translate-y)) rotate(var(--tw-rotate)) skewX(var(--tw-skew-x)) skewY(var(--tw-skew-y)) scaleX(var(--tw-scale-x)) scaleY(var(--tw-scale-y));
    }
  }

  &.position-bottom {
    bottom: 100%;
  }

  &.position-bottom {
    --tw-translate-y: 100%;
    transform: translate(var(--tw-translate-x), var(--tw-translate-y)) rotate(var(--tw-rotate)) skewX(var(--tw-skew-x)) skewY(var(--tw-skew-y)) scaleX(var(--tw-scale-x)) scaleY(var(--tw-scale-y));
  }

  &.position-bottom {
    border-top-left-radius: 8px;
    border-top-right-radius: 8px;
  }

  &.position-bottom {

    &::before {
      bottom: 0px;
    }

    &::before {
      --tw-translate-y: 100%;
      transform: translate(var(--tw-translate-x), var(--tw-translate-y)) rotate(var(--tw-rotate)) skewX(var(--tw-skew-x)) skewY(var(--tw-skew-y)) scaleX(var(--tw-scale-x)) scaleY(var(--tw-scale-y));
    }

  }

  &.is-open {
    --tw-translate-y: 0px;
    transform: translate(var(--tw-translate-x), var(--tw-translate-y)) rotate(var(--tw-rotate)) skewX(var(--tw-skew-x)) skewY(var(--tw-skew-y)) scaleX(var(--tw-scale-x)) scaleY(var(--tw-scale-y));
  }
}


.react-scan-header-item {
  position: absolute;
  inset: 0px;
  --tw-translate-y: -200%;
  transform: translate(var(--tw-translate-x), var(--tw-translate-y)) rotate(var(--tw-rotate)) skewX(var(--tw-skew-x)) skewY(var(--tw-skew-y)) scaleX(var(--tw-scale-x)) scaleY(var(--tw-scale-y));
  transition-property: transform;
  transition-timing-function: cubic-bezier(0.4, 0, 0.2, 1);
  transition-duration: 300ms;

  &.is-visible {
    --tw-translate-y: 0px;
    transform: translate(var(--tw-translate-x), var(--tw-translate-y)) rotate(var(--tw-rotate)) skewX(var(--tw-skew-x)) skewY(var(--tw-skew-y)) scaleX(var(--tw-scale-x)) scaleY(var(--tw-scale-y));
  }
}

.react-scan-components-tree:has(.resize-v-line:hover, .resize-v-line:active) .tree {
  overflow: hidden;
}



.react-scan-expandable {
  display: grid;
  grid-template-rows: 0fr;
  overflow: hidden;
  transition-property: all;
  transition-timing-function: cubic-bezier(0.4, 0, 0.2, 1);
  transition-duration: 75ms;
  transition-timing-function: ease-out;

  > * {
    min-height: 0;
  }

  &.react-scan-expanded {
    grid-template-rows: 1fr;
    transition-duration: 100ms;
  }
}



.after\\:absolute::after {
  content: var(--tw-content);
  position: absolute;
}



.after\\:inset-0::after {
  content: var(--tw-content);
  inset: 0px;
}



.after\\:left-1\\/2::after {
  content: var(--tw-content);
  left: 50%;
}



.after\\:top-\\[100\\%\\]::after {
  content: var(--tw-content);
  top: 100%;
}



.after\\:h-\\[6px\\]::after {
  content: var(--tw-content);
  height: 6px;
}



.after\\:w-\\[10px\\]::after {
  content: var(--tw-content);
  width: 10px;
}



.after\\:-translate-x-1\\/2::after {
  content: var(--tw-content);
  --tw-translate-x: -50%;
  transform: translate(var(--tw-translate-x), var(--tw-translate-y)) rotate(var(--tw-rotate)) skewX(var(--tw-skew-x)) skewY(var(--tw-skew-y)) scaleX(var(--tw-scale-x)) scaleY(var(--tw-scale-y));
}



@keyframes fadeOut {

  0% {
    content: var(--tw-content);
    opacity: 1;
  }

  100% {
    content: var(--tw-content);
    opacity: 0;
  }
}



.after\\:animate-\\[fadeOut_1s_ease-out_forwards\\]::after {
  content: var(--tw-content);
  animation: fadeOut 1s ease-out forwards;
}



.after\\:border-l-\\[5px\\]::after {
  content: var(--tw-content);
  border-left-width: 5px;
}



.after\\:border-r-\\[5px\\]::after {
  content: var(--tw-content);
  border-right-width: 5px;
}



.after\\:border-t-\\[6px\\]::after {
  content: var(--tw-content);
  border-top-width: 6px;
}



.after\\:border-l-transparent::after {
  content: var(--tw-content);
  border-left-color: transparent;
}



.after\\:border-r-transparent::after {
  content: var(--tw-content);
  border-right-color: transparent;
}



.after\\:border-t-white::after {
  content: var(--tw-content);
  --tw-border-opacity: 1;
  border-top-color: rgb(255 255 255 / var(--tw-border-opacity, 1));
}



.after\\:bg-purple-500\\/30::after {
  content: var(--tw-content);
  background-color: rgb(168 85 247 / 0.3);
}



.after\\:content-\\[\\"\\"\\]::after {
  --tw-content: "";
  content: var(--tw-content);
}



.focus-within\\:border-\\[\\#454545\\]:focus-within {
  --tw-border-opacity: 1;
  border-color: rgb(69 69 69 / var(--tw-border-opacity, 1));
}



.hover\\:bg-\\[\\#0f0f0f\\]:hover {
  --tw-bg-opacity: 1;
  background-color: rgb(15 15 15 / var(--tw-bg-opacity, 1));
}



.hover\\:bg-\\[\\#18181B\\]:hover {
  --tw-bg-opacity: 1;
  background-color: rgb(24 24 27 / var(--tw-bg-opacity, 1));
}



.hover\\:bg-\\[\\#34343b\\]:hover {
  --tw-bg-opacity: 1;
  background-color: rgb(52 52 59 / var(--tw-bg-opacity, 1));
}



.hover\\:bg-\\[\\#5f3f9a\\]\\/20:hover {
  background-color: rgb(95 63 154 / 0.2);
}



.hover\\:bg-\\[\\#5f3f9a\\]\\/40:hover {
  background-color: rgb(95 63 154 / 0.4);
}



.hover\\:bg-red-600:hover {
  --tw-bg-opacity: 1;
  background-color: rgb(220 38 38 / var(--tw-bg-opacity, 1));
}



.hover\\:bg-zinc-700:hover {
  --tw-bg-opacity: 1;
  background-color: rgb(63 63 70 / var(--tw-bg-opacity, 1));
}



.hover\\:bg-zinc-800\\/50:hover {
  background-color: rgb(39 39 42 / 0.5);
}



.hover\\:text-neutral-300:hover {
  --tw-text-opacity: 1;
  color: rgb(212 212 212 / var(--tw-text-opacity, 1));
}



.hover\\:text-white:hover {
  --tw-text-opacity: 1;
  color: rgb(255 255 255 / var(--tw-text-opacity, 1));
}



.group:hover .group-hover\\:bg-\\[\\#21437982\\] {
  background-color: #21437982;
}



.group:hover .group-hover\\:bg-\\[\\#5b2d89\\] {
  --tw-bg-opacity: 1;
  background-color: rgb(91 45 137 / var(--tw-bg-opacity, 1));
}



.group:hover .group-hover\\:bg-\\[\\#6a6a6a\\] {
  --tw-bg-opacity: 1;
  background-color: rgb(106 106 106 / var(--tw-bg-opacity, 1));
}



.group:hover .group-hover\\:bg-\\[\\#efda1a2f\\] {
  background-color: #efda1a2f;
}



.group:hover .group-hover\\:opacity-100 {
  opacity: 1;
}



.peer\\/bottom:hover ~ .peer-hover\\/bottom\\:rounded-b-none {
  border-bottom-right-radius: 0px;
  border-bottom-left-radius: 0px;
}



.peer\\/left:hover ~ .peer-hover\\/left\\:rounded-l-none {
  border-top-left-radius: 0px;
  border-bottom-left-radius: 0px;
}



.peer\\/right:hover ~ .peer-hover\\/right\\:rounded-r-none {
  border-top-right-radius: 0px;
  border-bottom-right-radius: 0px;
}



.peer\\/top:hover ~ .peer-hover\\/top\\:rounded-t-none {
  border-top-left-radius: 0px;
  border-top-right-radius: 0px;
}`,rK=r(27791),rZ=r(27791),rQ=r(45994),r0=r(61704);r(45994);var r1=r(45994),r2=r(61704),r4=r(45994),r5=r(10201),r3=(0,r2.computed)(()=>ez("absolute inset-0 flex items-center gap-x-2","translate-y-0","transition-transform duration-300",eO.value&&"-translate-y-[200%]")),r6=()=>{let e=(0,r4.useRef)(null),t=(0,r4.useRef)(null),[r,n]=(0,r4.useState)(null);(0,r2.useSignalEffect)(()=>{let e=ij.inspectState.value;"focused"===e.kind&&n(e.fiber)}),(0,r2.useSignalEffect)(()=>{let r=eJ.value;(0,r2.untracked)(()=>{let n;if("focused"!==ij.inspectState.value.kind||!e.current||!t.current)return;let{totalUpdates:o,currentIndex:i,updates:a,isVisible:s,windowOffset:l}=r,c=Math.max(0,o-1),d=s?`#${l+i} Re-render`:c>0?`\xd7${c}`:"";if(c>0&&i>=0&&i<a.length){let e=a[i]?.fiberInfo?.selfTime;n=e>0?e<.1-Number.EPSILON?"< 0.1ms":`${Number(e.toFixed(1))}ms`:void 0}e.current.dataset.text=d?` \u2022 ${d}`:"",t.current.dataset.text=n?` \u2022 ${n}`:""})});let o=(0,r4.useMemo)(()=>{if(!r)return null;let{name:e,wrappers:t,wrapperTypes:n}=eA(r),o=t.length?`${t.join("(")}(${e})${")".repeat(t.length)}`:e??"",i=n[0];return(0,r5.jsxs)("span",{title:o,className:"flex items-center gap-x-1",children:[e??"Unknown",(0,r5.jsx)("span",{title:i?.title,className:"flex items-center gap-x-1 text-[10px] text-purple-400",children:!!i&&(0,r5.jsxs)(r5.Fragment,{children:[(0,r5.jsx)("span",{className:ez("rounded py-[1px] px-1","truncate",i.compiler&&"bg-purple-800 text-neutral-400",!i.compiler&&"bg-neutral-700 text-neutral-300","memo"===i.type&&"bg-[#5f3f9a] text-white"),children:i.type},i.type),i.compiler&&(0,r5.jsx)("span",{className:"text-yellow-300",children:"\u2728"})]})}),n.length>1&&(0,r5.jsxs)("span",{className:"text-[10px] text-neutral-400",children:["\xd7",n.length-1]})]})},[r]);return(0,r5.jsxs)("div",{className:r3,children:[o,(0,r5.jsxs)("div",{className:"flex items-center gap-x-2 mr-auto text-xs text-[#888]",children:[(0,r5.jsx)("span",{ref:e,className:"with-data-text cursor-pointer !overflow-visible",title:"Click to toggle between rerenders and total renders"}),(0,r5.jsx)("span",{ref:t,className:"with-data-text !overflow-visible"})]})]})},r8=r(10201),r7=()=>{let e=((e,t,r=t)=>{let[n,o]=(0,r1.useState)(e);return(0,r1.useEffect)(()=>{if(e===n)return;let i=setTimeout(()=>o(e),e?t:r);return()=>clearTimeout(i)},[e,t,r]),n})("focused"===ij.inspectState.value.kind,150,0);if("notifications"!==eL.value.view)return(0,r8.jsxs)("div",{className:"react-scan-header",children:[(0,r8.jsx)("div",{className:"relative flex-1 h-full",children:(0,r8.jsx)("div",{className:ez("react-scan-header-item is-visible",!e&&"!duration-0"),children:(0,r8.jsx)(r6,{})})}),(0,r8.jsx)("button",{type:"button",title:"Close",className:"react-scan-close-button",onClick:()=>{eL.value={view:"none"},ij.inspectState.value={kind:"inspect-off"}},children:(0,r8.jsx)($,{name:"icon-close"})})]})},r9=r(61704),ne=r(45994),nt=r(10201),nr=({className:e,...t})=>(0,nt.jsxs)("div",{className:ez("react-scan-toggle",e),children:[(0,nt.jsx)("input",{type:"checkbox",...t}),(0,nt.jsx)("div",{})]}),nn=r(45994),no=r(10201),ni=({fps:e})=>(0,no.jsxs)("div",{className:ez("flex items-center gap-x-1 px-2 w-full","h-6","rounded-md","font-mono leading-none","bg-[#141414]","ring-1 ring-white/[0.08]"),children:[(0,no.jsx)("div",{style:{color:e<30?"#EF4444":e<50?"#F59E0B":"rgb(214,132,245)"},className:"text-sm font-semibold tracking-wide transition-colors ease-in-out w-full flex justify-center items-center",children:e}),(0,no.jsx)("span",{className:"text-white/30 text-[11px] font-medium tracking-wide ml-auto min-w-fit",children:"FPS"})]}),na=()=>{let[e,t]=(0,nn.useState)(null);return(0,nn.useEffect)(()=>{let e=setInterval(()=>{t(rh())},200);return()=>clearInterval(e)},[]),(0,no.jsx)("div",{className:ez("flex items-center justify-end gap-x-2 px-1 ml-1 w-[72px]","whitespace-nowrap text-sm text-white"),children:null===e?(0,no.jsx)(no.Fragment,{children:"\uFE0F"}):(0,no.jsx)(ni,{fps:e})})},ns=r(27791),nl=r(45994),nc=r(17402);a=null!=(o=r(96540))?p(g(o)):{},b(!i&&o&&o.__esModule?a:h(a,"default",{value:o,enumerable:!0}),o),U&&(window.Cypress||navigator.webdriver);var nd=()=>U?(void 0===window.reactScanIdCounter&&(window.reactScanIdCounter=0),`${++window.reactScanIdCounter}`):"0",nu=e=>{},np=class _BoundedArray extends Array{constructor(e=25){super(),this.capacity=e}push(...e){let t=super.push(...e);for(;this.length>this.capacity;)this.shift();return t}static fromArray(e,t){let r=new _BoundedArray(t);return r.push(...e),r}},nh=new class{constructor(e){this.subscribers=new Set,this.currentValue=e}subscribe(e){return this.subscribers.add(e),e(this.currentValue),()=>{this.subscribers.delete(e)}}setState(e){this.currentValue=e,this.subscribers.forEach(t=>t(e))}getCurrentState(){return this.currentValue}}(new np(150)),nm=r(62224),nf=new class{constructor(){this.channels={}}publish(e,t,r=!0){let n=this.channels[t];if(!n){if(!r)return;this.channels[t]={callbacks:new np(50),state:new np(50)},this.channels[t].state.push(e);return}n.state.push(e),n.callbacks.forEach(t=>t(e))}getAvailableChannels(){return np.fromArray(Object.keys(this.channels),50)}subscribe(e,t,r=!1){let n=()=>(r||this.channels[e].state.forEach(e=>{t(e)}),()=>{let r=this.channels[e].callbacks.filter(e=>e!==t);this.channels[e].callbacks=np.fromArray(r,50)}),o=this.channels[e];return o?o.callbacks.push(t):(this.channels[e]={callbacks:new np(50),state:new np(50)},this.channels[e].callbacks.push(t)),n()}updateChannelState(e,t,r=!0){let n=this.channels[e];if(!n){if(!r)return;let n=new np(50),o={callbacks:new np(50),state:n};this.channels[e]=o,o.state=t(n);return}n.state=t(n.state)}getChannelState(e){return this.channels[e].state??new np(50)}},ng=r(62224),nx={skipProviders:!0,skipHocs:!0,skipContainers:!0,skipMinified:!0,skipUtilities:!0,skipBoundaries:!0},nb=[/Provider$/,/^Provider$/,/^Context$/],nw=[/^with[A-Z]/,/^forward(?:Ref)?$/i,/^Forward(?:Ref)?\(/],nv=[/^(?:App)?Container$/,/^Root$/,/^ReactDev/],ny=[/^Fragment$/,/^Suspense$/,/^ErrorBoundary$/,/^Portal$/,/^Consumer$/,/^Layout$/,/^Router/,/^Hydration/],n_=[/^Boundary$/,/Boundary$/,/^Provider$/,/Provider$/],nk=(e,t=nx)=>{let r=[];return t.skipProviders&&r.push(...nb),t.skipHocs&&r.push(...nw),t.skipContainers&&r.push(...nv),t.skipUtilities&&r.push(...ny),t.skipBoundaries&&r.push(...n_),!r.some(t=>t.test(e))},nj=[/^[a-z]$/,/^[a-z][0-9]$/,/^_+$/,/^[A-Za-z][_$]$/,/^[a-z]{1,2}$/],nC=e=>{for(let t=0;t<nj.length;t++)if(nj[t].test(e))return!0;let t=!/[aeiou]/i.test(e),r=(e.match(/\d/g)?.length??0)>e.length/2,n=/^[a-z]+$/.test(e),o=/[$_]{2,}/.test(e);return Number(t)+Number(r)+Number(n)+Number(o)>=2},nS=e=>{let t=(0,ng.getDisplayName)(e);return t?t.replace(/^(?:Memo|Forward(?:Ref)?|With.*?)\((?<inner>.*?)\)$/,"$<inner>"):""},nN="never-hidden",nT=null,nE=new np(25),nz=(e,t)=>{let r=null,n=t=>{switch(e){case"pointer":if("start"===t.phase)return"pointerup";if(t.target instanceof HTMLInputElement||t.target instanceof HTMLSelectElement)return"change";return"click";case"keyboard":if("start"===t.phase)return"keydown";return"change"}},o={current:{kind:"uninitialized-stage",interactionUUID:nd(),stageStart:Date.now(),interactionType:e}},i=r=>{if(r.composedPath().some(e=>e instanceof Element&&"react-scan-toolbar-root"===e.id)||(Date.now()-o.current.stageStart>2e3&&(o.current={kind:"uninitialized-stage",interactionUUID:nd(),stageStart:Date.now(),interactionType:e}),"uninitialized-stage"!==o.current.kind))return;let i=performance.now();t?.onStart?.(o.current.interactionUUID);let s=(e=>{let t=tP(e);if(!t)return;let r=t?(0,nm.getDisplayName)(t?.type):"N/A";if(r||(r=((e,t=()=>!0)=>{let r=e;for(;r;){let e=(0,nm.getDisplayName)(r.type);if(e&&t(e))return e;r=r.return}return null})(t,e=>e.length>2)??"N/A"),r)return{componentPath:((e,t=nx)=>{if(!e||!(0,ng.getDisplayName)(e.type))return[];let r=[],n=e;for(;n.return;){let e=nS(n.type);e&&!nC(e)&&nk(e,t)&&e.toLowerCase()!==e&&r.push(e),n=n.return}let o=Array(r.length);for(let e=0;e<r.length;e++)o[e]=r[r.length-e-1];return o})(t),childrenTree:{},componentName:r,elementFiber:t}})(r.target);if(!s)return void t?.onError?.(o.current.interactionUUID);let l={},c=nM(l);o.current={...o.current,interactionType:e,blockingTimeStart:Date.now(),childrenTree:s.childrenTree,componentName:s.componentName,componentPath:s.componentPath,fiberRenders:l,kind:"interaction-start",interactionStartDetail:i,stopListeningForRenders:c};let d=n({phase:"end",target:r.target});document.addEventListener(d,a,{once:!0}),requestAnimationFrame(()=>{document.removeEventListener(d,a)})};document.addEventListener(n({phase:"start"}),i,{capture:!0});let a=(n,i,a)=>{if("interaction-start"!==o.current.kind&&i===r){if("pointer"===e&&n.target instanceof HTMLSelectElement){o.current={kind:"uninitialized-stage",interactionUUID:nd(),stageStart:Date.now(),interactionType:e};return}t?.onError?.(o.current.interactionUUID),o.current={kind:"uninitialized-stage",interactionUUID:nd(),stageStart:Date.now(),interactionType:e},nu("pointer -> click");return}r=i,(({onMicroTask:e,onRAF:t,onTimeout:r,abort:n})=>{queueMicrotask(()=>{n?.()===!0||e()&&requestAnimationFrame(()=>{n?.()===!0||t()&&setTimeout(()=>{n?.()!==!0&&r()},0)})})})({abort:a,onMicroTask:()=>"uninitialized-stage"!==o.current.kind&&(o.current={...o.current,kind:"js-end-stage",jsEndDetail:performance.now()},!0),onRAF:()=>"js-end-stage"!==o.current.kind&&"raf-stage"!==o.current.kind?(t?.onError?.(o.current.interactionUUID),nu("bad transition to raf"),o.current={kind:"uninitialized-stage",interactionUUID:nd(),stageStart:Date.now(),interactionType:e},!1):(o.current={...o.current,kind:"raf-stage",rafStart:performance.now()},!0),onTimeout:()=>{if("raf-stage"!==o.current.kind){t?.onError?.(o.current.interactionUUID),o.current={kind:"uninitialized-stage",interactionUUID:nd(),stageStart:Date.now(),interactionType:e},nu("raf->timeout");return}let r=Date.now(),n=Object.freeze({...o.current,kind:"timeout-stage",blockingTimeEnd:r,commitEnd:performance.now()});o.current={kind:"uninitialized-stage",interactionUUID:nd(),stageStart:r,interactionType:e};let i=!1,a=e=>{i=!0;let r={detailedTiming:n,latency:"auto-complete-race"===e.kind?e.detailedTiming.commitEnd-e.detailedTiming.interactionStartDetail:e.entry.latency,completedAt:Date.now(),flushNeeded:!0};t?.onComplete?.(n.interactionUUID,r,e);let o=nE.filter(e=>e.interactionUUID!==n.interactionUUID);return nE=np.fromArray(o,25),r},s={completeInteraction:a,endDateTime:Date.now(),startDateTime:n.blockingTimeStart,type:e,interactionUUID:n.interactionUUID};if(nE.push(s),nF())setTimeout(()=>{if(i)return;a({kind:"auto-complete-race",detailedTiming:n,interactionUUID:n.interactionUUID});let e=nE.filter(e=>e.interactionUUID!==n.interactionUUID);nE=np.fromArray(e,25)},1e3);else{let e=nE.filter(e=>e.interactionUUID!==n.interactionUUID);nE=np.fromArray(e,25),a({kind:"auto-complete-race",detailedTiming:n,interactionUUID:n.interactionUUID})}}})},s=e=>{let t=nd();a(e,t,()=>t!==r)};return"keyboard"===e&&document.addEventListener("keypress",s),()=>{document.removeEventListener(n({phase:"start"}),i,{capture:!0}),document.removeEventListener("keypress",s)}},nR=e=>(0,nm.traverseFiber)(e,e=>{if((0,nm.isHostFiber)(e))return!0})?.stateNode,nF=()=>"PerformanceEventTiming"in globalThis,nM=e=>{let t=t=>{let r=(0,nm.getDisplayName)(t.type);if(!r)return;let n=e[r];if(!n){let n=new Set,o=t.return&&t$(t.return),i=o&&(0,nm.getDisplayName)(o[0]);i&&n.add(i);let{selfTime:a,totalTime:s}=(0,nm.getTimings)(t),l=rs(t),c={current:[],changes:new Set,changesCounts:new Map},d={fiberProps:l.fiberProps||c,fiberState:l.fiberState||c,fiberContext:l.fiberContext||c};e[r]={renderCount:1,hasMemoCache:(0,nm.hasMemoCache)(t),wasFiberRenderMount:nO(t),parents:n,selfTime:a,totalTime:s,nodeInfo:[{element:nR(t),name:(0,nm.getDisplayName)(t.type)??"Unknown",selfTime:(0,nm.getTimings)(t).selfTime}],changes:d};return}if(t$(t)?.[0]?.type){let e=t.return&&t$(t.return),r=e&&(0,nm.getDisplayName)(e[0]);r&&n.parents.add(r)}let{selfTime:o,totalTime:i}=(0,nm.getTimings)(t),a=rs(t);if(!a)return;let s={current:[],changes:new Set,changesCounts:new Map};n.wasFiberRenderMount=n.wasFiberRenderMount||nO(t),n.hasMemoCache=n.hasMemoCache||(0,nm.hasMemoCache)(t),n.changes={fiberProps:nA(n.changes?.fiberProps||s,a.fiberProps||s),fiberState:nA(n.changes?.fiberState||s,a.fiberState||s),fiberContext:nA(n.changes?.fiberContext||s,a.fiberContext||s)},n.renderCount+=1,n.selfTime+=o,n.totalTime+=i,n.nodeInfo.push({element:nR(t),name:(0,nm.getDisplayName)(t.type)??"Unknown",selfTime:(0,nm.getTimings)(t).selfTime})};return ij.interactionListeningForRenders=t,()=>{ij.interactionListeningForRenders===t&&(ij.interactionListeningForRenders=null)}},nA=(e,t)=>{let r={current:[...e.current],changes:new Set,changesCounts:new Map};for(let e of t.current)r.current.some(t=>t.name===e.name)||r.current.push(e);for(let n of t.changes)if("string"==typeof n||"number"==typeof n){r.changes.add(n);let o=e.changesCounts.get(n)||0,i=t.changesCounts.get(n)||0;r.changesCounts.set(n,o+i)}return r},nO=e=>{if(!e.alternate)return!0;let t=e.alternate,r=t&&null!=t.memoizedState&&null!=t.memoizedState.element&&!0!==t.memoizedState.isDehydrated,n=null!=e.memoizedState&&null!=e.memoizedState.element&&!0!==e.memoizedState.isDehydrated;return!r&&n},nP=e=>{let t,r=new Set,n=(e,n)=>{let o="function"==typeof e?e(t):e;if(!Object.is(o,t)){let e=t;t=n??("object"!=typeof o||null===o)?o:Object.assign({},t,o),r.forEach(r=>r(t,e))}},o=()=>t,i={setState:n,getState:o,getInitialState:()=>a,subscribe:(e,n)=>{let o,i;n?(o=e,i=n):i=e;let a=o?o(t):void 0,s=(e,t)=>{if(o){let r=o(e),n=o(t);Object.is(a,r)||(a=r,i(r,n))}else i(e,t)};return r.add(s),()=>r.delete(s)}},a=t=e(n,o,i);return i},nD=e=>e?nP(e):nP,nI=null;nD()(e=>({state:{events:[]},actions:{addEvent:t=>{e(e=>({state:{events:[...e.state.events,t]}}))},clear:()=>{e({state:{events:[]}})}}}));var n$=nD()((e,t)=>{let r=new Set;return{state:{events:[]},actions:{addEvent:n=>{r.forEach(e=>e(n));let o=[...t().state.events,n],i=new Set;o.forEach(e=>{if("interaction"!==e.kind){let t;(t=o.find(t=>{if("long-render"!==t.kind&&t.id!==e.id&&(e.data.startAt<=t.data.startAt&&e.data.endAt<=t.data.endAt&&e.data.endAt>=t.data.startAt||t.data.startAt<=e.data.startAt&&t.data.endAt>=e.data.startAt||e.data.startAt<=t.data.startAt&&e.data.endAt>=t.data.endAt))return!0}))&&(()=>{i.add(e.id)})(t)}});let a=o.filter(e=>!i.has(e.id));e(()=>({state:{events:a}}))},addListener:e=>(r.add(e),()=>{r.delete(e)}),clear:()=>{e({state:{events:[]}})}}}}),nL=null,nH=null,nU=null,nY=[],nB=e=>{let t=e.filter(e=>e.length>2);return 0===t.length?e.at(-1)??"Unknown":t.at(-1)},nW=e=>{switch(e.kind){case"interaction":{let{renderTime:t,otherJSTime:r,framePreparation:n,frameConstruction:o,frameDraw:i}=e;return t+r+n+o+(i??0)}case"dropped-frames":return e.otherTime+e.renderTime}},nV=e=>{let t=nW(e.timing);switch(e.kind){case"interaction":if(t<200)return"low";if(t<500)return"needs-improvement";return"high";case"dropped-frames":if(t<50)return"low";if(t<150)return"needs-improvement";return"high"}},nX=()=>(0,nl.useContext)(nq),nq=(0,ns.createContext)(null),nG=r(10201),nJ=({size:e=24,className:t})=>(0,nG.jsx)("svg",{xmlns:"http://www.w3.org/2000/svg",width:e,height:e,viewBox:"0 0 24 24",fill:"none",stroke:"currentColor","stroke-width":"2","stroke-linecap":"round","stroke-linejoin":"round",className:ez(["lucide lucide-chevron-right",t]),children:(0,nG.jsx)("path",{d:"m9 18 6-6-6-6"})}),nK=({className:e="",size:t=24,events:r=[]})=>{let n=r.includes(!0),o=r.filter(e=>e).length,i=n?Math.max(.6*t,14):Math.max(.4*t,6);return(0,nG.jsxs)("div",{className:"relative",children:[(0,nG.jsxs)("svg",{xmlns:"http://www.w3.org/2000/svg",width:t,height:t,viewBox:"0 0 24 24",fill:"none",stroke:"currentColor","stroke-width":"2","stroke-linecap":"round","stroke-linejoin":"round",className:`lucide lucide-bell ${e}`,children:[(0,nG.jsx)("path",{d:"M10.268 21a2 2 0 0 0 3.464 0"}),(0,nG.jsx)("path",{d:"M3.262 15.326A1 1 0 0 0 4 17h16a1 1 0 0 0 .74-1.673C19.41 13.956 18 12.499 18 8A6 6 0 0 0 6 8c0 4.499-1.411 5.956-2.738 7.326"})]}),r.length>0&&o>0&&iC.options.value.showNotificationCount&&(0,nG.jsx)("div",{className:ez(["absolute",n?"-top-2.5 -right-2.5":"-top-1 -right-1","rounded-full","flex items-center justify-center","text-[8px] font-medium text-white","aspect-square",n?"bg-red-500/90":"bg-purple-500/90"]),style:{width:`${i}px`,height:`${i}px`,padding:n?"0.5px":"0"},children:n&&(o>99?">99":o)})]})},nZ=({className:e="",size:t=24})=>(0,nG.jsxs)("svg",{xmlns:"http://www.w3.org/2000/svg",width:t,height:t,viewBox:"0 0 24 24",fill:"none",stroke:"currentColor","stroke-width":"2","stroke-linecap":"round","stroke-linejoin":"round",className:e,children:[(0,nG.jsx)("path",{d:"M18 6 6 18"}),(0,nG.jsx)("path",{d:"m6 6 12 12"})]}),nQ=({className:e="",size:t=24})=>(0,nG.jsxs)("svg",{xmlns:"http://www.w3.org/2000/svg",width:t,height:t,viewBox:"0 0 24 24",fill:"none",stroke:"currentColor","stroke-width":"2","stroke-linecap":"round","stroke-linejoin":"round",className:e,children:[(0,nG.jsx)("path",{d:"M11 4.702a.705.705 0 0 0-1.203-.498L6.413 7.587A1.4 1.4 0 0 1 5.416 8H3a1 1 0 0 0-1 1v6a1 1 0 0 0 1 1h2.416a1.4 1.4 0 0 1 .997.413l3.383 3.384A.705.705 0 0 0 11 19.298z"}),(0,nG.jsx)("path",{d:"M16 9a5 5 0 0 1 0 6"}),(0,nG.jsx)("path",{d:"M19.364 18.364a9 9 0 0 0 0-12.728"})]}),n0=({className:e="",size:t=24})=>(0,nG.jsxs)("svg",{xmlns:"http://www.w3.org/2000/svg",width:t,height:t,viewBox:"0 0 24 24",fill:"none",stroke:"currentColor","stroke-width":"2","stroke-linecap":"round","stroke-linejoin":"round",className:e,children:[(0,nG.jsx)("path",{d:"M16 9a5 5 0 0 1 .95 2.293"}),(0,nG.jsx)("path",{d:"M19.364 5.636a9 9 0 0 1 1.889 9.96"}),(0,nG.jsx)("path",{d:"m2 2 20 20"}),(0,nG.jsx)("path",{d:"m7 7-.587.587A1.4 1.4 0 0 1 5.416 8H3a1 1 0 0 0-1 1v6a1 1 0 0 0 1 1h2.416a1.4 1.4 0 0 1 .997.413l3.383 3.384A.705.705 0 0 0 11 19.298V11"}),(0,nG.jsx)("path",{d:"M9.828 4.172A.686.686 0 0 1 11 4.657v.686"})]}),n1=({size:e=24,className:t})=>(0,nG.jsxs)("svg",{xmlns:"http://www.w3.org/2000/svg",width:e,height:e,viewBox:"0 0 24 24",fill:"none",stroke:"currentColor","stroke-width":"2","stroke-linecap":"round","stroke-linejoin":"round",className:ez(["lucide lucide-arrow-left",t]),children:[(0,nG.jsx)("path",{d:"m12 19-7-7 7-7"}),(0,nG.jsx)("path",{d:"M19 12H5"})]}),n2=({className:e="",size:t=24})=>(0,nG.jsxs)("svg",{xmlns:"http://www.w3.org/2000/svg",width:t,height:t,viewBox:"0 0 24 24",fill:"none",stroke:"currentColor","stroke-width":"2","stroke-linecap":"round","stroke-linejoin":"round",className:e,children:[(0,nG.jsx)("path",{d:"M14 4.1 12 6"}),(0,nG.jsx)("path",{d:"m5.1 8-2.9-.8"}),(0,nG.jsx)("path",{d:"m6 12-1.9 2"}),(0,nG.jsx)("path",{d:"M7.2 2.2 8 5.1"}),(0,nG.jsx)("path",{d:"M9.037 9.69a.498.498 0 0 1 .653-.653l11 4.5a.5.5 0 0 1-.074.949l-4.349 1.041a1 1 0 0 0-.74.739l-1.04 4.35a.5.5 0 0 1-.95.074z"})]}),n4=({className:e="",size:t=24})=>(0,nG.jsxs)("svg",{xmlns:"http://www.w3.org/2000/svg",width:t,height:t,viewBox:"0 0 24 24",fill:"none",stroke:"currentColor","stroke-width":"2","stroke-linecap":"round","stroke-linejoin":"round",className:e,children:[(0,nG.jsx)("path",{d:"M10 8h.01"}),(0,nG.jsx)("path",{d:"M12 12h.01"}),(0,nG.jsx)("path",{d:"M14 8h.01"}),(0,nG.jsx)("path",{d:"M16 12h.01"}),(0,nG.jsx)("path",{d:"M18 8h.01"}),(0,nG.jsx)("path",{d:"M6 8h.01"}),(0,nG.jsx)("path",{d:"M7 16h10"}),(0,nG.jsx)("path",{d:"M8 12h.01"}),(0,nG.jsx)("rect",{width:"20",height:"16",x:"2",y:"4",rx:"2"})]}),n5=({className:e="",size:t=24})=>(0,nG.jsxs)("svg",{xmlns:"http://www.w3.org/2000/svg",width:t,height:t,viewBox:"0 0 24 24",fill:"none",stroke:"currentColor","stroke-width":"2","stroke-linecap":"round","stroke-linejoin":"round",className:e,style:{transform:"rotate(180deg)"},children:[(0,nG.jsx)("circle",{cx:"12",cy:"12",r:"10"}),(0,nG.jsx)("path",{d:"m4.9 4.9 14.2 14.2"})]}),n3=({className:e="",size:t=24})=>(0,nG.jsxs)("svg",{xmlns:"http://www.w3.org/2000/svg",width:t,height:t,viewBox:"0 0 24 24",fill:"none",stroke:"currentColor",strokeWidth:"2",strokeLinecap:"round",strokeLinejoin:"round",className:e,children:[(0,nG.jsx)("polyline",{points:"22 17 13.5 8.5 8.5 13.5 2 7"}),(0,nG.jsx)("polyline",{points:"16 17 22 17 22 11"})]}),n6=r(17402),n8=r(45994),n7=r(17402),n9=r(17402),oe=r(10201),ot=({children:e,triggerContent:t,wrapperProps:r})=>{let[n,o]=(0,n9.useState)("closed"),[i,a]=(0,n9.useState)(null),[s,l]=(0,n9.useState)({width:window.innerWidth,height:window.innerHeight}),c=(0,n9.useRef)(null),d=(0,n9.useRef)(null),u=(0,n9.useContext)(ix),p=(0,n9.useRef)(!1);(0,n9.useEffect)(()=>{let e=()=>{l({width:window.innerWidth,height:window.innerHeight}),h()};return window.addEventListener("resize",e),()=>window.removeEventListener("resize",e)},[]);let h=()=>{if(c.current&&u){let e=c.current.getBoundingClientRect(),t=u.getBoundingClientRect(),r=e.left+e.width/2,n=e.top;a(new DOMRect(r-t.left,n-t.top,e.width,e.height))}};(0,n9.useEffect)(()=>{h()},[c.current]),(0,n9.useEffect)(()=>{if("opening"===n){let e=setTimeout(()=>o("open"),120);return()=>clearTimeout(e)}if("closing"===n){let e=setTimeout(()=>o("closed"),120);return()=>clearTimeout(e)}},[n]),(0,n9.useEffect)(()=>{let e=setInterval(()=>{p.current||"closed"===n||o("closing")},1e3);return()=>clearInterval(e)},[n]);let m=()=>{if(!i||!u)return{top:0,left:0};let e=u.getBoundingClientRect(),t=d.current?.offsetHeight||40,r=i.x+e.left,n=i.y+e.top,o=r,a=n-4;return o-87.5<5?o=92.5:o+87.5>s.width-5&&(o=s.width-5-87.5),a-t<5&&(a=n+i.height+4),{top:a-e.top,left:o-e.left}};return(0,oe.jsxs)(oe.Fragment,{children:[u&&i&&"closed"!==n&&(0,n9.createPortal)((0,oe.jsx)("div",{ref:d,className:ez(["absolute z-100 bg-white text-black rounded-lg px-3 py-2 shadow-lg","transform transition-all duration-120 ease-[cubic-bezier(0.23,1,0.32,1)]",'after:content-[""] after:absolute after:top-[100%]',"after:left-1/2 after:-translate-x-1/2","after:w-[10px] after:h-[6px]","after:border-l-[5px] after:border-l-transparent","after:border-r-[5px] after:border-r-transparent","after:border-t-[6px] after:border-t-white","pointer-events-none","opening"===n||"closing"===n?"opacity-0 translate-y-1":"opacity-100 translate-y-0"]),style:{top:m().top+"px",left:m().left+"px",transform:"translate(-50%, -100%)",minWidth:"175px"},children:e}),u),(0,oe.jsx)("div",{ref:c,onMouseEnter:()=>{p.current=!0,h(),o("opening")},onMouseLeave:()=>{p.current=!1,h(),o("closing")},...r,children:t})]})},or=r(10201),on=({selectedEvent:e})=>{let{notificationState:t,setNotificationState:r,setRoute:n}=nX();return(0,or.jsxs)("div",{className:ez(["flex w-full justify-between items-center px-3 py-2 text-xs"]),children:[(0,or.jsxs)("div",{className:ez(["bg-[#18181B] flex items-center gap-x-1 p-1 rounded-sm"]),children:[(0,or.jsx)("button",{onClick:()=>{n({route:"render-visualization",routeMessage:null})},className:ez(["w-1/2 flex items-center justify-center whitespace-nowrap py-[5px] px-1 gap-x-1","render-visualization"===t.route||"render-explanation"===t.route?"text-white bg-[#7521c8] rounded-sm":"text-[#6E6E77] bg-[#18181B] rounded-sm"]),children:"Ranked"}),(0,or.jsx)("button",{onClick:()=>{n({route:"other-visualization",routeMessage:null})},className:ez(["w-1/2 flex items-center justify-center whitespace-nowrap py-[5px] px-1 gap-x-1","other-visualization"===t.route?"text-white bg-[#7521c8] rounded-sm":"text-[#6E6E77] bg-[#18181B] rounded-sm"]),children:"Overview"}),(0,or.jsx)("button",{onClick:()=>{n({route:"optimize",routeMessage:null})},className:ez(["w-1/2 flex items-center justify-center whitespace-nowrap py-[5px] px-1 gap-x-1","optimize"===t.route?"text-white bg-[#7521c8] rounded-sm":"text-[#6E6E77] bg-[#18181B] rounded-sm"]),children:(0,or.jsx)("span",{children:"Prompts"})})]}),(0,or.jsx)(ot,{triggerContent:(0,or.jsx)("button",{onClick:()=>{r(e=>{e.audioNotificationsOptions.enabled&&"closed"!==e.audioNotificationsOptions.audioContext.state&&e.audioNotificationsOptions.audioContext.close();let t=e.audioNotificationsOptions.enabled;localStorage.setItem("react-scan-notifications-audio",String(!t));let r=new AudioContext;return e.audioNotificationsOptions.enabled||z(r),t&&r.close(),{...e,audioNotificationsOptions:t?{audioContext:null,enabled:!1}:{audioContext:r,enabled:!0}}})},className:"ml-auto",children:(0,or.jsxs)("div",{className:ez(["flex gap-x-2 justify-center items-center text-[#6E6E77]"]),children:[(0,or.jsx)("span",{children:"Alerts"}),t.audioNotificationsOptions.enabled?(0,or.jsx)(nQ,{size:16,className:"text-[#6E6E77]"}):(0,or.jsx)(n0,{size:16,className:"text-[#6E6E77]"})]})}),children:(0,or.jsx)(or.Fragment,{children:"Play a chime when a slowdown is recorded"})})]})},oo=r(45994),oi=r(10201),oa=e=>{let t="";return e.toSorted((e,t)=>t.totalTime-e.totalTime).slice(0,30).filter(e=>e.totalTime>5).forEach(e=>{let r="";r+="Component Name:",r+=e.name,r+=`
`,r+=`Rendered: ${e.count} times
`,r+=`Sum of self times for ${e.name} is ${e.totalTime.toFixed(0)}ms
`,e.changes.props.length>0&&(r+=`Changed props for all ${e.name} instances ("name:count" pairs)
`,e.changes.props.forEach(e=>{r+=`${e.name}:${e.count}x
`})),e.changes.state.length>0&&(r+=`Changed state for all ${e.name} instances ("hook index:count" pairs)
`,e.changes.state.forEach(e=>{r+=`${e.index}:${e.count}x
`})),e.changes.context.length>0&&(r+=`Changed context for all ${e.name} instances ("context display name (if exists):count" pairs)
`,e.changes.context.forEach(e=>{r+=`${e.name}:${e.count}x
`})),t+=r,t+=`
`}),t},os=(e,t)=>(()=>{switch(e){case"data":switch(t.kind){case"dropped-frames":return(({renderTime:e,otherTime:t,formattedReactData:r})=>`I will provide you with a set of high level, and low level performance data about a large frame drop in a React App:
### High level
- react component render time: ${e.toFixed(0)}ms
- how long it took to run everything else (other JavaScript, hooks like useEffect, style recalculations, layerization, paint & commit and everything else the browser might do to draw a new frame after javascript mutates the DOM): ${t}ms

### Low level
We also have lower level information about react components, such as their render time, and which props/state/context changed when they re-rendered.
${r}`)({formattedReactData:oa(t.groupedFiberRenders),renderTime:t.groupedFiberRenders.reduce((e,t)=>e+t.totalTime,0),otherTime:t.timing.otherTime});case"interaction":return(({renderTime:e,eHandlerTimeExcludingRenders:t,toRafTime:r,commitTime:n,framePresentTime:o,formattedReactData:i})=>`I will provide you with a set of high level, and low level performance data about an interaction in a React App:
### High level
- react component render time: ${e.toFixed(0)}ms
- how long it took to run javascript event handlers (EXCLUDING REACT RENDERS): ${t.toFixed(0)}ms
- how long it took from the last event handler time, to the last request animation frame: ${r.toFixed(0)}ms
	- things like prepaint, style recalculations, layerization, async web API's like observers may occur during this time
- how long it took from the last request animation frame to when the dom was committed: ${n.toFixed(0)}ms
	- during this period you will see paint, commit, potential style recalcs, and other misc browser activity. Frequently high times here imply css that makes the browser do a lot of work, or mutating expensive dom properties during the event handler stage. This can be many things, but it narrows the problem scope significantly when this is high
${o&&`- how long it took from dom commit for the frame to be presented: ${o.toFixed(0)}ms. This is when information about how to paint the next frame is sent to the compositor threads, and when the GPU does work. If this is high, look for issues that may be a bottleneck for operations occurring during this time`}

### Low level
We also have lower level information about react components, such as their render time, and which props/state/context changed when they re-rendered.
${i}`)({commitTime:t.timing.frameConstruction,eHandlerTimeExcludingRenders:t.timing.otherJSTime,formattedReactData:oa(t.groupedFiberRenders),framePresentTime:t.timing.frameDraw,renderTime:t.groupedFiberRenders.reduce((e,t)=>e+t.totalTime,0),toRafTime:t.timing.framePreparation})}case"explanation":switch(t.kind){case"dropped-frames":return(({renderTime:e,otherTime:t,formattedReactData:r})=>`Your goal will be to help me find the source of a performance problem in a React App. I collected a large dataset about this specific performance problem.

We have the high level time of how much react spent rendering, and what else the browser spent time on during this slowdown

- react component render time: ${e.toFixed(0)}ms
- other time (other JavaScript, hooks like useEffect, style recalculations, layerization, paint & commit and everything else the browser might do to draw a new frame after javascript mutates the DOM): ${t}ms


We also have lower level information about react components, such as their render time, and which props/state/context changed when they re-rendered.

${r}

You may notice components have many renders, but much fewer props/state/context changes. This normally implies most of the components could of been memoized to avoid computation

It's also important to remember if a component had no props/state/context change, and it was memoized, it would not render. So a flow we can go through is:
- find the most expensive components
- see what's causing them to render
- determine how you can make those state/props/context not change for a large set of the renders
- once there are no more changes left, you can memoize the component so it no longer unnecessarily re-renders. 


An important thing to note is that if you see a lot of react renders (some components with very high render counts), but other time is much higher than render time, it is possible that the components with lots of renders run hooks like useEffect/useLayoutEffect, which run outside of what we profile (just react render time).

It's also good to note that react profiles hook times in development, and if many hooks are called (lets say 5,000 components all called a useEffect), it will have to profile every single one, and this can add significant overhead when thousands of effects ran.

If it's not possible to explain the root problem from this data, please ask me for more data explicitly, and what we would need to know to find the source of the performance problem.
`)({formattedReactData:oa(t.groupedFiberRenders),renderTime:t.groupedFiberRenders.reduce((e,t)=>e+t.totalTime,0),otherTime:t.timing.otherTime});case"interaction":return(({interactionType:e,name:t,time:r,renderTime:n,eHandlerTimeExcludingRenders:o,toRafTime:i,commitTime:a,framePresentTime:s,formattedReactData:l})=>`Your goal will be to help me find the source of a performance problem. I collected a large dataset about this specific performance problem.

There was a ${e} on a component named ${t}. This means, roughly, the component that handled the ${e} event was named ${t}.

We have a set of high level, and low level data about the performance issue.

The click took ${r.toFixed(0)}ms from interaction start, to when a new frame was presented to a user.

We also provide you with a breakdown of what the browser spent time on during the period of interaction start to frame presentation.

- react component render time: ${n.toFixed(0)}ms
- how long it took to run javascript event handlers (EXCLUDING REACT RENDERS): ${o.toFixed(0)}ms
- how long it took from the last event handler time, to the last request animation frame: ${i.toFixed(0)}ms
	- things like prepaint, style recalculations, layerization, async web API's like observers may occur during this time
- how long it took from the last request animation frame to when the dom was committed: ${a.toFixed(0)}ms
	- during this period you will see paint, commit, potential style recalcs, and other misc browser activity. Frequently high times here imply css that makes the browser do a lot of work, or mutating expensive dom properties during the event handler stage. This can be many things, but it narrows the problem scope significantly when this is high
${s&&`- how long it took from dom commit for the frame to be presented: ${s.toFixed(0)}ms. This is when information about how to paint the next frame is sent to the compositor threads, and when the GPU does work. If this is high, look for issues that may be a bottleneck for operations occurring during this time`}

We also have lower level information about react components, such as their render time, and which props/state/context changed when they re-rendered.

${l}


You may notice components have many renders, but much fewer props/state/context changes. This normally implies most of the components could of been memoized to avoid computation

It's also important to remember if a component had no props/state/context change, and it was memoized, it would not render. So a flow we can go through is:
- find the most expensive components
- see what's causing them to render
- determine how you can make those state/props/context not change for a large set of the renders
- once there are no more changes left, you can memoize the component so it no longer unnecessarily re-renders. 


An important thing to note is that if you see a lot of react renders (some components with very high render counts), but javascript excluding renders is much higher than render time, it is possible that the components with lots of renders run hooks like useEffect/useLayoutEffect, which run during the JS event handler period.

It's also good to note that react profiles hook times in development, and if many hooks are called (lets say 5,000 components all called a useEffect), it will have to profile every single one. And it may also be the case the comparison of the hooks dependency can be expensive, and that would not be tracked in render time.

If it's not possible to explain the root problem from this data, please ask me for more data explicitly, and what we would need to know to find the source of the performance problem.
`)({commitTime:t.timing.frameConstruction,eHandlerTimeExcludingRenders:t.timing.otherJSTime,formattedReactData:oa(t.groupedFiberRenders),framePresentTime:t.timing.frameDraw,interactionType:t.type,name:nB(t.componentPath),renderTime:t.groupedFiberRenders.reduce((e,t)=>e+t.totalTime,0),time:nW(t.timing),toRafTime:t.timing.framePreparation})}case"fix":switch(t.kind){case"dropped-frames":return(({renderTime:e,otherTime:t,formattedReactData:r})=>`You will attempt to implement a performance improvement to a large slowdown in a react app

Your should split your goals into 2 parts:
- identifying the problem
- fixing the problem
	- it is okay to implement a fix even if you aren't 100% sure the fix solves the performance problem. When you aren't sure, you should tell the user to try repeating the interaction, and feeding the "Formatted Data" in the React Scan notifications optimize tab. This allows you to start a debugging flow with the user, where you attempt a fix, and observe the result. The user may make a mistake when they pass you the formatted data, so must make sure, given the data passed to you, that the associated data ties to the same interaction you were trying to debug.

Make sure to check if the user has the react compiler enabled (project dependent, configured through build tool), so you don't unnecessarily memoize components. If it is, you do not need to worry about memoizing user components

One challenge you may face is the performance problem lies in a node_module, not in user code. If you are confident the problem originates because of a node_module, there are multiple strategies, which are context dependent:
- you can try to work around the problem, knowing which module is slow
- you can determine if its possible to resolve the problem in the node_module by modifying non node_module code
- you can monkey patch the node_module to experiment and see if it's really the problem (you can modify a functions properties to hijack the call for example)
- you can determine if it's feasible to replace whatever node_module is causing the problem with a performant option (this is an extreme)


We have the high level time of how much react spent rendering, and what else the browser spent time on during this slowdown

- react component render time: ${e.toFixed(0)}ms
- other time: ${t}ms


We also have lower level information about react components, such as their render time, and which props/state/context changed when they re-rendered.

${r}

You may notice components have many renders, but much fewer props/state/context changes. This normally implies most of the components could of been memoized to avoid computation

It's also important to remember if a component had no props/state/context change, and it was memoized, it would not render. So the flow should be:
- find the most expensive components
- see what's causing them to render
- determine how you can make those state/props/context not change for a large set of the renders
- once there are no more changes left, you can memoize the component so it no longer unnecessarily re-renders. 

An important thing to note is that if you see a lot of react renders (some components with very high render counts), but other time is much higher than render time, it is possible that the components with lots of renders run hooks like useEffect/useLayoutEffect, which run outside of what we profile (just react render time).

It's also good to note that react profiles hook times in development, and if many hooks are called (lets say 5,000 components all called a useEffect), it will have to profile every single one. And it may also be the case the comparison of the hooks dependency can be expensive, and that would not be tracked in render time.

If a node_module is the component with high renders, you can experiment to see if that component is the root issue (because of hooks). You should use the same instructions for node_module debugging mentioned previously.

If renders don't seem to be the problem, see if there are any expensive CSS properties being added/mutated, or any expensive DOM Element mutations/new elements being created that could cause this slowdown. 
`)({formattedReactData:oa(t.groupedFiberRenders),renderTime:t.groupedFiberRenders.reduce((e,t)=>e+t.totalTime,0),otherTime:t.timing.otherTime});case"interaction":return(({interactionType:e,name:t,componentPath:r,time:n,renderTime:o,eHandlerTimeExcludingRenders:i,toRafTime:a,commitTime:s,framePresentTime:l,formattedReactData:c})=>`You will attempt to implement a performance improvement to a user interaction in a React app. You will be provided with data about the interaction, and the slow down.

Your should split your goals into 2 parts:
- identifying the problem
- fixing the problem
	- it is okay to implement a fix even if you aren't 100% sure the fix solves the performance problem. When you aren't sure, you should tell the user to try repeating the interaction, and feeding the "Formatted Data" in the React Scan notifications optimize tab. This allows you to start a debugging flow with the user, where you attempt a fix, and observe the result. The user may make a mistake when they pass you the formatted data, so must make sure, given the data passed to you, that the associated data ties to the same interaction you were trying to debug.


Make sure to check if the user has the react compiler enabled (project dependent, configured through build tool), so you don't unnecessarily memoize components. If it is, you do not need to worry about memoizing user components

One challenge you may face is the performance problem lies in a node_module, not in user code. If you are confident the problem originates because of a node_module, there are multiple strategies, which are context dependent:
- you can try to work around the problem, knowing which module is slow
- you can determine if its possible to resolve the problem in the node_module by modifying non node_module code
- you can monkey patch the node_module to experiment and see if it's really the problem (you can modify a functions properties to hijack the call for example)
- you can determine if it's feasible to replace whatever node_module is causing the problem with a performant option (this is an extreme)

The interaction was a ${e} on the component named ${t}. This component has the following ancestors ${r}. This is the path from the component, to the root. This should be enough information to figure out where this component is in the user's code base

This path is the component that was clicked, so it should tell you roughly where component had an event handler that triggered a state change.

Please note that the leaf node of this path might not be user code (if they use a UI library), and they may contain many wrapper components that just pass through children that aren't relevant to the actual click. So make you sure analyze the path and understand what the user code is doing

We have a set of high level, and low level data about the performance issue.

The click took ${n.toFixed(0)}ms from interaction start, to when a new frame was presented to a user.

We also provide you with a breakdown of what the browser spent time on during the period of interaction start to frame presentation.

- react component render time: ${o.toFixed(0)}ms
- how long it took to run javascript event handlers (EXCLUDING REACT RENDERS): ${i.toFixed(0)}ms
- how long it took from the last event handler time, to the last request animation frame: ${a.toFixed(0)}ms
	- things like prepaint, style recalculations, layerization, async web API's like observers may occur during this time
- how long it took from the last request animation frame to when the dom was committed: ${s.toFixed(0)}ms
	- during this period you will see paint, commit, potential style recalcs, and other misc browser activity. Frequently high times here imply css that makes the browser do a lot of work, or mutating expensive dom properties during the event handler stage. This can be many things, but it narrows the problem scope significantly when this is high
${l&&`- how long it took from dom commit for the frame to be presented: ${l.toFixed(0)}ms. This is when information about how to paint the next frame is sent to the compositor threads, and when the GPU does work. If this is high, look for issues that may be a bottleneck for operations occurring during this time`}


We also have lower level information about react components, such as their render time, and which props/state/context changed when they re-rendered.

${c}

You may notice components have many renders, but much fewer props/state/context changes. This normally implies most of the components could of been memoized to avoid computation

It's also important to remember if a component had no props/state/context change, and it was memoized, it would not render. So the flow should be:
- find the most expensive components
- see what's causing them to render
- determine how you can make those state/props/context not change for a large set of the renders
- once there are no more changes left, you can memoize the component so it no longer unnecessarily re-renders. 

An important thing to note is that if you see a lot of react renders (some components with very high render counts), but javascript excluding renders is much higher than render time, it is possible that the components with lots of renders run hooks like useEffect/useLayoutEffect, which run during the JS event handler period.

It's also good to note that react profiles hook times in development, and if many hooks are called (lets say 5,000 components all called a useEffect), it will have to profile every single one. And it may also be the case the comparison of the hooks dependency can be expensive, and that would not be tracked in render time.

If a node_module is the component with high renders, you can experiment to see if that component is the root issue (because of hooks). You should use the same instructions for node_module debugging mentioned previously.

`)({commitTime:t.timing.frameConstruction,componentPath:t.componentPath.join(">"),eHandlerTimeExcludingRenders:t.timing.otherJSTime,formattedReactData:oa(t.groupedFiberRenders),framePresentTime:t.timing.frameDraw,interactionType:t.type,name:nB(t.componentPath),renderTime:t.groupedFiberRenders.reduce((e,t)=>e+t.totalTime,0),time:nW(t.timing),toRafTime:t.timing.framePreparation})}}})(),ol=({selectedEvent:e})=>{let[t,r]=(0,oo.useState)("fix"),[n,o]=(0,oo.useState)(!1);return(0,oi.jsxs)("div",{className:ez(["w-full h-full"]),children:[(0,oi.jsxs)("div",{className:ez(["border border-[#27272A] rounded-sm h-4/5 text-xs overflow-hidden"]),children:[(0,oi.jsx)("div",{className:ez(["bg-[#18181B] p-1 rounded-t-sm"]),children:(0,oi.jsxs)("div",{className:ez(["flex items-center gap-x-1"]),children:[(0,oi.jsx)("button",{onClick:()=>r("fix"),className:ez(["flex items-center justify-center whitespace-nowrap py-1.5 px-3 rounded-sm","fix"===t?"text-white bg-[#7521c8]":"text-[#6E6E77] hover:text-white"]),children:"Fix"}),(0,oi.jsx)("button",{onClick:()=>r("explanation"),className:ez(["flex items-center justify-center whitespace-nowrap py-1.5 px-3 rounded-sm","explanation"===t?"text-white bg-[#7521c8]":"text-[#6E6E77] hover:text-white"]),children:"Explanation"}),(0,oi.jsx)("button",{onClick:()=>r("data"),className:ez(["flex items-center justify-center whitespace-nowrap py-1.5 px-3 rounded-sm","data"===t?"text-white bg-[#7521c8]":"text-[#6E6E77] hover:text-white"]),children:"Data"})]})}),(0,oi.jsx)("div",{className:ez(["overflow-y-auto h-full"]),children:(0,oi.jsx)("pre",{className:ez(["p-2 h-full","whitespace-pre-wrap break-words","text-gray-300 font-mono "]),children:os(t,e)})})]}),(0,oi.jsxs)("button",{onClick:async()=>{let r=os(t,e);await navigator.clipboard.writeText(r),o(!0),setTimeout(()=>o(!1),1e3)},className:ez(["mt-4 px-4 py-2 bg-[#18181B] text-[#6E6E77] rounded-sm","hover:text-white transition-colors duration-200","flex items-center justify-center gap-x-2 text-xs"]),children:[(0,oi.jsx)("span",{children:n?"Copied!":"Copy Prompt"}),(0,oi.jsx)("svg",{xmlns:"http://www.w3.org/2000/svg",width:"16",height:"16",viewBox:"0 0 24 24",fill:"none",stroke:"currentColor",strokeWidth:"2",strokeLinecap:"round",strokeLinejoin:"round",className:ez(["transition-transform duration-200",n&&"scale-110"]),children:n?(0,oi.jsx)("path",{d:"M20 6L9 17l-5-5"}):(0,oi.jsxs)(oi.Fragment,{children:[(0,oi.jsx)("rect",{width:"14",height:"14",x:"8",y:"8",rx:"2",ry:"2"}),(0,oi.jsx)("path",{d:"M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2"})]})})]})]})},oc=r(45994),od=r(10201),ou=({selectedEvent:e})=>{let[t]=(0,oc.useState)(iR()??!1),{notificationState:r}=nX(),[n,o]=(0,oc.useState)(r.routeMessage?.name?[r.routeMessage.name]:[]),i=((e,t)=>{switch(e.kind){case"dropped-frames":return[...t?[{name:"Total Processing Time",time:nW(e.timing),color:"bg-red-500",kind:"total-processing-time"}]:[{name:"Renders",time:e.timing.renderTime,color:"bg-purple-500",kind:"render"},{name:"JavaScript, DOM updates, Draw Frame",time:e.timing.otherTime,color:"bg-[#4b4b4b]",kind:"other-frame-drop"}]];case"interaction":return[...t?[]:[{name:"Renders",time:e.timing.renderTime,color:"bg-purple-500",kind:"render"}],{name:t?"React Renders, Hooks, Other JavaScript":"JavaScript/React Hooks ",time:e.timing.otherJSTime,color:"bg-[#EFD81A]",kind:"other-javascript"},{name:"Update DOM and Draw New Frame",time:nW(e.timing)-e.timing.renderTime-e.timing.otherJSTime,color:"bg-[#1D3A66]",kind:"other-not-javascript"}]}})(e,t),a=(0,oc.useContext)(ix);(0,oc.useEffect)(()=>{if(r.routeMessage?.name){let e=a?.querySelector("#overview-scroll-container"),t=a?.querySelector(`#react-scan-overview-bar-${r.routeMessage.name}`);if(e&&t){let r=t.getBoundingClientRect().top,n=e.getBoundingClientRect().top;e.scrollTop=e.scrollTop+(r-n)}}},[r.route]),(0,oc.useEffect)(()=>{"other-visualization"===r.route&&o(e=>r.routeMessage?.name?[r.routeMessage.name]:e)},[r.route]);let s=i.reduce((e,t)=>e+t.time,0);return(0,od.jsxs)("div",{className:"rounded-sm border border-zinc-800 text-xs",children:[(0,od.jsx)("div",{className:"p-2 border-b border-zinc-800 bg-zinc-900/50",children:(0,od.jsxs)("div",{className:"flex items-center justify-between",children:[(0,od.jsx)("h3",{className:"text-xs font-medium",children:"What was time spent on?"}),(0,od.jsxs)("span",{className:"text-xs text-zinc-400",children:["Total: ",s.toFixed(0),"ms"]})]})}),(0,od.jsx)("div",{className:"divide-y divide-zinc-800",children:i.map(t=>{let r=n.includes(t.kind);return(0,od.jsxs)("div",{id:`react-scan-overview-bar-${t.kind}`,children:[(0,od.jsx)("button",{onClick:()=>o(e=>e.includes(t.kind)?e.filter(e=>e!==t.kind):[...e,t.kind]),className:"w-full px-3 py-2 flex items-center gap-4 hover:bg-zinc-800/50 transition-colors",children:(0,od.jsxs)("div",{className:"flex-1",children:[(0,od.jsxs)("div",{className:"flex items-center justify-between mb-2",children:[(0,od.jsxs)("div",{className:"flex items-center gap-0.5",children:[(0,od.jsx)("svg",{className:`h-4 w-4 text-zinc-400 transition-transform ${r?"rotate-90":""}`,fill:"none",stroke:"currentColor",viewBox:"0 0 24 24",children:(0,od.jsx)("path",{strokeLinecap:"round",strokeLinejoin:"round",strokeWidth:2,d:"M9 5l7 7-7 7"})}),(0,od.jsx)("span",{className:"font-medium flex items-center text-left",children:t.name})]}),(0,od.jsxs)("span",{className:" text-zinc-400",children:[t.time.toFixed(0),"ms"]})]}),(0,od.jsx)("div",{className:"h-1 bg-zinc-800 rounded-full overflow-hidden",children:(0,od.jsx)("div",{className:`h-full ${t.color} transition-all`,style:{width:`${t.time/s*100}%`}})})]})}),r&&(0,od.jsx)("div",{className:"bg-zinc-900/30 border-t border-zinc-800 px-2.5 py-3",children:(0,od.jsx)("p",{className:" text-zinc-400 mb-4 text-xs",children:(()=>{switch(e.kind){case"interaction":switch(t.kind){case"render":return(0,od.jsx)(og,{input:om(e)});case"other-javascript":return(0,od.jsx)(og,{input:of(e)});case"other-not-javascript":return(0,od.jsx)(og,{input:op(e)})}case"dropped-frames":switch(t.kind){case"total-processing-time":return(0,od.jsx)(og,{input:{kind:"total-processing",data:{time:nW(e.timing)}}});case"render":return(0,od.jsx)(od.Fragment,{children:(0,od.jsx)(og,{input:{kind:"render",data:{topByTime:e.groupedFiberRenders.toSorted((e,t)=>t.totalTime-e.totalTime).slice(0,3).map(t=>({name:t.name,percentage:t.totalTime/nW(e.timing)}))}}})});case"other-frame-drop":return(0,od.jsx)(og,{input:{kind:"other"}})}}})()})})]},t.kind)})})]})},op=e=>{let t=e.groupedFiberRenders.reduce((e,t)=>e+t.count,0),r=e.timing.renderTime,n=nW(e.timing);return t>100?{kind:"high-render-count-update-dom-draw-frame",data:{count:t,percentageOfTotal:r/n*100,copyButton:(0,od.jsx)(oh,{})}}:{kind:"update-dom-draw-frame",data:{copyButton:(0,od.jsx)(oh,{})}}},oh=()=>{let[e,t]=(0,oc.useState)(!1),{notificationState:r}=nX();return(0,od.jsxs)("button",{onClick:async()=>{r.selectedEvent&&(await navigator.clipboard.writeText(os("explanation",r.selectedEvent)),t(!0),setTimeout(()=>t(!1),1e3))},className:"bg-zinc-800 flex hover:bg-zinc-700 text-zinc-200 px-2 py-1 rounded gap-x-3",children:[(0,od.jsx)("span",{children:e?"Copied!":"Copy Prompt"}),(0,od.jsx)("svg",{xmlns:"http://www.w3.org/2000/svg",width:"16",height:"16",viewBox:"0 0 24 24",fill:"none",stroke:"currentColor",strokeWidth:"2",strokeLinecap:"round",strokeLinejoin:"round",className:ez(["transition-transform duration-200",e&&"scale-110"]),children:e?(0,od.jsx)("path",{d:"M20 6L9 17l-5-5"}):(0,od.jsxs)(od.Fragment,{children:[(0,od.jsx)("rect",{width:"14",height:"14",x:"8",y:"8",rx:"2",ry:"2"}),(0,od.jsx)("path",{d:"M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2"})]})})]})},om=e=>e.timing.renderTime/nW(e.timing)>.3?{kind:"render",data:{topByTime:e.groupedFiberRenders.toSorted((e,t)=>t.totalTime-e.totalTime).slice(0,3).map(t=>({percentage:t.totalTime/nW(e.timing),name:t.name}))}}:{kind:"other"},of=e=>{let t=e.groupedFiberRenders.reduce((e,t)=>e+t.count,0);return e.timing.otherJSTime/nW(e.timing)<.2?{kind:"js-explanation-base"}:e.groupedFiberRenders.find(e=>e.count>200)||e.groupedFiberRenders.reduce((e,t)=>e+t.count,0)>500?{kind:"high-render-count-high-js",data:{renderCount:t,topByCount:e.groupedFiberRenders.filter(e=>e.count>100).toSorted((e,t)=>t.count-e.count).slice(0,3)}}:e.timing.otherJSTime/nW(e.timing)>.3?e.timing.renderTime>.2?{kind:"js-explanation-base"}:{kind:"low-render-count-high-js",data:{renderCount:t}}:{kind:"js-explanation-base"}},og=({input:e})=>{switch(e.kind){case"total-processing":return(0,od.jsxs)("div",{className:ez(["text-[#E4E4E7] text-[10px] leading-6 flex flex-col gap-y-2"]),children:[(0,od.jsxs)("p",{children:["This is the time it took to draw the entire frame that was presented to the user. To be at 60FPS, this number needs to be ","<=16ms"]}),(0,od.jsx)("p",{children:'To debug the issue, check the "Ranked" tab to see if there are significant component renders'}),(0,od.jsx)("p",{children:"On a production React build, React Scan can't access the time it took for component to render. To get that information, run React Scan on a development build"}),(0,od.jsxs)("p",{children:["To understand precisely what caused the slowdown while in production, use the ",(0,od.jsx)("strong",{children:"Chrome profiler"})," and analyze the function call times."]}),(0,od.jsx)("p",{})]});case"render":return(0,od.jsxs)("div",{className:ez(["text-[#E4E4E7] text-[10px] leading-6 flex flex-col gap-y-2"]),children:[(0,od.jsx)("p",{children:"This is the time it took React to run components, and internal logic to handle the output of your component."}),(0,od.jsxs)("div",{className:ez(["flex flex-col"]),children:[(0,od.jsx)("p",{children:"The slowest components for this time period were:"}),e.data.topByTime.map(e=>(0,od.jsxs)("div",{children:[(0,od.jsx)("strong",{children:e.name}),":"," ",(100*e.percentage).toFixed(0),"% of total"]},e.name))]}),(0,od.jsx)("p",{children:'To view the render times of all your components, and what caused them to render, go to the "Ranked" tab'}),(0,od.jsx)("p",{children:'The "Ranked" tab shows the render times of every component.'}),(0,od.jsx)("p",{children:"The render times of the same components are grouped together into one bar."}),(0,od.jsx)("p",{children:"Clicking the component will show you what props, state, or context caused the component to re-render."})]});case"js-explanation-base":return(0,od.jsxs)("div",{className:ez(["text-[#E4E4E7] text-[10px] leading-6 flex flex-col gap-y-2"]),children:[(0,od.jsx)("p",{children:"This is the period when JavaScript hooks and other JavaScript outside of React Renders run."}),(0,od.jsxs)("p",{children:["The most common culprit for high JS time is expensive hooks, like expensive callbacks inside of ",(0,od.jsx)("code",{children:"useEffect"}),"'s or a large number of useEffect's called, but this can also be JavaScript event handlers (",(0,od.jsx)("code",{children:"'onclick'"}),", ",(0,od.jsx)("code",{children:"'onchange'"}),") that performed expensive computation."]}),(0,od.jsx)("p",{children:"If you have lots of components rendering that call hooks, like useEffect, it can add significant overhead even if the callbacks are not expensive. If this is the case, you can try optimizing the renders of those components to avoid the hook from having to run."}),(0,od.jsxs)("p",{children:["You should profile your app using the"," ",(0,od.jsx)("strong",{children:"Chrome DevTools profiler"})," to learn exactly which functions took the longest to execute."]})]});case"high-render-count-high-js":return(0,od.jsxs)("div",{className:ez(["text-[#E4E4E7] text-[10px] leading-6 flex flex-col gap-y-2"]),children:[(0,od.jsx)("p",{children:"This is the period when JavaScript hooks and other JavaScript outside of React Renders run."}),0===e.data.renderCount?(0,od.jsxs)(od.Fragment,{children:[(0,od.jsx)("p",{children:"There were no renders, which means nothing related to React caused this slowdown. The most likely cause of the slowdown is a slow JavaScript event handler, or code related to a Web API"}),(0,od.jsxs)("p",{children:["You should try to reproduce the slowdown while profiling your website with the",(0,od.jsx)("strong",{children:"Chrome DevTools profiler"})," to see exactly what functions took the longest to execute."]})]}):(0,od.jsxs)(od.Fragment,{children:[" ",(0,od.jsxs)("p",{children:["There were ",(0,od.jsx)("strong",{children:e.data.renderCount})," renders, which could have contributed to the high JavaScript/Hook time if they ran lots of hooks, like ",(0,od.jsx)("code",{children:"useEffects"}),"."]}),(0,od.jsxs)("div",{className:ez(["flex flex-col"]),children:[(0,od.jsx)("p",{children:"You should try optimizing the renders of:"}),e.data.topByCount.map(e=>(0,od.jsxs)("div",{children:["- ",(0,od.jsx)("strong",{children:e.name})," (rendered ",e.count,"x)"]},e.name))]}),"and then checking if the problem still exists.",(0,od.jsxs)("p",{children:["You can also try profiling your app using the"," ",(0,od.jsx)("strong",{children:"Chrome DevTools profiler"})," to see exactly what functions took the longest to execute."]})]})]});case"low-render-count-high-js":return(0,od.jsxs)("div",{className:ez(["text-[#E4E4E7] text-[10px] leading-6 flex flex-col gap-y-2"]),children:[(0,od.jsx)("p",{children:"This is the period when JavaScript hooks and other JavaScript outside of React Renders run."}),(0,od.jsxs)("p",{children:["There were only ",(0,od.jsx)("strong",{children:e.data.renderCount})," renders detected, which means either you had very expensive hooks like"," ",(0,od.jsx)("code",{children:"useEffect"}),"/",(0,od.jsx)("code",{children:"useLayoutEffect"}),", or there is other JavaScript running during this interaction that took up the majority of the time."]}),(0,od.jsxs)("p",{children:["To understand precisely what caused the slowdown, use the"," ",(0,od.jsx)("strong",{children:"Chrome profiler"})," and analyze the function call times."]})]});case"high-render-count-update-dom-draw-frame":return(0,od.jsxs)("div",{className:ez(["text-[#E4E4E7] text-[10px] leading-6 flex flex-col gap-y-2"]),children:[(0,od.jsx)("p",{children:"These are the calculations the browser is forced to do in response to the JavaScript that ran during the interaction."}),(0,od.jsx)("p",{children:"This can be caused by CSS updates/CSS recalculations, or new DOM elements/DOM mutations."}),(0,od.jsxs)("p",{children:["During this interaction, there were"," ",(0,od.jsx)("strong",{children:e.data.count})," renders, which was"," ",(0,od.jsxs)("strong",{children:[e.data.percentageOfTotal.toFixed(0),"%"]})," of the time spent processing"]}),(0,od.jsx)("p",{children:"The work performed as a result of the renders may have forced the browser to spend a lot of time to draw the next frame."}),(0,od.jsx)("p",{children:'You can try optimizing the renders to see if the performance problem still exists using the "Ranked" tab.'}),(0,od.jsx)("p",{children:"If you use an AI-based code editor, you can export the performance data collected as a prompt."}),(0,od.jsx)("p",{children:e.data.copyButton}),(0,od.jsx)("p",{children:"Provide this formatted data to the model and ask it to find, or fix, what could be causing this performance problem."}),(0,od.jsx)("p",{children:'For a larger selection of prompts, try the "Prompts" tab'})]});case"update-dom-draw-frame":return(0,od.jsxs)("div",{className:ez(["text-[#E4E4E7] text-[10px] leading-6 flex flex-col gap-y-2"]),children:[(0,od.jsx)("p",{children:"These are the calculations the browser is forced to do in response to the JavaScript that ran during the interaction."}),(0,od.jsx)("p",{children:"This can be caused by CSS updates/CSS recalculations, or new DOM elements/DOM mutations."}),(0,od.jsx)("p",{children:"If you use an AI-based code editor, you can export the performance data collected as a prompt."}),(0,od.jsx)("p",{children:e.data.copyButton}),(0,od.jsx)("p",{children:"Provide this formatted data to the model and ask it to find, or fix, what could be causing this performance problem."}),(0,od.jsx)("p",{children:'For a larger selection of prompts, try the "Prompts" tab'})]});case"other":return(0,od.jsxs)("div",{className:ez(["text-[#E4E4E7] text-[10px] leading-6 flex flex-col gap-y-2"]),children:[(0,od.jsxs)("p",{children:["This is the time it took to run everything other than React renders. This can be hooks like ",(0,od.jsx)("code",{children:"useEffect"}),", other JavaScript not part of React, or work the browser has to do to update the DOM and draw the next frame."]}),(0,od.jsxs)("p",{children:["To get a better picture of what happened, profile your app using the"," ",(0,od.jsx)("strong",{children:"Chrome profiler"})," when the performance problem arises."]})]})}},ox=r(45994),ob=r(61704),ow=null,ov=null,oy=null,o_=(0,ob.signal)({kind:"idle",current:null}),ok=null,oj=()=>{ok&&cancelAnimationFrame(ok),ok=requestAnimationFrame(()=>{if(!ow||!ov)return;ov.clearRect(0,0,ow.width,ow.height);let e="hsl(271, 76%, 53%)",t=o_.value,{alpha:r,current:n}=(()=>{switch(t.kind){case"transition":{let e=t.current?.alpha&&t.current.alpha>0?t.current:t.transitionTo;return{alpha:e?e.alpha:0,current:e}}case"move-out":return{alpha:t.current?.alpha??0,current:t.current};case"idle":return{alpha:1,current:t.current}}})();switch(n?.rects.forEach(t=>{ov&&(ov.shadowColor=e,ov.shadowBlur=6,ov.strokeStyle=e,ov.lineWidth=2,ov.globalAlpha=r,ov.beginPath(),ov.rect(t.left,t.top,t.width,t.height),ov.stroke(),ov.shadowBlur=0,ov.beginPath(),ov.rect(t.left,t.top,t.width,t.height),ov.stroke())}),t.kind){case"move-out":if(0===t.current.alpha){o_.value={kind:"idle",current:null};return}t.current.alpha<=.01&&(t.current.alpha=0),t.current.alpha=Math.max(0,t.current.alpha-.03),oj();return;case"transition":if(t.current&&t.current.alpha>0){t.current.alpha=Math.max(0,t.current.alpha-.03),oj();return}if(1===t.transitionTo.alpha){o_.value={kind:"idle",current:t.transitionTo};return}t.transitionTo.alpha=Math.min(t.transitionTo.alpha+.03,1),oj();case"idle":return}})},oC=null;function oS(){oy&&(cancelAnimationFrame(oy),oy=null),ow?.parentNode&&ow.parentNode.removeChild(ow),ow=null,ov=null}var oN=r(10201),oT=()=>{let e=o_.value.current?o_.value.current:"transition"===o_.value.kind?o_.value.transitionTo:null;if(e){if("transition"===o_.value.kind){o_.value={kind:"move-out",current:o_.value.current?.alpha===0?o_.value.transitionTo:o_.value.current??o_.value.transitionTo};return}o_.value={kind:"move-out",current:{alpha:0,...e}}}},oE=({selectedEvent:e})=>{let t=nW(e.timing),r=t-e.timing.renderTime,[n]=(0,ox.useState)(iR()),o=e.groupedFiberRenders.map(e=>({event:e,kind:"render",totalTime:n?e.count:e.totalTime})),i=(()=>{switch(e.kind){case"dropped-frames":return e.timing.renderTime/t<.1;case"interaction":return(e.timing.otherJSTime+e.timing.renderTime)/t<.2}})();"interaction"!==e.kind||n||o.push({kind:"other-javascript",totalTime:e.timing.otherJSTime}),i&&!n&&("interaction"===e.kind?o.push({kind:"other-not-javascript",totalTime:nW(e.timing)-e.timing.renderTime-e.timing.otherJSTime}):o.push({kind:"other-frame-drop",totalTime:r}));let a=(0,ox.useRef)({lastCallAt:null,timer:null}),s=o.reduce((e,t)=>e+t.totalTime,0);return(0,oN.jsxs)("div",{className:ez(["flex flex-col h-full w-full gap-y-1"]),children:[n&&0===o.length?(0,oN.jsxs)("div",{className:"flex flex-col items-center justify-center h-full text-zinc-400",children:[(0,oN.jsx)("p",{className:"text-sm w-full text-left text-white mb-1.5",children:"No data available"}),(0,oN.jsx)("p",{className:"text-x w-full text-lefts",children:"No data was collected during this period"})]}):0===o.length?(0,oN.jsxs)("div",{className:"flex flex-col items-center justify-center h-full text-zinc-400",children:[(0,oN.jsx)("p",{className:"text-sm w-full text-left text-white mb-1.5",children:"No renders collected"}),(0,oN.jsx)("p",{className:"text-x w-full text-lefts",children:"There were no renders during this period"})]}):void 0,o.toSorted((e,t)=>t.totalTime-e.totalTime).map(e=>(0,oN.jsx)(oz,{bars:o,bar:e,debouncedMouseEnter:a,totalBarTime:s,isProduction:n},"render"===e.kind?e.event.id:e.kind))]})},oz=({bar:e,debouncedMouseEnter:t,totalBarTime:r,isProduction:n,bars:o,depth:i=0})=>{var a;let{setNotificationState:s,setRoute:l}=nX(),[c,d]=(0,ox.useState)(!1),u="render"!==e.kind||0===e.event.parents.size,p=o.filter(t=>"render"===t.kind&&"render"===e.kind&&e.event.parents.has(t.event.name)&&t.event.name!==e.event.name),h="render"===e.kind?Array.from(e.event.parents).filter(e=>!o.some(t=>"render"===t.kind&&t.event.name===e)):[];return(0,oN.jsxs)("div",{className:"w-full",children:[(0,oN.jsxs)("div",{className:ez(["w-full flex items-center relative text-xs min-w-0"]),children:[(0,oN.jsxs)("button",{onMouseLeave:()=>{t.current.timer&&clearTimeout(t.current.timer),oT()},onMouseEnter:async()=>{let r=async()=>{if(t.current.lastCallAt=Date.now(),"render"!==e.kind){let e=o_.value.current?o_.value.current:"transition"===o_.value.kind?o_.value.transitionTo:null;if(!e){o_.value={kind:"idle",current:null};return}o_.value={kind:"move-out",current:{alpha:0,...e}};return}let r=o_.value,n=(()=>{switch(r.kind){case"transition":return r.transitionTo;case"idle":case"move-out":return r.current}})(),o=[];if("transition"===r.kind){let t=r.current&&r.current.alpha>0?"fading-out":"fading-in";(()=>{switch(t){case"fading-in":o_.value={kind:"transition",current:r.transitionTo,transitionTo:{rects:o,alpha:0,name:e.event.name}};return;case"fading-out":o_.value={kind:"transition",current:o_.value.current?{alpha:0,...o_.value.current}:null,transitionTo:{rects:o,alpha:0,name:e.event.name}};return}})()}else o_.value={kind:"transition",transitionTo:{rects:o,alpha:0,name:e.event.name},current:n?{alpha:0,...n}:null};for await(let t of rU(e.event.elements.filter(e=>e instanceof Element)))t.forEach(({boundingClientRect:e})=>{o.push(e)}),oj()};if(t.current.lastCallAt&&Date.now()-t.current.lastCallAt<200){t.current.timer&&clearTimeout(t.current.timer),t.current.timer=setTimeout(()=>{r()},200);return}r()},onClick:()=>{"render"===e.kind?(s(t=>({...t,selectedFiber:e.event})),l({route:"render-explanation",routeMessage:null})):l({route:"other-visualization",routeMessage:{kind:"auto-open-overview-accordion",name:e.kind}})},className:ez(["h-full w-[90%] flex items-center hover:bg-[#0f0f0f] rounded-l-md min-w-0 relative"]),children:[(0,oN.jsx)("div",{style:{minWidth:"fit-content",width:`${e.totalTime/r*100}%`},className:ez(["flex items-center rounded-sm text-white text-xs h-[28px] shrink-0","render"===e.kind&&"bg-[#412162] group-hover:bg-[#5b2d89]","other-frame-drop"===e.kind&&"bg-[#44444a] group-hover:bg-[#6a6a6a]","other-javascript"===e.kind&&"bg-[#efd81a6b] group-hover:bg-[#efda1a2f]","other-not-javascript"===e.kind&&"bg-[#214379d4] group-hover:bg-[#21437982]"])}),(0,oN.jsx)("div",{className:ez(["absolute inset-0 flex items-center px-2","min-w-0"]),children:(0,oN.jsxs)("div",{className:"flex items-center gap-x-2 min-w-0 w-full",children:[(0,oN.jsx)("span",{className:ez(["truncate"]),children:(()=>{switch(e.kind){case"other-frame-drop":return"JavaScript, DOM updates, Draw Frame";case"other-javascript":return"JavaScript/React Hooks";case"other-not-javascript":return"Update DOM and Draw New Frame";case"render":return e.event.name}})()}),"render"===e.kind&&!(a=e.event).wasFiberRenderMount&&!a.hasMemoCache&&0===a.changes.context.length&&0===a.changes.props.length&&0===a.changes.state.length&&(0,oN.jsx)("div",{style:{lineHeight:"10px"},className:ez(["px-1 py-0.5 bg-[#6a369e] flex items-center rounded-sm font-semibold text-[8px] shrink-0"]),children:"Memoizable"})]})})]}),(0,oN.jsxs)("button",{onClick:()=>"render"===e.kind&&!u&&d(!c),className:ez(["flex items-center min-w-fit shrink-0 rounded-r-md h-[28px]",!u&&"hover:bg-[#0f0f0f]","render"!==e.kind||u?"cursor-default":"cursor-pointer"]),children:[(0,oN.jsx)("div",{className:"w-[20px] flex items-center justify-center",children:"render"===e.kind&&!u&&(0,oN.jsx)(nJ,{className:ez("transition-transform",c&&"rotate-90"),size:16})}),(0,oN.jsxs)("div",{style:{minWidth:u?"fit-content":n?"30px":"60px"},className:"flex items-center justify-end gap-x-1",children:["render"===e.kind&&(0,oN.jsxs)("span",{className:ez(["text-[10px]"]),children:["x",e.event.count]}),("render"!==e.kind||!n)&&(0,oN.jsxs)("span",{className:"text-[10px] text-[#7346a0] pr-1",children:[e.totalTime<1?"<1":e.totalTime.toFixed(0),"ms"]})]})]}),0===i&&(0,oN.jsx)("div",{className:ez(["absolute right-0 top-1/2 transition-none -translate-y-1/2 bg-white text-black px-2 py-1 rounded text-xs opacity-0 group-hover:opacity-100 transition-opacity mr-16","pointer-events-none"]),children:"Click to learn more"})]}),c&&(p.length>0||h.length>0)&&(0,oN.jsxs)("div",{className:"pl-3 flex flex-col gap-y-1 mt-1",children:[p.toSorted((e,t)=>t.totalTime-e.totalTime).map((e,a)=>(0,oN.jsx)(oz,{depth:i+1,bar:e,debouncedMouseEnter:t,totalBarTime:r,isProduction:n,bars:o},a)),h.map(e=>(0,oN.jsx)("div",{className:"w-full",children:(0,oN.jsx)("div",{className:"w-full flex items-center relative text-xs",children:(0,oN.jsxs)("div",{className:"h-full w-full flex items-center relative",children:[(0,oN.jsx)("div",{className:"flex items-center rounded-sm text-white text-xs h-[28px] w-full"}),(0,oN.jsx)("div",{className:"absolute inset-0 flex items-center px-2",children:(0,oN.jsx)("span",{className:"truncate whitespace-nowrap text-white/70 w-full",children:e})})]})})},e))]})]})},oR=r(45994),oF=r(10201),oM=({selectedEvent:e,selectedFiber:t})=>{let{setRoute:r}=nX(),[n,o]=(0,oR.useState)(!0),[i]=(0,oR.useState)(iR());(0,oR.useLayoutEffect)(()=>{let e=localStorage.getItem("react-scan-tip-shown"),t="true"===e||"false"!==e&&null;if(null===t){o(!0),localStorage.setItem("react-scan-tip-is-shown","true");return}t||o(!1)},[]);let a=0===t.changes.context.length&&0===t.changes.props.length&&0===t.changes.state.length;return(0,oF.jsxs)("div",{className:ez(["w-full min-h-fit h-full flex flex-col py-4 pt-0 rounded-sm"]),children:[(0,oF.jsxs)("div",{className:ez(["flex items-start gap-x-4 "]),children:[(0,oF.jsxs)("button",{onClick:()=>{r({route:"render-visualization",routeMessage:null})},className:ez(["text-white hover:bg-[#34343b] flex gap-x-1 justify-center items-center mb-4 w-fit px-2.5 py-1.5 text-xs rounded-sm bg-[#18181B]"]),children:[(0,oF.jsx)(n1,{size:14})," ",(0,oF.jsx)("span",{children:"Overview"})]}),(0,oF.jsxs)("div",{className:ez(["flex flex-col gap-y-1"]),children:[(0,oF.jsx)("div",{className:ez(["text-sm font-bold text-white overflow-x-hidden"]),children:(0,oF.jsx)("div",{className:"flex items-center gap-x-2 truncate",children:t.name})}),(0,oF.jsxs)("div",{className:ez(["flex gap-x-2"]),children:[!i&&(0,oF.jsx)(oF.Fragment,{children:(0,oF.jsxs)("div",{className:ez(["text-xs text-gray-400"]),children:["\u2022 Render time: ",t.totalTime.toFixed(0),"ms"]})}),(0,oF.jsxs)("div",{className:ez(["text-xs text-gray-400 mb-4"]),children:["\u2022 Renders: ",t.count,"x"]})]})]})]}),n&&!a&&(0,oF.jsxs)("div",{className:ez(["w-full mb-4 bg-[#0A0A0A] border border-[#27272A] rounded-sm overflow-hidden flex relative"]),children:[(0,oF.jsx)("button",{onClick:()=>{o(!1),localStorage.setItem("react-scan-tip-shown","false")},className:ez(["absolute right-2 top-2 rounded-sm p-1 hover:bg-[#18181B]"]),children:(0,oF.jsx)(nZ,{size:12})}),(0,oF.jsx)("div",{className:ez(["w-1 bg-[#d36cff]"])}),(0,oF.jsxs)("div",{className:ez(["flex-1"]),children:[(0,oF.jsx)("div",{className:ez(["px-3 py-2 text-gray-100 text-xs font-semibold"]),children:"How to stop renders"}),(0,oF.jsx)("div",{className:ez(["px-3 pb-2 text-gray-400 text-[10px]"]),children:"Stop the following props, state and context from changing between renders, and wrap the component in React.memo if not already"})]})]}),a&&(0,oF.jsxs)("div",{className:ez(["w-full mb-4 bg-[#0A0A0A] border border-[#27272A] rounded-sm overflow-hidden flex"]),children:[(0,oF.jsx)("div",{className:ez(["w-1 bg-[#d36cff]"])}),(0,oF.jsxs)("div",{className:ez(["flex-1"]),children:[(0,oF.jsx)("div",{className:ez(["px-3 py-2 text-gray-100 text-sm font-semibold"]),children:"No changes detected"}),(0,oF.jsx)("div",{className:ez(["px-3 pb-2 text-gray-400 text-xs"]),children:"This component would not of rendered if it was memoized"})]})]}),(0,oF.jsxs)("div",{className:ez(["flex w-full"]),children:[(0,oF.jsxs)("div",{className:ez(["flex flex-col border border-[#27272A] rounded-l-sm overflow-hidden w-1/3"]),children:[(0,oF.jsx)("div",{className:ez(["text-[14px] font-semibold px-2 py-2 bg-[#18181B] text-white flex justify-center"]),children:"Changed Props"}),t.changes.props.length>0?t.changes.props.toSorted((e,t)=>t.count-e.count).map(e=>(0,oF.jsxs)("div",{className:ez(["flex flex-col justify-between items-center border-t overflow-x-auto border-[#27272A] px-1 py-1 text-wrap bg-[#0A0A0A] text-[10px]"]),children:[(0,oF.jsx)("span",{className:ez(["text-white "]),children:e.name}),(0,oF.jsxs)("div",{className:ez([" text-[8px]  text-[#d36cff] pl-1 py-1 "]),children:[e.count,"/",t.count,"x"]})]},e.name)):(0,oF.jsx)("div",{className:ez(["flex items-center justify-center h-full bg-[#0A0A0A] text-[#A1A1AA] border-t border-[#27272A]"]),children:"No changes"})]}),(0,oF.jsxs)("div",{className:ez(["flex flex-col border border-[#27272A] border-l-0 overflow-hidden w-1/3"]),children:[(0,oF.jsx)("div",{className:ez([" text-[14px] font-semibold px-2 py-2 bg-[#18181B] text-white flex justify-center"]),children:"Changed State"}),t.changes.state.length>0?t.changes.state.toSorted((e,t)=>t.count-e.count).map(e=>(0,oF.jsxs)("div",{className:ez(["flex flex-col justify-between items-center border-t overflow-x-auto border-[#27272A] px-1 py-1 text-wrap bg-[#0A0A0A] text-[10px]"]),children:[(0,oF.jsxs)("span",{className:ez(["text-white "]),children:["index ",e.index]}),(0,oF.jsxs)("div",{className:ez(["rounded-full  text-[#d36cff] pl-1 py-1 text-[8px]"]),children:[e.count,"/",t.count,"x"]})]},e.index)):(0,oF.jsx)("div",{className:ez(["flex items-center justify-center h-full bg-[#0A0A0A] text-[#A1A1AA] border-t border-[#27272A]"]),children:"No changes"})]}),(0,oF.jsxs)("div",{className:ez(["flex flex-col border border-[#27272A] border-l-0 rounded-r-sm overflow-hidden w-1/3"]),children:[(0,oF.jsx)("div",{className:ez([" text-[14px] font-semibold px-2 py-2 bg-[#18181B] text-white flex justify-center"]),children:"Changed Context"}),t.changes.context.length>0?t.changes.context.toSorted((e,t)=>t.count-e.count).map(e=>(0,oF.jsxs)("div",{className:ez(["flex flex-col justify-between items-center border-t  border-[#27272A] px-1 py-1 bg-[#0A0A0A] text-[10px] overflow-x-auto"]),children:[(0,oF.jsx)("span",{className:ez(["text-white "]),children:e.name}),(0,oF.jsxs)("div",{className:ez(["rounded-full text-[#d36cff] pl-1 py-1 text-[8px] text-wrap"]),children:[e.count,"/",t.count,"x"]})]},e.name)):(0,oF.jsx)("div",{className:ez(["flex items-center justify-center h-full bg-[#0A0A0A] text-[#A1A1AA] border-t border-[#27272A] py-2"]),children:"No changes"})]})]})]})},oA=r(10201),oO=()=>{let{notificationState:e,setNotificationState:t}=nX(),[r,n]=(0,n7.useState)("..."),o=(0,n7.useRef)(null);if((0,n7.useEffect)(()=>{let e=setInterval(()=>{n(e=>"..."===e?"":e+".")},500);return()=>clearInterval(e)},[]),!e.selectedEvent)return(0,oA.jsxs)("div",{ref:o,className:ez(["h-full w-full flex flex-col items-center justify-center relative py-2 px-4"]),children:[(0,oA.jsx)("div",{className:ez(["p-2 flex justify-center items-center border-[#27272A] absolute top-0 right-0"]),children:(0,oA.jsx)("button",{onClick:()=>{eL.value={view:"none"}},children:(0,oA.jsx)(nZ,{size:18,className:"text-[#6F6F78]"})})}),(0,oA.jsx)("div",{className:ez(["flex flex-col items-start pt-5 bg-[#0A0A0A] p-5 rounded-sm max-w-md"," shadow-lg"]),children:(0,oA.jsxs)("div",{className:ez(["flex flex-col items-start gap-y-4"]),children:[(0,oA.jsx)("div",{className:ez(["flex items-center"]),children:(0,oA.jsxs)("span",{className:ez(["text-zinc-400 font-medium text-[17px]"]),children:["Scanning for slowdowns",r]})}),0!==e.events.length&&(0,oA.jsxs)("p",{className:ez(["text-xs"]),children:["Click on an item in the"," ",(0,oA.jsx)("span",{className:ez(["text-purple-400"]),children:"History"})," list to get started"]}),(0,oA.jsx)("p",{className:ez(["text-zinc-600 text-xs"]),children:"You don't need to keep this panel open for React Scan to record slowdowns"}),(0,oA.jsx)("p",{className:ez(["text-zinc-600 text-xs"]),children:"Enable audio alerts to hear a delightful ding every time a large slowdown is recorded"}),(0,oA.jsx)("button",{onClick:()=>{if(e.audioNotificationsOptions.enabled)return void t(e=>(e.audioNotificationsOptions.audioContext?.state!=="closed"&&e.audioNotificationsOptions.audioContext?.close(),localStorage.setItem("react-scan-notifications-audio","false"),{...e,audioNotificationsOptions:{audioContext:null,enabled:!1}}));localStorage.setItem("react-scan-notifications-audio","true");let r=new AudioContext;z(r),t(e=>({...e,audioNotificationsOptions:{enabled:!0,audioContext:r}}))},className:ez(["px-4 py-2 bg-zinc-800 hover:bg-zinc-700 rounded-sm w-full"," text-sm flex items-center gap-x-2 justify-center"]),children:e.audioNotificationsOptions.enabled?(0,oA.jsx)(oA.Fragment,{children:(0,oA.jsx)("span",{className:"flex items-center gap-x-1",children:"Disable audio alerts"})}):(0,oA.jsx)(oA.Fragment,{children:(0,oA.jsx)("span",{className:"flex items-center gap-x-1",children:"Enable audio alerts"})})})]})})]});switch(e.route){case"render-visualization":return(0,oA.jsx)(oP,{children:(0,oA.jsx)(oE,{selectedEvent:e.selectedEvent})});case"render-explanation":if(!e.selectedFiber)throw Error("Invariant: must have selected fiber when viewing render explanation");return(0,oA.jsx)(oP,{children:(0,oA.jsx)(oM,{selectedFiber:e.selectedFiber,selectedEvent:e.selectedEvent})});case"other-visualization":return(0,oA.jsx)(oP,{children:(0,oA.jsx)("div",{className:ez(["flex w-full h-full flex-col overflow-y-auto"]),id:"overview-scroll-container",children:(0,oA.jsx)(ou,{selectedEvent:e.selectedEvent})})});case"optimize":return(0,oA.jsx)(oP,{children:(0,oA.jsx)(ol,{selectedEvent:e.selectedEvent})})}e.route},oP=({children:e})=>{let{notificationState:t}=nX();if(!t.selectedEvent)throw Error("Invariant: d must have selected event when viewing render explanation");return(0,oA.jsxs)("div",{className:ez(["w-full h-full flex flex-col gap-y-2"]),children:[(0,oA.jsx)("div",{className:ez(["h-[50px] w-full"]),children:(0,oA.jsx)(on,{selectedEvent:t.selectedEvent})}),(0,oA.jsx)("div",{className:ez(["h-calc(100%-50px) flex flex-col overflow-y-auto px-3"]),children:e})]})},oD=r(10201),oI=({selectedEvent:e})=>{let t=nV(e);switch(e.kind){case"interaction":return(0,oD.jsx)("div",{className:ez(["w-full flex border-b border-[#27272A] min-h-[48px]"]),children:(0,oD.jsxs)("div",{className:ez(["min-w-fit w-full justify-start flex items-center border-r border-[#27272A] pl-5 pr-2 text-sm gap-x-4"]),children:[(0,oD.jsxs)("div",{className:ez(["flex items-center gap-x-2 "]),children:[(0,oD.jsx)("span",{className:ez(["text-[#5a5a5a] mr-0.5"]),children:"click"===e.type?"Clicked ":"Typed in "}),(0,oD.jsx)("span",{children:nB(e.componentPath)}),(0,oD.jsxs)("div",{className:ez(["w-fit flex items-center justify-center h-fit text-white px-1 rounded-sm font-semibold text-[10px] whitespace-nowrap","low"===t&&"bg-green-500/50","needs-improvement"===t&&"bg-[#b77116]","high"===t&&"bg-[#b94040]"]),children:[nW(e.timing).toFixed(0),"ms processing time"]})]}),(0,oD.jsx)("div",{className:ez(["flex items-center gap-x-2  justify-end ml-auto"]),children:(0,oD.jsx)("div",{className:ez(["p-2 flex justify-center items-center border-[#27272A]"]),children:(0,oD.jsx)("button",{onClick:()=>{eL.value={view:"none"}},title:"Close",children:(0,oD.jsx)(nZ,{size:18,className:"text-[#6F6F78]"})})})})]})});case"dropped-frames":return(0,oD.jsx)("div",{className:ez(["w-full flex border-b border-[#27272A] min-h-[48px]"]),children:(0,oD.jsxs)("div",{className:ez(["min-w-fit w-full justify-start flex items-center border-r border-[#27272A] pl-5 pr-2 text-sm gap-x-4"]),children:[(0,oD.jsxs)("div",{className:ez(["flex items-center gap-x-2 "]),children:["FPS Drop",(0,oD.jsxs)("div",{className:ez(["w-fit flex items-center justify-center h-fit text-white px-1 rounded-sm font-semibold text-[10px] whitespace-nowrap","low"===t&&"bg-green-500/50","needs-improvement"===t&&"bg-[#b77116]","high"===t&&"bg-[#b94040]"]),children:["dropped to ",e.fps," FPS"]})]}),(0,oD.jsx)("div",{className:ez(["flex items-center gap-x-2 w-2/4 justify-end ml-auto"]),children:(0,oD.jsx)("div",{className:ez(["p-2 flex justify-center items-center border-[#27272A]"]),children:(0,oD.jsx)("button",{onClick:()=>{eL.value={view:"none"}},children:(0,oD.jsx)(nZ,{size:18,className:"text-[#6F6F78]"})})})})]})})}},o$=r(17402),oL=r(45994),oH=r(10201),oU=({item:e,shouldFlash:t})=>{let[r,n]=(0,oL.useState)(!1),o=e.events.map(nV).reduce((e,t)=>{switch(t){case"high":return"high";case"needs-improvement":return"high"===e?"high":"needs-improvement";case"low":return e}},"low"),i=(({flashingItemsCount:e,totalEvents:t})=>{let[r,n]=(0,oL.useState)(!1),o=(0,oL.useRef)(0),i=(0,oL.useRef)(0);return(0,oL.useEffect)(()=>{if(o.current>=t)return;let e=Date.now()-i.current;if(e>=250){n(!1);let e=setTimeout(()=>{o.current=t,i.current=Date.now(),n(!0),setTimeout(()=>{n(!1)},2e3)},50);return()=>clearTimeout(e)}{let r=setTimeout(()=>{n(!1),setTimeout(()=>{o.current=t,i.current=Date.now(),n(!0),setTimeout(()=>{n(!1)},2e3)},50)},250-e);return()=>clearTimeout(r)}},[e]),r})({flashingItemsCount:e.events.reduce((e,r)=>t(r.id)?e+1:e,0),totalEvents:e.events.length});return(0,oH.jsxs)("div",{className:ez(["flex flex-col gap-y-0.5"]),children:[(0,oH.jsxs)("button",{onClick:()=>n(e=>!e),className:ez(["pl-2 py-1.5  text-sm flex items-center rounded-sm hover:bg-[#18181B] relative overflow-hidden",i&&!r&&"after:absolute after:inset-0 after:bg-purple-500/30 after:animate-[fadeOut_1s_ease-out_forwards]"]),children:[(0,oH.jsxs)("div",{className:ez(["w-4/5 flex items-center justify-start h-full text-xs truncate gap-x-1.5"]),children:[(0,oH.jsx)("span",{className:ez(["min-w-fit"]),children:(0,oH.jsx)(nJ,{className:ez(["text-[#A1A1AA] transition-transform",r?"rotate-90":""]),size:14},`chevron-${e.timestamp}`)}),(0,oH.jsx)("span",{className:ez(["text-xs"]),children:"collapsed-frame-drops"===e.kind?"FPS Drops":nB(e.events.at(0)?.componentPath??[])})]}),(0,oH.jsx)("div",{className:ez(["ml-auto min-w-fit flex justify-end items-center"]),children:(0,oH.jsxs)("div",{style:{lineHeight:"10px"},className:ez(["w-fit flex items-center text-[10px] justify-center h-full text-white px-1 py-1 rounded-sm font-semibold","low"===o&&"bg-green-500/60","needs-improvement"===o&&"bg-[#b77116] text-[10px]","high"===o&&"bg-[#b94040]"]),children:["x",e.events.length]})})]}),r&&(0,oH.jsx)(oY,{children:e.events.toSorted((e,t)=>t.timestamp-e.timestamp).map(e=>(0,oH.jsx)(oW,{event:e,shouldFlash:t(e.id)}))})]})},oY=({children:e})=>(0,oH.jsxs)("div",{className:"relative pl-6 flex flex-col gap-y-1",children:[(0,oH.jsx)("div",{className:"absolute left-3 top-0 bottom-0 w-px bg-[#27272A]"}),e]}),oB=r(10201),oW=({event:e,shouldFlash:t})=>{let{notificationState:r,setNotificationState:n}=nX(),o=nV(e),i=(({shouldFlash:e})=>{let[t,r]=(0,o$.useState)(e);return(0,o$.useEffect)(()=>{if(e){r(!0);let e=setTimeout(()=>{r(!1)},1e3);return()=>clearTimeout(e)}},[e]),t})({shouldFlash:t});switch(e.kind){case"interaction":return(0,oB.jsxs)("button",{onClick:()=>{n(t=>({...t,selectedEvent:e,route:"render-visualization",selectedFiber:null}))},className:ez(["pl-2 py-1.5  text-sm flex w-full items-center rounded-sm hover:bg-[#18181B] relative overflow-hidden",e.id===r.selectedEvent?.id&&"bg-[#18181B]",i&&"after:absolute after:inset-0 after:bg-purple-500/30 after:animate-[fadeOut_1s_ease-out_forwards]"]),children:[(0,oB.jsxs)("div",{className:ez(["w-4/5 flex items-center justify-start h-full gap-x-1.5"]),children:[(0,oB.jsx)("span",{className:ez(["min-w-fit text-xs"]),children:(()=>{switch(e.type){case"click":return(0,oB.jsx)(n2,{size:14});case"keyboard":return(0,oB.jsx)(n4,{size:14})}})()}),(0,oB.jsx)("span",{className:ez(["text-xs pr-1 truncate"]),children:nB(e.componentPath)})]}),(0,oB.jsx)("div",{className:ez([" min-w-fit flex justify-end items-center ml-auto"]),children:(0,oB.jsx)("div",{style:{lineHeight:"10px"},className:ez(["gap-x-0.5 w-fit flex items-end justify-center h-full text-white px-1 py-1 rounded-sm font-semibold text-[10px]","low"===o&&"bg-green-500/50","needs-improvement"===o&&"bg-[#b77116] text-[10px]","high"===o&&"bg-[#b94040]"]),children:(0,oB.jsxs)("div",{style:{lineHeight:"10px"},className:ez(["text-[10px] text-white flex items-end"]),children:[nW(e.timing).toFixed(0),"ms"]})})})]});case"dropped-frames":return(0,oB.jsxs)("button",{onClick:()=>{n(t=>({...t,selectedEvent:e,route:"render-visualization",selectedFiber:null}))},className:ez(["pl-2 py-1.5  w-full text-sm flex items-center rounded-sm hover:bg-[#18181B] relative overflow-hidden",e.id===r.selectedEvent?.id&&"bg-[#18181B]",i&&"after:absolute after:inset-0 after:bg-purple-500/30 after:animate-[fadeOut_1s_ease-out_forwards]"]),children:[(0,oB.jsxs)("div",{className:ez(["w-4/5 flex items-center justify-start h-full text-xs truncate"]),children:[(0,oB.jsx)(n3,{size:14,className:"mr-1.5"})," FPS Drop"]}),(0,oB.jsx)("div",{className:ez([" min-w-fit flex justify-end items-center ml-auto"]),children:(0,oB.jsxs)("div",{style:{lineHeight:"10px"},className:ez(["w-fit flex items-center justify-center h-full text-white px-1 py-1 rounded-sm text-[10px] font-bold","low"===o&&"bg-green-500/60","needs-improvement"===o&&"bg-[#b77116] text-[10px]","high"===o&&"bg-[#b94040]"]),children:[e.fps," FPS"]})})]})}},oV=(e=150)=>{let{notificationState:t}=nX(),[r,n]=(0,o$.useState)(t.events);return(0,o$.useEffect)(()=>{setTimeout(()=>{n(t.events)},e)},[t.events]),[r,n]},oX=()=>{let{notificationState:e,setNotificationState:t}=nX(),r=(e=>{let t=(0,o$.useRef)([]),[r,n]=(0,o$.useState)(new Set),o=(0,o$.useRef)(!0);return(0,o$.useEffect)(()=>{if(o.current){o.current=!1,t.current=e;return}let r=new Set(e.map(e=>e.id)),i=new Set(t.current.map(e=>e.id)),a=new Set;r.forEach(e=>{i.has(e)||a.add(e)}),a.size>0&&(n(a),setTimeout(()=>{n(new Set)},2e3)),t.current=e},[e]),e=>r.has(e)})(e.events),[n,o]=oV(),i=n.reduce((e,t)=>{let r=e.at(-1);if(!r)return[{kind:"single",event:t,timestamp:t.timestamp}];switch(r.kind){case"collapsed-keyboard":if("interaction"===t.kind&&"keyboard"===t.type&&t.componentPath.join("-")===r.events[0].componentPath.join("-"))return[...e.filter(e=>e!==r),{kind:"collapsed-keyboard",events:[...r.events,t],timestamp:Math.max(...[...r.events,t].map(e=>e.timestamp))}];return[...e,{kind:"single",event:t,timestamp:t.timestamp}];case"single":if("interaction"===r.event.kind&&"keyboard"===r.event.type&&"interaction"===t.kind&&"keyboard"===t.type&&r.event.componentPath.join("-")===t.componentPath.join("-"))return[...e.filter(e=>e!==r),{kind:"collapsed-keyboard",events:[r.event,t],timestamp:Math.max(r.event.timestamp,t.timestamp)}];if("dropped-frames"===r.event.kind&&"dropped-frames"===t.kind)return[...e.filter(e=>e!==r),{kind:"collapsed-frame-drops",events:[r.event,t],timestamp:Math.max(r.event.timestamp,t.timestamp)}];return[...e,{kind:"single",event:t,timestamp:t.timestamp}];case"collapsed-frame-drops":if("dropped-frames"===t.kind)return[...e.filter(e=>e!==r),{kind:"collapsed-frame-drops",events:[...r.events,t],timestamp:Math.max(...[...r.events,t].map(e=>e.timestamp))}];return[...e,{kind:"single",event:t,timestamp:t.timestamp}]}},[]).toSorted((e,t)=>t.timestamp-e.timestamp);return(0,oB.jsxs)("div",{className:ez(["w-full h-full gap-y-2 flex flex-col border-r border-[#27272A] overflow-y-auto"]),children:[(0,oB.jsxs)("div",{className:ez(["text-sm text-[#65656D] pl-3 pr-1 w-full flex items-center justify-between"]),children:[(0,oB.jsx)("span",{children:"History"}),(0,oB.jsx)(ot,{wrapperProps:{className:"h-full flex items-center justify-center ml-auto"},triggerContent:(0,oB.jsx)("button",{className:ez(["hover:bg-[#18181B] rounded-full p-2"]),title:"Clear all events",onClick:()=>{n$.getState().actions.clear(),t(e=>({...e,selectedEvent:null,selectedFiber:null,route:"other-visualization"===e.route?"other-visualization":"render-visualization"})),o([])},children:(0,oB.jsx)(n5,{className:ez([""]),size:16})}),children:(0,oB.jsx)("div",{className:ez(["w-full flex justify-center"]),children:"Clear all events"})})]}),(0,oB.jsxs)("div",{className:ez(["flex flex-col px-1 gap-y-1"]),children:[0===i.length&&(0,oB.jsx)("div",{className:ez(["flex items-center justify-center text-zinc-500 text-sm py-4"]),children:"No Events"}),i.map(e=>(()=>{switch(e.kind){case"collapsed-keyboard":case"collapsed-frame-drops":return(0,oB.jsx)(oU,{shouldFlash:r,item:e});case"single":return(0,oB.jsx)(oW,{event:e.event,shouldFlash:r(e.event.id)},e.event.id)}})())]})]})},oq=r(10201),oG=()=>{let e=(0,nc.useSyncExternalStore)(n$.subscribe,n$.getState),t=[];return(0,n8.useEffect)(()=>{let e=setInterval(()=>{t.forEach(e=>{e.groupedFiberRenders&&e.groupedFiberRenders.forEach(e=>{if(e.deletedAll)return;if(!e.elements||0===e.elements.length){e.deletedAll=!0;return}let t=e.elements.length;e.elements=e.elements.filter(e=>e&&e.isConnected),0===e.elements.length&&t>0&&(e.deletedAll=!0)})})},5e3);return()=>{clearInterval(e)}},[t]),e.state.events.forEach(e=>{let r=Object.values("interaction"===e.kind?e.data.meta.detailedTiming.fiberRenders:e.data.meta.fiberRenders).map(e=>({id:nd(),totalTime:e.nodeInfo.reduce((e,t)=>e+t.selfTime,0),count:e.nodeInfo.length,name:e.nodeInfo[0].name,deletedAll:!1,parents:e.parents,hasMemoCache:e.hasMemoCache,wasFiberRenderMount:e.wasFiberRenderMount,elements:e.nodeInfo.map(e=>e.element),changes:{context:e.changes.fiberContext.current.filter(t=>e.changes.fiberContext.changesCounts.get(t.name)).map(t=>({name:String(t.name),count:e.changes.fiberContext.changesCounts.get(t.name)??0})),props:e.changes.fiberProps.current.filter(t=>e.changes.fiberProps.changesCounts.get(t.name)).map(t=>({name:String(t.name),count:e.changes.fiberProps.changesCounts.get(t.name)??0})),state:e.changes.fiberState.current.filter(t=>e.changes.fiberState.changesCounts.get(Number(t.name))).map(t=>({index:t.name,count:e.changes.fiberState.changesCounts.get(Number(t.name))??0}))}})),n=r.reduce((e,t)=>e+t.totalTime,0);switch(e.kind){case"interaction":{let{commitEnd:o,jsEndDetail:i,interactionStartDetail:a,rafStart:s}=e.data.meta.detailedTiming;i-a-n<0&&nu("js time must be longer than render time");let l=Math.max(0,i-a-n),c=Math.max(e.data.meta.latency-(o-a),0);t.push({componentPath:e.data.meta.detailedTiming.componentPath,groupedFiberRenders:r,id:e.id,kind:"interaction",memory:null,timestamp:e.data.startAt,type:"keyboard"===e.data.meta.detailedTiming.interactionType?"keyboard":"click",timing:{renderTime:n,kind:"interaction",otherJSTime:l,framePreparation:s-i,frameConstruction:o-s,frameDraw:c}});return}case"long-render":return void t.push({kind:"dropped-frames",id:e.id,memory:null,timing:{kind:"dropped-frames",renderTime:n,otherTime:e.data.meta.latency},groupedFiberRenders:r,timestamp:e.data.startAt,fps:e.data.meta.fps})}}),t},oJ=()=>{let{notificationState:e,setNotificationState:t}=nX(),r=(0,n8.useRef)(null),n=(0,n8.useRef)(null),o=(0,n8.useRef)(0),[i]=oV(),a=i.filter(e=>"high"===nV(e)).length;return(0,n8.useEffect)(()=>{let e=localStorage.getItem("react-scan-notifications-audio");"false"!==e&&"true"!==e?localStorage.setItem("react-scan-notifications-audio","false"):"false"!==e&&t(e=>e.audioNotificationsOptions.enabled?e:{...e,audioNotificationsOptions:{enabled:!0,audioContext:new AudioContext}})},[]),(0,n8.useEffect)(()=>{let{audioNotificationsOptions:t}=e;!t.enabled||0===a||r.current&&r.current>=a||(n.current&&clearTimeout(n.current),n.current=setTimeout(()=>{z(t.audioContext),r.current=a,o.current=Date.now(),n.current=null},Math.max(0,1e3-(Date.now()-o.current))))},[a]),(0,n8.useEffect)(()=>{0===a&&(r.current=null)},[a]),(0,n8.useEffect)(()=>()=>{n.current&&clearTimeout(n.current)},[]),null},oK=(0,n6.forwardRef)((e,t)=>{let r=oG(),[n,o]=(0,n8.useState)({detailsExpanded:!1,events:r,filterBy:"latest",moreInfoExpanded:!1,route:"render-visualization",selectedEvent:r.toSorted((e,t)=>e.timestamp-t.timestamp).at(-1)??null,selectedFiber:null,routeMessage:null,audioNotificationsOptions:{enabled:!1,audioContext:null}});return n.events=r,(0,oq.jsxs)(nq.Provider,{value:{notificationState:n,setNotificationState:o,setRoute:({route:e,routeMessage:t})=>{o(r=>{let n={...r,route:e,routeMessage:t};switch(e){case"render-visualization":case"optimize":case"other-visualization":return oT(),{...n,selectedFiber:null};case"render-explanation":return oT(),n}})}},children:[(0,oq.jsx)(oJ,{}),(0,oq.jsx)(oZ,{ref:t})]})}),oZ=(0,n6.forwardRef)((e,t)=>{let{notificationState:r}=nX();return(0,oq.jsxs)("div",{ref:t,className:ez(["h-full w-full flex flex-col"]),children:[r.selectedEvent&&(0,oq.jsxs)("div",{className:ez(["w-full h-[48px] flex flex-col",r.moreInfoExpanded&&"h-[235px]",r.moreInfoExpanded&&"dropped-frames"===r.selectedEvent.kind&&"h-[150px]"]),children:[(0,oq.jsx)(oI,{selectedEvent:r.selectedEvent}),r.moreInfoExpanded&&(0,oq.jsx)(oQ,{})]}),(0,oq.jsxs)("div",{className:ez(["flex ",r.selectedEvent?"h-[calc(100%-48px)]":"h-full",r.moreInfoExpanded&&"h-[calc(100%-200px)]",r.moreInfoExpanded&&r.selectedEvent?.kind==="dropped-frames"&&"h-[calc(100%-150px)]"]),children:[(0,oq.jsx)("div",{className:ez(["h-full min-w-[200px]"]),children:(0,oq.jsx)(oX,{})}),(0,oq.jsx)("div",{className:ez(["w-[calc(100%-200px)] h-full overflow-y-auto"]),children:(0,oq.jsx)(oO,{})})]})]})}),oQ=()=>{let{notificationState:e}=nX();if(!e.selectedEvent)throw Error("Invariant must have selected event for more info");let t=e.selectedEvent;return(0,oq.jsx)("div",{className:ez(["px-4 py-2 border-b border-[#27272A] bg-[#18181B]/50 h-[calc(100%-40px)]","dropped-frames"===t.kind&&"h-[calc(100%-25px)]"]),children:(0,oq.jsx)("div",{className:ez(["flex flex-col gap-y-4 h-full"]),children:(()=>{switch(t.kind){case"interaction":return(0,oq.jsxs)(oq.Fragment,{children:[(0,oq.jsxs)("div",{className:ez(["flex items-center gap-x-3"]),children:[(0,oq.jsx)("span",{className:"text-[#6F6F78] text-xs font-medium",children:"click"===t.type?"Clicked component location":"Typed in component location"}),(0,oq.jsx)("div",{className:"font-mono text-[#E4E4E7] flex items-center bg-[#27272A] pl-2 py-1 rounded-sm overflow-x-auto",children:t.componentPath.toReversed().map((e,r)=>(0,oq.jsxs)(oq.Fragment,{children:[(0,oq.jsx)("span",{style:{lineHeight:"14px"},className:"text-[10px] whitespace-nowrap",children:e},e),r<t.componentPath.length-1&&(0,oq.jsx)("span",{className:"text-[#6F6F78] mx-0.5",children:"\u2039"})]}))})]}),(0,oq.jsxs)("div",{className:ez(["flex items-center gap-x-3"]),children:[(0,oq.jsx)("span",{className:"text-[#6F6F78] text-xs font-medium",children:"Total Time"}),(0,oq.jsxs)("span",{className:"text-[#E4E4E7] bg-[#27272A] px-1.5 py-1 rounded-sm text-xs",children:[nW(t.timing).toFixed(0),"ms"]})]}),(0,oq.jsxs)("div",{className:ez(["flex items-center gap-x-3"]),children:[(0,oq.jsx)("span",{className:"text-[#6F6F78] text-xs font-medium",children:"Occurred"}),(0,oq.jsx)("span",{className:"text-[#E4E4E7] bg-[#27272A] px-1.5 py-1 rounded-sm text-xs",children:`${((Date.now()-t.timestamp)/1e3).toFixed(0)}s ago`})]})]});case"dropped-frames":return(0,oq.jsxs)(oq.Fragment,{children:[(0,oq.jsxs)("div",{className:ez(["flex items-center gap-x-3"]),children:[(0,oq.jsx)("span",{className:"text-[#6F6F78] text-xs font-medium",children:"Total Time"}),(0,oq.jsxs)("span",{className:"text-[#E4E4E7] bg-[#27272A] px-1.5 py-1 rounded-sm text-xs",children:[nW(t.timing).toFixed(0),"ms"]})]}),(0,oq.jsxs)("div",{className:ez(["flex items-center gap-x-3"]),children:[(0,oq.jsx)("span",{className:"text-[#6F6F78] text-xs font-medium",children:"Occurred"}),(0,oq.jsx)("span",{className:"text-[#E4E4E7] bg-[#27272A] px-1.5 py-1 rounded-sm text-xs",children:`${((Date.now()-t.timestamp)/1e3).toFixed(0)}s ago`})]})]})}})()})})},o0=r(10201),o1=eY(()=>{let e=oG(),[t,r]=(0,ne.useState)(e);(0,ne.useEffect)(()=>{let t=setTimeout(()=>{r(e)},600);return()=>{clearTimeout(t)}},[e]);let n=ij.inspectState,o="inspecting"===n.value.kind,i="focused"===n.value.kind,[a,s]=(0,ne.useState)([]),l=(0,ne.useCallback)(()=>{switch(ij.inspectState.value.kind){case"inspecting":eL.value={view:"none"},ij.inspectState.value={kind:"inspect-off"};return;case"focused":eL.value={view:"inspector"},ij.inspectState.value={kind:"inspecting",hoveredDomElement:null};return;case"inspect-off":eL.value={view:"none"},ij.inspectState.value={kind:"inspecting",hoveredDomElement:null};return;case"uninitialized":return}},[]),c=(0,ne.useCallback)(e=>{if(e.preventDefault(),e.stopPropagation(),!iC.instrumentation)return;let t=!iC.instrumentation.isPaused.value;iC.instrumentation.isPaused.value=t,eM("react-scan-options",{...eF("react-scan-options"),enabled:!t})},[]);(0,r9.useSignalEffect)(()=>{"uninitialized"===ij.inspectState.value.kind&&(ij.inspectState.value={kind:"inspect-off"})});let d=null,u="#999";return o?(d=(0,o0.jsx)($,{name:"icon-inspect"}),u="#8e61e3"):i?(d=(0,o0.jsx)($,{name:"icon-focus"}),u="#8e61e3"):(d=(0,o0.jsx)($,{name:"icon-inspect"}),u="#999"),(0,ne.useLayoutEffect)(()=>{"notifications"!==eL.value.view||s([...new Set(e.map(e=>e.id)).values()])},[e.length,eL.value.view]),(0,o0.jsxs)("div",{className:"flex max-h-9 min-h-9 flex-1 items-stretch overflow-hidden",children:[(0,o0.jsx)("div",{className:"h-full flex items-center min-w-fit",children:(0,o0.jsx)("button",{type:"button",id:"react-scan-inspect-element",title:"Inspect element",onClick:l,className:"button flex items-center justify-center h-full w-full pl-3 pr-2.5",style:{color:u},children:d})}),(0,o0.jsx)("div",{className:"h-full flex items-center justify-center",children:(0,o0.jsx)("button",{type:"button",id:"react-scan-notifications",title:"Notifications",onClick:()=>{switch("inspect-off"!==ij.inspectState.value.kind&&(ij.inspectState.value={kind:"inspect-off"}),eL.value.view){case"inspector":ij.inspectState.value={kind:"inspect-off"},s([...new Set(e.map(e=>e.id)).values()]),eL.value={view:"notifications"};return;case"notifications":eL.value={view:"none"};return;case"none":s([...new Set(e.map(e=>e.id)).values()]),eL.value={view:"notifications"};return}},className:"button flex items-center justify-center h-full pl-2.5 pr-2.5",style:{color:u},children:(0,o0.jsx)(nK,{events:t.filter(e=>!a.includes(e.id)).map(e=>"high"===nV(e)),size:16,className:ez(["text-[#999]","notifications"===eL.value.view&&"text-[#8E61E3]"])})})}),(0,o0.jsx)(nr,{checked:!iC.instrumentation?.isPaused.value,onChange:c,className:"place-self-center",title:"Outline Re-renders"}),iC.options.value.showFPS&&(0,o0.jsx)(na,{})]})}),o2=r(10201),o4=(0,r0.computed)(()=>"inspecting"===ij.inspectState.value.kind),o5=(0,r0.computed)(()=>ez("relative","flex-1","flex flex-col","rounded-t-lg","overflow-hidden","opacity-100","transition-[opacity]",o4.value&&"opacity-0 duration-0 delay-0")),o3=(0,r0.computed)(()=>"inspector"===eL.value.view),o6=(0,r0.computed)(()=>"notifications"===eL.value.view),o8=()=>(0,o2.jsxs)("div",{className:ez("flex flex-1 flex-col","overflow-hidden z-10","rounded-lg","bg-black","opacity-100","transition-[border-radius]","peer-hover/left:rounded-l-none","peer-hover/right:rounded-r-none","peer-hover/top:rounded-t-none","peer-hover/bottom:rounded-b-none"),children:[(0,o2.jsxs)("div",{className:o5,children:[(0,o2.jsx)(r7,{}),(0,o2.jsxs)("div",{className:ez("relative","flex-1 flex","text-white","bg-[#0A0A0A]","transition-opacity delay-150","overflow-hidden","border-b border-[#222]"),children:[(0,o2.jsx)(o7,{isOpen:o3,children:(0,o2.jsx)(tO,{})}),(0,o2.jsx)(o7,{isOpen:o6,children:(0,o2.jsx)(oK,{})})]})]}),(0,o2.jsx)(o1,{})]}),o7=({isOpen:e,children:t})=>(0,o2.jsx)("div",{className:ez("flex-1","opacity-0","overflow-y-auto overflow-x-hidden","transition-opacity delay-0","pointer-events-none",e.value&&"opacity-100 delay-150 pointer-events-auto"),children:(0,o2.jsx)("div",{className:"absolute inset-0 flex",children:t})}),o9=r(62224),ie=r(45994),it=(e,t,r)=>e+(t-e)*r,ir=r(10201),io={frameInterval:1e3/60,speeds:{fast:.51,slow:.1,off:0}},ii=U&&window.devicePixelRatio||1,ia=()=>{let e=(0,ie.useRef)(null),t=(0,ie.useRef)(null),r=(0,ie.useRef)(null),n=(0,ie.useRef)(null),o=(0,ie.useRef)(null),i=(0,ie.useRef)(0),a=(0,ie.useRef)(),s=(0,ie.useRef)(new Map),l=(0,ie.useRef)(!1),c=(0,ie.useRef)(0),d=(e,t,o,i)=>{if(!r.current)return;let a=r.current;t.clearRect(0,0,e.width,e.height),t.strokeStyle="rgba(142, 97, 227, 0.5)",t.fillStyle="rgba(173, 97, 230, 0.10)","locked"===o?t.setLineDash([]):t.setLineDash([4]),t.lineWidth=1,t.fillRect(a.left,a.top,a.width,a.height),t.strokeRect(a.left,a.top,a.width,a.height),((e,t,r,o)=>{if(!o)return;let i=(o?.type&&(0,o9.getDisplayName)(o.type))??"Unknown";e.save(),e.font="12px system-ui, -apple-system, sans-serif";let a=e.measureText(i).width,s=14*("locked"===r),l=6*("locked"===r),c=t.left,d=t.top-24-4;if(e.fillStyle="rgb(37, 37, 38, .75)",e.beginPath(),e.roundRect(c,d,a+16+s+l,24,3),e.fill(),"locked"===r){let t,r,o,i=c+8,a=d+(24-s)/2+2;e.save(),e.strokeStyle="white",e.fillStyle="white",e.lineWidth=1.5,t=.6*s,r=.5*s,e.beginPath(),e.arc(i+(s-t)/2+t/2,a+r/2,t/2,Math.PI,0,!1),e.stroke(),o=.8*s,e.fillRect(i+(s-o)/2,a+r/2,o,.5*s),e.restore(),n.current={x:i,y:a,width:s,height:s}}else n.current=null;e.fillStyle="white",e.textBaseline="middle";e.fillText(i,c+8+("locked"===r?s+l:0),d+12),e.restore()})(t,a,o,i)},u=async(e,t,n,o)=>{if(!e||!t||!n)return;let{parentCompositeFiber:s}=tU(e),l=await tH(e);s&&l&&((e,t,n,o,s)=>{var l;let u,p,h;if(t.save(),!r.current){r.current=n,d(e,t,o,s),t.restore();return}u=iC.options.value.animationSpeed,p=io.speeds[u]??io.speeds.off,h=a=>{if(a-c.current<io.frameInterval){i.current=requestAnimationFrame(h);return}(c.current=a,r.current)?(r.current={left:it(r.current.left,n.left,p),top:it(r.current.top,n.top,p),width:it(r.current.width,n.width,p),height:it(r.current.height,n.height,p)},d(e,t,o,s),Math.abs(r.current.left-n.left)>.1||Math.abs(r.current.top-n.top)>.1||Math.abs(r.current.width-n.width)>.1||Math.abs(r.current.height-n.height)>.1?i.current=requestAnimationFrame(h):(r.current=n,d(e,t,o,s),cancelAnimationFrame(i.current),t.restore(),l?.())):cancelAnimationFrame(i.current)},cancelAnimationFrame(i.current),clearTimeout(a.current),i.current=requestAnimationFrame(h),a.current=setTimeout(()=>{cancelAnimationFrame(i.current),r.current=n,d(e,t,o,s),t.restore(),l?.()},1e3)})(t,n,l,o,s)},p=t=>{if(!e.current||l.current)return;let i=a=>{if(e.current&&"opacity"===a.propertyName&&l.current){var s;let a;e.current.removeEventListener("transitionend",i),(a=(s=e.current).getContext("2d"))&&a.clearRect(0,0,s.width,s.height),r.current=null,n.current=null,o.current=null,s.classList.remove("fade-in"),l.current=!1,t?.()}},a=s.current.get("fade-out");a&&(a(),s.current.delete("fade-out")),e.current.addEventListener("transitionend",i),s.current.set("fade-out",()=>{e.current?.removeEventListener("transitionend",i)}),l.current=!0,e.current.classList.remove("fade-in"),requestAnimationFrame(()=>{e.current?.classList.add("fade-out")})},h=()=>{e.current&&(l.current=!1,e.current.classList.remove("fade-out"),requestAnimationFrame(()=>{e.current?.classList.add("fade-in")}))},m=eR(n=>{if("inspecting"!==ij.inspectState.peek().kind||!t.current)return;t.current.style.pointerEvents="none";let i=document.elementFromPoint(n?.clientX??0,n?.clientY??0);if(t.current.style.removeProperty("pointer-events"),clearTimeout(a.current),i&&i!==e.current){let{parentCompositeFiber:e}=tU(i);if(e){let t=tV(e);if(t)return void(t!==o.current&&(o.current=t,tW.has(t.tagName)?p():h(),ij.inspectState.value={kind:"inspecting",hoveredDomElement:t}))}}r.current&&e.current&&!l.current&&p()},32),f=(e,t)=>{let r=n.current;if(!r)return!1;let o=t.getBoundingClientRect(),i=t.width/o.width,a=t.height/o.height,s=(e.clientX-o.left)*i,l=(e.clientY-o.top)*a,c=s/ii,d=l/ii;return c>=r.x&&c<=r.x+r.width&&d>=r.y&&d<=r.y+r.height},g=r=>{if(r.__reactScanSyntheticEvent)return;let n=ij.inspectState.peek(),i=e.current;if(i&&t.current){if(f(r,i)){r.preventDefault(),r.stopPropagation(),"focused"===n.kind&&(ij.inspectState.value={kind:"inspecting",hoveredDomElement:n.focusedDomElement});return}"inspecting"===n.kind&&(e=>{let t=["react-scan-inspect-element","react-scan-power"];if(e.target instanceof HTMLElement&&t.includes(e.target.id))return;let r=o.current?.tagName;if(r&&tW.has(r))return;e.preventDefault(),e.stopPropagation();let n=o.current??document.elementFromPoint(e.clientX,e.clientY);if(!n)return;let i=e.composedPath().at(0);if(i instanceof HTMLElement&&t.includes(i.id)){let t=new MouseEvent(e.type,e);t.__reactScanSyntheticEvent=!0,i.dispatchEvent(t);return}let{parentCompositeFiber:a}=tU(n);if(!a)return;let s=tV(a);if(!s){o.current=null,ij.inspectState.value={kind:"inspect-off"};return}ij.inspectState.value={kind:"focused",focusedDomElement:s,fiber:a}})(r)}},x=t=>{if("Escape"!==t.key)return;let n=ij.inspectState.peek();if(e.current&&document.activeElement?.id!=="react-scan-root"&&(eL.value={view:"none"},"focused"===n.kind||"inspecting"===n.kind))switch(t.preventDefault(),t.stopPropagation(),n.kind){case"focused":h(),r.current=null,o.current=n.focusedDomElement,ij.inspectState.value={kind:"inspecting",hoveredDomElement:n.focusedDomElement};break;case"inspecting":p(()=>{eO.value=!1,ij.inspectState.value={kind:"inspect-off"}})}},b=(e,t)=>{let r=e.getBoundingClientRect();e.width=r.width*ii,e.height=r.height*ii,t.scale(ii,ii),t.save()},w=()=>{let t=ij.inspectState.peek(),n=e.current;if(!n)return;let o=n?.getContext("2d");o&&(cancelAnimationFrame(i.current),clearTimeout(a.current),b(n,o),r.current=null,"focused"===t.kind&&t.focusedDomElement?u(t.focusedDomElement,n,o,"locked"):"inspecting"===t.kind&&t.hoveredDomElement&&u(t.hoveredDomElement,n,o,"inspecting"))},v=t=>{let r=ij.inspectState.peek(),n=e.current;n&&("inspecting"===r.kind||f(t,n))&&(t.preventDefault(),t.stopPropagation(),t.stopImmediatePropagation())};return(0,ie.useEffect)(()=>{let n=e.current;if(!n)return;let l=n?.getContext("2d");if(!l)return;b(n,l);let c=ij.inspectState.subscribe(e=>{((e,n,a)=>{let l;switch(s.current.get(e.kind)?.(),t.current&&"inspecting"!==e.kind&&(t.current.style.pointerEvents="none"),i.current&&cancelAnimationFrame(i.current),e.kind){case"inspect-off":p();return;case"inspecting":u(e.hoveredDomElement,n,a,"inspecting");break;case"focused":if(!e.focusedDomElement)return;o.current!==e.focusedDomElement&&(o.current=e.focusedDomElement),eL.value={view:"inspector"},u(e.focusedDomElement,n,a,"locked"),(l=ij.lastReportTime.subscribe(()=>{if(i.current&&r.current){let{parentCompositeFiber:t}=tU(e.focusedDomElement);t&&u(e.focusedDomElement,n,a,"locked")}}))&&s.current.set(e.kind,l)}})(e,n,l)});return window.addEventListener("scroll",w,{passive:!0}),window.addEventListener("resize",w,{passive:!0}),document.addEventListener("pointermove",m,{passive:!0,capture:!0}),document.addEventListener("pointerdown",v,{capture:!0}),document.addEventListener("click",g,{capture:!0}),document.addEventListener("keydown",x,{capture:!0}),()=>{for(let e of s.current.values())e?.();c(),window.removeEventListener("scroll",w),window.removeEventListener("resize",w),document.removeEventListener("pointermove",m,{capture:!0}),document.removeEventListener("click",g,{capture:!0}),document.removeEventListener("pointerdown",v,{capture:!0}),document.removeEventListener("keydown",x,{capture:!0}),i.current&&cancelAnimationFrame(i.current),clearTimeout(a.current)}},[]),(0,ir.jsxs)(ir.Fragment,{children:[(0,ir.jsx)("div",{ref:t,className:ez("fixed top-0 left-0 w-screen h-screen","z-[214748365]"),style:{pointerEvents:"none"}}),(0,ir.jsx)("canvas",{ref:e,dir:"ltr",className:ez("react-scan-inspector-overlay","fixed top-0 left-0 w-screen h-screen","pointer-events-none","z-[214748367]")})]})},is=class{constructor(e,t){this.width=e,this.height=t,this.maxWidth=e-48,this.maxHeight=t-48}rightEdge(e){return this.width-e-24}bottomEdge(e){return this.height-e-24}isFullWidth(e){return e>=this.maxWidth}isFullHeight(e){return e>=this.maxHeight}},il=()=>{let e=window.innerWidth,t=window.innerHeight;return d&&d.width===e&&d.height===t?d:d=new is(e,t)},ic=(e,t,r)=>{let n,o,i="rtl"===getComputedStyle(document.body).direction,a=window.innerWidth,s=window.innerHeight,l=550===t,c=l?t:Math.min(t,a-48),d=l?r:Math.min(r,s-48),u=a-c-24,p=s-d-24;switch(e){case"top-right":n=i?-24:u,o=24;break;case"bottom-right":n=i?-24:u,o=p;break;case"bottom-left":n=i?-u:24,o=p;break;case"top-left":n=i?-u:24,o=24;break;default:n=24,o=24}return l&&(n=i?Math.min(-24,Math.max(n,-u)):Math.max(24,Math.min(n,u)),o=Math.max(24,Math.min(o,p))),{x:n,y:o}},id=(e,t,r)=>{let n=r?il().maxWidth:il().maxHeight;return Math.min(Math.max(r?550:400,e+t),n)},iu=r(45994),ip=r(10201),ih=({position:e})=>{let t=(0,iu.useRef)(null),r=(0,iu.useRef)(null),n=(0,iu.useRef)(null),o=(0,iu.useRef)(null);(0,iu.useEffect)(()=>{let i=t.current;if(!i)return;let a=()=>{var t,r,n;i.classList.remove("pointer-events-none");let o="focused"===ij.inspectState.value.kind,a="none"!==eL.value.view;(o||a)&&(t=eI.value.corner,r=eI.value.dimensions.isFullWidth,n=eI.value.dimensions.isFullHeight,r&&n||(r||n?r?e!==t.split("-")[0]:!!n&&e!==t.split("-")[1]:((e,t)=>{let[r,n]=t.split("-");return e!==r&&e!==n})(e,t)))?i.classList.remove("hidden","pointer-events-none","opacity-0"):i.classList.add("hidden","pointer-events-none","opacity-0")},s=eI.subscribe(e=>{(null===r.current||null===n.current||null===o.current||e.dimensions.width!==r.current||e.dimensions.height!==n.current||e.corner!==o.current)&&(a(),r.current=e.dimensions.width,n.current=e.dimensions.height,o.current=e.corner)}),l=ij.inspectState.subscribe(()=>{a()});return()=>{s(),l(),r.current=null,n.current=null,o.current=null}},[]);let i=(0,iu.useCallback)(t=>{t.preventDefault(),t.stopPropagation();let r=eP.value;if(!r)return;let n=r.style,{dimensions:o}=eI.value,i=t.clientX,a=t.clientY,s=o.width,l=o.height,c=o.position;eI.value={...eI.value,dimensions:{...o,isFullWidth:!1,isFullHeight:!1,width:s,height:l,position:c}};let d=null,u=t=>{d||(n.transition="none",d=requestAnimationFrame(()=>{let{newSize:r,newPosition:o}=((e,t,r,n,o)=>{let i="rtl"===getComputedStyle(document.body).direction,a=window.innerWidth-48,s=window.innerHeight-48,l=t.width,c=t.height,d=r.x,u=r.y;if(i&&e.includes("right")){let e=-r.x+t.width-24;l=Math.min(a,Math.max(550,Math.min(t.width+n,e))),d=r.x+(l-t.width)}if(i&&e.includes("left")){let e=window.innerWidth-r.x-24;l=Math.min(a,Math.max(550,Math.min(t.width-n,e)))}if(!i&&e.includes("right")){let e=window.innerWidth-r.x-24;l=Math.min(a,Math.max(550,Math.min(t.width+n,e)))}if(!i&&e.includes("left")){let e=r.x+t.width-24;l=Math.min(a,Math.max(550,Math.min(t.width-n,e))),d=r.x-(l-t.width)}if(e.includes("bottom")){let e=window.innerHeight-r.y-24;c=Math.min(s,Math.max(400,Math.min(t.height+o,e)))}if(e.includes("top")){let e=r.y+t.height-24;c=Math.min(s,Math.max(400,Math.min(t.height-o,e))),u=r.y-(c-t.height)}let p=window.innerWidth-24-l,h=window.innerHeight-24-c;return{newSize:{width:l,height:c},newPosition:{x:d=i?Math.min(-24,Math.max(d,-p)):Math.max(24,Math.min(d,p)),y:u=Math.max(24,Math.min(u,h))}}})(e,{width:s,height:l},c,t.clientX-i,t.clientY-a);n.transform=`translate3d(${o.x}px, ${o.y}px, 0)`,n.width=`${r.width}px`,n.height=`${r.height}px`;let u=Math.min(Math.floor(r.width-120),Math.max(240,eI.value.componentsTree.width));eI.value={...eI.value,dimensions:{isFullWidth:!1,isFullHeight:!1,width:r.width,height:r.height,position:o},componentsTree:{...eI.value.componentsTree,width:u}},d=null}))},p=()=>{d&&(cancelAnimationFrame(d),d=null),document.removeEventListener("pointermove",u),document.removeEventListener("pointerup",p);let{dimensions:e,corner:t}=eI.value,o=il(),i=o.isFullWidth(e.width),a=o.isFullHeight(e.height),s=t;(i&&a||i||a)&&(s=(e=>{let t=il(),r={"top-left":Math.hypot(e.x,e.y),"top-right":Math.hypot(t.maxWidth-e.x,e.y),"bottom-left":Math.hypot(e.x,t.maxHeight-e.y),"bottom-right":Math.hypot(t.maxWidth-e.x,t.maxHeight-e.y)},n="top-left";for(let e in r)r[e]<r[n]&&(n=e);return n})(e.position));let l=ic(s,e.width,e.height),c=()=>{r.removeEventListener("transitionend",c)};r.addEventListener("transitionend",c),n.transform=`translate3d(${l.x}px, ${l.y}px, 0)`,eI.value={...eI.value,corner:s,dimensions:{isFullWidth:i,isFullHeight:a,width:e.width,height:e.height,position:l},lastDimensions:{isFullWidth:i,isFullHeight:a,width:e.width,height:e.height,position:l}},eM(H,{corner:s,dimensions:eI.value.dimensions,lastDimensions:eI.value.lastDimensions,componentsTree:eI.value.componentsTree})};document.addEventListener("pointermove",u,{passive:!0}),document.addEventListener("pointerup",p)},[]),a=(0,iu.useCallback)(t=>{t.preventDefault(),t.stopPropagation();let r=eP.value;if(!r)return;let n=r.style,{dimensions:o,corner:i}=eI.value,a=il(),s=a.isFullWidth(o.width),l=a.isFullHeight(o.height),c=s&&l,d=(s||l)&&!c,u=o.width,p=o.height,h=((e,t,r,n,o)=>{if(r){if("top-left"===e)return"bottom-right";if("top-right"===e)return"bottom-left";if("bottom-left"===e)return"top-right";if("bottom-right"===e)return"top-left";let[r,n]=t.split("-");if("left"===e)return`${r}-right`;if("right"===e)return`${r}-left`;if("top"===e)return`bottom-${n}`;if("bottom"===e)return`top-${n}`}if(n){if("left"===e)return`${t.split("-")[0]}-right`;if("right"===e)return`${t.split("-")[0]}-left`}if(o){if("top"===e)return`bottom-${t.split("-")[1]}`;if("bottom"===e)return`top-${t.split("-")[1]}`}return t})(e,i,c,s,l);"left"===e||"right"===e?(u=s?o.width:a.maxWidth,d&&(u=s?550:a.maxWidth)):(p=l?o.height:a.maxHeight,d&&(p=l?400:a.maxHeight)),c&&("left"===e||"right"===e?u=550:p=400);let m=ic(h,u,p),f={isFullWidth:a.isFullWidth(u),isFullHeight:a.isFullHeight(p),width:u,height:p,position:m},g=Math.floor(u-275),x=eI.value.componentsTree.width,b=Math.floor(.3*u),w=s?240:"left"!==e&&"right"!==e||s?Math.min(g,Math.max(240,x)):Math.min(g,Math.max(240,b));requestAnimationFrame(()=>{eI.value={corner:h,dimensions:f,lastDimensions:o,componentsTree:{...eI.value.componentsTree,width:w}},n.transition="all 0.3s cubic-bezier(0.4, 0, 0.2, 1)",n.width=`${u}px`,n.height=`${p}px`,n.transform=`translate3d(${m.x}px, ${m.y}px, 0)`}),eM(H,{corner:h,dimensions:f,lastDimensions:o,componentsTree:{...eI.value.componentsTree,width:w}})},[]);return(0,ip.jsx)("div",{ref:t,onPointerDown:i,onDblClick:a,className:ez("absolute z-50","flex items-center justify-center","group","transition-colors select-none","peer",{"resize-left peer/left":"left"===e,"resize-right peer/right z-10":"right"===e,"resize-top peer/top":"top"===e,"resize-bottom peer/bottom":"bottom"===e}),children:(0,ip.jsx)("span",{className:"resize-line-wrapper",children:(0,ip.jsx)("span",{className:"resize-line",children:(0,ip.jsx)($,{name:"icon-ellipsis",size:18,className:ez("text-neutral-400",("left"===e||"right"===e)&&"rotate-90")})})})})},im=r(10201),ig=()=>{let e=(0,rQ.useRef)(null),t=(0,rQ.useRef)(!1),r=(0,rQ.useRef)(0),n=(0,rQ.useRef)(0),o=(0,rQ.useCallback)((o=!0)=>{let i,a;if(!e.current)return;let{corner:s}=eI.value;if(t.current){let e=eI.value.lastDimensions;i=id(e.width,0,!0),a=id(e.height,0,!1)}else{let e=eI.value.dimensions;e.width>r.current&&(eI.value={...eI.value,lastDimensions:{isFullWidth:e.isFullWidth,isFullHeight:e.isFullHeight,width:e.width,height:e.height,position:e.position}}),i=r.current,a=n.current}let l=ic(s,i,a),c=i<550||a<400,d=e.current,u=d.style,p=null,h=()=>{e$(),d.removeEventListener("transitionend",h),p&&(cancelAnimationFrame(p),p=null)};d.addEventListener("transitionend",h),u.transition="all 0.3s cubic-bezier(0.4, 0, 0.2, 1)",p=requestAnimationFrame(()=>{u.width=`${i}px`,u.height=`${a}px`,u.transform=`translate3d(${l.x}px, ${l.y}px, 0)`,p=null});let m={isFullWidth:i>=window.innerWidth-48,isFullHeight:a>=window.innerHeight-48,width:i,height:a,position:l};eI.value={corner:s,dimensions:m,lastDimensions:t?eI.value.lastDimensions:i>r.current?m:eI.value.lastDimensions,componentsTree:eI.value.componentsTree},o&&!c&&eM(H,{corner:eI.value.corner,dimensions:eI.value.dimensions,lastDimensions:eI.value.lastDimensions,componentsTree:eI.value.componentsTree}),e$()},[]),i=(0,rQ.useCallback)(t=>{if(t.preventDefault(),!e.current||t.target.closest("button"))return;let r=e.current,n=r.style,{dimensions:o}=eI.value,i=t.clientX,a=t.clientY,s=o.position.x,l=o.position.y,c=s,d=l,u=null,p=!1,h=i,m=a,f=e=>{u||(p=!0,h=e.clientX,m=e.clientY,u=requestAnimationFrame(()=>{let e=h-i,t=m-a;c=Number(s)+e,d=Number(l)+t,n.transition="none",n.transform=`translate3d(${c}px, ${d}px, 0)`,u=null}))},g=()=>{if(!r)return;u&&(cancelAnimationFrame(u),u=null),document.removeEventListener("pointermove",f),document.removeEventListener("pointerup",g);let e=Math.abs(h-i),t=Math.abs(m-a),x=Math.sqrt(e*e+t*t);if(!p||x<60)return;let b=((e,t,r,n,o=100)=>{let i=void 0!==r?e-r:0,a=void 0!==n?t-n:0,s=window.innerWidth/2,l=window.innerHeight/2,c=i>o,d=a>o;if(c||i<-o){let e=t>l;return c?e?"bottom-right":"top-right":e?"bottom-left":"top-left"}if(d||a<-o){let t=e>s;return d?t?"bottom-right":"bottom-left":t?"top-right":"top-left"}return e>s?t>l?"bottom-right":"top-right":t>l?"bottom-left":"top-left"})(h,m,i,a,"focused"===ij.inspectState.value.kind?80:40);if(b===eI.value.corner){n.transition="transform 0.3s cubic-bezier(0.4, 0, 0.2, 1)";let e=eI.value.dimensions.position;requestAnimationFrame(()=>{n.transform=`translate3d(${e.x}px, ${e.y}px, 0)`});return}let w=ic(b,o.width,o.height);if(c===s&&d===l)return;let v=()=>{n.transition="none",e$(),r.removeEventListener("transitionend",v),u&&(cancelAnimationFrame(u),u=null)};r.addEventListener("transitionend",v),n.transition="transform 0.3s cubic-bezier(0.4, 0, 0.2, 1)",requestAnimationFrame(()=>{n.transform=`translate3d(${w.x}px, ${w.y}px, 0)`}),eI.value={corner:b,dimensions:{isFullWidth:o.isFullWidth,isFullHeight:o.isFullHeight,width:o.width,height:o.height,position:w},lastDimensions:eI.value.lastDimensions,componentsTree:eI.value.componentsTree},eM(H,{corner:b,dimensions:eI.value.dimensions,lastDimensions:eI.value.lastDimensions,componentsTree:eI.value.componentsTree})};document.addEventListener("pointermove",f),document.addEventListener("pointerup",g)},[]);(0,rQ.useEffect)(()=>{if(!e.current)return;e.current.style.width="min-content",n.current=36,r.current=e.current.offsetWidth,e.current.style.maxWidth="calc(100vw - 48px)",e.current.style.maxHeight="calc(100vh - 48px)","focused"!==ij.inspectState.value.kind&&(eI.value={...eI.value,dimensions:{isFullWidth:!1,isFullHeight:!1,width:r.current,height:n.current,position:eI.value.dimensions.position}}),eP.value=e.current;let i=eI.subscribe(t=>{if(!e.current)return;let{x:r,y:n}=t.dimensions.position,{width:o,height:i}=t.dimensions,a=e.current;requestAnimationFrame(()=>{a.style.transform=`translate3d(${r}px, ${n}px, 0)`,a.style.width=`${o}px`,a.style.height=`${i}px`})}),a=eL.subscribe(e=>{t.current="none"!==e.view,o()}),s=ij.inspectState.subscribe(e=>{t.current="focused"===e.kind,o()}),l=()=>{o(!0)};return window.addEventListener("resize",l,{passive:!0}),()=>{window.removeEventListener("resize",l),a(),s(),i(),eM(H,{...eD,corner:eI.value.corner})}},[]);let[a,s]=(0,rQ.useState)(!1);return(0,rQ.useEffect)(()=>{s(!0)},[]),(0,im.jsxs)(im.Fragment,{children:[(0,im.jsx)(ia,{}),(0,im.jsx)(ix.Provider,{value:e.current,children:(0,im.jsxs)("div",{id:"react-scan-toolbar",dir:"ltr",ref:e,onPointerDown:i,className:ez("fixed inset-0 rounded-lg shadow-lg","flex flex-col","font-mono text-[13px]","user-select-none","opacity-0","cursor-move","z-[124124124124]","animate-fade-in animation-duration-300 animation-delay-300","will-change-transform","[touch-action:none]"),children:[(0,im.jsx)(ih,{position:"top"}),(0,im.jsx)(ih,{position:"bottom"}),(0,im.jsx)(ih,{position:"left"}),(0,im.jsx)(ih,{position:"right"}),(0,im.jsx)(o8,{})]})})]})},ix=(0,rZ.createContext)(null),ib=r(10201),iw=()=>(0,ib.jsxs)("svg",{xmlns:"http://www.w3.org/2000/svg",style:"display: none;",children:[(0,ib.jsx)("title",{children:"React Scan Icons"}),(0,ib.jsxs)("symbol",{id:"icon-inspect",viewBox:"0 0 24 24",fill:"none","stroke-width":"2","stroke-linecap":"round","stroke-linejoin":"round",children:[(0,ib.jsx)("path",{d:"M12.034 12.681a.498.498 0 0 1 .647-.647l9 3.5a.5.5 0 0 1-.033.943l-3.444 1.068a1 1 0 0 0-.66.66l-1.067 3.443a.5.5 0 0 1-.943.033z"}),(0,ib.jsx)("path",{d:"M5 3a2 2 0 0 0-2 2"}),(0,ib.jsx)("path",{d:"M19 3a2 2 0 0 1 2 2"}),(0,ib.jsx)("path",{d:"M5 21a2 2 0 0 1-2-2"}),(0,ib.jsx)("path",{d:"M9 3h1"}),(0,ib.jsx)("path",{d:"M9 21h2"}),(0,ib.jsx)("path",{d:"M14 3h1"}),(0,ib.jsx)("path",{d:"M3 9v1"}),(0,ib.jsx)("path",{d:"M21 9v2"}),(0,ib.jsx)("path",{d:"M3 14v1"})]}),(0,ib.jsxs)("symbol",{id:"icon-focus",viewBox:"0 0 24 24",fill:"none","stroke-width":"2","stroke-linecap":"round","stroke-linejoin":"round",children:[(0,ib.jsx)("path",{d:"M12.034 12.681a.498.498 0 0 1 .647-.647l9 3.5a.5.5 0 0 1-.033.943l-3.444 1.068a1 1 0 0 0-.66.66l-1.067 3.443a.5.5 0 0 1-.943.033z"}),(0,ib.jsx)("path",{d:"M21 11V5a2 2 0 0 0-2-2H5a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h6"})]}),(0,ib.jsx)("symbol",{id:"icon-next",viewBox:"0 0 24 24",fill:"none","stroke-width":"2","stroke-linecap":"round","stroke-linejoin":"round",children:(0,ib.jsx)("path",{d:"M6 9h6V5l7 7-7 7v-4H6V9z"})}),(0,ib.jsx)("symbol",{id:"icon-previous",viewBox:"0 0 24 24",fill:"none","stroke-width":"2","stroke-linecap":"round","stroke-linejoin":"round",children:(0,ib.jsx)("path",{d:"M18 15h-6v4l-7-7 7-7v4h6v6z"})}),(0,ib.jsxs)("symbol",{id:"icon-close",viewBox:"0 0 24 24",fill:"none","stroke-width":"2","stroke-linecap":"round","stroke-linejoin":"round",children:[(0,ib.jsx)("line",{x1:"18",y1:"6",x2:"6",y2:"18"}),(0,ib.jsx)("line",{x1:"6",y1:"6",x2:"18",y2:"18"})]}),(0,ib.jsxs)("symbol",{id:"icon-replay",viewBox:"0 0 24 24",fill:"none","stroke-width":"2","stroke-linecap":"round","stroke-linejoin":"round",children:[(0,ib.jsx)("path",{d:"M3 7V5a2 2 0 0 1 2-2h2"}),(0,ib.jsx)("path",{d:"M17 3h2a2 2 0 0 1 2 2v2"}),(0,ib.jsx)("path",{d:"M21 17v2a2 2 0 0 1-2 2h-2"}),(0,ib.jsx)("path",{d:"M7 21H5a2 2 0 0 1-2-2v-2"}),(0,ib.jsx)("circle",{cx:"12",cy:"12",r:"1"}),(0,ib.jsx)("path",{d:"M18.944 12.33a1 1 0 0 0 0-.66 7.5 7.5 0 0 0-13.888 0 1 1 0 0 0 0 .66 7.5 7.5 0 0 0 13.888 0"})]}),(0,ib.jsxs)("symbol",{id:"icon-ellipsis",viewBox:"0 0 24 24",fill:"none",stroke:"currentColor","stroke-width":"2","stroke-linecap":"round","stroke-linejoin":"round",children:[(0,ib.jsx)("circle",{cx:"12",cy:"12",r:"1"}),(0,ib.jsx)("circle",{cx:"19",cy:"12",r:"1"}),(0,ib.jsx)("circle",{cx:"5",cy:"12",r:"1"})]}),(0,ib.jsxs)("symbol",{id:"icon-copy",viewBox:"0 0 24 24",fill:"none",stroke:"currentColor","stroke-width":"2","stroke-linecap":"round","stroke-linejoin":"round",children:[(0,ib.jsx)("rect",{width:"14",height:"14",x:"8",y:"8",rx:"2",ry:"2"}),(0,ib.jsx)("path",{d:"M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2"})]}),(0,ib.jsx)("symbol",{id:"icon-check",viewBox:"0 0 24 24",fill:"none",stroke:"currentColor","stroke-width":"2","stroke-linecap":"round","stroke-linejoin":"round",children:(0,ib.jsx)("path",{d:"M20 6 9 17l-5-5"})}),(0,ib.jsx)("symbol",{id:"icon-chevron-right",viewBox:"0 0 24 24",fill:"none",stroke:"currentColor","stroke-width":"2","stroke-linecap":"round","stroke-linejoin":"round",children:(0,ib.jsx)("path",{d:"m9 18 6-6-6-6"})}),(0,ib.jsxs)("symbol",{id:"icon-settings",viewBox:"0 0 24 24",fill:"none",stroke:"currentColor","stroke-width":"2","stroke-linecap":"round","stroke-linejoin":"round",children:[(0,ib.jsx)("path",{d:"M12.22 2h-.44a2 2 0 0 0-2 2v.18a2 2 0 0 1-1 1.73l-.43.25a2 2 0 0 1-2 0l-.15-.08a2 2 0 0 0-2.73.73l-.22.38a2 2 0 0 0 .73 2.73l.15.1a2 2 0 0 1 1 1.72v.51a2 2 0 0 1-1 1.74l-.15.09a2 2 0 0 0-.73 2.73l.22.38a2 2 0 0 0 2.73.73l.15-.08a2 2 0 0 1 2 0l.43.25a2 2 0 0 1 1 1.73V20a2 2 0 0 0 2 2h.44a2 2 0 0 0 2-2v-.18a2 2 0 0 1 1-1.73l.43-.25a2 2 0 0 1 2 0l.15.08a2 2 0 0 0 2.73-.73l.22-.39a2 2 0 0 0-.73-2.73l-.15-.08a2 2 0 0 1-1-1.74v-.5a2 2 0 0 1 1-1.74l.15-.09a2 2 0 0 0 .73-2.73l-.22-.38a2 2 0 0 0-2.73-.73l-.15.08a2 2 0 0 1-2 0l-.43-.25a2 2 0 0 1-1-1.73V4a2 2 0 0 0-2-2z"}),(0,ib.jsx)("circle",{cx:"12",cy:"12",r:"3"})]}),(0,ib.jsx)("symbol",{id:"icon-flame",viewBox:"0 0 24 24",children:(0,ib.jsx)("path",{d:"M8.5 14.5A2.5 2.5 0 0 0 11 12c0-1.38-.5-2-1-3-1.072-2.143-.224-4.054 2-6 .5 2.5 2 4.9 4 6.5 2 1.6 3 3.5 3 5.5a7 7 0 1 1-14 0c0-1.153.433-2.294 1-3a2.5 2.5 0 0 0 2.5 2.5z"})}),(0,ib.jsxs)("symbol",{id:"icon-function",viewBox:"0 0 24 24",fill:"none",stroke:"currentColor","stroke-width":"2","stroke-linecap":"round","stroke-linejoin":"round",children:[(0,ib.jsx)("rect",{width:"18",height:"18",x:"3",y:"3",rx:"2",ry:"2"}),(0,ib.jsx)("path",{d:"M9 17c2 0 2.8-1 2.8-2.8V10c0-2 1-3.3 3.2-3"}),(0,ib.jsx)("path",{d:"M9 11.2h5.7"})]}),(0,ib.jsxs)("symbol",{id:"icon-triangle-alert",viewBox:"0 0 24 24",fill:"none",stroke:"currentColor","stroke-width":"2","stroke-linecap":"round","stroke-linejoin":"round",children:[(0,ib.jsx)("path",{d:"m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3"}),(0,ib.jsx)("path",{d:"M12 9v4"}),(0,ib.jsx)("path",{d:"M12 17h.01"})]}),(0,ib.jsxs)("symbol",{id:"icon-gallery-horizontal-end",viewBox:"0 0 24 24",fill:"none",stroke:"currentColor","stroke-width":"2","stroke-linecap":"round","stroke-linejoin":"round",children:[(0,ib.jsx)("path",{d:"M2 7v10"}),(0,ib.jsx)("path",{d:"M6 5v14"}),(0,ib.jsx)("rect",{width:"12",height:"18",x:"10",y:"3",rx:"2"})]}),(0,ib.jsxs)("symbol",{id:"icon-search",viewBox:"0 0 24 24",fill:"none",stroke:"currentColor","stroke-width":"2","stroke-linecap":"round","stroke-linejoin":"round",children:[(0,ib.jsx)("circle",{cx:"11",cy:"11",r:"8"}),(0,ib.jsx)("line",{x1:"21",y1:"21",x2:"16.65",y2:"16.65"})]}),(0,ib.jsxs)("symbol",{id:"icon-lock",viewBox:"0 0 24 24",fill:"none",stroke:"currentColor","stroke-width":"2","stroke-linecap":"round","stroke-linejoin":"round",children:[(0,ib.jsx)("rect",{width:"18",height:"11",x:"3",y:"11",rx:"2",ry:"2"}),(0,ib.jsx)("path",{d:"M7 11V7a5 5 0 0 1 10 0v4"})]}),(0,ib.jsxs)("symbol",{id:"icon-lock-open",viewBox:"0 0 24 24",fill:"none",stroke:"currentColor","stroke-width":"2","stroke-linecap":"round","stroke-linejoin":"round",children:[(0,ib.jsx)("rect",{width:"18",height:"11",x:"3",y:"11",rx:"2",ry:"2"}),(0,ib.jsx)("path",{d:"M7 11V7a5 5 0 0 1 9.9-1"})]}),(0,ib.jsxs)("symbol",{id:"icon-sanil",viewBox:"0 0 24 24",fill:"none",stroke:"currentColor","stroke-width":"2","stroke-linecap":"round","stroke-linejoin":"round",children:[(0,ib.jsx)("path",{d:"M2 13a6 6 0 1 0 12 0 4 4 0 1 0-8 0 2 2 0 0 0 4 0"}),(0,ib.jsx)("circle",{cx:"10",cy:"13",r:"8"}),(0,ib.jsx)("path",{d:"M2 21h12c4.4 0 8-3.6 8-8V7a2 2 0 1 0-4 0v6"}),(0,ib.jsx)("path",{d:"M18 3 19.1 5.2"})]})]}),iv=r(10201),iy=class extends rK.Component{constructor(){super(...arguments),this.state={hasError:!1,error:null},this.handleReset=()=>{this.setState({hasError:!1,error:null})}}static getDerivedStateFromError(e){return{hasError:!0,error:e}}render(){return this.state.hasError?(0,iv.jsx)("div",{className:"fixed bottom-4 right-4 z-[124124124124]",children:(0,iv.jsxs)("div",{className:"p-3 bg-black rounded-lg shadow-lg w-80",children:[(0,iv.jsxs)("div",{className:"flex items-center gap-2 mb-2 text-red-400 text-sm font-medium",children:[(0,iv.jsx)($,{name:"icon-flame",className:"text-red-500",size:14}),"React Scan ran into a problem"]}),(0,iv.jsx)("div",{className:"p-2 bg-black rounded font-mono text-xs text-red-300 mb-3 break-words",children:this.state.error?.message||JSON.stringify(this.state.error)}),(0,iv.jsx)("button",{type:"button",onClick:this.handleReset,className:"px-3 py-1.5 bg-red-500 hover:bg-red-600 text-white rounded text-xs font-medium transition-colors flex items-center justify-center gap-1.5",children:"Restart"})]})}):this.props.children}},i_=null,ik=null,ij={wasDetailsOpen:(0,_.signal)(!0),isInIframe:(0,_.signal)(U&&window.self!==window.top),inspectState:(0,_.signal)({kind:"uninitialized"}),monitor:(0,_.signal)(null),fiberRoots:new Set,reportData:new Map,legacyReportData:new Map,lastReportTime:(0,_.signal)(0),interactionListeningForRenders:null,changesListeners:new Map},iC={instrumentation:null,componentAllowList:null,options:(0,_.signal)({enabled:!0,log:!1,showToolbar:!0,animationSpeed:"fast",dangerouslyForceRunInProduction:!1,showFPS:!0,showNotificationCount:!0,allowInIframe:!1}),onRender:null,scheduledOutlines:new Map,activeOutlines:new Map,Store:ij,version:"0.3.4"};U&&window.__REACT_SCAN_EXTENSION__&&(window.__REACT_SCAN_VERSION__=iC.version);var iS=e=>{let t=[],r={};for(let n in e){if(!(n in iC.options.value))continue;let o=e[n];switch(n){case"enabled":case"log":case"showToolbar":case"showNotificationCount":case"dangerouslyForceRunInProduction":case"showFPS":case"allowInIframe":"boolean"!=typeof o?t.push(`- ${n} must be a boolean. Got "${o}"`):r[n]=o;break;case"animationSpeed":["slow","fast","off"].includes(o)?r[n]=o:t.push(`- Invalid animation speed "${o}". Using default "fast"`);break;case"onCommitStart":"function"!=typeof o?t.push(`- ${n} must be a function. Got "${o}"`):r.onCommitStart=o;break;case"onCommitFinish":"function"!=typeof o?t.push(`- ${n} must be a function. Got "${o}"`):r.onCommitFinish=o;break;case"onRender":"function"!=typeof o?t.push(`- ${n} must be a function. Got "${o}"`):r.onRender=o;break;case"onPaintStart":case"onPaintFinish":"function"!=typeof o?t.push(`- ${n} must be a function. Got "${o}"`):r[n]=o;break;default:t.push(`- Unknown option "${n}"`)}}return t.length>0&&console.warn(`[React Scan] Invalid options:
${t.join(`
`)}`),r},iN=e=>{if(e){for(let t of Array.from(ij.legacyReportData.values()))if(t.type===e)return t;return null}return ij.legacyReportData},iT=e=>{try{let t=iS(e);if(0===Object.keys(t).length)return;let r="showToolbar"in t&&void 0!==t.showToolbar,n={...iC.options.value,...t},{instrumentation:o}=iC;o&&"enabled"in t&&(o.isPaused.value=!1===t.enabled),iC.options.value=n;try{let e=eF("react-scan-options")?.enabled;"boolean"==typeof e&&(n.enabled=e)}catch(e){"verbose"===iC.options.value._debug&&console.error("[React Scan Internal Error]","Failed to create notifications outline canvas",e)}return eM("react-scan-options",n),r&&iM(!!n.showToolbar),n}catch(e){"verbose"===iC.options.value._debug&&console.error("[React Scan Internal Error]","Failed to create notifications outline canvas",e)}},iE=()=>iC.options,iz=null,iR=()=>{if(null!==iz)return iz;for(let e of(u??=(0,k.getRDTHook)()).renderers.values())"production"===(0,k.detectReactBuildType)(e)&&(iz=!0);return iz},iF=()=>{try{if(!U||iR()&&!iC.options.value.dangerouslyForceRunInProduction)return;let e=eF("react-scan-options");if(e){let t=iS(e);Object.keys(t).length>0&&(iC.options.value={...iC.options.value,...t})}let t=iE();(e=>{var t,r;let n,o;if(globalThis.__REACT_SCAN_STOP__)return;let i=!1,a=()=>{i||(n&&cancelAnimationFrame(n),n=requestAnimationFrame(()=>{i=!0;let t=(()=>{var e;let t,r;(r=document.querySelector("[data-react-scan]"))&&r.remove();let n=document.createElement("div");n.setAttribute("data-react-scan","true");let o=n.attachShadow({mode:"open"}),i=document.createElement("canvas");if(i.style.position="fixed",i.style.top="0",i.style.left="0",i.style.pointerEvents="none",i.style.zIndex="2147483646",i.setAttribute("aria-hidden","true"),o.appendChild(i),!i)return null;rO=rX(),rM=i;let{innerWidth:a,innerHeight:s}=window;i.style.width=`${a}px`,i.style.height=`${s}px`;let l=a*rO,c=s*rO;if(i.width=l,i.height=c,rV&&!window.__REACT_SCAN_EXTENSION__)try{rF=new Worker(URL.createObjectURL(new Blob([rR],{type:"application/javascript"})));let e=i.transferControlToOffscreen();rF?.postMessage({type:"init",canvas:e,width:i.width,height:i.height,dpr:rO},[e])}catch(e){console.warn("Failed to initialize OffscreenCanvas worker:",e)}rF||(e=rO,(t=i.getContext("2d",{alpha:!0}))&&t.scale(e,e),rA=t);let d=!1;window.addEventListener("resize",()=>{d||(d=!0,setTimeout(()=>{let e=window.innerWidth,t=window.innerHeight;rO=rX(),i.style.width=`${e}px`,i.style.height=`${t}px`,rF?rF.postMessage({type:"resize",width:e,height:t,dpr:rO}):(i.width=e*rO,i.height=t*rO,rA&&(rA.resetTransform(),rA.scale(rO,rO)),rW()),d=!1}))});let u=window.scrollX,p=window.scrollY,h=!1;return window.addEventListener("scroll",()=>{h||(h=!0,setTimeout(()=>{let{scrollX:e,scrollY:t}=window,r=e-u,n=t-p;u=e,p=t,rF?rF.postMessage({type:"scroll",deltaX:r,deltaY:n}):requestAnimationFrame(rz.bind(null,rD,r,n)),h=!1},32))}),setInterval(()=>{r$.size&&requestAnimationFrame(rB)},32),o.appendChild(i),n})();t&&document.documentElement.appendChild(t),e()}))},l=(t="react-scan-devtools-0.1.0",r={onCommitStart:()=>{iC.options.value.onCommitStart?.()},onActive:()=>{globalThis.__REACT_SCAN_STOP__||(a(),window.__REACT_SCAN_EXTENSION__||(globalThis.__REACT_SCAN__={ReactScanInternals:iC}),clearInterval(s),s=setInterval(()=>{rq&&(ij.lastReportTime.value=Date.now(),rq=!1)},50),(()=>{if(window.hideIntro){window.hideIntro=void 0;return}console.log("%c[\xb7] %cReact Scan","font-weight:bold;color:#7a68e8;font-size:20px;","font-weight:bold;font-size:14px;"),console.log("Try React Scan Monitoring to target performance issues in production: https://react-scan.com/monitoring")})())},onError:()=>{},isValidFiber:rG,onRender:(e,t)=>{(0,j.isCompositeFiber)(e)&&ij.interactionListeningForRenders?.(e,t);let r=iC.instrumentation?.isPaused.value,n="inspect-off"===ij.inspectState.value.kind||"uninitialized"===ij.inspectState.value.kind;r&&n||(r||(e=>{if(!(0,j.isCompositeFiber)(e))return;let t="string"==typeof e.type?e.type:(0,j.getDisplayName)(e);if(!t)return;let r=rI.get(e),n=(0,j.getNearestHostFibers)(e),o=(0,j.didFiberCommit)(e);r?r.count++:(rI.set(e,{name:t,count:1,elements:n.map(e=>e.stateNode),didCommit:+!!o}),r$.add(e))})(e),iC.options.value.log&&(e=>{let t=new Map;for(let r=0,n=e.length;r<n;r++){let n=e[r];if(!n.componentName)continue;let o=t.get(n.componentName)??[],i=T([{aggregatedCount:1,computedKey:null,name:n.componentName,frame:null,...n,changes:{type:n.changes.reduce((e,t)=>e|t.type,0),unstable:n.changes.some(e=>e.unstable)},phase:n.phase,computedCurrent:null}]);if(!i)continue;let a=null,s=null;if(n.changes)for(let e=0,t=n.changes.length;e<t;e++){let{name:t,prevValue:r,nextValue:i,unstable:l,type:c}=n.changes[e];1===c?(s??={},(a??={})[`${l?"\u26A0\uFE0F":""}${t} (prev)`]=r,s[`${l?"\u26A0\uFE0F":""}${t} (next)`]=i):o.push({prev:r,next:i,type:4===c?"context":"state",unstable:l??!1})}a&&s&&o.push({prev:a,next:s,type:"props",unstable:!1}),t.set(i,o)}for(let[e,r]of Array.from(t.entries())){for(let{type:t,prev:n,next:o,unstable:i}of(console.group(`%c${e}`,"background: hsla(0,0%,70%,.3); border-radius:3px; padding: 0 2px;"),r))console.log(`${t}:`,i?"\u26A0\uFE0F":"",n,"!==",o);console.groupEnd()}})(t),"focused"===ij.inspectState.value.kind&&(eK.value=Date.now()),n||(e=>{if((0,j.isCompositeFiber)(e)&&!1!==iC.options.value.showToolbar&&"focused"===ij.inspectState.value.kind){let{selfTime:t}=(0,j.getTimings)(e),r=(0,j.getDisplayName)(e.type),n=(0,j.getFiberId)(e),o=ij.reportData.get(n),i=o?.count??0,a=o?.time??0,s=ij.changesListeners.get((0,j.getFiberId)(e));if(s?.length){let t,r=tB(e).map(e=>({type:1,name:e.name,value:e.value,prevValue:e.prevValue,unstable:!1})),n=(e=>{if(!e)return[];let t=[];if(e.tag===S.FunctionComponentTag||e.tag===S.ForwardRefTag||e.tag===S.SimpleMemoComponentTag||e.tag===S.MemoComponentTag){let r=e.memoizedState,n=e.alternate?.memoizedState,o=0;for(;r;){if(r.queue&&void 0!==r.memoizedState){let e={type:2,name:o.toString(),value:r.memoizedState,prevValue:n?.memoizedState};E(e.prevValue,e.value)||t.push(e)}r=r.next,n=n?.next,o++}return t}if(e.tag===S.ClassComponentTag){let r={type:3,name:"state",value:e.memoizedState,prevValue:e.alternate?.memoizedState};E(r.prevValue,r.value)||t.push(r)}return t})(e),o=(t=[],(0,S.traverseContexts)(e,rg.bind(t)),t).map(e=>({name:e.name,type:4,value:e.value,contextType:e.contextType}));s.forEach(e=>{e({propsChanges:r,stateChanges:n,contextChanges:o})})}let l={count:i+1,time:a+t||0,renders:[],displayName:r,type:(0,j.getType)(e.type)||null,changes:[]};ij.reportData.set(n,l),rq=!0}})(e),iC.options.value.onRender?.(e,t))},onCommitFinish:()=>{a(),iC.options.value.onCommitFinish?.()},onPostCommitFiberRoot(){a()},trackChanges:!1},o={isPaused:(0,C.signal)(!iC.options.value.enabled),fiberRoots:new WeakSet},rx.set(t,{key:t,config:r,instrumentation:o}),rb||(rb=!0,(0,S.instrument)({name:"react-scan",onActive:r.onActive,onCommitFiberRoot(e,t){o.fiberRoots.add(t);let r=rw();for(let e of r)e.config.onCommitStart();for(let e of((0,S.traverseRenderedFibers)(t.current,(e,t)=>{let r=(0,S.getType)(e.type);if(!r)return null;let n=rw(),o=[];for(let t=0,r=n.length;t<r;t++)n[t].config.isValidFiber(e)&&o.push(t);if(!o.length)return null;let i=[];if(n.some(e=>e.config.trackChanges)){let t=rt(e).changes,r=rr(e).changes,n=rn(e).changes;for(let n of(i.push.apply(null,t.map(e=>({type:1,name:e.name,value:e.value}))),r))e.tag===S.ClassComponentTag?i.push({type:3,name:n.name.toString(),value:n.value}):i.push({type:2,name:n.name.toString(),value:n.value});i.push.apply(null,n.map(e=>({type:4,name:e.name,value:e.value,contextType:Number(e.contextType)})))}let{selfTime:a,totalTime:s}=(0,S.getTimings)(e),l=rh(),c={phase:R[t],componentName:(0,S.getDisplayName)(r),count:1,changes:i,time:a,forget:(0,S.hasMemoCache)(e),unnecessary:null,didCommit:(0,S.didFiberCommit)(e),fps:l},d=i.length>0,u=(0,S.getMutatedHostFibers)(e).length>0;"update"===t&&((e,t,r,n,o)=>{let i=Date.now(),a=r_(e);if((n||o)&&(!a||i-(a.lastRenderTimestamp||0)>16)){var s;let n,o,l,c=a||{selfTime:0,totalTime:0,renderCount:0,lastRenderTimestamp:i};c.renderCount=(c.renderCount||0)+1,c.selfTime=t||0,c.totalTime=r||0,c.lastRenderTimestamp=i,s={...c},n=(0,S.getType)(e.type),o=ry(e),(l=rv.get(n))||(l=new Map,rv.set(n,l)),l.set(o,s)}})(e,a,s,d,u);for(let t=0,r=o.length;t<r;t++)n[o[t]].config.onRender(e,[c])}),r))e.config.onCommitFinish()},onPostCommitFiberRoot(){for(let e of rw())e.config.onPostCommitFiberRoot()}})),o);iC.instrumentation=l})(()=>{iM(!!t.value.showToolbar)}),!ij.monitor.value&&U&&setTimeout(()=>{(0,k.isInstrumentationActive)()||console.error("[React Scan] Failed to load. Must import React Scan before React runs.")},5e3)}catch(e){"verbose"===iC.options.value._debug&&console.error("[React Scan Internal Error]","Failed to create notifications outline canvas",e)}},iM=e=>{var t;let r,n,o,i,a,s,d,u,p,h,m,f,g,x,b;window.reactScanCleanupListeners?.();let w=(r=(e=>{let t;l?.(),t=()=>{document.hidden&&(nN=Date.now())},document.addEventListener("visibilitychange",t),l=()=>{document.removeEventListener("visibilitychange",t)};let r=new Map,n=new Map,o=t=>{if(!t.interactionId)return;if(t.interactionId&&t.target&&!n.has(t.interactionId)&&n.set(t.interactionId,t.target),t.target){let e=t.target;for(;e;){if("react-scan-toolbar-root"===e.id||"react-scan-root"===e.id)return;e=e.parentElement}}let o=r.get(t.interactionId);if(o)t.duration>o.latency?(o.entries=[t],o.latency=t.duration):t.duration===o.latency&&t.startTime===o.entries[0].startTime&&o.entries.push(t);else{var i;let n=["pointerup","click"].includes(i=t.name)?"pointer":(i.includes("key"),["keydown","keyup"].includes(i))?"keyboard":null;if(!n)return;let o={id:t.interactionId,latency:t.duration,entries:[t],target:t.target,type:n,startTime:t.startTime,endTime:Date.now(),processingStart:t.processingStart,processingEnd:t.processingEnd,duration:t.duration,inputDelay:t.processingStart-t.startTime,processingDuration:t.processingEnd-t.processingStart,presentationDelay:t.duration-(t.processingEnd-t.startTime),timestamp:Date.now(),timeSinceTabInactive:"never-hidden"===nN?"never-hidden":Date.now()-nN,visibilityState:document.visibilityState,timeOrigin:performance.timeOrigin,referrer:document.referrer};r.set(o.id,o),nT||(nT=requestAnimationFrame(()=>{requestAnimationFrame(()=>{e(r.get(o.id)),nT=null})}))}},i=new PerformanceObserver(e=>{let t=e.getEntries();for(let e=0,r=t.length;e<r;e++)o(t[e])});try{i.observe({type:"event",buffered:!0,durationThreshold:16}),i.observe({type:"first-input",buffered:!0})}catch{}return()=>i.disconnect()})(e=>{nf.publish({kind:"entry-received",entry:e},"recording")}),n=e=>{c=e.composedPath().map(e=>e.id).filter(Boolean).includes("react-scan-toolbar")},document.addEventListener("mouseover",n),nU=n,o=()=>{nU&&document.removeEventListener("mouseover",nU)},i=()=>{nL=performance.now(),nH=performance.timeOrigin},document.addEventListener("visibilitychange",i),a=()=>{document.removeEventListener("visibilitychange",i)},u=function e(){let t=null;nI=null,t=nM(nI={});let r=performance.timeOrigin,n=performance.now();return s=requestAnimationFrame(()=>{d=setTimeout(()=>{let o=performance.now(),i=o-n,a=performance.timeOrigin;nY.push(o+a);let s=nY.filter(e=>o+a-e<=1e3),l=s.length;nY=s;let d=null!==nL&&null!==nH?o+a-(nH+nL)<100:null,u=null!==c&&c;!(i>150)||d||"visible"!==document.visibilityState||u||n$.getState().actions.addEvent({kind:"long-render",id:nd(),data:{endAt:a+o,startAt:n+r,meta:{fiberRenders:nI,latency:i,fps:l}}}),nL=null,nH=null,t?.(),e()},0)}),t}(),p=()=>{u(),cancelAnimationFrame(s),clearTimeout(d)},m=nz("pointer",{onComplete:h=async(e,t,r)=>{n$.getState().actions.addEvent({kind:"interaction",id:nd(),data:{startAt:t.detailedTiming.blockingTimeStart,endAt:performance.now()+performance.timeOrigin,meta:{...t,kind:r.kind}}});let n=nf.getChannelState("recording");t.detailedTiming.stopListeningForRenders(),n.length&&nf.updateChannelState("recording",()=>new np(50))}}),f=nz("keyboard",{onComplete:h}),t=e=>{nh.setState(np.fromArray(nh.getCurrentState().concat(e),150))},g=nf.subscribe("recording",e=>{let r="auto-complete-race"===e.kind?nE.find(t=>t.interactionUUID===e.interactionUUID):((e,t)=>{let r=null;for(let n of t){if(n.type!==e.type)continue;if(null===r){r=n;continue}let t=(e,t)=>Math.abs(e.startDateTime)-(t.startTime+t.timeOrigin);t(n,e)<t(r,e)&&(r=n)}return r})(e.entry,nE);r&&t(r.completeInteraction(e))}),()=>{o(),a(),p(),r(),m(),g(),f()}),v=iA();window.reactScanCleanupListeners=()=>{w(),v?.()};let y=window.__REACT_SCAN_TOOLBAR_CONTAINER__;if(!e)return void y?.remove();y?.remove();let{shadowRoot:_}=(()=>{if(i_&&ik)return{rootContainer:i_,shadowRoot:ik};(i_=document.createElement("div")).id="react-scan-root",ik=i_.attachShadow({mode:"open"});let e=document.createElement("style");return e.textContent=rJ,ik.appendChild(e),document.documentElement.appendChild(i_),{rootContainer:i_,shadowRoot:ik}})();(x=document.createElement("div")).id="react-scan-toolbar-root",window.__REACT_SCAN_TOOLBAR_CONTAINER__=x,_.appendChild(x),(0,rK.render)((0,iv.jsx)(iy,{children:(0,iv.jsxs)(iv.Fragment,{children:[(0,iv.jsx)(iw,{}),(0,iv.jsx)(ig,{})]})}),x),b=x.remove.bind(x),x.remove=()=>{window.__REACT_SCAN_TOOLBAR_CONTAINER__=void 0,x.hasChildNodes()&&((0,rK.render)(null,x),(0,rK.render)(null,x)),b()}},iA=()=>{try{let e=document.documentElement;return(e=>{if(!(ov=(ow=document.createElement("canvas")).getContext("2d",{alpha:!0})))return null;let t=window.devicePixelRatio||1,{innerWidth:r,innerHeight:n}=window;ow.style.width=`${r}px`,ow.style.height=`${n}px`,ow.width=r*t,ow.height=n*t,ow.style.position="fixed",ow.style.left="0",ow.style.top="0",ow.style.pointerEvents="none",ow.style.zIndex="2147483600",ov.scale(t,t),e.appendChild(ow),oC&&window.removeEventListener("resize",oC);let o=()=>{if(!ow||!ov)return;let e=window.devicePixelRatio||1,{innerWidth:t,innerHeight:r}=window;ow.style.width=`${t}px`,ow.style.height=`${r}px`,ow.width=t*e,ow.height=r*e,ov.scale(e,e),oj()};return oC=o,window.addEventListener("resize",o),o_.subscribe(()=>{requestAnimationFrame(()=>{oj()})}),oS})(e)}catch(e){"verbose"===iC.options.value._debug&&console.error("[React Scan Internal Error]","Failed to create notifications outline canvas",e)}},iO=(e={})=>{iT(e),ij.isInIframe.value&&!iC.options.value.allowInIframe||(!1!==e.enabled||!0===e.showToolbar)&&iF()},iP=(e={})=>{iT(e),iF()},iD=(e,t)=>{let r=iC.onRender;iC.onRender=(n,o)=>{r?.(n,o),(0,k.getType)(n.type)===e&&t(n,o)}},iI=new WeakSet,i$=e=>{e&&"object"==typeof e&&iI.add(e)}},45994:(e,t,r)=>{"use strict";r.r(t),r.d(t,{useCallback:()=>C,useContext:()=>S,useDebugValue:()=>N,useEffect:()=>v,useErrorBoundary:()=>T,useId:()=>E,useImperativeHandle:()=>k,useLayoutEffect:()=>y,useMemo:()=>j,useReducer:()=>w,useRef:()=>_,useState:()=>b});var n,o,i,a,s=r(27791),l=0,c=[],d=s.options,u=d.__b,p=d.__r,h=d.diffed,m=d.__c,f=d.unmount,g=d.__;function x(e,t){d.__h&&d.__h(o,e,l||t),l=0;var r=o.__H||(o.__H={__:[],__h:[]});return e>=r.__.length&&r.__.push({}),r.__[e]}function b(e){return l=1,w(O,e)}function w(e,t,r){var i=x(n++,2);if(i.t=e,!i.__c&&(i.__=[r?r(t):O(void 0,t),function(e){var t=i.__N?i.__N[0]:i.__[0],r=i.t(t,e);t!==r&&(i.__N=[r,i.__[1]],i.__c.setState({}))}],i.__c=o,!o.u)){var a=function(e,t,r){if(!i.__c.__H)return!0;var n=i.__c.__H.__.filter(function(e){return!!e.__c});if(n.every(function(e){return!e.__N}))return!s||s.call(this,e,t,r);var o=i.__c.props!==e;return n.forEach(function(e){if(e.__N){var t=e.__[0];e.__=e.__N,e.__N=void 0,t!==e.__[0]&&(o=!0)}}),s&&s.call(this,e,t,r)||o};o.u=!0;var s=o.shouldComponentUpdate,l=o.componentWillUpdate;o.componentWillUpdate=function(e,t,r){if(this.__e){var n=s;s=void 0,a(e,t,r),s=n}l&&l.call(this,e,t,r)},o.shouldComponentUpdate=a}return i.__N||i.__}function v(e,t){var r=x(n++,3);!d.__s&&A(r.__H,t)&&(r.__=e,r.i=t,o.__H.__h.push(r))}function y(e,t){var r=x(n++,4);!d.__s&&A(r.__H,t)&&(r.__=e,r.i=t,o.__h.push(r))}function _(e){return l=5,j(function(){return{current:e}},[])}function k(e,t,r){l=6,y(function(){return"function"==typeof e?(e(t()),function(){return e(null)}):e?(e.current=t(),function(){return e.current=null}):void 0},null==r?r:r.concat(e))}function j(e,t){var r=x(n++,7);return A(r.__H,t)&&(r.__=e(),r.__H=t,r.__h=e),r.__}function C(e,t){return l=8,j(function(){return e},t)}function S(e){var t=o.context[e.__c],r=x(n++,9);return r.c=e,t?(null==r.__&&(r.__=!0,t.sub(o)),t.props.value):e.__}function N(e,t){d.useDebugValue&&d.useDebugValue(t?t(e):e)}function T(e){var t=x(n++,10),r=b();return t.__=e,o.componentDidCatch||(o.componentDidCatch=function(e,n){t.__&&t.__(e,n),r[1](e)}),[r[0],function(){r[1](void 0)}]}function E(){var e=x(n++,11);if(!e.__){for(var t=o.__v;null!==t&&!t.__m&&null!==t.__;)t=t.__;var r=t.__m||(t.__m=[0,0]);e.__="P"+r[0]+"-"+r[1]++}return e.__}function z(){for(var e;e=c.shift();)if(e.__P&&e.__H)try{e.__H.__h.forEach(F),e.__H.__h.forEach(M),e.__H.__h=[]}catch(t){e.__H.__h=[],d.__e(t,e.__v)}}d.__b=function(e){o=null,u&&u(e)},d.__=function(e,t){e&&t.__k&&t.__k.__m&&(e.__m=t.__k.__m),g&&g(e,t)},d.__r=function(e){p&&p(e),n=0;var t=(o=e.__c).__H;t&&(i===o?(t.__h=[],o.__h=[],t.__.forEach(function(e){e.__N&&(e.__=e.__N),e.i=e.__N=void 0})):(t.__h.forEach(F),t.__h.forEach(M),t.__h=[],n=0)),i=o},d.diffed=function(e){h&&h(e);var t=e.__c;t&&t.__H&&(t.__H.__h.length&&(1!==c.push(t)&&a===d.requestAnimationFrame||((a=d.requestAnimationFrame)||function(e){var t,r=function(){clearTimeout(n),R&&cancelAnimationFrame(t),setTimeout(e)},n=setTimeout(r,100);R&&(t=requestAnimationFrame(r))})(z)),t.__H.__.forEach(function(e){e.i&&(e.__H=e.i),e.i=void 0})),i=o=null},d.__c=function(e,t){t.some(function(e){try{e.__h.forEach(F),e.__h=e.__h.filter(function(e){return!e.__||M(e)})}catch(r){t.some(function(e){e.__h&&(e.__h=[])}),t=[],d.__e(r,e.__v)}}),m&&m(e,t)},d.unmount=function(e){f&&f(e);var t,r=e.__c;r&&r.__H&&(r.__H.__.forEach(function(e){try{F(e)}catch(e){t=e}}),r.__H=void 0,t&&d.__e(t,r.__v))};var R="function"==typeof requestAnimationFrame;function F(e){var t=o,r=e.__c;"function"==typeof r&&(e.__c=void 0,r()),o=t}function M(e){var t=o;e.__c=e.__(),o=t}function A(e,t){return!e||e.length!==t.length||t.some(function(t,r){return t!==e[r]})}function O(e,t){return"function"==typeof t?t(e):t}},61704:(e,t,r)=>{"use strict";r.r(t),r.d(t,{Signal:()=>x,batch:()=>c,computed:()=>k,effect:()=>T,signal:()=>b,untracked:()=>u,useComputed:()=>M,useSignal:()=>F,useSignalEffect:()=>A});var n,o,i=r(27791),a=r(45994),s=Symbol.for("preact-signals");function l(){if(h>1)h--;else{for(var e,t=!1;void 0!==p;){var r=p;for(p=void 0,m++;void 0!==r;){var n=r.o;if(r.o=void 0,r.f&=-3,!(8&r.f)&&w(r))try{r.c()}catch(r){t||(e=r,t=!0)}r=n}}if(m=0,h--,t)throw e}}function c(e){if(h>0)return e();h++;try{return e()}finally{l()}}var d=void 0;function u(e){var t=d;d=void 0;try{return e()}finally{d=t}}var p=void 0,h=0,m=0,f=0;function g(e){if(void 0!==d){var t=e.n;if(void 0===t||t.t!==d)return t={i:0,S:e,p:d.s,n:void 0,t:d,e:void 0,x:void 0,r:t},void 0!==d.s&&(d.s.n=t),d.s=t,e.n=t,32&d.f&&e.S(t),t;if(-1===t.i)return t.i=0,void 0!==t.n&&(t.n.p=t.p,void 0!==t.p&&(t.p.n=t.n),t.p=d.s,t.n=void 0,d.s.n=t,d.s=t),t}}function x(e){this.v=e,this.i=0,this.n=void 0,this.t=void 0}function b(e){return new x(e)}function w(e){for(var t=e.s;void 0!==t;t=t.n)if(t.S.i!==t.i||!t.S.h()||t.S.i!==t.i)return!0;return!1}function v(e){for(var t=e.s;void 0!==t;t=t.n){var r=t.S.n;if(void 0!==r&&(t.r=r),t.S.n=t,t.i=-1,void 0===t.n){e.s=t;break}}}function y(e){for(var t=e.s,r=void 0;void 0!==t;){var n=t.p;-1===t.i?(t.S.U(t),void 0!==n&&(n.n=t.n),void 0!==t.n&&(t.n.p=n)):r=t,t.S.n=t.r,void 0!==t.r&&(t.r=void 0),t=n}e.s=r}function _(e){x.call(this,void 0),this.x=e,this.s=void 0,this.g=f-1,this.f=4}function k(e){return new _(e)}function j(e){var t=e.u;if(e.u=void 0,"function"==typeof t){h++;var r=d;d=void 0;try{t()}catch(t){throw e.f&=-2,e.f|=8,C(e),t}finally{d=r,l()}}}function C(e){for(var t=e.s;void 0!==t;t=t.n)t.S.U(t);e.x=void 0,e.s=void 0,j(e)}function S(e){if(d!==this)throw Error("Out-of-order effect");y(this),d=e,this.f&=-2,8&this.f&&C(this),l()}function N(e){this.x=e,this.u=void 0,this.s=void 0,this.o=void 0,this.f=32}function T(e){var t=new N(e);try{t.c()}catch(e){throw t.d(),e}return t.d.bind(t)}function E(e,t){i.options[e]=t.bind(null,i.options[e]||function(){})}function z(e){o&&o(),o=e&&e.S()}function R(e){var t=this,r=e.data,n=F(r);n.value=r;var o=(0,a.useMemo)(function(){for(var e=t.__v;e=e.__;)if(e.__c){e.__c.__$f|=4;break}return t.__$u.c=function(){var e,r=t.__$u.S(),n=o.value;r(),(0,i.isValidElement)(n)||3!==(null==(e=t.base)?void 0:e.nodeType)?(t.__$f|=1,t.setState({})):t.base.data=n},k(function(){var e=n.value.value;return 0===e?0:!0===e?"":e||""})},[]);return o.value}function F(e){return(0,a.useMemo)(function(){return b(e)},[])}function M(e){var t=(0,a.useRef)(e);return t.current=e,n.__$f|=4,(0,a.useMemo)(function(){return k(function(){return t.current()})},[])}function A(e){var t=(0,a.useRef)(e);t.current=e,(0,a.useEffect)(function(){return T(function(){return t.current()})},[])}x.prototype.brand=s,x.prototype.h=function(){return!0},x.prototype.S=function(e){this.t!==e&&void 0===e.e&&(e.x=this.t,void 0!==this.t&&(this.t.e=e),this.t=e)},x.prototype.U=function(e){if(void 0!==this.t){var t=e.e,r=e.x;void 0!==t&&(t.x=r,e.e=void 0),void 0!==r&&(r.e=t,e.x=void 0),e===this.t&&(this.t=r)}},x.prototype.subscribe=function(e){var t=this;return T(function(){var r=t.value,n=d;d=void 0;try{e(r)}finally{d=n}})},x.prototype.valueOf=function(){return this.value},x.prototype.toString=function(){return this.value+""},x.prototype.toJSON=function(){return this.value},x.prototype.peek=function(){var e=d;d=void 0;try{return this.value}finally{d=e}},Object.defineProperty(x.prototype,"value",{get:function(){var e=g(this);return void 0!==e&&(e.i=this.i),this.v},set:function(e){if(e!==this.v){if(m>100)throw Error("Cycle detected");this.v=e,this.i++,f++,h++;try{for(var t=this.t;void 0!==t;t=t.x)t.t.N()}finally{l()}}}}),(_.prototype=new x).h=function(){if(this.f&=-3,1&this.f)return!1;if(32==(36&this.f)||(this.f&=-5,this.g===f))return!0;if(this.g=f,this.f|=1,this.i>0&&!w(this))return this.f&=-2,!0;var e=d;try{v(this),d=this;var t=this.x();(16&this.f||this.v!==t||0===this.i)&&(this.v=t,this.f&=-17,this.i++)}catch(e){this.v=e,this.f|=16,this.i++}return d=e,y(this),this.f&=-2,!0},_.prototype.S=function(e){if(void 0===this.t){this.f|=36;for(var t=this.s;void 0!==t;t=t.n)t.S.S(t)}x.prototype.S.call(this,e)},_.prototype.U=function(e){if(void 0!==this.t&&(x.prototype.U.call(this,e),void 0===this.t)){this.f&=-33;for(var t=this.s;void 0!==t;t=t.n)t.S.U(t)}},_.prototype.N=function(){if(!(2&this.f)){this.f|=6;for(var e=this.t;void 0!==e;e=e.x)e.t.N()}},Object.defineProperty(_.prototype,"value",{get:function(){if(1&this.f)throw Error("Cycle detected");var e=g(this);if(this.h(),void 0!==e&&(e.i=this.i),16&this.f)throw this.v;return this.v}}),N.prototype.c=function(){var e=this.S();try{if(8&this.f||void 0===this.x)return;var t=this.x();"function"==typeof t&&(this.u=t)}finally{e()}},N.prototype.S=function(){if(1&this.f)throw Error("Cycle detected");this.f|=1,this.f&=-9,j(this),v(this),h++;var e=d;return d=this,S.bind(this,e)},N.prototype.N=function(){2&this.f||(this.f|=2,this.o=p,p=this)},N.prototype.d=function(){this.f|=8,1&this.f||C(this)},R.displayName="_st",Object.defineProperties(x.prototype,{constructor:{configurable:!0,value:void 0},type:{configurable:!0,value:R},props:{configurable:!0,get:function(){return{data:this}}},__b:{configurable:!0,value:1}}),E("__b",function(e,t){if("string"==typeof t.type){var r,n=t.props;for(var o in n)if("children"!==o){var i=n[o];i instanceof x&&(r||(t.__np=r={}),r[o]=i,n[o]=i.peek())}}e(t)}),E("__r",function(e,t){z();var r,o,i=t.__c;i&&(i.__$f&=-2,void 0===(o=i.__$u)&&(T(function(){r=this}),r.c=function(){i.__$f|=1,i.setState({})},i.__$u=o=r)),n=i,z(o),e(t)}),E("__e",function(e,t,r,o){z(),n=void 0,e(t,r,o)}),E("diffed",function(e,t){if(z(),n=void 0,"string"==typeof t.type&&(r=t.__e)){var r,o=t.__np,i=t.props;if(o){var a=r.U;if(a)for(var s in a){var l=a[s];void 0===l||s in o||(l.d(),a[s]=void 0)}else r.U=a={};for(var c in o){var d=a[c],u=o[c];void 0===d?(d=function(e,t,r,n){var o=t in e&&void 0===e.ownerSVGElement,i=b(r);return{o:function(e,t){i.value=e,n=t},d:T(function(){var r=i.value.value;n[t]!==r&&(n[t]=r,o?e[t]=r:r?e.setAttribute(t,r):e.removeAttribute(t))})}}(r,c,u,i),a[c]=d):d.o(u,i)}}}e(t)}),E("unmount",function(e,t){if("string"==typeof t.type){var r=t.__e;if(r){var n=r.U;if(n)for(var o in r.U=void 0,n){var i=n[o];i&&i.d()}}}else{var a=t.__c;if(a){var s=a.__$u;s&&(a.__$u=void 0,s.d())}}e(t)}),E("__h",function(e,t,r,n){(n<3||9===n)&&(t.__$f|=2),e(t,r,n)}),i.Component.prototype.shouldComponentUpdate=function(e,t){var r=this.__$u,n=r&&void 0!==r.s;for(var o in t)return!0;if(this.__f||"boolean"==typeof this.u&&!0===this.u){if(!(n||2&this.__$f||4&this.__$f)||1&this.__$f)return!0}else if(!(n||4&this.__$f)||3&this.__$f)return!0;for(var i in e)if("__source"!==i&&e[i]!==this.props[i])return!0;for(var a in this.props)if(!(a in e))return!0;return!1}},62224:(e,t,r)=>{let n=r(82399);r(88091),t.BIPPY_INSTRUMENTATION_STRING=n.BIPPY_INSTRUMENTATION_STRING,t.CONCURRENT_MODE_NUMBER=n.CONCURRENT_MODE_NUMBER,t.CONCURRENT_MODE_SYMBOL_STRING=n.CONCURRENT_MODE_SYMBOL_STRING,t.ClassComponentTag=n.ClassComponentTag,t.ContextConsumerTag=n.ContextConsumerTag,t.DEPRECATED_ASYNC_MODE_SYMBOL_STRING=n.DEPRECATED_ASYNC_MODE_SYMBOL_STRING,t.DehydratedSuspenseComponentTag=n.DehydratedSuspenseComponentTag,t.ELEMENT_TYPE_SYMBOL_STRING=n.ELEMENT_TYPE_SYMBOL_STRING,t.ForwardRefTag=n.ForwardRefTag,t.FragmentTag=n.FragmentTag,t.FunctionComponentTag=n.FunctionComponentTag,t.HostComponentTag=n.HostComponentTag,t.HostHoistableTag=n.HostHoistableTag,t.HostRootTag=n.HostRootTag,t.HostSingletonTag=n.HostSingletonTag,t.HostTextTag=n.HostTextTag,t.INSTALL_ERROR=n.INSTALL_ERROR,t.INSTALL_HOOK_SCRIPT_STRING=n.INSTALL_HOOK_SCRIPT_STRING,t.LegacyHiddenComponentTag=n.LegacyHiddenComponentTag,t.MemoComponentTag=n.MemoComponentTag,t.OffscreenComponentTag=n.OffscreenComponentTag,t.SimpleMemoComponentTag=n.SimpleMemoComponentTag,t.SuspenseComponentTag=n.SuspenseComponentTag,t.TRANSITIONAL_ELEMENT_TYPE_SYMBOL_STRING=n.TRANSITIONAL_ELEMENT_TYPE_SYMBOL_STRING,t._fiberRoots=n._fiberRoots,t._renderers=n._renderers,t.createFiberVisitor=n.createFiberVisitor,t.detectReactBuildType=n.detectReactBuildType,t.didFiberCommit=n.didFiberCommit,t.didFiberRender=n.didFiberRender,t.fiberIdMap=n.fiberIdMap,t.getDisplayName=n.getDisplayName,t.getFiberFromHostInstance=n.getFiberFromHostInstance,t.getFiberId=n.getFiberId,t.getFiberStack=n.getFiberStack,t.getLatestFiber=n.getLatestFiber,t.getMutatedHostFibers=n.getMutatedHostFibers,t.getNearestHostFiber=n.getNearestHostFiber,t.getNearestHostFibers=n.getNearestHostFibers,t.getRDTHook=n.getRDTHook,t.getTimings=n.getTimings,t.getType=n.getType,t.hasMemoCache=n.hasMemoCache,t.hasRDTHook=n.hasRDTHook,t.installRDTHook=n.installRDTHook,t.instrument=n.instrument,t.isClientEnvironment=n.isClientEnvironment,t.isCompositeFiber=n.isCompositeFiber,t.isHostFiber=n.isHostFiber,t.isInstrumentationActive=n.isInstrumentationActive,t.isReactRefresh=n.isReactRefresh,t.isRealReactDevtools=n.isRealReactDevtools,t.isValidElement=n.isValidElement,t.isValidFiber=n.isValidFiber,t.mountFiberRecursively=n.mountFiberRecursively,t.onCommitFiberRoot=n.onCommitFiberRoot,t.patchRDTHook=n.patchRDTHook,t.safelyInstallRDTHook=n.safelyInstallRDTHook,t.secure=n.secure,t.setFiberId=n.setFiberId,t.shouldFilterFiber=n.shouldFilterFiber,t.traverseContexts=n.traverseContexts,t.traverseFiber=n.traverseFiber,t.traverseProps=n.traverseProps,t.traverseRenderedFibers=n.traverseRenderedFibers,t.traverseState=n.traverseState,t.unmountFiber=n.unmountFiber,t.unmountFiberChildrenRecursively=n.unmountFiberChildrenRecursively,t.updateFiberRecursively=n.updateFiberRecursively,t.version=n.version},82399:(e,t)=>{let r,n="0.3.14",o=`bippy-${n}`,i=Object.defineProperty,a=Object.prototype.hasOwnProperty,s=()=>{},l=e=>{try{Function.prototype.toString.call(e).indexOf("^_^")>-1&&setTimeout(()=>{throw Error("React is running in production mode, but dead code elimination has not been applied. Read how to correctly configure React for production: https://reactjs.org/link/perf-use-production-build")})}catch{}},c=(e=x())=>"getFiberRoots"in e,d=!1,u=(e=x())=>!!d||("function"==typeof e.inject&&(r=e.inject.toString()),!!r?.includes("(injected)")),p=new Set,h=new Set,m=e=>{let t=new Map,r=0,n={checkDCE:l,supportsFiber:!0,supportsFlight:!0,hasUnsupportedRendererAttached:!1,renderers:t,onCommitFiberRoot:s,onCommitFiberUnmount:s,onPostCommitFiberRoot:s,inject(e){let o=++r;return t.set(o,e),h.add(e),n._instrumentationIsActive||(n._instrumentationIsActive=!0,p.forEach(e=>e())),o},_instrumentationSource:o,_instrumentationIsActive:!1};try{i(globalThis,"__REACT_DEVTOOLS_GLOBAL_HOOK__",{get:()=>n,set(t){if(t&&"object"==typeof t){let r=n.renderers;n=t,r.size>0&&(r.forEach((e,r)=>{h.add(e),t.renderers.set(r,e)}),f(e))}},configurable:!0,enumerable:!0});let t=window.hasOwnProperty,r=!1;i(window,"hasOwnProperty",{value:function(){try{if(!r&&"__REACT_DEVTOOLS_GLOBAL_HOOK__"===arguments[0])return globalThis.__REACT_DEVTOOLS_GLOBAL_HOOK__=void 0,r=!0,-0}catch{}return t.apply(this,arguments)},configurable:!0,writable:!0})}catch{f(e)}return n},f=e=>{e&&p.add(e);try{let t=globalThis.__REACT_DEVTOOLS_GLOBAL_HOOK__;if(!t)return;if(!t._instrumentationSource){if(t.checkDCE=l,t.supportsFiber=!0,t.supportsFlight=!0,t.hasUnsupportedRendererAttached=!1,t._instrumentationSource=o,t._instrumentationIsActive=!1,t.renderers.size){t._instrumentationIsActive=!0,p.forEach(e=>e());return}let e=t.inject;u(t)&&!c()&&(d=!0,t.inject({scheduleRefresh(){}})&&(t._instrumentationIsActive=!0)),t.inject=r=>{let n=e(r);return h.add(r),t._instrumentationIsActive=!0,p.forEach(e=>e()),n}}(t.renderers.size||t._instrumentationIsActive||u())&&e?.()}catch{}},g=()=>a.call(globalThis,"__REACT_DEVTOOLS_GLOBAL_HOOK__"),x=e=>g()?(f(e),globalThis.__REACT_DEVTOOLS_GLOBAL_HOOK__):m(e),b=()=>!!("undefined"!=typeof window&&(window.document?.createElement||window.navigator?.product==="ReactNative")),w=()=>{try{b()&&x()}catch{}},v="Symbol(react.element)",y="Symbol(react.transitional.element)",_="Symbol(react.concurrent_mode)",k="Symbol(react.async_mode)",j=e=>"object"==typeof e&&null!=e&&"$$typeof"in e&&[v,y].includes(String(e.$$typeof)),C=e=>"object"==typeof e&&null!=e&&"tag"in e&&"stateNode"in e&&"return"in e&&"child"in e&&"sibling"in e&&"flags"in e,S=e=>{switch(e.tag){case 5:case 26:case 27:return!0;default:return"string"==typeof e.type}},N=e=>{switch(e.tag){case 0:case 1:case 15:case 14:case 11:return!0;default:return!1}},T=(e,t)=>{try{let r=e.dependencies,n=e.alternate?.dependencies;if(!r||!n||"object"!=typeof r||!("firstContext"in r)||"object"!=typeof n||!("firstContext"in n))return!1;let o=r.firstContext,i=n.firstContext;for(;o&&"object"==typeof o&&"memoizedValue"in o||i&&"object"==typeof i&&"memoizedValue"in i;){if(!0===t(o,i))return!0;o=o?.next,i=i?.next}}catch{}return!1},E=(e,t)=>{try{let r=e.memoizedState,n=e.alternate?.memoizedState;for(;r||n;){if(!0===t(r,n))return!0;r=r?.next,n=n?.next}}catch{}return!1},z=(e,t)=>{try{let r=e.memoizedProps,n=e.alternate?.memoizedProps||{};for(let e of new Set([...Object.keys(n),...Object.keys(r)])){let o=n?.[e],i=r?.[e];if(!0===t(e,i,o))return!0}}catch{}return!1},R=e=>{let t=e.memoizedProps,r=e.alternate?.memoizedProps||{},n=e.flags??e.effectTag??0;switch(e.tag){case 1:case 0:case 9:case 11:case 14:case 15:return(1&n)==1;default:if(!e.alternate)return!0;return r!==t||e.alternate.memoizedState!==e.memoizedState||e.alternate.ref!==e.ref}},F=e=>(13374&e.flags)!=0||(13374&e.subtreeFlags)!=0,M=e=>{let t=[],r=[e];for(;r.length;){let e=r.pop();e&&(S(e)&&F(e)&&R(e)&&t.push(e),e.child&&r.push(e.child),e.sibling&&r.push(e.sibling))}return t},A=e=>{let t=[],r=e;for(;r.return;)t.push(r),r=r.return;return t},O=e=>{switch(e.tag){case 18:case 6:case 7:case 23:case 22:return!0;case 3:return!1;default:{let t="object"==typeof e.type&&null!==e.type?e.type.$$typeof:e.type;switch("symbol"==typeof t?t.toString():t){case 60111:case _:case k:return!0;default:return!1}}}},P=(e,t=!1)=>{let r=I(e,S,t);return r||(r=I(e,S,!t)),r},D=e=>{let t=[],r=[];for(S(e)?t.push(e):e.child&&r.push(e.child);r.length;){let e=r.pop();if(!e)break;S(e)?t.push(e):e.child&&r.push(e.child),e.sibling&&r.push(e.sibling)}return t},I=(e,t,r=!1)=>{if(!e)return null;if(!0===t(e))return e;let n=r?e.return:e.child;for(;n;){let e=I(n,t,r);if(e)return e;n=r?null:n.sibling}return null},$=e=>{let t=e?.actualDuration??0,r=t,n=e?.child??null;for(;t>0&&null!=n;)r-=n.actualDuration??0,n=n.sibling;return{selfTime:r,totalTime:t}},L=e=>!!e.updateQueue?.memoCache,H=e=>"function"==typeof e?e:"object"==typeof e&&e?H(e.type||e.render):null,U=e=>{if("string"==typeof e)return e;if("function"!=typeof e&&!("object"==typeof e&&e))return null;let t=e.displayName||e.name||null;if(t)return t;let r=H(e);return r&&(r.displayName||r.name)||null},Y=e=>{try{if("string"==typeof e.version&&e.bundleType>0)return"development"}catch{}return"production"},B=()=>!!x()._instrumentationIsActive||c()||u(),W=e=>{let t=e.alternate;if(!t)return e;if(t.actualStartTime&&e.actualStartTime)return t.actualStartTime>e.actualStartTime?t:e;for(let t of es){let r=I(t.current,t=>{if(t===e)return!0});if(r)return r}return e},V=0,X=new WeakMap,q=(e,t=V++)=>{X.set(e,t)},G=e=>{let t=X.get(e);return!t&&e.alternate&&(t=X.get(e.alternate)),t||q(e,t=V++),t},J=(e,t,r)=>{let n=t;for(;null!=n;){if(X.has(n)||G(n),!O(n)&&R(n)&&e(n,"mount"),13===n.tag)if(null!==n.memoizedState){let t=n.child,r=t?t.sibling:null;if(r){let t=r.child;null!==t&&J(e,t,!1)}}else{let t=null;null!==n.child&&(t=n.child.child),null!==t&&J(e,t,!1)}else null!=n.child&&J(e,n.child,!0);n=r?n.sibling:null}},K=(e,t,r,n)=>{if(X.has(t)||G(t),!r)return;X.has(r)||G(r);let o=13===t.tag,i=!O(t);i&&R(t)&&e(t,"update");let a=o&&null!==r.memoizedState,s=o&&null!==t.memoizedState;if(a&&s){let n=t.child?.sibling??null,o=r.child?.sibling??null;null!==n&&null!==o&&K(e,n,o,t)}else if(a&&!s){let r=t.child;null!==r&&J(e,r,!0)}else if(!a&&s){Q(e,r);let n=t.child?.sibling??null;null!==n&&J(e,n,!0)}else if(t.child!==r.child){let r=t.child;for(;r;){if(r.alternate){let o=r.alternate;K(e,r,o,i?t:n)}else J(e,r,!1);r=r.sibling}}},Z=(e,t)=>{3!==t.tag&&O(t)||e(t,"unmount")},Q=(e,t)=>{let r=13===t.tag&&null!==t.memoizedState,n=t.child;if(r){let e=t.child,r=e?.sibling??null;n=r?.child??null}for(;null!==n;)null!==n.return&&(Z(e,n),Q(e,n)),n=n.sibling},ee=0,et=new WeakMap,er=(e,t)=>{let r="current"in e?e.current:e,n=et.get(e);n||(n={prevFiber:null,id:ee++},et.set(e,n));let{prevFiber:o}=n;if(r)if(null!==o){let e=o&&null!=o.memoizedState&&null!=o.memoizedState.element&&!0!==o.memoizedState.isDehydrated,n=null!=r.memoizedState&&null!=r.memoizedState.element&&!0!==r.memoizedState.isDehydrated;!e&&n?J(t,r,!1):e&&n?K(t,r,r.alternate,null):e&&!n&&Z(t,r)}else J(t,r,!0);else Z(t,r);n.prevFiber=r},en=({onRender:e})=>(t,r,n)=>{er(r,e)},eo=e=>x(()=>{let t=x();e.onActive?.(),t._instrumentationSource=e.name??o;let r=t.onCommitFiberRoot;e.onCommitFiberRoot&&(t.onCommitFiberRoot=(t,n,o)=>{r&&r(t,n,o),e.onCommitFiberRoot?.(t,n,o)});let n=t.onCommitFiberUnmount;e.onCommitFiberUnmount&&(t.onCommitFiberUnmount=(t,r)=>{n&&n(t,r),e.onCommitFiberUnmount?.(t,r)});let i=t.onPostCommitFiberRoot;e.onPostCommitFiberRoot&&(t.onPostCommitFiberRoot=(t,r)=>{i&&i(t,r),e.onPostCommitFiberRoot?.(t,r)})}),ei=e=>{for(let t of x().renderers.values())try{let r=t.findFiberByHostInstance?.(e);if(r)return r}catch{}if("object"==typeof e&&null!=e){if("_reactRootContainer"in e)return e._reactRootContainer?._internalRoot?.current?.child;for(let t in e)if(t.startsWith("__reactInternalInstance$")||t.startsWith("__reactFiber"))return e[t]||null}return null},ea=Error(),es=new Set,el=(e,t={})=>{let r,n=e.onActive,o=g(),i=c(),a=u(),s=t.isProduction??!1;return e.onActive=()=>{clearTimeout(r);let o=!0;try{for(let e of x().renderers.values()){let[r]=e.version.split(".");Number(r)<(t.minReactMajorVersion??17)&&(o=!1);let n=Y(e);"development"!==n&&(s=!0,t.dangerouslyRunInProduction||(o=!1))}}catch(e){t.onError?.(e)}if(!o){e.onCommitFiberRoot=void 0,e.onCommitFiberUnmount=void 0,e.onPostCommitFiberRoot=void 0,e.onActive=void 0;return}n?.();try{let r=e.onCommitFiberRoot;r&&(e.onCommitFiberRoot=(e,n,o)=>{es.has(n)||es.add(n);try{r(e,n,o)}catch(e){t.onError?.(e)}});let n=e.onCommitFiberUnmount;n&&(e.onCommitFiberUnmount=(e,r)=>{try{n(e,r)}catch(e){t.onError?.(e)}});let o=e.onPostCommitFiberRoot;o&&(e.onPostCommitFiberRoot=(e,r)=>{try{o(e,r)}catch(e){t.onError?.(e)}})}catch(e){t.onError?.(e)}},o||i||a||(r=setTimeout(()=>{s||t.onError?.(ea),stop()},t.installCheckTimeout??100)),e},ec=e=>eo(el({onCommitFiberRoot:(t,r)=>{e(r)}}));Object.defineProperty(t,"BIPPY_INSTRUMENTATION_STRING",{enumerable:!0,get:function(){return o}}),Object.defineProperty(t,"CONCURRENT_MODE_NUMBER",{enumerable:!0,get:function(){return 60111}}),Object.defineProperty(t,"CONCURRENT_MODE_SYMBOL_STRING",{enumerable:!0,get:function(){return _}}),Object.defineProperty(t,"ClassComponentTag",{enumerable:!0,get:function(){return 1}}),Object.defineProperty(t,"ContextConsumerTag",{enumerable:!0,get:function(){return 9}}),Object.defineProperty(t,"DEPRECATED_ASYNC_MODE_SYMBOL_STRING",{enumerable:!0,get:function(){return k}}),Object.defineProperty(t,"DehydratedSuspenseComponentTag",{enumerable:!0,get:function(){return 18}}),Object.defineProperty(t,"ELEMENT_TYPE_SYMBOL_STRING",{enumerable:!0,get:function(){return v}}),Object.defineProperty(t,"ForwardRefTag",{enumerable:!0,get:function(){return 11}}),Object.defineProperty(t,"FragmentTag",{enumerable:!0,get:function(){return 7}}),Object.defineProperty(t,"FunctionComponentTag",{enumerable:!0,get:function(){return 0}}),Object.defineProperty(t,"HostComponentTag",{enumerable:!0,get:function(){return 5}}),Object.defineProperty(t,"HostHoistableTag",{enumerable:!0,get:function(){return 26}}),Object.defineProperty(t,"HostRootTag",{enumerable:!0,get:function(){return 3}}),Object.defineProperty(t,"HostSingletonTag",{enumerable:!0,get:function(){return 27}}),Object.defineProperty(t,"HostTextTag",{enumerable:!0,get:function(){return 6}}),Object.defineProperty(t,"INSTALL_ERROR",{enumerable:!0,get:function(){return ea}}),Object.defineProperty(t,"INSTALL_HOOK_SCRIPT_STRING",{enumerable:!0,get:function(){return"(()=>{try{var t=()=>{};const n=new Map;let o=0;globalThis.__REACT_DEVTOOLS_GLOBAL_HOOK__={checkDCE:t,supportsFiber:!0,supportsFlight:!0,hasUnsupportedRendererAttached:!1,renderers:n,onCommitFiberRoot:t,onCommitFiberUnmount:t,onPostCommitFiberRoot:t,inject(t){var e=++o;return n.set(e,t),globalThis.__REACT_DEVTOOLS_GLOBAL_HOOK__._instrumentationIsActive=!0,e},_instrumentationIsActive:!1,_script:!0}}catch{}})()"}}),Object.defineProperty(t,"LegacyHiddenComponentTag",{enumerable:!0,get:function(){return 23}}),Object.defineProperty(t,"MemoComponentTag",{enumerable:!0,get:function(){return 14}}),Object.defineProperty(t,"OffscreenComponentTag",{enumerable:!0,get:function(){return 22}}),Object.defineProperty(t,"SimpleMemoComponentTag",{enumerable:!0,get:function(){return 15}}),Object.defineProperty(t,"SuspenseComponentTag",{enumerable:!0,get:function(){return 13}}),Object.defineProperty(t,"TRANSITIONAL_ELEMENT_TYPE_SYMBOL_STRING",{enumerable:!0,get:function(){return y}}),Object.defineProperty(t,"_fiberRoots",{enumerable:!0,get:function(){return es}}),Object.defineProperty(t,"_renderers",{enumerable:!0,get:function(){return h}}),Object.defineProperty(t,"createFiberVisitor",{enumerable:!0,get:function(){return en}}),Object.defineProperty(t,"detectReactBuildType",{enumerable:!0,get:function(){return Y}}),Object.defineProperty(t,"didFiberCommit",{enumerable:!0,get:function(){return F}}),Object.defineProperty(t,"didFiberRender",{enumerable:!0,get:function(){return R}}),Object.defineProperty(t,"fiberIdMap",{enumerable:!0,get:function(){return X}}),Object.defineProperty(t,"getDisplayName",{enumerable:!0,get:function(){return U}}),Object.defineProperty(t,"getFiberFromHostInstance",{enumerable:!0,get:function(){return ei}}),Object.defineProperty(t,"getFiberId",{enumerable:!0,get:function(){return G}}),Object.defineProperty(t,"getFiberStack",{enumerable:!0,get:function(){return A}}),Object.defineProperty(t,"getLatestFiber",{enumerable:!0,get:function(){return W}}),Object.defineProperty(t,"getMutatedHostFibers",{enumerable:!0,get:function(){return M}}),Object.defineProperty(t,"getNearestHostFiber",{enumerable:!0,get:function(){return P}}),Object.defineProperty(t,"getNearestHostFibers",{enumerable:!0,get:function(){return D}}),Object.defineProperty(t,"getRDTHook",{enumerable:!0,get:function(){return x}}),Object.defineProperty(t,"getTimings",{enumerable:!0,get:function(){return $}}),Object.defineProperty(t,"getType",{enumerable:!0,get:function(){return H}}),Object.defineProperty(t,"hasMemoCache",{enumerable:!0,get:function(){return L}}),Object.defineProperty(t,"hasRDTHook",{enumerable:!0,get:function(){return g}}),Object.defineProperty(t,"installRDTHook",{enumerable:!0,get:function(){return m}}),Object.defineProperty(t,"instrument",{enumerable:!0,get:function(){return eo}}),Object.defineProperty(t,"isClientEnvironment",{enumerable:!0,get:function(){return b}}),Object.defineProperty(t,"isCompositeFiber",{enumerable:!0,get:function(){return N}}),Object.defineProperty(t,"isHostFiber",{enumerable:!0,get:function(){return S}}),Object.defineProperty(t,"isInstrumentationActive",{enumerable:!0,get:function(){return B}}),Object.defineProperty(t,"isReactRefresh",{enumerable:!0,get:function(){return u}}),Object.defineProperty(t,"isRealReactDevtools",{enumerable:!0,get:function(){return c}}),Object.defineProperty(t,"isValidElement",{enumerable:!0,get:function(){return j}}),Object.defineProperty(t,"isValidFiber",{enumerable:!0,get:function(){return C}}),Object.defineProperty(t,"mountFiberRecursively",{enumerable:!0,get:function(){return J}}),Object.defineProperty(t,"onCommitFiberRoot",{enumerable:!0,get:function(){return ec}}),Object.defineProperty(t,"patchRDTHook",{enumerable:!0,get:function(){return f}}),Object.defineProperty(t,"safelyInstallRDTHook",{enumerable:!0,get:function(){return w}}),Object.defineProperty(t,"secure",{enumerable:!0,get:function(){return el}}),Object.defineProperty(t,"setFiberId",{enumerable:!0,get:function(){return q}}),Object.defineProperty(t,"shouldFilterFiber",{enumerable:!0,get:function(){return O}}),Object.defineProperty(t,"traverseContexts",{enumerable:!0,get:function(){return T}}),Object.defineProperty(t,"traverseFiber",{enumerable:!0,get:function(){return I}}),Object.defineProperty(t,"traverseProps",{enumerable:!0,get:function(){return z}}),Object.defineProperty(t,"traverseRenderedFibers",{enumerable:!0,get:function(){return er}}),Object.defineProperty(t,"traverseState",{enumerable:!0,get:function(){return E}}),Object.defineProperty(t,"unmountFiber",{enumerable:!0,get:function(){return Z}}),Object.defineProperty(t,"unmountFiberChildrenRecursively",{enumerable:!0,get:function(){return Q}}),Object.defineProperty(t,"updateFiberRecursively",{enumerable:!0,get:function(){return K}}),Object.defineProperty(t,"version",{enumerable:!0,get:function(){return n}})},88091:(e,t,r)=>{r(82399).safelyInstallRDTHook()}}]);
//# sourceMappingURL=39219-24ebcbb66fa9.js.map
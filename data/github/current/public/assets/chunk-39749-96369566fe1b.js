"use strict";(globalThis.webpackChunk_github_ui_github_ui=globalThis.webpackChunk_github_ui_github_ui||[]).push([[39749],{39749:(e,t,r)=>{r.d(t,{Dc:()=>$,Dx:()=>C,GQ:()=>w,Xb:()=>ov,Zf:()=>ob,iX:()=>y,t3:()=>op,xI:()=>f});var n,i,o,l=r(96330),a=!l.S$&&!!l.IJ,s=()=>void 0,d=e=>null!=e,u=e=>"function"!=typeof e||e.length?e:e(),c=e=>Array.isArray(e)?e:e?[e]:[],g=a?e=>(0,l.QQ)()?(0,l.Ki)(e):e:l.Ki,f=function(e){let[t,r]=(0,l.n5)(),n=e?.throw?(e,t)=>{throw r(e instanceof Error?e:Error(t)),e}:(e,t)=>{r(e instanceof Error?e:Error(t))},i=e?.api?Array.isArray(e.api)?e.api:[e.api]:[globalThis.localStorage].filter(Boolean),o=e?.prefix?`${e.prefix}.`:"",a=new Map,s=new Proxy({},{get(t,r){let s=a.get(r);s||(s=(0,l.n5)(void 0,{equals:!1}),a.set(r,s)),s[0]();let d=i.reduce((e,t)=>{if(null!==e||!t)return e;try{return t.getItem(`${o}${r}`)}catch(e){return n(e,`Error reading ${o}${r} from ${t.name}`),null}},null);return null!==d&&e?.deserializer?e.deserializer(d,r,e.options):d}});return e?.sync!==!1&&(0,l.Rc)(()=>{let e=e=>{let t=!1;i.forEach(r=>{try{r!==e.storageArea&&e.key&&e.newValue!==r.getItem(e.key)&&(e.newValue?r.setItem(e.key,e.newValue):r.removeItem(e.key),t=!0)}catch(t){n(t,`Error synching api ${r.name} from storage event (${e.key}=${e.newValue})`)}}),t&&e.key&&a.get(e.key)?.[1]()};"addEventListener"in globalThis?(globalThis.addEventListener("storage",e),(0,l.Ki)(()=>globalThis.removeEventListener("storage",e))):(i.forEach(t=>t.addEventListener?.("storage",e)),(0,l.Ki)(()=>i.forEach(t=>t.removeEventListener?.("storage",e))))}),[s,(t,r,l)=>{let s=e?.serializer?e.serializer(r,t,l??e.options):r,d=`${o}${t}`;i.forEach(e=>{try{e.getItem(d)!==s&&e.setItem(d,s)}catch(r){n(r,`Error setting ${o}${t} to ${s} in ${e.name}`)}});let u=a.get(t);u&&u[1]()},{clear:()=>i.forEach(e=>{try{e.clear()}catch(t){n(t,`Error clearing ${e.name}`)}}),error:t,remove:e=>i.forEach(t=>{try{t.removeItem(`${o}${e}`)}catch(r){n(r,`Error removing ${o}${e} from ${t.name}`)}}),toJSON:()=>{let t={},r=(r,n)=>{if(!t.hasOwnProperty(r)){let i=n&&e?.deserializer?e.deserializer(n,r,e.options):n;i&&(t[r]=i)}};return i.forEach(e=>{if("function"==typeof e.getAll){let t;try{t=e.getAll()}catch(t){n(t,`Error getting all values from in ${e.name}`)}for(let e of t)r(e,t[e])}else{let i=0,o;try{for(;o=e.key(i++);)t.hasOwnProperty(o)||r(o,e.getItem(o))}catch(t){n(t,`Error getting all values from ${e.name}`)}}}),t}}]},p=e=>{if(!e)return"";let t="";for(let r in e){if(!e.hasOwnProperty(r))continue;let n=e[r];t+=n instanceof Date?`; ${r}=${n.toUTCString()}`:"boolean"==typeof n?`; ${r}`:`; ${r}=${n}`}return t},h=("function"==typeof(n={_cookies:[globalThis.document,"cookie"],getItem:e=>h._cookies[0][h._cookies[1]].match("(^|;)\\s*"+e+"\\s*=\\s*([^;]+)")?.pop()??null,setItem:(e,t,r)=>{let n=h.getItem(e);h._cookies[0][h._cookies[1]]=`${e}=${t}${p(r)}`;let i=Object.assign(new Event("storage"),{key:e,oldValue:n,newValue:t,url:globalThis.document.URL,storageArea:h});window.dispatchEvent(i)},removeItem:e=>{h._cookies[0][h._cookies[1]]=`${e}=deleted${p({expires:new Date(0)})}`},key:e=>{let t=null,r=0;return h._cookies[0][h._cookies[1]].replace(/(?:^|;)\s*(.+?)\s*=\s*[^;]+/g,(n,i)=>(!t&&i&&r++===e&&(t=i),"")),t},get length(){let e=0;return h._cookies[0][h._cookies[1]].replace(/(?:^|;)\s*.+?\s*=\s*[^;]+/g,t=>(e+=+!!t,"")),e}}).clear||(n.clear=()=>{let e;for(;e=n.key(0);)n.removeItem(e)}),n),v="bottom",y="system",b=Object.keys(l.O$)[0],m=Object.keys(l.bs)[0],w=(0,l.q6)({client:void 0,onlineManager:void 0,queryFlavor:"",version:"",shadowDOMTarget:void 0});function x(){return(0,l.NT)(w)}var k=(0,l.q6)(void 0),$=e=>{let[t,r]=(0,l.n5)(null),n=()=>{let e=t();null!=e&&(e.close(),r(null))},i=(n,i)=>{if(null!=t())return;let o=window.open("","TSQD-Devtools-Panel",`width=${n},height=${i},popup`);if(!o)throw Error("Failed to open popup. Please allow popups for this site to view the devtools in picture-in-picture mode.");o.document.head.innerHTML="",o.document.body.innerHTML="",(0,l.MQ)(o.document),o.document.title="TanStack Query Devtools",o.document.body.style.margin="0",o.addEventListener("pagehide",()=>{e.setLocalStore("pip_open","false"),r(null)}),[...(x().shadowDOMTarget||document).styleSheets].forEach(e=>{try{let t=[...e.cssRules].map(e=>e.cssText).join(""),r=document.createElement("style"),n=e.ownerNode,i="";n&&"id"in n&&(i=n.id),i&&r.setAttribute("id",i),r.textContent=t,o.document.head.appendChild(r)}catch(r){let t=document.createElement("link");if(null==e.href)return;t.rel="stylesheet",t.type=e.type,t.media=e.media.toString(),t.href=e.href,o.document.head.appendChild(t)}}),(0,l.z_)(["focusin","focusout","pointermove","keydown","pointerdown","pointerup","click","mousedown","input"],o.document),e.setLocalStore("pip_open","true"),r(o)};(0,l.EH)(()=>{"true"!==(e.localStore.pip_open??"false")||e.disabled||i(Number(window.innerWidth),Number(e.localStore.height||500))}),(0,l.EH)(()=>{let e=(x().shadowDOMTarget||document).querySelector("#_goober"),r=t();if(e&&r){let t=new MutationObserver(()=>{let t=(x().shadowDOMTarget||r.document).querySelector("#_goober");t&&(t.textContent=e.textContent)});t.observe(e,{childList:!0,subtree:!0,characterDataOldValue:!0}),(0,l.Ki)(()=>{t.disconnect()})}});let o=(0,l.To)(()=>({pipWindow:t(),requestPipWindow:i,closePipWindow:n,disabled:e.disabled??!1}));return(0,l.a0)(k.Provider,{value:o,get children(){return e.children}})},S=()=>(0,l.To)(()=>{let e=(0,l.NT)(k);if(!e)throw Error("usePiPWindow must be used within a PiPProvider");return e()}),C=(0,l.q6)(()=>"dark");function q(){return(0,l.NT)(C)}var E={"\xc0":"A","\xc1":"A","\xc2":"A","\xc3":"A","\xc4":"A","\xc5":"A",\u1EA4:"A",\u1EAE:"A",\u1EB2:"A",\u1EB4:"A",\u1EB6:"A","\xc6":"AE",\u1EA6:"A",\u1EB0:"A",\u0202:"A","\xc7":"C",\u1E08:"C","\xc8":"E","\xc9":"E","\xca":"E","\xcb":"E",\u1EBE:"E",\u1E16:"E",\u1EC0:"E",\u1E14:"E",\u1E1C:"E",\u0206:"E","\xcc":"I","\xcd":"I","\xce":"I","\xcf":"I",\u1E2E:"I",\u020A:"I","\xd0":"D","\xd1":"N","\xd2":"O","\xd3":"O","\xd4":"O","\xd5":"O","\xd6":"O","\xd8":"O",\u1ED0:"O",\u1E4C:"O",\u1E52:"O",\u020E:"O","\xd9":"U","\xda":"U","\xdb":"U","\xdc":"U","\xdd":"Y","\xe0":"a","\xe1":"a","\xe2":"a","\xe3":"a","\xe4":"a","\xe5":"a",\u1EA5:"a",\u1EAF:"a",\u1EB3:"a",\u1EB5:"a",\u1EB7:"a","\xe6":"ae",\u1EA7:"a",\u1EB1:"a",\u0203:"a","\xe7":"c",\u1E09:"c","\xe8":"e","\xe9":"e","\xea":"e","\xeb":"e",\u1EBF:"e",\u1E17:"e",\u1EC1:"e",\u1E15:"e",\u1E1D:"e",\u0207:"e","\xec":"i","\xed":"i","\xee":"i","\xef":"i",\u1E2F:"i",\u020B:"i","\xf0":"d","\xf1":"n","\xf2":"o","\xf3":"o","\xf4":"o","\xf5":"o","\xf6":"o","\xf8":"o",\u1ED1:"o",\u1E4D:"o",\u1E53:"o",\u020F:"o","\xf9":"u","\xfa":"u","\xfb":"u","\xfc":"u","\xfd":"y","\xff":"y",\u0100:"A",\u0101:"a",\u0102:"A",\u0103:"a",\u0104:"A",\u0105:"a",\u0106:"C",\u0107:"c",\u0108:"C",\u0109:"c",\u010A:"C",\u010B:"c",\u010C:"C",\u010D:"c",C\u0306:"C",c\u0306:"c",\u010E:"D",\u010F:"d",\u0110:"D",\u0111:"d",\u0112:"E",\u0113:"e",\u0114:"E",\u0115:"e",\u0116:"E",\u0117:"e",\u0118:"E",\u0119:"e",\u011A:"E",\u011B:"e",\u011C:"G",\u01F4:"G",\u011D:"g",\u01F5:"g",\u011E:"G",\u011F:"g",\u0120:"G",\u0121:"g",\u0122:"G",\u0123:"g",\u0124:"H",\u0125:"h",\u0126:"H",\u0127:"h",\u1E2A:"H",\u1E2B:"h",\u0128:"I",\u0129:"i",\u012A:"I",\u012B:"i",\u012C:"I",\u012D:"i",\u012E:"I",\u012F:"i",\u0130:"I",\u0131:"i",\u0132:"IJ",\u0133:"ij",\u0134:"J",\u0135:"j",\u0136:"K",\u0137:"k",\u1E30:"K",\u1E31:"k",K\u0306:"K",k\u0306:"k",\u0139:"L",\u013A:"l",\u013B:"L",\u013C:"l",\u013D:"L",\u013E:"l",\u013F:"L",\u0140:"l",\u0141:"l",\u0142:"l",\u1E3E:"M",\u1E3F:"m",M\u0306:"M",m\u0306:"m",\u0143:"N",\u0144:"n",\u0145:"N",\u0146:"n",\u0147:"N",\u0148:"n",\u0149:"n",N\u0306:"N",n\u0306:"n",\u014C:"O",\u014D:"o",\u014E:"O",\u014F:"o",\u0150:"O",\u0151:"o",\u0152:"OE",\u0153:"oe",P\u0306:"P",p\u0306:"p",\u0154:"R",\u0155:"r",\u0156:"R",\u0157:"r",\u0158:"R",\u0159:"r",R\u0306:"R",r\u0306:"r",\u0212:"R",\u0213:"r",\u015A:"S",\u015B:"s",\u015C:"S",\u015D:"s",\u015E:"S",\u0218:"S",\u0219:"s",\u015F:"s",\u0160:"S",\u0161:"s",\u0162:"T",\u0163:"t",\u021B:"t",\u021A:"T",\u0164:"T",\u0165:"t",\u0166:"T",\u0167:"t",T\u0306:"T",t\u0306:"t",\u0168:"U",\u0169:"u",\u016A:"U",\u016B:"u",\u016C:"U",\u016D:"u",\u016E:"U",\u016F:"u",\u0170:"U",\u0171:"u",\u0172:"U",\u0173:"u",\u0216:"U",\u0217:"u",V\u0306:"V",v\u0306:"v",\u0174:"W",\u0175:"w",\u1E82:"W",\u1E83:"w",X\u0306:"X",x\u0306:"x",\u0176:"Y",\u0177:"y",\u0178:"Y",Y\u0306:"Y",y\u0306:"y",\u0179:"Z",\u017A:"z",\u017B:"Z",\u017C:"z",\u017D:"Z",\u017E:"z",\u017F:"s",\u0192:"f",\u01A0:"O",\u01A1:"o",\u01AF:"U",\u01B0:"u",\u01CD:"A",\u01CE:"a",\u01CF:"I",\u01D0:"i",\u01D1:"O",\u01D2:"o",\u01D3:"U",\u01D4:"u",\u01D5:"U",\u01D6:"u",\u01D7:"U",\u01D8:"u",\u01D9:"U",\u01DA:"u",\u01DB:"U",\u01DC:"u",\u1EE8:"U",\u1EE9:"u",\u1E78:"U",\u1E79:"u",\u01FA:"A",\u01FB:"a",\u01FC:"AE",\u01FD:"ae",\u01FE:"O",\u01FF:"o","\xde":"TH","\xfe":"th",\u1E54:"P",\u1E55:"p",\u1E64:"S",\u1E65:"s",X\u0301:"X",x\u0301:"x",\u0403:"\u0413",\u0453:"\u0433",\u040C:"\u041A",\u045C:"\u043A",A\u030B:"A",a\u030B:"a",E\u030B:"E",e\u030B:"e",I\u030B:"I",i\u030B:"i",\u01F8:"N",\u01F9:"n",\u1ED2:"O",\u1ED3:"o",\u1E50:"O",\u1E51:"o",\u1EEA:"U",\u1EEB:"u",\u1E80:"W",\u1E81:"w",\u1EF2:"Y",\u1EF3:"y",\u0200:"A",\u0201:"a",\u0204:"E",\u0205:"e",\u0208:"I",\u0209:"i",\u020C:"O",\u020D:"o",\u0210:"R",\u0211:"r",\u0214:"U",\u0215:"u",B\u030C:"B",b\u030C:"b",\u010C\u0323:"C",\u010D\u0323:"c","\xca\u030C":"E","\xea\u030C":"e",F\u030C:"F",f\u030C:"f",\u01E6:"G",\u01E7:"g",\u021E:"H",\u021F:"h",J\u030C:"J",\u01F0:"j",\u01E8:"K",\u01E9:"k",M\u030C:"M",m\u030C:"m",P\u030C:"P",p\u030C:"p",Q\u030C:"Q",q\u030C:"q",\u0158\u0329:"R",\u0159\u0329:"r",\u1E66:"S",\u1E67:"s",V\u030C:"V",v\u030C:"v",W\u030C:"W",w\u030C:"w",X\u030C:"X",x\u030C:"x",Y\u030C:"Y",y\u030C:"y",A\u0327:"A",a\u0327:"a",B\u0327:"B",b\u0327:"b",\u1E10:"D",\u1E11:"d",\u0228:"E",\u0229:"e",\u0190\u0327:"E",\u025B\u0327:"e",\u1E28:"H",\u1E29:"h",I\u0327:"I",i\u0327:"i",\u0197\u0327:"I",\u0268\u0327:"i",M\u0327:"M",m\u0327:"m",O\u0327:"O",o\u0327:"o",Q\u0327:"Q",q\u0327:"q",U\u0327:"U",u\u0327:"u",X\u0327:"X",x\u0327:"x",Z\u0327:"Z",z\u0327:"z"},T=RegExp(Object.keys(E).join("|"),"g");function M(e,t,r){var n;if((r=r||{}).threshold=null!=(n=r.threshold)?n:1,!r.accessors){let n=F(e,t,r);return{rankedValue:e,rank:n,accessorIndex:-1,accessorThreshold:r.threshold,passed:n>=r.threshold}}let i=function(e,t){let r=[];for(let i=0,o=t.length;i<o;i++){var n;let o=t[i],l="function"==typeof(n=o)?z:{...z,...n},a=function(e,t){let r=t;"object"==typeof t&&(r=t.accessor);let n=r(e);return null==n?[]:Array.isArray(n)?n:[String(n)]}(e,o);for(let e=0,t=a.length;e<t;e++)r.push({itemValue:a[e],attributes:l})}return r}(e,r.accessors),o={rankedValue:e,rank:0,accessorIndex:-1,accessorThreshold:r.threshold,passed:!1};for(let e=0;e<i.length;e++){let n=i[e],l=F(n.itemValue,t,r),{minRanking:a,maxRanking:s,threshold:d=r.threshold}=n.attributes;l<a&&l>=1?l=a:l>s&&(l=s),(l=Math.min(l,s))>=d&&l>o.rank&&(o.rank=l,o.passed=!0,o.accessorIndex=e,o.accessorThreshold=d,o.rankedValue=n.itemValue)}return o}function F(e,t,r){let n;return(e=D(e,r),(t=D(t,r)).length>e.length)?0:e===t?7:(e=e.toLowerCase())===(t=t.toLowerCase())?6:e.startsWith(t)?5:e.includes(` ${t}`)?4:e.includes(t)?3:1===t.length?0:(n="",e.split(" ").forEach(e=>{e.split("-").forEach(e=>{n+=e.substr(0,1)})}),n).includes(t)?2:function(e,t){let r=0,n=0;function i(e,t,n){for(let i=n,o=t.length;i<o;i++)if(t[i]===e)return r+=1,i+1;return -1}let o=i(t[0],e,0);if(o<0)return 0;n=o;for(let r=1,o=t.length;r<o;r++)if(!((n=i(t[r],e,n))>-1))return 0;return 1+1/(n-o)*(r/t.length)}(e,t)}function D(e,t){let{keepDiacritics:r}=t;return e=`${e}`,r||(e=e.replace(T,e=>E[e])),e}var z={maxRanking:1/0,minRanking:-1/0},L={data:""},O=/(?:([\u0080-\uFFFF\w-%@]+) *:? *([^{;]+?);|([^;}{]*?) *{)|(}\s*)/g,A=/\/\*[^]*?\*\/|  +/g,I=/\n+/g,K=(e,t)=>{let r="",n="",i="";for(let o in e){let l=e[o];"@"==o[0]?"i"==o[1]?r=o+" "+l+";":n+="f"==o[1]?K(l,o):o+"{"+K(l,"k"==o[1]?"":t)+"}":"object"==typeof l?n+=K(l,t?t.replace(/([^,])+/g,e=>o.replace(/([^,]*:\S+\([^)]*\))|([^,])+/g,t=>/&/.test(t)?t.replace(/&/g,e):e?e+" "+t:t)):o):null!=l&&(o=/^--/.test(o)?o:o.replace(/[A-Z]/g,"-$&").toLowerCase(),i+=K.p?K.p(o,l):o+":"+l+";")}return r+(t&&i?t+"{"+i+"}":i)+n},P={},B=e=>{if("object"==typeof e){let t="";for(let r in e)t+=r+B(e[r]);return t}return e};function R(e){let t,r,n,i=this||{},o=e.call?e(i.p):e;return((e,t,r,n,i)=>{var o;let l=B(e),a=P[l]||(P[l]=(e=>{let t=0,r=11;for(;t<e.length;)r=101*r+e.charCodeAt(t++)>>>0;return"go"+r})(l));if(!P[a]){let t=l!==e?e:(e=>{let t,r,n=[{}];for(;t=O.exec(e.replace(A,""));)t[4]?n.shift():t[3]?(r=t[3].replace(I," ").trim(),n.unshift(n[0][r]=n[0][r]||{})):n[0][t[1]]=t[2].replace(I," ").trim();return n[0]})(e);P[a]=K(i?{["@keyframes "+a]:t}:t,r?"":"."+a)}let s=r&&P.g?P.g:null;return r&&(P.g=P[a]),o=P[a],s?t.data=t.data.replace(s,o):-1===t.data.indexOf(o)&&(t.data=n?o+t.data:t.data+o),a})(o.unshift?o.raw?(t=[].slice.call(arguments,1),r=i.p,o.reduce((e,n,i)=>{let o=t[i];if(o&&o.call){let e=o(r),t=e&&e.props&&e.props.className||/^go/.test(e)&&e;o=t?"."+t:e&&"object"==typeof e?e.props?"":K(e,""):!1===e?"":e}return e+n+(null==o?"":o)},"")):o.reduce((e,t)=>Object.assign(e,t&&t.call?t(i.p):t),{}):o,(n=i.target,"object"==typeof window?((n?n.querySelector("#_goober"):window._goober)||Object.assign((n||document.head).appendChild(document.createElement("style")),{innerHTML:" ",id:"_goober"})).firstChild:n||L),i.g,i.o,i.k)}function H(){for(var e,t,r=0,n="",i=arguments.length;r<i;r++)(e=arguments[r])&&(t=function e(t){var r,n,i="";if("string"==typeof t||"number"==typeof t)i+=t;else if("object"==typeof t)if(Array.isArray(t)){var o=t.length;for(r=0;r<o;r++)t[r]&&(n=e(t[r]))&&(i&&(i+=" "),i+=n)}else for(n in t)t[n]&&(i&&(i+=" "),i+=n);return i}(e))&&(n&&(n+=" "),n+=t);return n}function G(...e){return(...t)=>{for(let r of e)r&&r(...t)}}R.bind({g:1}),R.bind({k:1});var U=l.S$?e=>null!=e&&"object"==typeof e&&"t"in e:e=>e instanceof Element;function Y(e){requestAnimationFrame(()=>requestAnimationFrame(e))}var V=e=>{let t=(0,l.To)(()=>{let t=e.name||"s";return{enterActive:(e.enterActiveClass||t+"-enter-active").split(" "),enter:(e.enterClass||t+"-enter").split(" "),enterTo:(e.enterToClass||t+"-enter-to").split(" "),exitActive:(e.exitActiveClass||t+"-exit-active").split(" "),exit:(e.exitClass||t+"-exit").split(" "),exitTo:(e.exitToClass||t+"-exit-to").split(" "),move:(e.moveClass||t+"-move").split(" ")}});return function(e,t){let r=(0,l.vz)(e);if(l.S$){let e=r.slice();return()=>e}let{onChange:n}=t,i=new Set(t.appear?void 0:r),o=new WeakSet,[a,s]=(0,l.n5)([],{equals:!1}),[d]=(0,l.pn)(),u=e=>{for(let t of(s(t=>(t.push.apply(t,e),t)),e))o.delete(t)},c=(e,t,r)=>e.splice(r,0,t);return(0,l.To)(t=>{let r=a(),s=e();if(s[l.WX],(0,l.vz)(d))return d(),t;if(r.length){let e=t.filter(e=>!r.includes(e));return r.length=0,n({list:e,added:[],removed:[],unchanged:e,finishRemoved:u}),e}return(0,l.vz)(()=>{let e=new Set(s),r=s.slice(),l=[],a=[],d=[];for(let e of s)(i.has(e)?d:l).push(e);let g=!l.length;for(let n=0;n<t.length;n++){let i=t[n];e.has(i)||(o.has(i)||(a.push(i),o.add(i)),c(r,i,n)),g&&i!==r[n]&&(g=!1)}return!a.length&&g?t:(n({list:r,added:l,removed:a,unchanged:d,finishRemoved:u}),i=e,r)})},t.appear?[]:r.slice())}(function(e,t=U,r=U){let n=(0,l.To)(e),i=(0,l.To)(()=>(function e(t,r){if(r(t))return t;if("function"==typeof t&&!t.length)return e(t(),r);if(Array.isArray(t)){let n=[];for(let i of t){let t=e(i,r);t&&(Array.isArray(t)?n.push.apply(n,t):n.push(t))}return n.length?n:null}return null})(n(),l.S$?r:t));return i.toArray=()=>{let e=i();return Array.isArray(e)?e:e?[e]:[]},i}(()=>e.children).toArray,{appear:e.appear,onChange({added:r,removed:n,finishRemoved:i,list:o}){let l=t();for(let t of r)!function(e,t,r,n){let{onBeforeEnter:i,onEnter:o,onAfterEnter:l}=t;function a(t){t&&t.target!==r||(r.removeEventListener("transitionend",a),r.removeEventListener("animationend",a),r.classList.remove(...e.enterActive),r.classList.remove(...e.enterTo),l?.(r))}i?.(r),r.classList.add(...e.enter),r.classList.add(...e.enterActive),queueMicrotask(()=>{r.parentNode&&o?.(r,()=>a())}),Y(()=>{r.classList.remove(...e.enter),r.classList.add(...e.enterTo),(!o||o.length<2)&&(r.addEventListener("transitionend",a),r.addEventListener("animationend",a))})}(l,e,t);let a=[];for(let e of o)e.isConnected&&(e instanceof HTMLElement||e instanceof SVGElement)&&a.push({el:e,rect:e.getBoundingClientRect()});for(let t of(queueMicrotask(()=>{let e=[];for(let{el:t,rect:r}of a)if(t.isConnected){let n=t.getBoundingClientRect(),i=r.left-n.left,o=r.top-n.top;(i||o)&&(t.style.transform=`translate(${i}px, ${o}px)`,t.style.transitionDuration="0s",e.push(t))}for(let t of(document.body.offsetHeight,e)){let e=function(r){(r.target===t||/transform$/.test(r.propertyName))&&(t.removeEventListener("transitionend",e),t.classList.remove(...l.move))};t.classList.add(...l.move),t.style.transform=t.style.transitionDuration="",t.addEventListener("transitionend",e)}}),n))!function(e,t,r,n){let{onBeforeExit:i,onExit:o,onAfterExit:l}=t;if(!r.parentNode)return n?.();function a(t){t&&t.target!==r||(n?.(),r.removeEventListener("transitionend",a),r.removeEventListener("animationend",a),r.classList.remove(...e.exitActive),r.classList.remove(...e.exitTo),l?.(r))}i?.(r),r.classList.add(...e.exit),r.classList.add(...e.exitActive),o?.(r,()=>a()),Y(()=>{r.classList.remove(...e.exit),r.classList.add(...e.exitTo),(!o||o.length<2)&&(r.addEventListener("transitionend",a),r.addEventListener("animationend",a))})}(l,e,t,()=>i([t]))}})},N=Symbol("fallback");function j(e){for(let t of e)t.dispose()}function Q(e){let{by:t}=e;return(0,l.To)(function(e,t,r,n={}){if(l.S$){let t=e(),i=[];if(t&&t.length)for(let e=0,n=t.length;e<n;e++)i.push(r(()=>t[e],()=>e));else n.fallback&&(i=[n.fallback()]);return()=>i}let i=new Map;return(0,l.Ki)(()=>j(i.values())),()=>{let r=e()||[];return r[l.WX],(0,l.vz)(()=>{if(!r.length)return(j(i.values()),i.clear(),n.fallback)?[(0,l.Hr)(e=>(i.set(N,{dispose:e}),n.fallback()))]:[];let e=Array(r.length),a=i.get(N);if(!i.size||a){a?.dispose(),i.delete(N);for(let n=0;n<r.length;n++){let i=r[n],l=t(i,n);o(e,i,n,l)}return e}let s=new Set(i.keys());for(let n=0;n<r.length;n++){let l=r[n],a=t(l,n);s.delete(a);let d=i.get(a);d?(e[n]=d.mapped,d.setIndex?.(n),d.setItem(()=>l)):o(e,l,n,a)}for(let e of s)i.get(e)?.dispose(),i.delete(e);return e})};function o(e,t,n,o){(0,l.Hr)(a=>{let[s,d]=(0,l.n5)(t),u={setItem:d,dispose:a};if(r.length>1){let[e,t]=(0,l.n5)(n);u.setIndex=t,u.mapped=r(s,e)}else u.mapped=r(s);i.set(o,u),e[n]=u.mapped})}}(()=>e.each,"function"==typeof t?t:e=>e[t],e.children,"fallback"in e?{fallback:()=>e.fallback}:void 0))}function W(e,t,r){if(l.S$)return;let n=new WeakMap,{observe:i,unobserve:o}=function(e,t){if(l.S$)return{observe:s,unobserve:s};let r=new ResizeObserver(e);return(0,l.Ki)(r.disconnect.bind(r)),{observe:e=>r.observe(e,t),unobserve:r.unobserve.bind(r)}}(e=>{for(let r of e){let{contentRect:e,target:i}=r,o=Math.round(e.width),l=Math.round(e.height),a=n.get(i);a&&a.width===o&&a.height===l||(t(e,i,r),n.set(i,{width:o,height:l}))}},r);(0,l.EH)(t=>{let r=c(u(e)).filter(d);return!function(e,t,r,n){let i,o,l=e.length,a=t.length,s=0;if(!a){for(;s<l;s++)r(e[s]);return}if(!l){for(;s<a;s++)n(t[s]);return}for(;s<a&&t[s]===e[s];s++);for(i of(t=t.slice(s),e=e.slice(s),t))e.includes(i)||n(i);for(o of e)t.includes(o)||r(o)}(r,t,i,o),r},[])}var _=/((?:--)?(?:\w+-?)+)\s*:\s*([^;]*)/g;function Z(e){let t,r={};for(;t=_.exec(e);)r[t[1]]=t[2];return r}function X(e,t){if("string"==typeof e){if("string"==typeof t)return`${e};${t}`;e=Z(e)}else"string"==typeof t&&(t=Z(t));return{...e,...t}}function J(e,t){let r=[...e],n=r.indexOf(t);return -1!==n&&r.splice(n,1),r}function ee(e){return"[object String]"===Object.prototype.toString.call(e)}function et(e){return t=>`${e()}-${t}`}function er(e,t){return!!e&&(e===t||e.contains(t))}function en(e,t=!1){let{activeElement:r}=ei(e);if(!r?.nodeName)return null;if(eo(r)&&r.contentDocument)return en(r.contentDocument.body,t);if(t){let e=r.getAttribute("aria-activedescendant");if(e){let t=ei(r).getElementById(e);if(t)return t}}return r}function ei(e){return e?e.ownerDocument||e:document}function eo(e){return"IFRAME"===e.tagName}var el=((i=el||{}).Escape="Escape",i.Enter="Enter",i.Tab="Tab",i.Space=" ",i.ArrowDown="ArrowDown",i.ArrowLeft="ArrowLeft",i.ArrowRight="ArrowRight",i.ArrowUp="ArrowUp",i.End="End",i.Home="Home",i.PageDown="PageDown",i.PageUp="PageUp",i);function ea(e){return"undefined"!=typeof window&&null!=window.navigator&&e.test(window.navigator.userAgentData?.platform||window.navigator.platform)}function es(){return ea(/^Mac/i)}function ed(e,t){return t&&("function"==typeof t?t(e):t[0](t[1],e)),e?.defaultPrevented}function eu(e){return t=>{for(let r of e)ed(t,r)}}function ec(e){if(e)if(function(){if(null==eg){eg=!1;try{document.createElement("div").focus({get preventScroll(){return eg=!0,!0}})}catch(e){}}return eg}())e.focus({preventScroll:!0});else{let t=function(e){let t=e.parentNode,r=[],n=document.scrollingElement||document.documentElement;for(;t instanceof HTMLElement&&t!==n;)(t.offsetHeight<t.scrollHeight||t.offsetWidth<t.scrollWidth)&&r.push({element:t,scrollTop:t.scrollTop,scrollLeft:t.scrollLeft}),t=t.parentNode;return n instanceof HTMLElement&&r.push({element:n,scrollTop:n.scrollTop,scrollLeft:n.scrollLeft}),r}(e);e.focus(),function(e){for(let{element:t,scrollTop:r,scrollLeft:n}of e)t.scrollTop=r,t.scrollLeft=n}(t)}}var eg=null,ef=["input:not([type='hidden']):not([disabled])","select:not([disabled])","textarea:not([disabled])","button:not([disabled])","a[href]","area[href]","[tabindex]","iframe","object","embed","audio[controls]","video[controls]","[contenteditable]:not([contenteditable='false'])"],ep=[...ef,'[tabindex]:not([tabindex="-1"]):not([disabled])'],eh=ef.join(":not([hidden]),")+",[tabindex]:not([disabled]):not([hidden])",ev=ep.join(':not([hidden]):not([tabindex="-1"]),');function ey(e){return eb(e)&&!(0>parseInt(e.getAttribute("tabindex")||"0",10))}function eb(e){return e.matches(eh)&&em(e)}function em(e,t){var r,n;return"#comment"!==e.nodeName&&function(e){if(!(e instanceof HTMLElement)&&!(e instanceof SVGElement))return!1;let{display:t,visibility:r}=e.style,n="none"!==t&&"hidden"!==r&&"collapse"!==r;if(n){if(!e.ownerDocument.defaultView)return n;let{getComputedStyle:t}=e.ownerDocument.defaultView,{display:r,visibility:i}=t(e);n="none"!==r&&"hidden"!==i&&"collapse"!==i}return n}(e)&&(r=e,n=t,!r.hasAttribute("hidden")&&("DETAILS"!==r.nodeName||!n||"SUMMARY"===n.nodeName||r.hasAttribute("open")))&&(!e.parentElement||em(e.parentElement,e))}function ew(e){var t;let r;for(;e&&(t=e,r=window.getComputedStyle(t),!/(auto|scroll)/.test(r.overflow+r.overflowX+r.overflowY));)e=e.parentElement;return e||document.scrollingElement||document.documentElement}function ex(){}function ek(e,t){return(0,l.v6)(e,t)}var e$=new Map,eS=new Set;function eC(){if("undefined"==typeof window)return;let e=t=>{if(!t.target)return;let r=e$.get(t.target);if(r&&(r.delete(t.propertyName),0===r.size&&(t.target.removeEventListener("transitioncancel",e),e$.delete(t.target)),0===e$.size)){for(let e of eS)e();eS.clear()}};document.body.addEventListener("transitionrun",t=>{if(!t.target)return;let r=e$.get(t.target);r||(r=new Set,e$.set(t.target,r),t.target.addEventListener("transitioncancel",e)),r.add(t.propertyName)}),document.body.addEventListener("transitionend",e)}function eq(e,t){let r=eE(e,t,"left"),n=eE(e,t,"top"),i=t.offsetWidth,o=t.offsetHeight,l=e.scrollLeft,a=e.scrollTop,s=l+e.offsetWidth,d=a+e.offsetHeight;r<=l?l=r:r+i>s&&(l+=r+i-s),n<=a?a=n:n+o>d&&(a+=n+o-d),e.scrollLeft=l,e.scrollTop=a}function eE(e,t,r){let n="left"===r?"offsetLeft":"offsetTop",i=0;for(;t.offsetParent&&(i+=t[n],t.offsetParent!==e);){if(t.offsetParent.contains(e)){i-=e[n];break}t=t.offsetParent}return i}"undefined"!=typeof document&&("loading"!==document.readyState?eC():document.addEventListener("DOMContentLoaded",eC));var eT={border:"0",clip:"rect(0 0 0 0)","clip-path":"inset(50%)",height:"1px",margin:"0 -1px -1px 0",overflow:"hidden",padding:"0",position:"absolute",width:"1px","white-space":"nowrap"};function eM(e){return t=>(e(t),()=>e(void 0))}function eF(e,t){let[r,n]=(0,l.n5)(eD(t?.()));return(0,l.EH)(()=>{n(e()?.tagName.toLowerCase()||eD(t?.()))}),r}function eD(e){return ee(e)?e:void 0}function ez(e){let[t,r]=(0,l.rg)(e,["as"]);if(!t.as)throw Error("[kobalte]: Polymorphic is missing the required `as` prop.");return(0,l.a0)(l.Qi,(0,l.v6)(r,{get component(){return t.as}}))}var eL=["id","name","validationState","required","disabled","readOnly"],eO=(0,l.q6)();function eA(){let e=(0,l.NT)(eO);if(void 0===e)throw Error("[kobalte]: `useFormControlContext` must be used within a `FormControlContext.Provider` component");return e}function eI(e){let t=eA(),r=ek({id:t.generateId("description")},e);return(0,l.EH)(()=>(0,l.Ki)(t.registerDescription(r.id))),(0,l.a0)(ez,(0,l.v6)({as:"div"},()=>t.dataset(),r))}function eK(e){let t=eA(),r=ek({id:t.generateId("error-message")},e),[n,i]=(0,l.rg)(r,["forceMount"]);return(0,l.EH)(()=>{"invalid"===t.validationState()&&(0,l.Ki)(t.registerErrorMessage(i.id))}),(0,l.a0)(l.wv,{get when(){return n.forceMount||"invalid"===t.validationState()},get children(){return(0,l.a0)(ez,(0,l.v6)({as:"div"},()=>t.dataset(),i))}})}function eP(e){let t,r=eA(),n=ek({id:r.generateId("label")},e),[i,o]=(0,l.rg)(n,["ref"]),a=eF(()=>t,()=>"label");return(0,l.EH)(()=>(0,l.Ki)(r.registerLabel(o.id))),(0,l.a0)(ez,(0,l.v6)({as:"label",ref(e){let r=G(e=>t=e,i.ref);"function"==typeof r&&r(e)},get for(){return(0,l.ph)(()=>"label"===a())()?r.fieldId():void 0}},()=>r.dataset(),o))}function eB(e){let[t,r]=(0,l.n5)(e.defaultValue?.()),n=(0,l.To)(()=>e.value?.()!==void 0),i=(0,l.To)(()=>n()?e.value?.():t());return[i,t=>{(0,l.vz)(()=>{let o=function(e,...t){return"function"==typeof e?e(...t):e}(t,i());return Object.is(o,i())||(n()||r(o),e.onChange?.(o)),o})}]}function eR(e){let[t,r]=eB(e);return[()=>t()??!1,r]}var eH=Object.defineProperty,eG=(e,t)=>{for(var r in t)eH(e,r,{get:t[r],enumerable:!0})},eU=(0,l.q6)();function eY(e,t){return!!(t.compareDocumentPosition(e)&Node.DOCUMENT_POSITION_PRECEDING)}function eV(e,t){let r,n,i=(r=e.map((e,t)=>[t,e]),n=!1,(r.sort(([e,t],[r,i])=>{let o=t.ref(),l=i.ref();return o!==l&&o&&l?eY(o,l)?(e>r&&(n=!0),-1):(e<r&&(n=!0),1):0}),n)?r.map(([e,t])=>t):e);e!==i&&t(i)}var eN=new Set(["Avst","Arab","Armi","Syrc","Samr","Mand","Thaa","Mend","Nkoo","Adlm","Rohg","Hebr"]),ej=new Set(["ae","ar","arc","bcc","bqi","ckb","dv","fa","glk","he","ku","mzn","nqo","pnb","ps","sd","ug","ur","yi"]);function eQ(){let e="undefined"!=typeof navigator&&(navigator.language||navigator.userLanguage)||"en-US";return{locale:e,direction:!function(e){if(Intl.Locale){let t=new Intl.Locale(e).maximize().script??"";return eN.has(t)}let t=e.split("-")[0];return ej.has(t)}(e)?"ltr":"rtl"}}var eW=eQ(),e_=new Set;function eZ(){for(let e of(eW=eQ(),e_))e(eW)}var eX=(0,l.q6)();function eJ(){let e=function(){let e={locale:"en-US",direction:"ltr"},[t,r]=(0,l.n5)(eW),n=(0,l.To)(()=>l.S$?e:t());return(0,l.Rc)(()=>{0===e_.size&&window.addEventListener("languagechange",eZ),e_.add(r),(0,l.Ki)(()=>{e_.delete(r),0===e_.size&&window.removeEventListener("languagechange",eZ)})}),{locale:()=>n().locale,direction:()=>n().direction}}();return(0,l.NT)(eX)||e}var e0=new Map,e1=class _Selection extends Set{anchorKey;currentKey;constructor(e,t,r){super(e),e instanceof _Selection?(this.anchorKey=t||e.anchorKey,this.currentKey=r||e.currentKey):(this.anchorKey=t,this.currentKey=r)}};function e2(e){return es()||ea(/^iPhone/i)||ea(/^iPad/i)||es()&&navigator.maxTouchPoints>1?e.altKey:e.ctrlKey}function e5(e){return es()?e.metaKey:e.ctrlKey}function e3(e,t){let r=()=>u(e.key),n=()=>u(e.shouldUseVirtualFocus),i=t=>{"none"!==u(e.selectionManager).selectionMode()&&("single"===u(e.selectionManager).selectionMode()?u(e.selectionManager).isSelected(r())&&!u(e.selectionManager).disallowEmptySelection()?u(e.selectionManager).toggleSelection(r()):u(e.selectionManager).replaceSelection(r()):t?.shiftKey?u(e.selectionManager).extendSelection(r()):"toggle"===u(e.selectionManager).selectionBehavior()||e5(t)||"pointerType"in t&&"touch"===t.pointerType?u(e.selectionManager).toggleSelection(r()):u(e.selectionManager).replaceSelection(r()))},o=()=>u(e.disabled)||u(e.selectionManager).isDisabled(r()),a=()=>!o()&&u(e.selectionManager).canSelectItem(r()),s=null,d=(0,l.To)(()=>{if(!(n()||o()))return r()===u(e.selectionManager).focusedKey()?0:-1}),c=(0,l.To)(()=>u(e.virtualized)?void 0:r());return(0,l.EH)((0,l.on)([t,r,n,()=>u(e.selectionManager).focusedKey(),()=>u(e.selectionManager).isFocused()],([t,r,n,i,o])=>{t&&r===i&&o&&!n&&document.activeElement!==t&&(e.focus?e.focus():ec(t))})),{isSelected:()=>u(e.selectionManager).isSelected(r()),isDisabled:o,allowsSelection:a,tabIndex:d,dataKey:c,onPointerDown:t=>{a()&&(s=t.pointerType,"mouse"!==t.pointerType||0!==t.button||u(e.shouldSelectOnPressUp)||i(t))},onPointerUp:t=>{a()&&"mouse"===t.pointerType&&0===t.button&&u(e.shouldSelectOnPressUp)&&u(e.allowsDifferentPressOrigin)&&i(t)},onClick:t=>{a()&&(u(e.shouldSelectOnPressUp)&&!u(e.allowsDifferentPressOrigin)||"mouse"!==s)&&i(t)},onKeyDown:t=>{a()&&["Enter"," "].includes(t.key)&&(e2(t)?u(e.selectionManager).toggleSelection(r()):i(t))},onMouseDown:e=>{o()&&e.preventDefault()},onFocus:i=>{let l=t();!(n()||o())&&l&&i.target===l&&u(e.selectionManager).setFocusedKey(r())}}}var e4=class{collection;state;constructor(e,t){this.collection=e,this.state=t}selectionMode(){return this.state.selectionMode()}disallowEmptySelection(){return this.state.disallowEmptySelection()}selectionBehavior(){return this.state.selectionBehavior()}setSelectionBehavior(e){this.state.setSelectionBehavior(e)}isFocused(){return this.state.isFocused()}setFocused(e){this.state.setFocused(e)}focusedKey(){return this.state.focusedKey()}setFocusedKey(e){(null==e||this.collection().getItem(e))&&this.state.setFocusedKey(e)}selectedKeys(){return this.state.selectedKeys()}isSelected(e){if("none"===this.state.selectionMode())return!1;let t=this.getKey(e);return null!=t&&this.state.selectedKeys().has(t)}isEmpty(){return 0===this.state.selectedKeys().size}isSelectAll(){if(this.isEmpty())return!1;let e=this.state.selectedKeys();return this.getAllSelectableKeys().every(t=>e.has(t))}firstSelectedKey(){let e;for(let t of this.state.selectedKeys()){let r=this.collection().getItem(t),n=r?.index!=null&&e?.index!=null&&r.index<e.index;(!e||n)&&(e=r)}return e?.key}lastSelectedKey(){let e;for(let t of this.state.selectedKeys()){let r=this.collection().getItem(t),n=r?.index!=null&&e?.index!=null&&r.index>e.index;(!e||n)&&(e=r)}return e?.key}extendSelection(e){if("none"===this.selectionMode())return;if("single"===this.selectionMode())return void this.replaceSelection(e);let t=this.getKey(e);if(null==t)return;let r=this.state.selectedKeys(),n=r.anchorKey||t,i=new e1(r,n,t);for(let e of this.getKeyRange(n,r.currentKey||t))i.delete(e);for(let e of this.getKeyRange(t,n))this.canSelectItem(e)&&i.add(e);this.state.setSelectedKeys(i)}getKeyRange(e,t){let r=this.collection().getItem(e),n=this.collection().getItem(t);return r&&n?null!=r.index&&null!=n.index&&r.index<=n.index?this.getKeyRangeInternal(e,t):this.getKeyRangeInternal(t,e):[]}getKeyRangeInternal(e,t){let r=[],n=e;for(;null!=n;){let e=this.collection().getItem(n);if(e&&"item"===e.type&&r.push(n),n===t)return r;n=this.collection().getKeyAfter(n)}return[]}getKey(e){let t=this.collection().getItem(e);return t?t&&"item"===t.type?t.key:null:e}toggleSelection(e){if("none"===this.selectionMode())return;if("single"===this.selectionMode()&&!this.isSelected(e))return void this.replaceSelection(e);let t=this.getKey(e);if(null==t)return;let r=new e1(this.state.selectedKeys());r.has(t)?r.delete(t):this.canSelectItem(t)&&(r.add(t),r.anchorKey=t,r.currentKey=t),this.disallowEmptySelection()&&0===r.size||this.state.setSelectedKeys(r)}replaceSelection(e){if("none"===this.selectionMode())return;let t=this.getKey(e);if(null==t)return;let r=this.canSelectItem(t)?new e1([t],t,t):new e1;this.state.setSelectedKeys(r)}setSelectedKeys(e){if("none"===this.selectionMode())return;let t=new e1;for(let r of e){let e=this.getKey(r);if(null!=e&&(t.add(e),"single"===this.selectionMode()))break}this.state.setSelectedKeys(t)}selectAll(){"multiple"===this.selectionMode()&&this.state.setSelectedKeys(new Set(this.getAllSelectableKeys()))}clearSelection(){let e=this.state.selectedKeys();!this.disallowEmptySelection()&&e.size>0&&this.state.setSelectedKeys(new e1)}toggleSelectAll(){this.isSelectAll()?this.clearSelection():this.selectAll()}select(e,t){"none"!==this.selectionMode()&&("single"===this.selectionMode()?this.isSelected(e)&&!this.disallowEmptySelection()?this.toggleSelection(e):this.replaceSelection(e):"toggle"===this.selectionBehavior()||t&&"touch"===t.pointerType?this.toggleSelection(e):this.replaceSelection(e))}isSelectionEqual(e){if(e===this.state.selectedKeys())return!0;let t=this.selectedKeys();if(e.size!==t.size)return!1;for(let r of e)if(!t.has(r))return!1;for(let r of t)if(!e.has(r))return!1;return!0}canSelectItem(e){if("none"===this.state.selectionMode())return!1;let t=this.collection().getItem(e);return null!=t&&!t.disabled}isDisabled(e){let t=this.collection().getItem(e);return!t||t.disabled}getAllSelectableKeys(){let e=[];return(t=>{for(;null!=t;){if(this.canSelectItem(t)){let r=this.collection().getItem(t);if(!r)continue;"item"===r.type&&e.push(t)}t=this.collection().getKeyAfter(t)}})(this.collection().getFirstKey()),e}},e6=class{keyMap=new Map;iterable;firstKey;lastKey;constructor(e){let t;for(const t of(this.iterable=e,e))this.keyMap.set(t.key,t);if(0===this.keyMap.size)return;let r=0;for(const[e,n]of this.keyMap)t?(t.nextKey=e,n.prevKey=t.key):(this.firstKey=e,n.prevKey=void 0),"item"===n.type&&(n.index=r++),(t=n).nextKey=void 0;this.lastKey=t.key}*[Symbol.iterator](){yield*this.iterable}getSize(){return this.keyMap.size}getKeys(){return this.keyMap.keys()}getKeyBefore(e){return this.keyMap.get(e)?.prevKey}getKeyAfter(e){return this.keyMap.get(e)?.nextKey}getFirstKey(){return this.firstKey}getLastKey(){return this.lastKey}getItem(e){return this.keyMap.get(e)}at(e){let t=[...this.getKeys()];return this.getItem(t[e])}},e7=e=>"function"==typeof e?e():e,e9=e=>{let t=(0,l.To)(()=>{let t=e7(e.element);if(t)return getComputedStyle(t)}),r=()=>t()?.animationName??"none",[n,i]=(0,l.n5)(e7(e.show)?"present":"hidden"),o="none";return(0,l.EH)(n=>{let a=e7(e.show);return(0,l.vz)(()=>{if(n===a)return a;let e=o,l=r();a?i("present"):"none"===l||t()?.display==="none"?i("hidden"):!0===n&&e!==l?i("hiding"):i("hidden")}),a}),(0,l.EH)(()=>{let t=e7(e.element);if(!t)return;let a=e=>{e.target===t&&(o=r())},s=e=>{let o=r().includes(e.animationName);e.target===t&&o&&"hiding"===n()&&i("hidden")};t.addEventListener("animationstart",a),t.addEventListener("animationcancel",s),t.addEventListener("animationend",s),(0,l.Ki)(()=>{t.removeEventListener("animationstart",a),t.removeEventListener("animationcancel",s),t.removeEventListener("animationend",s)})}),{present:()=>"present"===n()||"hiding"===n(),state:n}},e8="data-kb-top-layer",te=!1,tt=[];function tr(e){return tt.findIndex(t=>t.node===e)}function tn(){return tt.filter(e=>e.isPointerBlocking)}function ti(){return tn().length>0}function to(e){let t=tr([...tn()].slice(-1)[0]?.node);return tr(e)<t}var tl=function(e){return tt[tt.length-1].node===e},ta=function(e){tt.push(e)},ts=function(e){let t=tr(e);t<0||tt.splice(t,1)},td=function(){for(let{node:e}of tt)e.style.pointerEvents=to(e)?"none":"auto"},tu=function(e){if(ti()&&!te){let t=ei(e);o=document.body.style.pointerEvents,t.body.style.pointerEvents="none",te=!0}},tc=function(e){if(ti())return;let t=ei(e);t.body.style.pointerEvents=o,0===t.body.style.length&&t.body.removeAttribute("style"),te=!1};eG({},{Button:()=>tp,Root:()=>tf});var tg=["button","color","file","image","reset","submit"];function tf(e){let t,r=ek({type:"button"},e),[n,i]=(0,l.rg)(r,["ref","type","disabled"]),o=eF(()=>t,()=>"button"),a=(0,l.To)(()=>{var e;let t,r=o();return null!=r&&("button"===(t=(e={tagName:r,type:n.type}).tagName.toLowerCase())||"input"===t&&!!e.type&&-1!==tg.indexOf(e.type))}),s=(0,l.To)(()=>"input"===o()),d=(0,l.To)(()=>"a"===o()&&t?.getAttribute("href")!=null);return(0,l.a0)(ez,(0,l.v6)({as:"button",ref(e){let r=G(e=>t=e,n.ref);"function"==typeof r&&r(e)},get type(){return a()||s()?n.type:void 0},get role(){return a()||d()?void 0:"button"},get tabIndex(){return a()||d()||n.disabled?void 0:0},get disabled(){return a()||s()?n.disabled:void 0},get"aria-disabled"(){return!(a()||s())&&!!n.disabled||void 0},get"data-disabled"(){return n.disabled?"":void 0}},i))}var tp=tf,th=["top","right","bottom","left"],tv=Math.min,ty=Math.max,tb=Math.round,tm=Math.floor,tw=e=>({x:e,y:e}),tx={left:"right",right:"left",bottom:"top",top:"bottom"},tk={start:"end",end:"start"};function t$(e,t){return"function"==typeof e?e(t):e}function tS(e){return e.split("-")[0]}function tC(e){return e.split("-")[1]}function tq(e){return"x"===e?"y":"x"}function tE(e){return"y"===e?"height":"width"}function tT(e){return["top","bottom"].includes(tS(e))?"y":"x"}function tM(e){return e.replace(/start|end/g,e=>tk[e])}function tF(e){return e.replace(/left|right|bottom|top/g,e=>tx[e])}function tD(e){return"number"!=typeof e?{top:0,right:0,bottom:0,left:0,...e}:{top:e,right:e,bottom:e,left:e}}function tz(e){let{x:t,y:r,width:n,height:i}=e;return{width:n,height:i,top:r,left:t,right:t+n,bottom:r+i,x:t,y:r}}function tL(e,t,r){let n,{reference:i,floating:o}=e,l=tT(t),a=tq(tT(t)),s=tE(a),d=tS(t),u="y"===l,c=i.x+i.width/2-o.width/2,g=i.y+i.height/2-o.height/2,f=i[s]/2-o[s]/2;switch(d){case"top":n={x:c,y:i.y-o.height};break;case"bottom":n={x:c,y:i.y+i.height};break;case"right":n={x:i.x+i.width,y:g};break;case"left":n={x:i.x-o.width,y:g};break;default:n={x:i.x,y:i.y}}switch(tC(t)){case"start":n[a]-=f*(r&&u?-1:1);break;case"end":n[a]+=f*(r&&u?-1:1)}return n}var tO=async(e,t,r)=>{let{placement:n="bottom",strategy:i="absolute",middleware:o=[],platform:l}=r,a=o.filter(Boolean),s=await (null==l.isRTL?void 0:l.isRTL(t)),d=await l.getElementRects({reference:e,floating:t,strategy:i}),{x:u,y:c}=tL(d,n,s),g=n,f={},p=0;for(let r=0;r<a.length;r++){let{name:o,fn:h}=a[r],{x:v,y:y,data:b,reset:m}=await h({x:u,y:c,initialPlacement:n,placement:g,strategy:i,middlewareData:f,rects:d,platform:l,elements:{reference:e,floating:t}});u=null!=v?v:u,c=null!=y?y:c,f={...f,[o]:{...f[o],...b}},m&&p<=50&&(p++,"object"==typeof m&&(m.placement&&(g=m.placement),m.rects&&(d=!0===m.rects?await l.getElementRects({reference:e,floating:t,strategy:i}):m.rects),{x:u,y:c}=tL(d,g,s)),r=-1)}return{x:u,y:c,placement:g,strategy:i,middlewareData:f}};async function tA(e,t){var r;void 0===t&&(t={});let{x:n,y:i,platform:o,rects:l,elements:a,strategy:s}=e,{boundary:d="clippingAncestors",rootBoundary:u="viewport",elementContext:c="floating",altBoundary:g=!1,padding:f=0}=t$(t,e),p=tD(f),h=a[g?"floating"===c?"reference":"floating":c],v=tz(await o.getClippingRect({element:null==(r=await (null==o.isElement?void 0:o.isElement(h)))||r?h:h.contextElement||await (null==o.getDocumentElement?void 0:o.getDocumentElement(a.floating)),boundary:d,rootBoundary:u,strategy:s})),y="floating"===c?{x:n,y:i,width:l.floating.width,height:l.floating.height}:l.reference,b=await (null==o.getOffsetParent?void 0:o.getOffsetParent(a.floating)),m=await (null==o.isElement?void 0:o.isElement(b))&&await (null==o.getScale?void 0:o.getScale(b))||{x:1,y:1},w=tz(o.convertOffsetParentRelativeRectToViewportRelativeRect?await o.convertOffsetParentRelativeRectToViewportRelativeRect({elements:a,rect:y,offsetParent:b,strategy:s}):y);return{top:(v.top-w.top+p.top)/m.y,bottom:(w.bottom-v.bottom+p.bottom)/m.y,left:(v.left-w.left+p.left)/m.x,right:(w.right-v.right+p.right)/m.x}}function tI(e,t){return{top:e.top-t.height,right:e.right-t.width,bottom:e.bottom-t.height,left:e.left-t.width}}function tK(e){return th.some(t=>e[t]>=0)}async function tP(e,t){let{placement:r,platform:n,elements:i}=e,o=await (null==n.isRTL?void 0:n.isRTL(i.floating)),l=tS(r),a=tC(r),s="y"===tT(r),d=["left","top"].includes(l)?-1:1,u=o&&s?-1:1,c=t$(t,e),{mainAxis:g,crossAxis:f,alignmentAxis:p}="number"==typeof c?{mainAxis:c,crossAxis:0,alignmentAxis:null}:{mainAxis:0,crossAxis:0,alignmentAxis:null,...c};return a&&"number"==typeof p&&(f="end"===a?-1*p:p),s?{x:f*u,y:g*d}:{x:g*d,y:f*u}}function tB(e){return tG(e)?(e.nodeName||"").toLowerCase():"#document"}function tR(e){var t;return(null==e||null==(t=e.ownerDocument)?void 0:t.defaultView)||window}function tH(e){var t;return null==(t=(tG(e)?e.ownerDocument:e.document)||window.document)?void 0:t.documentElement}function tG(e){return e instanceof Node||e instanceof tR(e).Node}function tU(e){return e instanceof Element||e instanceof tR(e).Element}function tY(e){return e instanceof HTMLElement||e instanceof tR(e).HTMLElement}function tV(e){return"undefined"!=typeof ShadowRoot&&(e instanceof ShadowRoot||e instanceof tR(e).ShadowRoot)}function tN(e){let{overflow:t,overflowX:r,overflowY:n,display:i}=tZ(e);return/auto|scroll|overlay|hidden|clip/.test(t+n+r)&&!["inline","contents"].includes(i)}function tj(e){return[":popover-open",":modal"].some(t=>{try{return e.matches(t)}catch(e){return!1}})}function tQ(e){let t=tW(),r=tU(e)?tZ(e):e;return"none"!==r.transform||"none"!==r.perspective||!!r.containerType&&"normal"!==r.containerType||!t&&!!r.backdropFilter&&"none"!==r.backdropFilter||!t&&!!r.filter&&"none"!==r.filter||["transform","perspective","filter"].some(e=>(r.willChange||"").includes(e))||["paint","layout","strict","content"].some(e=>(r.contain||"").includes(e))}function tW(){return"undefined"!=typeof CSS&&!!CSS.supports&&CSS.supports("-webkit-backdrop-filter","none")}function t_(e){return["html","body","#document"].includes(tB(e))}function tZ(e){return tR(e).getComputedStyle(e)}function tX(e){return tU(e)?{scrollLeft:e.scrollLeft,scrollTop:e.scrollTop}:{scrollLeft:e.scrollX,scrollTop:e.scrollY}}function tJ(e){if("html"===tB(e))return e;let t=e.assignedSlot||e.parentNode||tV(e)&&e.host||tH(e);return tV(t)?t.host:t}function t0(e,t,r){var n;void 0===t&&(t=[]),void 0===r&&(r=!0);let i=function e(t){let r=tJ(t);return t_(r)?t.ownerDocument?t.ownerDocument.body:t.body:tY(r)&&tN(r)?r:e(r)}(e),o=i===(null==(n=e.ownerDocument)?void 0:n.body),l=tR(i);return o?t.concat(l,l.visualViewport||[],tN(i)?i:[],l.frameElement&&r?t0(l.frameElement):[]):t.concat(i,t0(i,[],r))}function t1(e){let t=tZ(e),r=parseFloat(t.width)||0,n=parseFloat(t.height)||0,i=tY(e),o=i?e.offsetWidth:r,l=i?e.offsetHeight:n,a=tb(r)!==o||tb(n)!==l;return a&&(r=o,n=l),{width:r,height:n,$:a}}function t2(e){return tU(e)?e:e.contextElement}function t5(e){let t=t2(e);if(!tY(t))return tw(1);let r=t.getBoundingClientRect(),{width:n,height:i,$:o}=t1(t),l=(o?tb(r.width):r.width)/n,a=(o?tb(r.height):r.height)/i;return l&&Number.isFinite(l)||(l=1),a&&Number.isFinite(a)||(a=1),{x:l,y:a}}var t3=tw(0);function t4(e){let t=tR(e);return tW()&&t.visualViewport?{x:t.visualViewport.offsetLeft,y:t.visualViewport.offsetTop}:t3}function t6(e,t,r,n){var i;void 0===t&&(t=!1),void 0===r&&(r=!1);let o=e.getBoundingClientRect(),l=t2(e),a=tw(1);t&&(n?tU(n)&&(a=t5(n)):a=t5(e));let s=(void 0===(i=r)&&(i=!1),n&&(!i||n===tR(l))&&i)?t4(l):tw(0),d=(o.left+s.x)/a.x,u=(o.top+s.y)/a.y,c=o.width/a.x,g=o.height/a.y;if(l){let e=tR(l),t=n&&tU(n)?tR(n):n,r=e,i=r.frameElement;for(;i&&n&&t!==r;){let e=t5(i),t=i.getBoundingClientRect(),n=tZ(i),o=t.left+(i.clientLeft+parseFloat(n.paddingLeft))*e.x,l=t.top+(i.clientTop+parseFloat(n.paddingTop))*e.y;d*=e.x,u*=e.y,c*=e.x,g*=e.y,d+=o,u+=l,i=(r=tR(i)).frameElement}}return tz({width:c,height:g,x:d,y:u})}function t7(e){return t6(tH(e)).left+tX(e).scrollLeft}function t9(e,t,r){var n;let i;if("viewport"===t)i=function(e,t){let r=tR(e),n=tH(e),i=r.visualViewport,o=n.clientWidth,l=n.clientHeight,a=0,s=0;if(i){o=i.width,l=i.height;let e=tW();(!e||e&&"fixed"===t)&&(a=i.offsetLeft,s=i.offsetTop)}return{width:o,height:l,x:a,y:s}}(e,r);else if("document"===t){let t,r,o,l,a,s,d;n=tH(e),t=tH(n),r=tX(n),o=n.ownerDocument.body,l=ty(t.scrollWidth,t.clientWidth,o.scrollWidth,o.clientWidth),a=ty(t.scrollHeight,t.clientHeight,o.scrollHeight,o.clientHeight),s=-r.scrollLeft+t7(n),d=-r.scrollTop,"rtl"===tZ(o).direction&&(s+=ty(t.clientWidth,o.clientWidth)-l),i={width:l,height:a,x:s,y:d}}else if(tU(t)){let e,n,o,l,a,s;n=(e=t6(t,!0,"fixed"===r)).top+t.clientTop,o=e.left+t.clientLeft,l=tY(t)?t5(t):tw(1),a=t.clientWidth*l.x,s=t.clientHeight*l.y,i={width:a,height:s,x:o*l.x,y:n*l.y}}else{let r=t4(e);i={...t,x:t.x-r.x,y:t.y-r.y}}return tz(i)}function t8(e){return"static"===tZ(e).position}function re(e,t){return tY(e)&&"fixed"!==tZ(e).position?t?t(e):e.offsetParent:null}function rt(e,t){let r=tR(e);if(tj(e))return r;if(!tY(e)){let t=tJ(e);for(;t&&!t_(t);){if(tU(t)&&!t8(t))return t;t=tJ(t)}return r}let n=re(e,t);for(;n&&["table","td","th"].includes(tB(n))&&t8(n);)n=re(n,t);return n&&t_(n)&&t8(n)&&!tQ(n)?r:n||function(e){let t=tJ(e);for(;tY(t)&&!t_(t);){if(tQ(t))return t;if(tj(t))break;t=tJ(t)}return null}(e)||r}var rr=async function(e){let t=this.getOffsetParent||rt,r=this.getDimensions,n=await r(e.floating);return{reference:function(e,t,r){let n=tY(t),i=tH(t),o="fixed"===r,l=t6(e,!0,o,t),a={scrollLeft:0,scrollTop:0},s=tw(0);if(n||!n&&!o)if(("body"!==tB(t)||tN(i))&&(a=tX(t)),n){let e=t6(t,!0,o,t);s.x=e.x+t.clientLeft,s.y=e.y+t.clientTop}else i&&(s.x=t7(i));return{x:l.left+a.scrollLeft-s.x,y:l.top+a.scrollTop-s.y,width:l.width,height:l.height}}(e.reference,await t(e.floating),e.strategy),floating:{x:0,y:0,width:n.width,height:n.height}}},rn={convertOffsetParentRelativeRectToViewportRelativeRect:function(e){let{elements:t,rect:r,offsetParent:n,strategy:i}=e,o="fixed"===i,l=tH(n),a=!!t&&tj(t.floating);if(n===l||a&&o)return r;let s={scrollLeft:0,scrollTop:0},d=tw(1),u=tw(0),c=tY(n);if((c||!c&&!o)&&(("body"!==tB(n)||tN(l))&&(s=tX(n)),tY(n))){let e=t6(n);d=t5(n),u.x=e.x+n.clientLeft,u.y=e.y+n.clientTop}return{width:r.width*d.x,height:r.height*d.y,x:r.x*d.x-s.scrollLeft*d.x+u.x,y:r.y*d.y-s.scrollTop*d.y+u.y}},getDocumentElement:tH,getClippingRect:function(e){let{element:t,boundary:r,rootBoundary:n,strategy:i}=e,o=[..."clippingAncestors"===r?tj(t)?[]:function(e,t){let r=t.get(e);if(r)return r;let n=t0(e,[],!1).filter(e=>tU(e)&&"body"!==tB(e)),i=null,o="fixed"===tZ(e).position,l=o?tJ(e):e;for(;tU(l)&&!t_(l);){let t=tZ(l),r=tQ(l);r||"fixed"!==t.position||(i=null),(o?!r&&!i:!r&&"static"===t.position&&!!i&&["absolute","fixed"].includes(i.position)||tN(l)&&!r&&function e(t,r){let n=tJ(t);return!(n===r||!tU(n)||t_(n))&&("fixed"===tZ(n).position||e(n,r))}(e,l))?n=n.filter(e=>e!==l):i=t,l=tJ(l)}return t.set(e,n),n}(t,this._c):[].concat(r),n],l=o[0],a=o.reduce((e,r)=>{let n=t9(t,r,i);return e.top=ty(n.top,e.top),e.right=tv(n.right,e.right),e.bottom=tv(n.bottom,e.bottom),e.left=ty(n.left,e.left),e},t9(t,l,i));return{width:a.right-a.left,height:a.bottom-a.top,x:a.left,y:a.top}},getOffsetParent:rt,getElementRects:rr,getClientRects:function(e){return Array.from(e.getClientRects())},getDimensions:function(e){let{width:t,height:r}=t1(e);return{width:t,height:r}},getScale:t5,isElement:tU,isRTL:function(e){return"rtl"===tZ(e).direction}},ri=(0,l.q6)();function ro(){let e=(0,l.NT)(ri);if(void 0===e)throw Error("[kobalte]: `usePopperContext` must be used within a `Popper` component");return e}var rl=(0,l.vs)('<svg display="block" viewBox="0 0 30 30" style="transform:scale(1.02)"><g><path fill="none" d="M23,27.8c1.1,1.2,3.4,2.2,5,2.2h2H0h2c1.7,0,3.9-1,5-2.2l6.6-7.2c0.7-0.8,2-0.8,2.7,0L23,27.8L23,27.8z"></path><path stroke="none" d="M23,27.8c1.1,1.2,3.4,2.2,5,2.2h2H0h2c1.7,0,3.9-1,5-2.2l6.6-7.2c0.7-0.8,2-0.8,2.7,0L23,27.8L23,27.8z">'),ra={top:180,right:-90,bottom:0,left:90};function rs(e){let t=ro(),r=ek({size:30},e),[n,i]=(0,l.rg)(r,["ref","style","size"]),o=()=>t.currentPlacement().split("-")[0],a=function(e){let[t,r]=(0,l.n5)();return(0,l.EH)(()=>{let t=e();t&&r((ei(t).defaultView||window).getComputedStyle(t))}),t}(t.contentRef);return(0,l.a0)(ez,(0,l.v6)({as:"div",ref(e){let r=G(t.setArrowRef,n.ref);"function"==typeof r&&r(e)},"aria-hidden":"true",get style(){return X({position:"absolute","font-size":`${n.size}px`,width:"1em",height:"1em","pointer-events":"none",fill:a()?.getPropertyValue("background-color")||"none",stroke:a()?.getPropertyValue(`border-${o()}-color`)||"none","stroke-width":2*Number.parseInt(a()?.getPropertyValue(`border-${o()}-width`)||"0px")*(30/n.size)},n.style)}},i,{get children(){let e=rl(),t=e.firstChild;return(0,l.gb)(()=>(0,l.Bq)(t,"transform",`rotate(${ra[o()]} 15 15) translate(0 2)`)),e}}))}function rd(e){let{x:t=0,y:r=0,width:n=0,height:i=0}=e??{};if("function"==typeof DOMRect)return new DOMRect(t,r,n,i);let o={x:t,y:r,width:n,height:i,top:r,right:t+n,bottom:r+i,left:t};return{...o,toJSON:()=>o}}function ru(e){return/^(?:top|bottom|left|right)(?:-(?:start|end))?$/.test(e)}var rc={top:"bottom",right:"left",bottom:"top",left:"right"},rg=Object.assign(function(e){let t=ek({getAnchorRect:e=>e?.getBoundingClientRect(),placement:"bottom",gutter:0,shift:0,flip:!0,slide:!0,overlap:!1,sameWidth:!1,fitViewport:!1,hideWhenDetached:!1,detachedPadding:0,arrowPadding:4,overflowPadding:8},e),[r,n]=(0,l.n5)(),[i,o]=(0,l.n5)(),[a,s]=(0,l.n5)(t.placement),d=()=>{var e,r;return e=t.anchorRef?.(),r=t.getAnchorRect,{contextElement:e,getBoundingClientRect:()=>{let t=r(e);return t?rd(t):e?e.getBoundingClientRect():rd()}}},{direction:u}=eJ();async function c(){var e,n,o,l,a,c;let g,f,p,h,v,y=d(),b=r(),m=i();if(!y||!b)return;let w=(m?.clientHeight||0)/2,x="number"==typeof t.gutter?t.gutter+w:t.gutter??w;b.style.setProperty("--kb-popper-content-overflow-padding",`${t.overflowPadding}px`),y.getBoundingClientRect();let k=[(void 0===(e=({placement:e})=>({mainAxis:x,crossAxis:e.split("-")[1]?void 0:t.shift,alignmentAxis:t.shift}))&&(e=0),{name:"offset",options:e,async fn(t){var r,n;let{x:i,y:o,placement:l,middlewareData:a}=t,s=await tP(t,e);return l===(null==(r=a.offset)?void 0:r.placement)&&null!=(n=a.arrow)&&n.alignmentOffset?{}:{x:i+s.x,y:o+s.y,data:{...s,placement:l}}}})];if(!1!==t.flip){let e="string"==typeof t.flip?t.flip.split(" "):void 0;if(void 0!==e&&!e.every(ru))throw Error("`flip` expects a spaced-delimited list of placements");k.push({name:"flip",options:n={padding:t.overflowPadding,fallbackPlacements:e},async fn(e){var t,r,i,o,l,a,s,d;let u,c,g,{placement:f,middlewareData:p,rects:h,initialPlacement:v,platform:y,elements:b}=e,{mainAxis:m=!0,crossAxis:w=!0,fallbackPlacements:x,fallbackStrategy:k="bestFit",fallbackAxisSideDirection:$="none",flipAlignment:S=!0,...C}=t$(n,e);if(null!=(t=p.arrow)&&t.alignmentOffset)return{};let q=tS(f),E=tT(v),T=tS(v)===v,M=await (null==y.isRTL?void 0:y.isRTL(b.floating)),F=x||(T||!S?[tF(v)]:(u=tF(v),[tM(v),u,tM(u)])),D="none"!==$;!x&&D&&F.push(...(c=tC(v),g=function(e,t,r){let n=["left","right"],i=["right","left"];switch(e){case"top":case"bottom":if(r)return t?i:n;return t?n:i;case"left":case"right":return t?["top","bottom"]:["bottom","top"];default:return[]}}(tS(v),"start"===$,M),c&&(g=g.map(e=>e+"-"+c),S&&(g=g.concat(g.map(tM)))),g));let z=[v,...F],L=await tA(e,C),O=[],A=(null==(r=p.flip)?void 0:r.overflows)||[];if(m&&O.push(L[q]),w){let e,t,r,n,i=(a=f,s=h,void 0===(d=M)&&(d=!1),e=tC(a),r=tE(t=tq(tT(a))),n="x"===t?e===(d?"end":"start")?"right":"left":"start"===e?"bottom":"top",s.reference[r]>s.floating[r]&&(n=tF(n)),[n,tF(n)]);O.push(L[i[0]],L[i[1]])}if(A=[...A,{placement:f,overflows:O}],!O.every(e=>e<=0)){let e=((null==(i=p.flip)?void 0:i.index)||0)+1,t=z[e];if(t)return{data:{index:e,overflows:A},reset:{placement:t}};let r=null==(o=A.filter(e=>e.overflows[0]<=0).sort((e,t)=>e.overflows[1]-t.overflows[1])[0])?void 0:o.placement;if(!r)switch(k){case"bestFit":{let e=null==(l=A.filter(e=>{if(D){let t=tT(e.placement);return t===E||"y"===t}return!0}).map(e=>[e.placement,e.overflows.filter(e=>e>0).reduce((e,t)=>e+t,0)]).sort((e,t)=>e[1]-t[1])[0])?void 0:l[0];e&&(r=e);break}case"initialPlacement":r=v}if(f!==r)return{reset:{placement:r}}}return{}}})}(t.slide||t.overlap)&&k.push({name:"shift",options:o={mainAxis:t.slide,crossAxis:t.overlap,padding:t.overflowPadding},async fn(e){let{x:t,y:r,placement:n}=e,{mainAxis:i=!0,crossAxis:l=!1,limiter:a={fn:e=>{let{x:t,y:r}=e;return{x:t,y:r}}},...s}=t$(o,e),d={x:t,y:r},u=await tA(e,s),c=tT(tS(n)),g=tq(c),f=d[g],p=d[c];if(i){let e="y"===g?"top":"left",t="y"===g?"bottom":"right",r=f+u[e],n=f-u[t];f=ty(r,tv(f,n))}if(l){let e="y"===c?"top":"left",t="y"===c?"bottom":"right",r=p+u[e],n=p-u[t];p=ty(r,tv(p,n))}let h=a.fn({...e,[g]:f,[c]:p});return{...h,data:{x:h.x-t,y:h.y-r}}}}),k.push({name:"size",options:l={padding:t.overflowPadding,apply({availableWidth:e,availableHeight:r,rects:n}){let i=Math.round(n.reference.width);e=Math.floor(e),r=Math.floor(r),b.style.setProperty("--kb-popper-anchor-width",`${i}px`),b.style.setProperty("--kb-popper-content-available-width",`${e}px`),b.style.setProperty("--kb-popper-content-available-height",`${r}px`),t.sameWidth&&(b.style.width=`${i}px`),t.fitViewport&&(b.style.maxWidth=`${e}px`,b.style.maxHeight=`${r}px`)}},async fn(e){let t,r,{placement:n,rects:i,platform:o,elements:a}=e,{apply:s=()=>{},...d}=t$(l,e),u=await tA(e,d),c=tS(n),g=tC(n),f="y"===tT(n),{width:p,height:h}=i.floating;"top"===c||"bottom"===c?(t=c,r=g===(await (null==o.isRTL?void 0:o.isRTL(a.floating))?"start":"end")?"left":"right"):(r=c,t="end"===g?"top":"bottom");let v=h-u.top-u.bottom,y=p-u.left-u.right,b=tv(h-u[t],v),m=tv(p-u[r],y),w=!e.middlewareData.shift,x=b,k=m;if(f?k=g||w?tv(m,y):y:x=g||w?tv(b,v):v,w&&!g){let e=ty(u.left,0),t=ty(u.right,0),r=ty(u.top,0),n=ty(u.bottom,0);f?k=p-2*(0!==e||0!==t?e+t:ty(u.left,u.right)):x=h-2*(0!==r||0!==n?r+n:ty(u.top,u.bottom))}await s({...e,availableWidth:k,availableHeight:x});let $=await o.getDimensions(a.floating);return p!==$.width||h!==$.height?{reset:{rects:!0}}:{}}}),t.hideWhenDetached&&k.push({name:"hide",options:a={padding:t.detachedPadding},async fn(e){let{rects:t}=e,{strategy:r="referenceHidden",...n}=t$(a,e);switch(r){case"referenceHidden":{let r=tI(await tA(e,{...n,elementContext:"reference"}),t.reference);return{data:{referenceHiddenOffsets:r,referenceHidden:tK(r)}}}case"escaped":{let r=tI(await tA(e,{...n,altBoundary:!0}),t.floating);return{data:{escapedOffsets:r,escaped:tK(r)}}}default:return{}}}}),m&&k.push({name:"arrow",options:f={element:m,padding:t.arrowPadding},async fn(e){let{x:t,y:r,placement:n,rects:i,platform:o,elements:l,middlewareData:a}=e,{element:s,padding:d=0}=t$(f,e)||{};if(null==s)return{};let u=tD(d),c={x:t,y:r},g=tq(tT(n)),p=tE(g),h=await o.getDimensions(s),v="y"===g,y=v?"clientHeight":"clientWidth",b=i.reference[p]+i.reference[g]-c[g]-i.floating[p],m=c[g]-i.reference[g],w=await (null==o.getOffsetParent?void 0:o.getOffsetParent(s)),x=w?w[y]:0;x&&await (null==o.isElement?void 0:o.isElement(w))||(x=l.floating[y]||i.floating[p]);let k=x/2-h[p]/2-1,$=tv(u[v?"top":"left"],k),S=tv(u[v?"bottom":"right"],k),C=x-h[p]-S,q=x/2-h[p]/2+(b/2-m/2),E=ty($,tv(q,C)),T=!a.arrow&&null!=tC(n)&&q!==E&&i.reference[p]/2-(q<$?$:S)-h[p]/2<0,M=T?q<$?q-$:q-C:0;return{[g]:c[g]+M,data:{[g]:E,centerOffset:q-E-M,...T&&{alignmentOffset:M}},reset:T}}});let $=await (c={placement:t.placement,strategy:"absolute",middleware:k,platform:{...rn,isRTL:()=>"rtl"===u()}},p=new Map,v={...(h={platform:rn,...c}).platform,_c:p},tO(y,b,{...h,platform:v}));if(s($.placement),t.onCurrentPlacementChange?.($.placement),!b)return;b.style.setProperty("--kb-popper-content-transform-origin",function(e,t){let[r,n]=e.split("-"),i=rc[r];return n?"left"===r||"right"===r?`${i} ${"start"===n?"top":"bottom"}`:"start"===n?`${i} ${"rtl"===t?"right":"left"}`:`${i} ${"rtl"===t?"left":"right"}`:`${i} center`}($.placement,u()));let S=Math.round($.x),C=Math.round($.y);if(t.hideWhenDetached&&(g=$.middlewareData.hide?.referenceHidden?"hidden":"visible"),Object.assign(b.style,{top:"0",left:"0",transform:`translate3d(${S}px, ${C}px, 0)`,visibility:g}),m&&$.middlewareData.arrow){let{x:e,y:t}=$.middlewareData.arrow,r=$.placement.split("-")[0];Object.assign(m.style,{left:null!=e?`${e}px`:"",top:null!=t?`${t}px`:"",[r]:"100%"})}}return(0,l.EH)(()=>{let e=d(),t=r();if(!e||!t)return;let n=function(e,t,r,n){let i;void 0===n&&(n={});let{ancestorScroll:o=!0,ancestorResize:l=!0,elementResize:a="function"==typeof ResizeObserver,layoutShift:s="function"==typeof IntersectionObserver,animationFrame:d=!1}=n,u=t2(e),c=o||l?[...u?t0(u):[],...t0(t)]:[];c.forEach(e=>{o&&e.addEventListener("scroll",r,{passive:!0}),l&&e.addEventListener("resize",r)});let g=u&&s?function(e,t){let r,n=null,i=tH(e);function o(){var e;clearTimeout(r),null==(e=n)||e.disconnect(),n=null}return!function l(a,s){void 0===a&&(a=!1),void 0===s&&(s=1),o();let{left:d,top:u,width:c,height:g}=e.getBoundingClientRect();if(a||t(),!c||!g)return;let f={rootMargin:-tm(u)+"px "+-tm(i.clientWidth-(d+c))+"px "+-tm(i.clientHeight-(u+g))+"px "+-tm(d)+"px",threshold:ty(0,tv(1,s))||1},p=!0;function h(e){let t=e[0].intersectionRatio;if(t!==s){if(!p)return l();t?l(!1,t):r=setTimeout(()=>{l(!1,1e-7)},1e3)}p=!1}try{n=new IntersectionObserver(h,{...f,root:i.ownerDocument})}catch(e){n=new IntersectionObserver(h,f)}n.observe(e)}(!0),o}(u,r):null,f=-1,p=null;a&&(p=new ResizeObserver(e=>{let[n]=e;n&&n.target===u&&p&&(p.unobserve(t),cancelAnimationFrame(f),f=requestAnimationFrame(()=>{var e;null==(e=p)||e.observe(t)})),r()}),u&&!d&&p.observe(u),p.observe(t));let h=d?t6(e):null;return d&&function t(){let n=t6(e);h&&(n.x!==h.x||n.y!==h.y||n.width!==h.width||n.height!==h.height)&&r(),h=n,i=requestAnimationFrame(t)}(),r(),()=>{var e;c.forEach(e=>{o&&e.removeEventListener("scroll",r),l&&e.removeEventListener("resize",r)}),null==g||g(),null==(e=p)||e.disconnect(),p=null,d&&cancelAnimationFrame(i)}}(e,t,c,{elementResize:"function"==typeof ResizeObserver});(0,l.Ki)(n)}),(0,l.EH)(()=>{let e=r(),n=t.contentRef?.();e&&n&&queueMicrotask(()=>{e.style.zIndex=getComputedStyle(n).zIndex})}),(0,l.a0)(ri.Provider,{value:{currentPlacement:a,contentRef:()=>t.contentRef?.(),setPositionerRef:n,setArrowRef:o},get children(){return t.children}})},{Arrow:rs,Context:ri,usePopperContext:ro,Positioner:function(e){let t=ro(),[r,n]=(0,l.rg)(e,["ref","style"]);return(0,l.a0)(ez,(0,l.v6)({as:"div",ref(e){let n=G(t.setPositionerRef,r.ref);"function"==typeof n&&n(e)},"data-popper-positioner":"",get style(){return X({position:"absolute",top:0,left:0,"min-width":"max-content"},r.style)}},n))}}),rf="interactOutside.pointerDownOutside",rp="interactOutside.focusOutside",rh=(0,l.q6)();function rv(e){var t,r;let n,i,o,a,s,d,c,g,f,p,h=(0,l.NT)(rh),[v,y]=(0,l.rg)(e,["ref","disableOutsidePointerEvents","excludedElements","onEscapeKeyDown","onPointerDownOutside","onFocusOutside","onInteractOutside","onDismiss","bypassTopMostLayerCheck"]),b=new Set([]);return t={shouldExcludeElement:e=>!!n&&(v.excludedElements?.some(t=>er(t(),e))||[...b].some(t=>er(t,e))),onPointerDownOutside:e=>{!n||to(n)||(v.bypassTopMostLayerCheck||tl(n))&&(v.onPointerDownOutside?.(e),v.onInteractOutside?.(e),e.defaultPrevented||v.onDismiss?.())},onFocusOutside:e=>{v.onFocusOutside?.(e),v.onInteractOutside?.(e),e.defaultPrevented||v.onDismiss?.()}},o=ex,a=e=>t.onPointerDownOutside?.(e),s=e=>t.onFocusOutside?.(e),d=e=>t.onInteractOutside?.(e),c=e=>{let r=e.target;return!(!(r instanceof HTMLElement)||r.closest(`[${e8}]`)||!er(ei((()=>n)()),r)||er((()=>n)(),r))&&!t.shouldExcludeElement?.(r)},g=e=>{function t(){let t=(()=>n)(),r=e.target;if(!t||!r||!c(e))return;let i=eu([a,d]);r.addEventListener(rf,i,{once:!0});let o=new CustomEvent(rf,{bubbles:!1,cancelable:!0,detail:{originalEvent:e,isContextMenu:2===e.button||(es()?e.metaKey&&!e.ctrlKey:e.ctrlKey&&!e.metaKey)&&0===e.button}});r.dispatchEvent(o)}"touch"===e.pointerType?(ei((()=>n)()).removeEventListener("click",t),o=t,ei((()=>n)()).addEventListener("click",t,{once:!0})):t()},f=e=>{let t=(()=>n)(),r=e.target;if(!t||!r||!c(e))return;let i=eu([s,d]);r.addEventListener(rp,i,{once:!0});let o=new CustomEvent(rp,{bubbles:!1,cancelable:!0,detail:{originalEvent:e,isContextMenu:!1}});r.dispatchEvent(o)},(0,l.EH)(()=>{l.S$||u(t.isDisabled)||(i=window.setTimeout(()=>{ei((()=>n)()).addEventListener("pointerdown",g,!0)},0),ei((()=>n)()).addEventListener("focusin",f,!0),(0,l.Ki)(()=>{window.clearTimeout(i),ei((()=>n)()).removeEventListener("click",o),ei((()=>n)()).removeEventListener("pointerdown",g,!0),ei((()=>n)()).removeEventListener("focusin",f,!0)}))}),r={ownerDocument:()=>ei(n),onEscapeKeyDown:e=>{n&&tl(n)&&(v.onEscapeKeyDown?.(e),!e.defaultPrevented&&v.onDismiss&&(e.preventDefault(),v.onDismiss()))}},p=e=>{e.key===el.Escape&&r.onEscapeKeyDown?.(e)},(0,l.EH)(()=>{if(l.S$||u(r.isDisabled))return;let e=r.ownerDocument?.()??ei();e.addEventListener("keydown",p),(0,l.Ki)(()=>{e.removeEventListener("keydown",p)})}),(0,l.Rc)(()=>{if(!n)return;ta({node:n,isPointerBlocking:v.disableOutsidePointerEvents,dismiss:v.onDismiss});let e=h?.registerNestedLayer(n);td(),tu(n),(0,l.Ki)(()=>{n&&(ts(n),e?.(),td(),tc(n))})}),(0,l.EH)((0,l.on)([()=>n,()=>v.disableOutsidePointerEvents],([e,t])=>{if(!e)return;let r=tt[tr(e)];r&&r.isPointerBlocking!==t&&(r.isPointerBlocking=t,td()),t&&tu(e),(0,l.Ki)(()=>{tc(e)})},{defer:!0})),(0,l.a0)(rh.Provider,{value:{registerNestedLayer:e=>{b.add(e);let t=h?.registerNestedLayer(e);return()=>{b.delete(e),t?.()}}},get children(){return(0,l.a0)(ez,(0,l.v6)({as:"div",ref(e){let t=G(e=>n=e,v.ref);"function"==typeof t&&t(e)}},y))}})}function ry(e={}){let[t,r]=eR({value:()=>u(e.open),defaultValue:()=>!!u(e.defaultOpen),onChange:t=>e.onOpenChange?.(t)}),n=()=>{r(!0)},i=()=>{r(!1)};return{isOpen:t,setIsOpen:r,open:n,close:i,toggle:()=>{t()?i():n()}}}var rb={};eG(rb,{Description:()=>eI,ErrorMessage:()=>eK,Item:()=>r$,ItemControl:()=>rS,ItemDescription:()=>rC,ItemIndicator:()=>rq,ItemInput:()=>rE,ItemLabel:()=>rT,Label:()=>rM,RadioGroup:()=>rD,Root:()=>rF});var rm=(0,l.q6)();function rw(){let e=(0,l.NT)(rm);if(void 0===e)throw Error("[kobalte]: `useRadioGroupContext` must be used within a `RadioGroup` component");return e}var rx=(0,l.q6)();function rk(){let e=(0,l.NT)(rx);if(void 0===e)throw Error("[kobalte]: `useRadioGroupItemContext` must be used within a `RadioGroup.Item` component");return e}function r$(e){let t=eA(),r=rw(),n=ek({id:`${t.generateId("item")}-${(0,l.Ds)()}`},e),[i,o]=(0,l.rg)(n,["value","disabled","onPointerDown"]),[a,s]=(0,l.n5)(),[d,u]=(0,l.n5)(),[c,g]=(0,l.n5)(),[f,p]=(0,l.n5)(),[h,v]=(0,l.n5)(!1),y=(0,l.To)(()=>r.isSelectedValue(i.value)),b=(0,l.To)(()=>i.disabled||t.isDisabled()||!1),m=e=>{ed(e,i.onPointerDown),h()&&e.preventDefault()},w=(0,l.To)(()=>({...t.dataset(),"data-disabled":b()?"":void 0,"data-checked":y()?"":void 0})),x={value:()=>i.value,dataset:w,isSelected:y,isDisabled:b,inputId:a,labelId:d,descriptionId:c,inputRef:f,select:()=>r.setSelectedValue(i.value),generateId:et(()=>o.id),registerInput:eM(s),registerLabel:eM(u),registerDescription:eM(g),setIsFocused:v,setInputRef:p};return(0,l.a0)(rx.Provider,{value:x,get children(){return(0,l.a0)(ez,(0,l.v6)({as:"div",role:"group",onPointerDown:m},w,o))}})}function rS(e){let t=rk(),r=ek({id:t.generateId("control")},e),[n,i]=(0,l.rg)(r,["onClick","onKeyDown"]);return(0,l.a0)(ez,(0,l.v6)({as:"div",onClick:e=>{ed(e,n.onClick),t.select(),t.inputRef()?.focus()},onKeyDown:e=>{ed(e,n.onKeyDown),e.key===el.Space&&(t.select(),t.inputRef()?.focus())}},()=>t.dataset(),i))}function rC(e){let t=rk(),r=ek({id:t.generateId("description")},e);return(0,l.EH)(()=>(0,l.Ki)(t.registerDescription(r.id))),(0,l.a0)(ez,(0,l.v6)({as:"div"},()=>t.dataset(),r))}function rq(e){let t=rk(),r=ek({id:t.generateId("indicator")},e),[n,i]=(0,l.rg)(r,["ref","forceMount"]),[o,a]=(0,l.n5)(),{present:s}=e9({show:()=>n.forceMount||t.isSelected(),element:()=>o()??null});return(0,l.a0)(l.wv,{get when(){return s()},get children(){return(0,l.a0)(ez,(0,l.v6)({as:"div",ref(e){let t=G(a,n.ref);"function"==typeof t&&t(e)}},()=>t.dataset(),i))}})}function rE(e){let t=eA(),r=rw(),n=rk(),i=ek({id:n.generateId("input")},e),[o,a]=(0,l.rg)(i,["ref","style","aria-labelledby","aria-describedby","onChange","onFocus","onBlur"]),[s,d]=(0,l.n5)(!1);return(0,l.EH)((0,l.on)([()=>n.isSelected(),()=>n.value()],e=>{if(!e[0]&&e[1]===n.value())return;d(!0);let t=n.inputRef();t?.dispatchEvent(new Event("input",{bubbles:!0,cancelable:!0})),t?.dispatchEvent(new Event("change",{bubbles:!0,cancelable:!0}))},{defer:!0})),(0,l.EH)(()=>(0,l.Ki)(n.registerInput(a.id))),(0,l.a0)(ez,(0,l.v6)({as:"input",ref(e){let t=G(n.setInputRef,o.ref);"function"==typeof t&&t(e)},type:"radio",get name(){return t.name()},get value(){return n.value()},get checked(){return n.isSelected()},get required(){return t.isRequired()},get disabled(){return n.isDisabled()},get readonly(){return t.isReadOnly()},get style(){return X({...eT},o.style)},get"aria-labelledby"(){return[o["aria-labelledby"],n.labelId(),null!=o["aria-labelledby"]&&null!=a["aria-label"]?a.id:void 0].filter(Boolean).join(" ")||void 0},get"aria-describedby"(){return[o["aria-describedby"],n.descriptionId(),r.ariaDescribedBy()].filter(Boolean).join(" ")||void 0},onChange:e=>{ed(e,o.onChange),e.stopPropagation(),s()||(r.setSelectedValue(n.value()),e.target.checked=n.isSelected()),d(!1)},onFocus:e=>{ed(e,o.onFocus),n.setIsFocused(!0)},onBlur:e=>{ed(e,o.onBlur),n.setIsFocused(!1)}},()=>n.dataset(),a))}function rT(e){let t=rk(),r=ek({id:t.generateId("label")},e);return(0,l.EH)(()=>(0,l.Ki)(t.registerLabel(r.id))),(0,l.a0)(ez,(0,l.v6)({as:"label",get for(){return t.inputId()}},()=>t.dataset(),r))}function rM(e){return(0,l.a0)(eP,(0,l.v6)({as:"span"},e))}function rF(e){var t;let r,n=ek({id:`radiogroup-${(0,l.Ds)()}`,orientation:"vertical"},e),[i,o,a]=(0,l.rg)(n,["ref","value","defaultValue","onChange","orientation","aria-labelledby","aria-describedby"],eL),[s,d]=eB({value:()=>i.value,defaultValue:()=>i.defaultValue,onChange:e=>i.onChange?.(e)}),{formControlContext:c}=function(e){let t=ek({id:`form-control-${(0,l.Ds)()}`},e),[r,n]=(0,l.n5)(),[i,o]=(0,l.n5)(),[a,s]=(0,l.n5)(),[d,c]=(0,l.n5)();return{formControlContext:{name:()=>u(t.name)??u(t.id),dataset:(0,l.To)(()=>({"data-valid":"valid"===u(t.validationState)?"":void 0,"data-invalid":"invalid"===u(t.validationState)?"":void 0,"data-required":u(t.required)?"":void 0,"data-disabled":u(t.disabled)?"":void 0,"data-readonly":u(t.readOnly)?"":void 0})),validationState:()=>u(t.validationState),isRequired:()=>u(t.required),isDisabled:()=>u(t.disabled),isReadOnly:()=>u(t.readOnly),labelId:r,fieldId:i,descriptionId:a,errorMessageId:d,getAriaLabelledBy:(e,t,n)=>{let i=null!=n||null!=r();return[n,r(),i&&null!=t?e:void 0].filter(Boolean).join(" ")||void 0},getAriaDescribedBy:e=>[a(),d(),e].filter(Boolean).join(" ")||void 0,generateId:et(()=>u(t.id)),registerLabel:eM(n),registerField:eM(o),registerDescription:eM(s),registerErrorMessage:eM(c)}}}(o);t=()=>d(i.defaultValue??""),(0,l.EH)((0,l.on)(()=>r,e=>{var r;if(null==e)return;let n=(r=e).matches("textarea, input, select, button")?r.form:r.closest("form");null!=n&&(n.addEventListener("reset",t,{passive:!0}),(0,l.Ki)(()=>{n.removeEventListener("reset",t)}))}));let g=()=>c.getAriaDescribedBy(i["aria-describedby"]),f=e=>e===s(),p={ariaDescribedBy:g,isSelectedValue:f,setSelectedValue:e=>{if(!(c.isReadOnly()||c.isDisabled())&&(d(e),r))for(let e of r.querySelectorAll("[type='radio']"))e.checked=f(e.value)}};return(0,l.a0)(eO.Provider,{value:c,get children(){return(0,l.a0)(rm.Provider,{value:p,get children(){return(0,l.a0)(ez,(0,l.v6)({as:"div",ref(e){let t=G(e=>r=e,i.ref);"function"==typeof t&&t(e)},role:"radiogroup",get id(){return u(o.id)},get"aria-invalid"(){return"invalid"===c.validationState()||void 0},get"aria-required"(){return c.isRequired()||void 0},get"aria-disabled"(){return c.isDisabled()||void 0},get"aria-readonly"(){return c.isReadOnly()||void 0},get"aria-orientation"(){return i.orientation},get"aria-labelledby"(){return c.getAriaLabelledBy(u(o.id),a["aria-label"],i["aria-labelledby"])},get"aria-describedby"(){return g()}},()=>c.dataset(),a))}})}})}var rD=Object.assign(rF,{Description:eI,ErrorMessage:eK,Item:r$,ItemControl:rS,ItemDescription:rC,ItemIndicator:rq,ItemInput:rE,ItemLabel:rT,Label:rM}),rz=class{collection;ref;collator;constructor(e,t,r){this.collection=e,this.ref=t,this.collator=r}getKeyBelow(e){let t=this.collection().getKeyAfter(e);for(;null!=t;){let e=this.collection().getItem(t);if(e&&"item"===e.type&&!e.disabled)return t;t=this.collection().getKeyAfter(t)}}getKeyAbove(e){let t=this.collection().getKeyBefore(e);for(;null!=t;){let e=this.collection().getItem(t);if(e&&"item"===e.type&&!e.disabled)return t;t=this.collection().getKeyBefore(t)}}getFirstKey(){let e=this.collection().getFirstKey();for(;null!=e;){let t=this.collection().getItem(e);if(t&&"item"===t.type&&!t.disabled)return e;e=this.collection().getKeyAfter(e)}}getLastKey(){let e=this.collection().getLastKey();for(;null!=e;){let t=this.collection().getItem(e);if(t&&"item"===t.type&&!t.disabled)return e;e=this.collection().getKeyBefore(e)}}getItem(e){return this.ref?.()?.querySelector(`[data-key="${e}"]`)??null}getKeyPageAbove(e){let t=this.ref?.(),r=this.getItem(e);if(!t||!r)return;let n=Math.max(0,r.offsetTop+r.offsetHeight-t.offsetHeight),i=e;for(;i&&r&&r.offsetTop>n;)r=null!=(i=this.getKeyAbove(i))?this.getItem(i):null;return i}getKeyPageBelow(e){let t=this.ref?.(),r=this.getItem(e);if(!t||!r)return;let n=Math.min(t.scrollHeight,r.offsetTop-r.offsetHeight+t.offsetHeight),i=e;for(;i&&r&&r.offsetTop<n;)r=null!=(i=this.getKeyBelow(i))?this.getItem(i):null;return i}getKeyForSearch(e,t){let r=this.collator?.();if(!r)return;let n=null!=t?this.getKeyBelow(t):this.getFirstKey();for(;null!=n;){let t=this.collection().getItem(n);if(t){let i=t.textValue.slice(0,e.length);if(t.textValue&&0===r.compare(i,e))return n}n=this.getKeyBelow(n)}}},rL="focusScope.autoFocusOnMount",rO="focusScope.autoFocusOnUnmount",rA={bubbles:!1,cancelable:!0},rI={stack:[],active(){return this.stack[0]},add(e){e!==this.active()&&this.active()?.pause(),this.stack=J(this.stack,e),this.stack.unshift(e)},remove(e){this.stack=J(this.stack,e),this.active()?.resume()}},rK=new WeakMap,rP=[],rB=new Map,rR=e=>{(0,l.EH)(()=>{let t=e7(e.style)??{},r=e7(e.properties)??[],n={};for(let r in t)n[r]=e.element.style[r];let i=rB.get(e.key);for(let t of(i?i.activeCount++:rB.set(e.key,{activeCount:1,originalStyles:n,properties:r.map(e=>e.key)}),Object.assign(e.element.style,e.style),r))e.element.style.setProperty(t.key,t.value);(0,l.Ki)(()=>{let t=rB.get(e.key);if(t){if(1!==t.activeCount)return void t.activeCount--;for(let[r,n]of(rB.delete(e.key),Object.entries(t.originalStyles)))e.element.style[r]=n;for(let r of t.properties)e.element.style.removeProperty(r);0===e.element.style.length&&e.element.removeAttribute("style"),e.cleanup?.()}})})},rH=(e,t)=>{switch(t){case"x":return[e.clientWidth,e.scrollLeft,e.scrollWidth];case"y":return[e.clientHeight,e.scrollTop,e.scrollHeight]}},rG=(e,t)=>{let r=getComputedStyle(e),n="x"===t?r.overflowX:r.overflowY;return"auto"===n||"scroll"===n||"HTML"===e.tagName&&"visible"===n},[rU,rY]=(0,l.n5)([]),rV=e=>e.changedTouches[0]?[e.changedTouches[0].clientX,e.changedTouches[0].clientY]:[0,0],rN=(e,t,r,n)=>{let i=null!==n&&rj(n,e),[o,l]=((e,t,r)=>{let n="x"===t&&"rtl"===window.getComputedStyle(e).direction?-1:1,i=e,o=0,l=0,a=!1;do{let[e,s,d]=rH(i,t),u=d-e-n*s;(0!==s||0!==u)&&rG(i,t)&&(o+=u,l+=s),i===(r??document.documentElement)?a=!0:i=i._$host??i.parentElement}while(i&&!a)return[o,l]})(e,t,i?n:void 0);return!(r>0&&1>=Math.abs(o)||r<0&&1>Math.abs(l))},rj=(e,t)=>{if(e.contains(t))return!0;let r=t;for(;r;){if(r===e)return!0;r=r._$host??r.parentElement}return!1},rQ=(0,l.q6)();function rW(){let e=(0,l.NT)(rQ);if(void 0===e)throw Error("[kobalte]: `useMenuContext` must be used within a `Menu` component");return e}var r_=(0,l.q6)();function rZ(){let e=(0,l.NT)(r_);if(void 0===e)throw Error("[kobalte]: `useMenuItemContext` must be used within a `Menu.Item` component");return e}var rX=(0,l.q6)();function rJ(){let e=(0,l.NT)(rX);if(void 0===e)throw Error("[kobalte]: `useMenuRootContext` must be used within a `MenuRoot` component");return e}function r0(e){let t,r,n,i=rJ(),o=rW(),a=ek({id:i.generateId(`item-${(0,l.Ds)()}`)},e),[s,d]=(0,l.rg)(a,["ref","textValue","disabled","closeOnSelect","checked","indeterminate","onSelect","onPointerMove","onPointerLeave","onPointerDown","onPointerUp","onClick","onKeyDown","onMouseDown","onFocus"]),[u,c]=(0,l.n5)(),[g,f]=(0,l.n5)(),[p,h]=(0,l.n5)(),v=()=>o.listState().selectionManager(),y=()=>d.id,b=()=>{s.onSelect?.(),s.closeOnSelect&&setTimeout(()=>{o.close(!0)})};r=function(){let e=(0,l.NT)(eU);if(void 0===e)throw Error("[kobalte]: `useDomCollectionContext` must be used within a `DomCollectionProvider` component");return e}(),n=ek({shouldRegisterItem:!0},{getItem:()=>({ref:()=>t,type:"item",key:y(),textValue:s.textValue??p()?.textContent??t?.textContent??"",disabled:s.disabled??!1})}),(0,l.EH)(()=>{if(!n.shouldRegisterItem)return;let e=r.registerItem(n.getItem());(0,l.Ki)(e)});let m=e3({key:y,selectionManager:v,shouldSelectOnPressUp:!0,allowsDifferentPressOrigin:!0,disabled:()=>s.disabled},()=>t),w=e=>{ed(e,s.onPointerMove),"mouse"===e.pointerType&&(s.disabled?o.onItemLeave(e):(o.onItemEnter(e),e.defaultPrevented||(ec(e.currentTarget),o.listState().selectionManager().setFocused(!0),o.listState().selectionManager().setFocusedKey(y()))))},x=e=>{ed(e,s.onPointerLeave),"mouse"===e.pointerType&&o.onItemLeave(e)},k=e=>{ed(e,s.onPointerUp),s.disabled||0!==e.button||b()},$=e=>{if((ed(e,s.onKeyDown),!e.repeat)&&!s.disabled)switch(e.key){case"Enter":case" ":b()}},S=(0,l.To)(()=>s.indeterminate?"mixed":null!=s.checked?s.checked:void 0),C=(0,l.To)(()=>({"data-indeterminate":s.indeterminate?"":void 0,"data-checked":s.checked&&!s.indeterminate?"":void 0,"data-disabled":s.disabled?"":void 0,"data-highlighted":v().focusedKey()===y()?"":void 0})),q={isChecked:()=>s.checked,dataset:C,setLabelRef:h,generateId:et(()=>d.id),registerLabel:eM(c),registerDescription:eM(f)};return(0,l.a0)(r_.Provider,{value:q,get children(){return(0,l.a0)(ez,(0,l.v6)({as:"div",ref(e){let r=G(e=>t=e,s.ref);"function"==typeof r&&r(e)},get tabIndex(){return m.tabIndex()},get"aria-checked"(){return S()},get"aria-disabled"(){return s.disabled},get"aria-labelledby"(){return u()},get"aria-describedby"(){return g()},get"data-key"(){return m.dataKey()},get onPointerDown(){return eu([s.onPointerDown,m.onPointerDown])},get onPointerUp(){return eu([k,m.onPointerUp])},get onClick(){return eu([s.onClick,m.onClick])},get onKeyDown(){return eu([$,m.onKeyDown])},get onMouseDown(){return eu([s.onMouseDown,m.onMouseDown])},get onFocus(){return eu([s.onFocus,m.onFocus])},onPointerMove:w,onPointerLeave:x},C,d))}})}function r1(e){let t=ek({closeOnSelect:!1},e),[r,n]=(0,l.rg)(t,["checked","defaultChecked","onChange","onSelect"]),i=function(e={}){let[t,r]=eR({value:()=>u(e.isSelected),defaultValue:()=>!!u(e.defaultIsSelected),onChange:t=>e.onSelectedChange?.(t)});return{isSelected:t,setIsSelected:t=>{u(e.isReadOnly)||u(e.isDisabled)||r(t)},toggle:()=>{u(e.isReadOnly)||u(e.isDisabled)||r(!t())}}}({isSelected:()=>r.checked,defaultIsSelected:()=>r.defaultChecked,onSelectedChange:e=>r.onChange?.(e),isDisabled:()=>n.disabled});return(0,l.a0)(r0,(0,l.v6)({role:"menuitemcheckbox",get checked(){return i.isSelected()},onSelect:()=>{r.onSelect?.(),i.toggle()}},n))}var r2=(0,l.q6)();function r5(){return(0,l.NT)(r2)}var r3={next:(e,t)=>"ltr"===e?"horizontal"===t?"ArrowRight":"ArrowDown":"horizontal"===t?"ArrowLeft":"ArrowUp",previous:(e,t)=>r3.next("ltr"===e?"rtl":"ltr",t)};function r4(e){let t=rJ(),r=rW(),n=r5(),{direction:i}=eJ(),o=ek({id:t.generateId("trigger")},e),[a,s]=(0,l.rg)(o,["ref","id","disabled","onPointerDown","onClick","onKeyDown","onMouseOver","onFocus"]),d=()=>t.value();void 0!==n&&(d=()=>t.value()??a.id,void 0===n.lastValue()&&n.setLastValue(d));let u=eF(()=>r.triggerRef(),()=>"button"),c=(0,l.To)(()=>"a"===u()&&r.triggerRef()?.getAttribute("href")!=null);(0,l.EH)((0,l.on)(()=>n?.value(),e=>{c()&&e===d()&&r.triggerRef()?.focus()}));let g=()=>{void 0!==n?r.isOpen()?n.value()===d()&&n.closeMenu():(n.autoFocusMenu()||n.setAutoFocusMenu(!0),r.open(!1)):r.toggle(!0)};return(0,l.EH)(()=>(0,l.Ki)(r.registerTriggerId(a.id))),(0,l.a0)(tf,(0,l.v6)({ref(e){let t=G(r.setTriggerRef,a.ref);"function"==typeof t&&t(e)},get"data-kb-menu-value-trigger"(){return t.value()},get id(){return a.id},get disabled(){return a.disabled},"aria-haspopup":"true",get"aria-expanded"(){return r.isOpen()},get"aria-controls"(){return(0,l.ph)(()=>!!r.isOpen())()?r.contentId():void 0},get"data-highlighted"(){return void 0!==d()&&n?.value()===d()||void 0},get tabIndex(){return void 0!==n?n.value()===d()||n.lastValue()===d()?0:-1:void 0},onPointerDown:e=>{ed(e,a.onPointerDown),e.currentTarget.dataset.pointerType=e.pointerType,a.disabled||"touch"===e.pointerType||0!==e.button||g()},onMouseOver:e=>{ed(e,a.onMouseOver),r.triggerRef()?.dataset.pointerType!=="touch"&&(a.disabled||void 0===n||void 0===n.value()||n.setValue(d))},onClick:e=>{ed(e,a.onClick),a.disabled||"touch"!==e.currentTarget.dataset.pointerType||g()},onKeyDown:e=>{if(ed(e,a.onKeyDown),!a.disabled){if(c())switch(e.key){case"Enter":case" ":return}switch(e.key){case"Enter":case" ":case"horizontal"===t.orientation()?"ArrowDown":"ArrowRight":e.stopPropagation(),e.preventDefault(),function(e,t){if(document.contains(e)){let t=document.scrollingElement||document.documentElement;if("hidden"===window.getComputedStyle(t).overflow){let r=ew(e);for(;e&&r&&e!==t&&r!==t;)eq(r,e),r=ew(e=r)}else{let{left:t,top:r}=e.getBoundingClientRect();e?.scrollIntoView?.({block:"nearest"});let{left:n,top:i}=e.getBoundingClientRect();(Math.abs(t-n)>1||Math.abs(r-i)>1)&&e.scrollIntoView?.({block:"nearest"})}}}(e.currentTarget),r.open("first"),n?.setAutoFocusMenu(!0),n?.setValue(d);break;case"horizontal"===t.orientation()?"ArrowUp":"ArrowLeft":e.stopPropagation(),e.preventDefault(),r.open("last");break;case r3.next(i(),t.orientation()):if(void 0===n)break;e.stopPropagation(),e.preventDefault(),n.nextMenu();break;case r3.previous(i(),t.orientation()):if(void 0===n)break;e.stopPropagation(),e.preventDefault(),n.previousMenu()}}},onFocus:e=>{ed(e,a.onFocus),void 0!==n&&"touch"!==e.currentTarget.dataset.pointerType&&n.setValue(d)},role:void 0!==n?"menuitem":void 0},()=>r.dataset(),s))}var r6=(0,l.q6)();function r7(e){var t,r;let n,i,o=rJ(),a=rW(),s=r5(),d=(0,l.NT)(r6),{direction:f}=eJ(),p=ek({id:o.generateId(`content-${(0,l.Ds)()}`)},e),[h,v]=(0,l.rg)(p,["ref","id","style","onOpenAutoFocus","onCloseAutoFocus","onEscapeKeyDown","onFocusOutside","onPointerEnter","onPointerMove","onKeyDown","onMouseDown","onFocusIn","onFocusOut"]),y=0,b=()=>null==a.parentMenuContext()&&void 0===s&&o.isModal(),m=(t={selectionManager:a.listState().selectionManager,collection:a.listState().collection,autoFocus:a.autoFocus,deferAutoFocus:!0,shouldFocusWrap:!0,disallowTypeAhead:()=>!a.listState().selectionManager().isFocused(),orientation:()=>"horizontal"===o.orientation()?"vertical":"horizontal"},r=()=>n,i=function(e){let{locale:t}=eJ(),r=(0,l.To)(()=>t()+(e?Object.entries(e).sort((e,t)=>e[0]<t[0]?-1:1).join():""));return(0,l.To)(()=>{let n,i=r();return e0.has(i)&&(n=e0.get(i)),n||(n=new Intl.Collator(t(),e),e0.set(i,n)),n})}({usage:"search",sensitivity:"base"}),function(e,t,r){let n=(0,l.v6)({selectOnFocus:()=>"replace"===u(e.selectionManager).selectionBehavior()},e),i=()=>t(),{direction:o}=eJ(),a={top:0,left:0};!function(e,t,r,n){if(l.S$)return;let i=()=>{c(u(e)).forEach(e=>{e&&c(u(t)).forEach(t=>{var n;return n=void 0,e.addEventListener(t,r,n),g(e.removeEventListener.bind(e,t,r,n))})})};"function"==typeof e?(0,l.EH)(i):(0,l.gb)(i)}(()=>u(n.isVirtualized)?void 0:i(),"scroll",()=>{let e=i();e&&(a={top:e.scrollTop,left:e.scrollLeft})});let{typeSelectHandlers:s}=function(e){let[t,r]=(0,l.n5)(""),[n,i]=(0,l.n5)(-1);return{typeSelectHandlers:{onKeyDown:o=>{var l,a;if(u(e.isDisabled))return;let s=u(e.keyboardDelegate),d=u(e.selectionManager);if(!s.getKeyForSearch)return;let c=1!==(l=o.key).length&&/^[A-Z]/i.test(l)?"":l;if(!c||o.ctrlKey||o.metaKey)return;" "===c&&t().trim().length>0&&(o.preventDefault(),o.stopPropagation());let g=r(e=>e+c),f=s.getKeyForSearch(g,d.focusedKey())??s.getKeyForSearch(g);null==f&&(a=g).split("").every(e=>e===a[0])&&(g=g[0],f=s.getKeyForSearch(g,d.focusedKey())??s.getKeyForSearch(g)),null!=f&&(d.setFocusedKey(f),e.onTypeSelect?.(f)),clearTimeout(n()),i(window.setTimeout(()=>r(""),500))}}}}({isDisabled:()=>u(n.disallowTypeAhead),keyboardDelegate:()=>u(n.keyboardDelegate),selectionManager:()=>u(n.selectionManager)}),d=()=>u(n.orientation)??"vertical",f=()=>{let e,r=u(n.autoFocus);if(!r)return;let i=u(n.selectionManager),o=u(n.keyboardDelegate);"first"===r&&(e=o.getFirstKey?.()),"last"===r&&(e=o.getLastKey?.());let l=i.selectedKeys();l.size&&(e=l.values().next().value),i.setFocused(!0),i.setFocusedKey(e);let a=t();a&&null==e&&!u(n.shouldUseVirtualFocus)&&ec(a)};return(0,l.Rc)(()=>{n.deferAutoFocus?setTimeout(f,0):f()}),(0,l.EH)((0,l.on)([i,()=>u(n.isVirtualized),()=>u(n.selectionManager).focusedKey()],e=>{let[t,r,i]=e;if(r)i&&n.scrollToKey?.(i);else if(i&&t){let e=t.querySelector(`[data-key="${i}"]`);e&&eq(t,e)}})),{tabIndex:(0,l.To)(()=>{if(!u(n.shouldUseVirtualFocus))return null==u(n.selectionManager).focusedKey()?0:-1}),onKeyDown:e=>{ed(e,s.onKeyDown),e.altKey&&"Tab"===e.key&&e.preventDefault();let r=t();if(!r?.contains(e.target))return;let i=u(n.selectionManager),l=u(n.selectOnFocus),a=t=>{null!=t&&(i.setFocusedKey(t),e.shiftKey&&"multiple"===i.selectionMode()?i.extendSelection(t):l&&!e2(e)&&i.replaceSelection(t))},c=u(n.keyboardDelegate),g=u(n.shouldFocusWrap),f=i.focusedKey();switch(e.key){case"vertical"===d()?"ArrowDown":"ArrowRight":if(c.getKeyBelow){let t;e.preventDefault(),null==(t=null!=f?c.getKeyBelow(f):c.getFirstKey?.())&&g&&(t=c.getFirstKey?.(f)),a(t)}break;case"vertical"===d()?"ArrowUp":"ArrowLeft":if(c.getKeyAbove){let t;e.preventDefault(),null==(t=null!=f?c.getKeyAbove(f):c.getLastKey?.())&&g&&(t=c.getLastKey?.(f)),a(t)}break;case"vertical"===d()?"ArrowLeft":"ArrowUp":if(c.getKeyLeftOf){e.preventDefault();let t="rtl"===o();a(null!=f?c.getKeyLeftOf(f):t?c.getFirstKey?.():c.getLastKey?.())}break;case"vertical"===d()?"ArrowRight":"ArrowDown":if(c.getKeyRightOf){e.preventDefault();let t="rtl"===o();a(null!=f?c.getKeyRightOf(f):t?c.getLastKey?.():c.getFirstKey?.())}break;case"Home":if(c.getFirstKey){e.preventDefault();let t=c.getFirstKey(f,e5(e));null!=t&&(i.setFocusedKey(t),e5(e)&&e.shiftKey&&"multiple"===i.selectionMode()?i.extendSelection(t):l&&i.replaceSelection(t))}break;case"End":if(c.getLastKey){e.preventDefault();let t=c.getLastKey(f,e5(e));null!=t&&(i.setFocusedKey(t),e5(e)&&e.shiftKey&&"multiple"===i.selectionMode()?i.extendSelection(t):l&&i.replaceSelection(t))}break;case"PageDown":c.getKeyPageBelow&&null!=f&&(e.preventDefault(),a(c.getKeyPageBelow(f)));break;case"PageUp":c.getKeyPageAbove&&null!=f&&(e.preventDefault(),a(c.getKeyPageAbove(f)));break;case"a":e5(e)&&"multiple"===i.selectionMode()&&!0!==u(n.disallowSelectAll)&&(e.preventDefault(),i.selectAll());break;case"Escape":!e.defaultPrevented&&(e.preventDefault(),u(n.disallowEmptySelection)||i.clearSelection());break;case"Tab":if(!u(n.allowsTabNavigation))if(e.shiftKey)r.focus();else{var p;let e,t,n,i,o=(p={tabbable:!0},n=p?.tabbable?ev:eh,i=document.createTreeWalker(r,NodeFilter.SHOW_ELEMENT,{acceptNode:e=>p?.from?.contains(e)?NodeFilter.FILTER_REJECT:e.matches(n)&&em(e)&&(!p?.accept||p.accept(e))?NodeFilter.FILTER_ACCEPT:NodeFilter.FILTER_SKIP}),p?.from&&(i.currentNode=p.from),i);do(t=o.lastChild())&&(e=t);while(t)e&&!e.contains(document.activeElement)&&ec(e)}}},onMouseDown:e=>{i()===e.target&&e.preventDefault()},onFocusIn:e=>{let t=u(n.selectionManager),r=u(n.keyboardDelegate),o=u(n.selectOnFocus);if(t.isFocused()){e.currentTarget.contains(e.target)||t.setFocused(!1);return}if(e.currentTarget.contains(e.target)){if(t.setFocused(!0),null==t.focusedKey()){let n=e=>{null!=e&&(t.setFocusedKey(e),o&&t.replaceSelection(e))},i=e.relatedTarget;i&&e.currentTarget.compareDocumentPosition(i)&Node.DOCUMENT_POSITION_FOLLOWING?n(t.lastSelectedKey()??r.getLastKey?.()):n(t.firstSelectedKey()??r.getFirstKey?.())}else if(!u(n.isVirtualized)){let e=i();if(e){e.scrollTop=a.top,e.scrollLeft=a.left;let r=e.querySelector(`[data-key="${t.focusedKey()}"]`);r&&(ec(r),eq(e,r))}}}},onFocusOut:e=>{let t=u(n.selectionManager);e.currentTarget.contains(e.relatedTarget)||t.setFocused(!1)}}}({selectionManager:()=>u(t.selectionManager),keyboardDelegate:(0,l.To)(()=>{let e=u(t.keyboardDelegate);return e||new rz(t.collection,r,i)}),autoFocus:()=>u(t.autoFocus),deferAutoFocus:()=>u(t.deferAutoFocus),shouldFocusWrap:()=>u(t.shouldFocusWrap),disallowEmptySelection:()=>u(t.disallowEmptySelection),selectOnFocus:()=>u(t.selectOnFocus),disallowTypeAhead:()=>u(t.disallowTypeAhead),shouldUseVirtualFocus:()=>u(t.shouldUseVirtualFocus),allowsTabNavigation:()=>u(t.allowsTabNavigation),isVirtualized:()=>u(t.isVirtualized),scrollToKey:e=>u(t.scrollToKey)?.(e),orientation:()=>u(t.orientation)},r));!function(e,t){let[r,n]=(0,l.n5)(!1),i={pause(){n(!0)},resume(){n(!1)}},o=null,a=t=>e.onMountAutoFocus?.(t),s=t=>e.onUnmountAutoFocus?.(t),d=()=>{let e=ei(t()).createElement("span");return e.setAttribute("data-focus-trap",""),e.tabIndex=0,Object.assign(e.style,eT),e},c=()=>{let e=t();return e?(function e(t,r){let n=Array.from(t.querySelectorAll(eh)).filter(ey);return r&&ey(t)&&n.unshift(t),n.forEach((t,r)=>{if(eo(t)&&t.contentDocument){let i=e(t.contentDocument.body,!1);n.splice(r,1,...i)}}),n})(e,!0).filter(e=>!e.hasAttribute("data-focus-trap")):[]},g=()=>{let e=c();return e.length>0?e[0]:null};(0,l.EH)(()=>{if(l.S$)return;let e=t();if(!e)return;rI.add(i);let r=en(e);if(!er(e,r)){let t=new CustomEvent(rL,rA);e.addEventListener(rL,a),e.dispatchEvent(t),t.defaultPrevented||setTimeout(()=>{ec(g()),en(e)===r&&ec(e)},0)}(0,l.Ki)(()=>{e.removeEventListener(rL,a),setTimeout(()=>{let n=new CustomEvent(rO,rA);(()=>{let e=t();if(!e)return!1;let r=en(e);return!(!r||er(e,r))&&eb(r)})()&&n.preventDefault(),e.addEventListener(rO,s),e.dispatchEvent(n),n.defaultPrevented||ec(r??ei(t()).body),e.removeEventListener(rO,s),rI.remove(i)},0)})}),(0,l.EH)(()=>{if(l.S$)return;let n=t();if(!n||!u(e.trapFocus)||r())return;let i=e=>{let t=e.target;t?.closest(`[${e8}]`)||(er(n,t)?o=t:ec(o))},a=e=>{let t=e.relatedTarget??en(n);!t?.closest(`[${e8}]`)&&(er(n,t)||ec(o))};ei(t()).addEventListener("focusin",i),ei(t()).addEventListener("focusout",a),(0,l.Ki)(()=>{ei(t()).removeEventListener("focusin",i),ei(t()).removeEventListener("focusout",a)})}),(0,l.EH)(()=>{if(l.S$)return;let n=t();if(!n||!u(e.trapFocus)||r())return;let i=d();n.insertAdjacentElement("afterbegin",i);let o=d();function a(e){let t,r=g(),n=(t=c()).length>0?t[t.length-1]:null;e.relatedTarget===r?ec(n):ec(r)}n.insertAdjacentElement("beforeend",o),i.addEventListener("focusin",a),o.addEventListener("focusin",a);let s=new MutationObserver(e=>{for(let t of e)t.previousSibling===o&&(o.remove(),n.insertAdjacentElement("beforeend",o)),t.nextSibling===i&&(i.remove(),n.insertAdjacentElement("afterbegin",i))});s.observe(n,{childList:!0,subtree:!1}),(0,l.Ki)(()=>{i.removeEventListener("focusin",a),o.removeEventListener("focusin",a),i.remove(),o.remove(),s.disconnect()})})}({trapFocus:()=>b()&&a.isOpen(),onMountAutoFocus:e=>{void 0===s&&h.onOpenAutoFocus?.(e)},onUnmountAutoFocus:h.onCloseAutoFocus},()=>n);let w=e=>{h.onEscapeKeyDown?.(e),s?.setAutoFocusMenu(!1),a.close(!0)},x=e=>{h.onFocusOutside?.(e),o.isModal()&&e.preventDefault()};(0,l.EH)(()=>(0,l.Ki)(a.registerContentId(h.id)));let k={ref:G(e=>{a.setContentRef(e),n=e},h.ref),role:"menu",get id(){return h.id},get tabIndex(){return m.tabIndex()},get"aria-labelledby"(){return a.triggerId()},onKeyDown:eu([h.onKeyDown,m.onKeyDown,e=>{if(er(e.currentTarget,e.target)&&("Tab"===e.key&&a.isOpen()&&e.preventDefault(),void 0!==s&&"true"!==e.currentTarget.getAttribute("aria-haspopup")))switch(e.key){case r3.next(f(),o.orientation()):e.stopPropagation(),e.preventDefault(),a.close(!0),s.setAutoFocusMenu(!0),s.nextMenu();break;case r3.previous(f(),o.orientation()):if(e.currentTarget.hasAttribute("data-closed"))break;e.stopPropagation(),e.preventDefault(),a.close(!0),s.setAutoFocusMenu(!0),s.previousMenu()}}]),onMouseDown:eu([h.onMouseDown,m.onMouseDown]),onFocusIn:eu([h.onFocusIn,m.onFocusIn]),onFocusOut:eu([h.onFocusOut,m.onFocusOut]),onPointerEnter:e=>{ed(e,h.onPointerEnter),a.isOpen()&&(a.parentMenuContext()?.listState().selectionManager().setFocused(!1),a.parentMenuContext()?.listState().selectionManager().setFocusedKey(void 0))},onPointerMove:e=>{if(ed(e,h.onPointerMove),"mouse"!==e.pointerType)return;let t=e.target,r=y!==e.clientX;er(e.currentTarget,t)&&r&&(a.setPointerDir(e.clientX>y?"right":"left"),y=e.clientX)},get"data-orientation"(){return o.orientation()}};return(0,l.a0)(l.wv,{get when(){return a.contentPresent()},get children(){return(0,l.a0)(l.wv,{get when(){return void 0===d||null!=a.parentMenuContext()},get fallback(){return(0,l.a0)(ez,(0,l.v6)({as:"div"},()=>a.dataset(),k,v))},get children(){return(0,l.a0)(rg.Positioner,{get children(){return(0,l.a0)(rv,(0,l.v6)({get disableOutsidePointerEvents(){return(0,l.ph)(()=>!!b())()&&a.isOpen()},get excludedElements(){return[a.triggerRef]},bypassTopMostLayerCheck:!0,get style(){return X({"--kb-menu-content-transform-origin":"var(--kb-popper-content-transform-origin)",position:"relative"},h.style)},onEscapeKeyDown:w,onFocusOutside:x,get onDismiss(){return a.close}},()=>a.dataset(),k,v))}})}})}})}function r9(e){var t;let r,n,i,o,a,s,d,u,c,g=rJ(),f=rW(),[p,h]=(0,l.rg)(e,["ref"]);return t={element:()=>r??null,enabled:()=>f.contentPresent()&&g.preventScroll()},n=(0,l.v6)({element:null,enabled:!0,hideScrollbar:!0,preventScrollbarShift:!0,preventScrollbarShiftMode:"padding",restoreScrollPosition:!0,allowPinchZoom:!1},t),i=(0,l.Ds)(),o=[0,0],a=null,s=null,(0,l.EH)(()=>{e7(n.enabled)&&(rY(e=>[...e,i]),(0,l.Ki)(()=>{rY(e=>e.filter(e=>e!==i))}))}),(0,l.EH)(()=>{if(!e7(n.enabled)||!e7(n.hideScrollbar))return;let{body:e}=document,t=window.innerWidth-e.offsetWidth;if(e7(n.preventScrollbarShift)){let r={overflow:"hidden"},i=[];t>0&&("padding"===e7(n.preventScrollbarShiftMode)?r.paddingRight=`calc(${window.getComputedStyle(e).paddingRight} + ${t}px)`:r.marginRight=`calc(${window.getComputedStyle(e).marginRight} + ${t}px)`,i.push({key:"--scrollbar-width",value:`${t}px`}));let o=window.scrollY,l=window.scrollX;rR({key:"prevent-scroll",element:e,style:r,properties:i,cleanup:()=>{e7(n.restoreScrollPosition)&&t>0&&window.scrollTo(l,o)}})}else rR({key:"prevent-scroll",element:e,style:{overflow:"hidden"}})}),(0,l.EH)(()=>{rU().indexOf(i)===rU().length-1&&e7(n.enabled)&&(document.addEventListener("wheel",u,{passive:!1}),document.addEventListener("touchstart",d,{passive:!1}),document.addEventListener("touchmove",c,{passive:!1}),(0,l.Ki)(()=>{document.removeEventListener("wheel",u),document.removeEventListener("touchstart",d),document.removeEventListener("touchmove",c)}))}),d=e=>{o=rV(e),a=null,s=null},u=e=>{let t,r=e.target,i=e7(n.element),o=[(t=e).deltaX,t.deltaY],l=Math.abs(o[0])>Math.abs(o[1])?"x":"y",a="x"===l?o[0]:o[1],s=rN(r,l,a,i);i&&rj(i,r)&&s||!e.cancelable||e.preventDefault()},c=e=>{let t,r=e7(n.element),i=e.target;if(2===e.touches.length)t=!e7(n.allowPinchZoom);else{if(null==a||null===s){let t=rV(e).map((e,t)=>o[t]-e),r=Math.abs(t[0])>Math.abs(t[1])?"x":"y";a=r,s="x"===r?t[0]:t[1]}if("range"===i.type)t=!1;else{let e=rN(i,a,s,r);t=!(r&&rj(r,i))||!e}}t&&e.cancelable&&e.preventDefault()},(0,l.a0)(r7,(0,l.v6)({ref(e){let t=G(e=>{r=e},p.ref);"function"==typeof t&&t(e)}},h))}var r8=(0,l.q6)();function ne(e){let t=ek({id:rJ().generateId(`group-${(0,l.Ds)()}`)},e),[r,n]=(0,l.n5)(),i={generateId:et(()=>t.id),registerLabelId:eM(n)};return(0,l.a0)(r8.Provider,{value:i,get children(){return(0,l.a0)(ez,(0,l.v6)({as:"div",role:"group",get"aria-labelledby"(){return r()}},t))}})}function nt(e){let t=function(){let e=(0,l.NT)(r8);if(void 0===e)throw Error("[kobalte]: `useMenuGroupContext` must be used within a `Menu.Group` component");return e}(),r=ek({id:t.generateId("label")},e),[n,i]=(0,l.rg)(r,["id"]);return(0,l.EH)(()=>(0,l.Ki)(t.registerLabelId(n.id))),(0,l.a0)(ez,(0,l.v6)({as:"span",get id(){return n.id},"aria-hidden":"true"},i))}function nr(e){let t=rW(),r=ek({children:"\u25BC"},e);return(0,l.a0)(ez,(0,l.v6)({as:"span","aria-hidden":"true"},()=>t.dataset(),r))}function nn(e){return(0,l.a0)(r0,(0,l.v6)({role:"menuitem",closeOnSelect:!0},e))}function ni(e){let t=rZ(),r=ek({id:t.generateId("description")},e),[n,i]=(0,l.rg)(r,["id"]);return(0,l.EH)(()=>(0,l.Ki)(t.registerDescription(n.id))),(0,l.a0)(ez,(0,l.v6)({as:"div",get id(){return n.id}},()=>t.dataset(),i))}function no(e){let t=rZ(),r=ek({id:t.generateId("indicator")},e),[n,i]=(0,l.rg)(r,["forceMount"]);return(0,l.a0)(l.wv,{get when(){return n.forceMount||t.isChecked()},get children(){return(0,l.a0)(ez,(0,l.v6)({as:"div"},()=>t.dataset(),i))}})}function nl(e){let t=rZ(),r=ek({id:t.generateId("label")},e),[n,i]=(0,l.rg)(r,["ref","id"]);return(0,l.EH)(()=>(0,l.Ki)(t.registerLabel(n.id))),(0,l.a0)(ez,(0,l.v6)({as:"div",ref(e){let r=G(t.setLabelRef,n.ref);"function"==typeof r&&r(e)},get id(){return n.id}},()=>t.dataset(),i))}function na(e){let t=rW();return(0,l.a0)(l.wv,{get when(){return t.contentPresent()},get children(){return(0,l.a0)(l.ZL,e)}})}var ns=(0,l.q6)();function nd(e){let t=ek({id:rJ().generateId(`radiogroup-${(0,l.Ds)()}`)},e),[r,n]=(0,l.rg)(t,["value","defaultValue","onChange","disabled"]),[i,o]=eB({value:()=>r.value,defaultValue:()=>r.defaultValue,onChange:e=>r.onChange?.(e)});return(0,l.a0)(ns.Provider,{value:{isDisabled:()=>r.disabled,isSelectedValue:e=>e===i(),setSelectedValue:o},get children(){return(0,l.a0)(ne,n)}})}function nu(e){let t=function(){let e=(0,l.NT)(ns);if(void 0===e)throw Error("[kobalte]: `useMenuRadioGroupContext` must be used within a `Menu.RadioGroup` component");return e}(),r=ek({closeOnSelect:!1},e),[n,i]=(0,l.rg)(r,["value","onSelect"]);return(0,l.a0)(r0,(0,l.v6)({role:"menuitemradio",get checked(){return t.isSelectedValue(n.value)},onSelect:()=>{n.onSelect?.(),t.setSelectedValue(n.value)}},i))}function nc(e){var t,r;let n,i,o,a=rJ(),s=(0,l.NT)(eU),d=(0,l.NT)(rQ),c=r5(),g=(0,l.NT)(r6),f=ek({placement:"horizontal"===a.orientation()?"bottom-start":"right-start"},e),[p,h]=(0,l.rg)(f,["open","defaultOpen","onOpenChange"]),v=0,y=null,b="right",[m,w]=(0,l.n5)(),[x,k]=(0,l.n5)(),[$,S]=(0,l.n5)(),[C,q]=(0,l.n5)(),[E,T]=(0,l.n5)(!0),[M,F]=(0,l.n5)(h.placement),[D,z]=(0,l.n5)([]),[L,O]=(0,l.n5)([]),{DomCollectionProvider:A}=function(e={}){let[t,r]=function(e){let[t,r]=eB(e);return[()=>t()??[],r]}({value:()=>u(e.items),onChange:t=>e.onItemsChange?.(t)});!function(e,t){if("function"!=typeof IntersectionObserver)return(0,l.EH)(()=>{let r=setTimeout(()=>{eV(e(),t)});(0,l.Ki)(()=>clearTimeout(r))});let r=[];(0,l.EH)(()=>{let n=new IntersectionObserver(()=>{let n=!!r.length;r=e(),n&&eV(e(),t)},{root:function(e){let t=e[0],r=e[e.length-1]?.ref(),n=t?.ref()?.parentElement;for(;n;){if(r&&n.contains(r))return n;n=n.parentElement}return ei(n).body}(e())});for(let t of e()){let e=t.ref();e&&n.observe(e)}(0,l.Ki)(()=>n.disconnect())})}(t,r);let n=e=>(r(t=>{let r=function(e,t){let r=t.ref();if(!r)return -1;let n=e.length;if(!n)return -1;for(;n--;){let t=e[n]?.ref();if(t&&eY(t,r))return n+1}return 0}(t,e);return function(e,t,r=-1){return r in e?[...e.slice(0,r),t,...e.slice(r)]:[...e,t]}(t,e,r)}),()=>{r(t=>{let r=t.filter(t=>t.ref()!==e.ref());return t.length===r.length?t:r})});return{DomCollectionProvider:e=>(0,l.a0)(eU.Provider,{value:{registerItem:n},get children(){return e.children}})}}({items:L,onItemsChange:O}),I=ry({open:()=>p.open,defaultOpen:()=>p.defaultOpen,onOpenChange:e=>p.onOpenChange?.(e)}),{present:K}=e9({show:()=>a.forceMount()||I.isOpen(),element:()=>C()??null}),P=(n=function(e){let t=ek({selectionMode:"none",selectionBehavior:"toggle"},e),[r,n]=(0,l.n5)(!1),[i,o]=(0,l.n5)(),[a,s]=function(e){let[t,r]=eB(e);return[()=>t()??new e1,r]}({value:(0,l.To)(()=>{let e=u(t.selectedKeys);return null!=e?new e1(e):e}),defaultValue:(0,l.To)(()=>{let e=u(t.defaultSelectedKeys);return null!=e?new e1(e):new e1}),onChange:e=>t.onSelectionChange?.(e)}),[d,c]=(0,l.n5)(u(t.selectionBehavior));return(0,l.EH)(()=>{let e=a();"replace"===u(t.selectionBehavior)&&"toggle"===d()&&"object"==typeof e&&0===e.size&&c("replace")}),(0,l.EH)(()=>{c(u(t.selectionBehavior)??"toggle")}),{selectionMode:()=>u(t.selectionMode),disallowEmptySelection:()=>u(t.disallowEmptySelection)??!1,selectionBehavior:d,setSelectionBehavior:c,isFocused:r,setFocused:n,focusedKey:i,setFocusedKey:o,selectedKeys:a,setSelectedKeys:e=>{(u(t.allowDuplicateSelectionEvents)||!function(e,t){if(e.size!==t.size)return!1;for(let r of e)if(!t.has(r))return!1;return!0}(e,a()))&&s(e)}}}(t={selectionMode:"none",dataSource:L}),o=new e4(i=function(e,t=[]){return(0,l.To)(()=>{let r=function e(t){let r=t.startIndex??0,n=t.startLevel??0,i=[],o=e=>{if(null==e)return"";let r=t.getKey??"key",n=ee(r)?e[r]:r(e);return null!=n?String(n):""},l=e=>{if(null==e)return"";let r=t.getTextValue??"textValue",n=ee(r)?e[r]:r(e);return null!=n?String(n):""},a=e=>{if(null==e)return!1;let r=t.getDisabled??"disabled";return(ee(r)?e[r]:r(e))??!1},s=e=>{if(null!=e)return ee(t.getSectionChildren)?e[t.getSectionChildren]:t.getSectionChildren?.(e)};for(let d of t.dataSource){if(ee(d)||"number"==typeof d){i.push({type:"item",rawValue:d,key:String(d),textValue:String(d),disabled:a(d),level:n,index:r}),r++;continue}if(null!=s(d)){i.push({type:"section",rawValue:d,key:"",textValue:"",disabled:!1,level:n,index:r}),r++;let o=s(d)??[];if(o.length>0){let l=e({dataSource:o,getKey:t.getKey,getTextValue:t.getTextValue,getDisabled:t.getDisabled,getSectionChildren:t.getSectionChildren,startIndex:r,startLevel:n+1});i.push(...l),r+=l.length}}else i.push({type:"item",rawValue:d,key:o(d),textValue:l(d),disabled:a(d),level:n,index:r}),r++}return i}({dataSource:u(e.dataSource),getKey:u(e.getKey),getTextValue:u(e.getTextValue),getDisabled:u(e.getDisabled),getSectionChildren:u(e.getSectionChildren)});for(let e=0;e<t.length;e++)t[e]();return e.factory(r)})}({dataSource:()=>u(t.dataSource),getKey:()=>u(t.getKey),getTextValue:()=>u(t.getTextValue),getDisabled:()=>u(t.getDisabled),getSectionChildren:()=>u(t.getSectionChildren),factory:e=>new e6(t.filter?t.filter(e):e)},[()=>t.filter]),n),(0,l.KZ)(()=>{let e=n.focusedKey();null==e||i().getItem(e)||n.setFocusedKey(void 0)}),{collection:i,selectionManager:()=>o}),B=e=>{T(e),I.open()},R=(e=!1)=>{I.close(),e&&d&&d.close(!0)},H=()=>{let e=C();e&&(ec(e),P.selectionManager().setFocused(!0),P.selectionManager().setFocusedKey(void 0))},G=()=>{null!=g?setTimeout(()=>H()):H()},U=e=>{var t;return b===y?.side&&!!(t=y?.area)&&function(e,t){let[r,n]=e,i=!1,o=t.length;for(let e=0,l=o-1;e<o;l=e++){let[a,s]=t[e],[d,u]=t[l],[,c]=t[0===l?o-1:l-1]||[0,0],g=(s-u)*(r-a)-(a-d)*(n-s);if(u<s){if(n>=u&&n<s){if(0===g)return!0;g>0&&(n===u?n>c&&(i=!i):i=!i)}}else if(s<u){if(n>s&&n<=u){if(0===g)return!0;g<0&&(n===u?n<c&&(i=!i):i=!i)}}else if(n==s&&(r>=d&&r<=a||r>=a&&r<=d))return!0}return i}([e.clientX,e.clientY],t)};r={isDisabled:()=>!(null==d&&I.isOpen()&&a.isModal()),targets:()=>[C(),...D()].filter(Boolean)},(0,l.EH)(()=>{u(r.isDisabled)||(0,l.Ki)(function(e,t=document.body){let r=new Set(e),n=new Set,i=e=>{for(let t of e.querySelectorAll(`[data-live-announcer], [${e8}]`))r.add(t);let t=e=>{if(r.has(e)||e.parentElement&&n.has(e.parentElement)&&"row"!==e.parentElement.getAttribute("role"))return NodeFilter.FILTER_REJECT;for(let t of r)if(e.contains(t))return NodeFilter.FILTER_SKIP;return NodeFilter.FILTER_ACCEPT},i=document.createTreeWalker(e,NodeFilter.SHOW_ELEMENT,{acceptNode:t}),l=t(e);if(l===NodeFilter.FILTER_ACCEPT&&o(e),l!==NodeFilter.FILTER_REJECT){let e=i.nextNode();for(;null!=e;)o(e),e=i.nextNode()}},o=e=>{let t=rK.get(e)??0;("true"!==e.getAttribute("aria-hidden")||0!==t)&&(0===t&&e.setAttribute("aria-hidden","true"),n.add(e),rK.set(e,t+1))};rP.length&&rP[rP.length-1].disconnect(),i(t);let l=new MutationObserver(e=>{for(let t of e)if("childList"===t.type&&0!==t.addedNodes.length&&![...r,...n].some(e=>e.contains(t.target))){for(let e of t.removedNodes)e instanceof Element&&(r.delete(e),n.delete(e));for(let e of t.addedNodes)(e instanceof HTMLElement||e instanceof SVGElement)&&("true"===e.dataset.liveAnnouncer||"true"===e.dataset.reactAriaTopLayer)?r.add(e):e instanceof Element&&i(e)}});l.observe(t,{childList:!0,subtree:!0});let a={observe(){l.observe(t,{childList:!0,subtree:!0})},disconnect(){l.disconnect()}};return rP.push(a),()=>{for(let e of(l.disconnect(),n)){let t=rK.get(e);if(null==t)return;1===t?(e.removeAttribute("aria-hidden"),rK.delete(e)):rK.set(e,t-1)}a===rP[rP.length-1]?(rP.pop(),rP.length&&rP[rP.length-1].observe()):rP.splice(rP.indexOf(a),1)}}(u(r.targets),u(r.root)))}),(0,l.EH)(()=>{let e=C();if(!e||!d)return;let t=d.registerNestedMenu(e);(0,l.Ki)(()=>{t()})}),(0,l.EH)(()=>{void 0===d&&c?.registerMenu(a.value(),[C(),...D()])}),(0,l.EH)(()=>{void 0===d&&void 0!==c&&(c.value()===a.value()?($()?.focus(),c.autoFocusMenu()&&B(!0)):R())}),(0,l.EH)(()=>{void 0===d&&void 0!==c&&I.isOpen()&&c.setValue(a.value())}),(0,l.Ki)(()=>{void 0===d&&c?.unregisterMenu(a.value())});let Y={dataset:(0,l.To)(()=>({"data-expanded":I.isOpen()?"":void 0,"data-closed":I.isOpen()?void 0:""})),isOpen:I.isOpen,contentPresent:K,nestedMenus:D,currentPlacement:M,pointerGraceTimeoutId:()=>v,autoFocus:E,listState:()=>P,parentMenuContext:()=>d,triggerRef:$,contentRef:C,triggerId:m,contentId:x,setTriggerRef:S,setContentRef:q,open:B,close:R,toggle:e=>{T(e),I.toggle()},focusContent:G,onItemEnter:e=>{U(e)&&e.preventDefault()},onItemLeave:e=>{U(e)||G()},onTriggerLeave:e=>{U(e)&&e.preventDefault()},setPointerDir:e=>b=e,setPointerGraceTimeoutId:e=>v=e,setPointerGraceIntent:e=>y=e,registerNestedMenu:e=>{z(t=>[...t,e]);let t=d?.registerNestedMenu(e);return()=>{z(t=>J(t,e)),t?.()}},registerItemToParentDomCollection:s?.registerItem,registerTriggerId:eM(w),registerContentId:eM(k)};return(0,l.a0)(A,{get children(){return(0,l.a0)(rQ.Provider,{value:Y,get children(){return(0,l.a0)(l.wv,{when:void 0===g,get fallback(){return h.children},get children(){return(0,l.a0)(rg,(0,l.v6)({anchorRef:$,contentRef:C,onCurrentPlacementChange:F},h))}})}})}})}function ng(e){let{direction:t}=eJ();return(0,l.a0)(nc,(0,l.v6)({get placement(){return"rtl"===t()?"left-start":"right-start"},flip:!0},e))}function nf(e){let t=rW(),r=rJ(),[n,i]=(0,l.rg)(e,["onFocusOutside","onKeyDown"]),{direction:o}=eJ();return(0,l.a0)(r7,(0,l.v6)({onOpenAutoFocus:e=>{e.preventDefault()},onCloseAutoFocus:e=>{e.preventDefault()},onFocusOutside:e=>{n.onFocusOutside?.(e);let r=e.target;er(t.triggerRef(),r)||t.close()},onKeyDown:e=>{let i,l;ed(e,n.onKeyDown);let a=er(e.currentTarget,e.target),s=(i=o(),l=r.orientation(),"ltr"===i?["horizontal"===l?"ArrowLeft":"ArrowUp"]:["horizontal"===l?"ArrowRight":"ArrowDown"]).includes(e.key),d=null!=t.parentMenuContext();a&&s&&d&&(t.close(),ec(t.triggerRef()))}},i))}var np=["Enter"," "];function nh(e){let t,r=rJ(),n=rW(),i=ek({id:r.generateId(`sub-trigger-${(0,l.Ds)()}`)},e),[o,a]=(0,l.rg)(i,["ref","id","textValue","disabled","onPointerMove","onPointerLeave","onPointerDown","onPointerUp","onClick","onKeyDown","onMouseDown","onFocus"]),s=null,d=()=>{l.S$||(s&&window.clearTimeout(s),s=null)},{direction:u}=eJ(),c=()=>o.id,g=()=>{let e=n.parentMenuContext();if(null==e)throw Error("[kobalte]: `Menu.SubTrigger` must be used within a `Menu.Sub` component");return e.listState().selectionManager()},f=e3({key:c,selectionManager:g,shouldSelectOnPressUp:!0,allowsDifferentPressOrigin:!0,disabled:()=>o.disabled},()=>t),p=e=>{ed(e,o.onClick),n.isOpen()||o.disabled||n.open(!0)},h=e=>{let t,i;ed(e,o.onKeyDown),e.repeat||!o.disabled&&(t=u(),i=r.orientation(),"ltr"===t?[...np,"horizontal"===i?"ArrowRight":"ArrowDown"]:[...np,"horizontal"===i?"ArrowLeft":"ArrowUp"]).includes(e.key)&&(e.stopPropagation(),e.preventDefault(),g().setFocused(!1),g().setFocusedKey(void 0),n.isOpen()||n.open("first"),n.focusContent(),n.listState().selectionManager().setFocused(!0),n.listState().selectionManager().setFocusedKey(n.listState().collection().getFirstKey()))};return(0,l.EH)(()=>{if(null==n.registerItemToParentDomCollection)throw Error("[kobalte]: `Menu.SubTrigger` must be used within a `Menu.Sub` component");let e=n.registerItemToParentDomCollection({ref:()=>t,type:"item",key:c(),textValue:o.textValue??t?.textContent??"",disabled:o.disabled??!1});(0,l.Ki)(e)}),(0,l.EH)((0,l.on)(()=>n.parentMenuContext()?.pointerGraceTimeoutId(),e=>{(0,l.Ki)(()=>{window.clearTimeout(e),n.parentMenuContext()?.setPointerGraceIntent(null)})})),(0,l.EH)(()=>(0,l.Ki)(n.registerTriggerId(o.id))),(0,l.Ki)(()=>{d()}),(0,l.a0)(ez,(0,l.v6)({as:"div",ref(e){let r=G(e=>{n.setTriggerRef(e),t=e},o.ref);"function"==typeof r&&r(e)},get id(){return o.id},role:"menuitem",get tabIndex(){return f.tabIndex()},"aria-haspopup":"true",get"aria-expanded"(){return n.isOpen()},get"aria-controls"(){return(0,l.ph)(()=>!!n.isOpen())()?n.contentId():void 0},get"aria-disabled"(){return o.disabled},get"data-key"(){return f.dataKey()},get"data-highlighted"(){return g().focusedKey()===c()?"":void 0},get"data-disabled"(){return o.disabled?"":void 0},get onPointerDown(){return eu([o.onPointerDown,f.onPointerDown])},get onPointerUp(){return eu([o.onPointerUp,f.onPointerUp])},get onClick(){return eu([p,f.onClick])},get onKeyDown(){return eu([h,f.onKeyDown])},get onMouseDown(){return eu([o.onMouseDown,f.onMouseDown])},get onFocus(){return eu([o.onFocus,f.onFocus])},onPointerMove:e=>{if(ed(e,o.onPointerMove),"mouse"!==e.pointerType)return;let t=n.parentMenuContext();if(t?.onItemEnter(e),!e.defaultPrevented){if(o.disabled)return void t?.onItemLeave(e);n.isOpen()||s||(n.parentMenuContext()?.setPointerGraceIntent(null),s=window.setTimeout(()=>{n.open(!1),d()},100)),t?.onItemEnter(e),e.defaultPrevented||(n.listState().selectionManager().isFocused()&&(n.listState().selectionManager().setFocused(!1),n.listState().selectionManager().setFocusedKey(void 0)),ec(e.currentTarget),t?.listState().selectionManager().setFocused(!0),t?.listState().selectionManager().setFocusedKey(c()))}},onPointerLeave:e=>{if(ed(e,o.onPointerLeave),"mouse"!==e.pointerType)return;d();let t=n.parentMenuContext(),r=n.contentRef();if(r){t?.setPointerGraceIntent({area:function(e,t,r){let n=e.split("-")[0],i=r.getBoundingClientRect(),o=[],l=t.clientX,a=t.clientY;switch(n){case"top":o.push([l,a+5]),o.push([i.left,i.bottom]),o.push([i.left,i.top]),o.push([i.right,i.top]),o.push([i.right,i.bottom]);break;case"right":o.push([l-5,a]),o.push([i.left,i.top]),o.push([i.right,i.top]),o.push([i.right,i.bottom]),o.push([i.left,i.bottom]);break;case"bottom":o.push([l,a-5]),o.push([i.right,i.top]),o.push([i.right,i.bottom]),o.push([i.left,i.bottom]),o.push([i.left,i.top]);break;case"left":o.push([l+5,a]),o.push([i.right,i.bottom]),o.push([i.left,i.bottom]),o.push([i.left,i.top]),o.push([i.right,i.top])}return o}(n.currentPlacement(),e,r),side:n.currentPlacement().split("-")[0]}),window.clearTimeout(t?.pointerGraceTimeoutId());let i=window.setTimeout(()=>{t?.setPointerGraceIntent(null)},300);t?.setPointerGraceTimeoutId(i)}else{if(t?.onTriggerLeave(e),e.defaultPrevented)return;t?.setPointerGraceIntent(null)}t?.onItemLeave(e)}},()=>n.dataset(),a))}function nv(e){let t=r5(),r=ek({id:`menu-${(0,l.Ds)()}`,modal:!0},e),[n,i]=(0,l.rg)(r,["id","modal","preventScroll","forceMount","open","defaultOpen","onOpenChange","value","orientation"]),o=ry({open:()=>n.open,defaultOpen:()=>n.defaultOpen,onOpenChange:e=>n.onOpenChange?.(e)}),a={isModal:()=>n.modal??!0,preventScroll:()=>n.preventScroll??a.isModal(),forceMount:()=>n.forceMount??!1,generateId:et(()=>n.id),value:()=>n.value,orientation:()=>n.orientation??t?.orientation()??"horizontal"};return(0,l.a0)(rX.Provider,{value:a,get children(){return(0,l.a0)(nc,(0,l.v6)({get open(){return o.isOpen()},get onOpenChange(){return o.setIsOpen}},i))}})}function ny(e){let t,r=ek({orientation:"horizontal"},e),[n,i]=(0,l.rg)(r,["ref","orientation"]),o=eF(()=>t,()=>"hr");return(0,l.a0)(ez,(0,l.v6)({as:"hr",ref(e){let r=G(e=>t=e,n.ref);"function"==typeof r&&r(e)},get role(){return"hr"!==o()?"separator":void 0},get"aria-orientation"(){return"vertical"===n.orientation?"vertical":void 0},get"data-orientation"(){return n.orientation}},i))}eG({},{Root:()=>ny,Separator:()=>nb});var nb=ny,nm={};function nw(e){let t=rJ(),r=rW(),[n,i]=(0,l.rg)(e,["onCloseAutoFocus","onInteractOutside"]),o=!1;return(0,l.a0)(r9,(0,l.v6)({onCloseAutoFocus:e=>{n.onCloseAutoFocus?.(e),o||ec(r.triggerRef()),o=!1,e.preventDefault()},onInteractOutside:e=>{n.onInteractOutside?.(e),(!t.isModal()||e.detail.isContextMenu)&&(o=!0)}},i))}function nx(e){let t=ek({id:`dropdownmenu-${(0,l.Ds)()}`},e);return(0,l.a0)(nv,t)}eG(nm,{Arrow:()=>rs,CheckboxItem:()=>r1,Content:()=>nw,DropdownMenu:()=>nk,Group:()=>ne,GroupLabel:()=>nt,Icon:()=>nr,Item:()=>nn,ItemDescription:()=>ni,ItemIndicator:()=>no,ItemLabel:()=>nl,Portal:()=>na,RadioGroup:()=>nd,RadioItem:()=>nu,Root:()=>nx,Separator:()=>ny,Sub:()=>ng,SubContent:()=>nf,SubTrigger:()=>nh,Trigger:()=>r4});var nk=Object.assign(nx,{Arrow:rs,CheckboxItem:r1,Content:nw,Group:ne,GroupLabel:nt,Icon:nr,Item:nn,ItemDescription:ni,ItemIndicator:no,ItemLabel:nl,Portal:na,RadioGroup:nd,RadioItem:nu,Separator:ny,Sub:ng,SubContent:nf,SubTrigger:nh,Trigger:r4}),n$={colors:{inherit:"inherit",current:"currentColor",transparent:"transparent",black:"#000000",white:"#ffffff",neutral:{50:"#f9fafb",100:"#f2f4f7",200:"#eaecf0",300:"#d0d5dd",400:"#98a2b3",500:"#667085",600:"#475467",700:"#344054",800:"#1d2939",900:"#101828"},darkGray:{50:"#525c7a",100:"#49536e",200:"#414962",300:"#394056",400:"#313749",500:"#292e3d",600:"#212530",700:"#191c24",800:"#111318",900:"#0b0d10"},gray:{50:"#f9fafb",100:"#f2f4f7",200:"#eaecf0",300:"#d0d5dd",400:"#98a2b3",500:"#667085",600:"#475467",700:"#344054",800:"#1d2939",900:"#101828"},blue:{25:"#F5FAFF",50:"#EFF8FF",100:"#D1E9FF",200:"#B2DDFF",300:"#84CAFF",400:"#53B1FD",500:"#2E90FA",600:"#1570EF",700:"#175CD3",800:"#1849A9",900:"#194185"},green:{25:"#F6FEF9",50:"#ECFDF3",100:"#D1FADF",200:"#A6F4C5",300:"#6CE9A6",400:"#32D583",500:"#12B76A",600:"#039855",700:"#027A48",800:"#05603A",900:"#054F31"},red:{50:"#fef2f2",100:"#fee2e2",200:"#fecaca",300:"#fca5a5",400:"#f87171",500:"#ef4444",600:"#dc2626",700:"#b91c1c",800:"#991b1b",900:"#7f1d1d",950:"#450a0a"},yellow:{25:"#FFFCF5",50:"#FFFAEB",100:"#FEF0C7",200:"#FEDF89",300:"#FEC84B",400:"#FDB022",500:"#F79009",600:"#DC6803",700:"#B54708",800:"#93370D",900:"#7A2E0E"},purple:{25:"#FAFAFF",50:"#F4F3FF",100:"#EBE9FE",200:"#D9D6FE",300:"#BDB4FE",400:"#9B8AFB",500:"#7A5AF8",600:"#6938EF",700:"#5925DC",800:"#4A1FB8",900:"#3E1C96"},teal:{25:"#F6FEFC",50:"#F0FDF9",100:"#CCFBEF",200:"#99F6E0",300:"#5FE9D0",400:"#2ED3B7",500:"#15B79E",600:"#0E9384",700:"#107569",800:"#125D56",900:"#134E48"},pink:{25:"#fdf2f8",50:"#fce7f3",100:"#fbcfe8",200:"#f9a8d4",300:"#f472b6",400:"#ec4899",500:"#db2777",600:"#be185d",700:"#9d174d",800:"#831843",900:"#500724"},cyan:{25:"#ecfeff",50:"#cffafe",100:"#a5f3fc",200:"#67e8f9",300:"#22d3ee",400:"#06b6d4",500:"#0891b2",600:"#0e7490",700:"#155e75",800:"#164e63",900:"#083344"}},alpha:{100:"ff",90:"e5",80:"cc",70:"b3",60:"99",50:"80",40:"66",30:"4d",20:"33",10:"1a",0:"00"},font:{size:{"2xs":"calc(var(--tsqd-font-size) * 0.625)",xs:"calc(var(--tsqd-font-size) * 0.75)",sm:"calc(var(--tsqd-font-size) * 0.875)",md:"var(--tsqd-font-size)",lg:"calc(var(--tsqd-font-size) * 1.125)",xl:"calc(var(--tsqd-font-size) * 1.25)","2xl":"calc(var(--tsqd-font-size) * 1.5)","3xl":"calc(var(--tsqd-font-size) * 1.875)","4xl":"calc(var(--tsqd-font-size) * 2.25)","5xl":"calc(var(--tsqd-font-size) * 3)","6xl":"calc(var(--tsqd-font-size) * 3.75)","7xl":"calc(var(--tsqd-font-size) * 4.5)","8xl":"calc(var(--tsqd-font-size) * 6)","9xl":"calc(var(--tsqd-font-size) * 8)"},lineHeight:{xs:"calc(var(--tsqd-font-size) * 1)",sm:"calc(var(--tsqd-font-size) * 1.25)",md:"calc(var(--tsqd-font-size) * 1.5)",lg:"calc(var(--tsqd-font-size) * 1.75)",xl:"calc(var(--tsqd-font-size) * 2)","2xl":"calc(var(--tsqd-font-size) * 2.25)","3xl":"calc(var(--tsqd-font-size) * 2.5)","4xl":"calc(var(--tsqd-font-size) * 2.75)","5xl":"calc(var(--tsqd-font-size) * 3)","6xl":"calc(var(--tsqd-font-size) * 3.25)","7xl":"calc(var(--tsqd-font-size) * 3.5)","8xl":"calc(var(--tsqd-font-size) * 3.75)","9xl":"calc(var(--tsqd-font-size) * 4)"},weight:{thin:"100",extralight:"200",light:"300",normal:"400",medium:"500",semibold:"600",bold:"700",extrabold:"800",black:"900"}},breakpoints:{xs:"320px",sm:"640px",md:"768px",lg:"1024px",xl:"1280px","2xl":"1536px"},border:{radius:{none:"0px",xs:"calc(var(--tsqd-font-size) * 0.125)",sm:"calc(var(--tsqd-font-size) * 0.25)",md:"calc(var(--tsqd-font-size) * 0.375)",lg:"calc(var(--tsqd-font-size) * 0.5)",xl:"calc(var(--tsqd-font-size) * 0.75)","2xl":"calc(var(--tsqd-font-size) * 1)","3xl":"calc(var(--tsqd-font-size) * 1.5)",full:"9999px"}},size:{0:"0px",.25:"calc(var(--tsqd-font-size) * 0.0625)",.5:"calc(var(--tsqd-font-size) * 0.125)",1:"calc(var(--tsqd-font-size) * 0.25)",1.5:"calc(var(--tsqd-font-size) * 0.375)",2:"calc(var(--tsqd-font-size) * 0.5)",2.5:"calc(var(--tsqd-font-size) * 0.625)",3:"calc(var(--tsqd-font-size) * 0.75)",3.5:"calc(var(--tsqd-font-size) * 0.875)",4:"calc(var(--tsqd-font-size) * 1)",4.5:"calc(var(--tsqd-font-size) * 1.125)",5:"calc(var(--tsqd-font-size) * 1.25)",5.5:"calc(var(--tsqd-font-size) * 1.375)",6:"calc(var(--tsqd-font-size) * 1.5)",6.5:"calc(var(--tsqd-font-size) * 1.625)",7:"calc(var(--tsqd-font-size) * 1.75)",8:"calc(var(--tsqd-font-size) * 2)",9:"calc(var(--tsqd-font-size) * 2.25)",10:"calc(var(--tsqd-font-size) * 2.5)",11:"calc(var(--tsqd-font-size) * 2.75)",12:"calc(var(--tsqd-font-size) * 3)",14:"calc(var(--tsqd-font-size) * 3.5)",16:"calc(var(--tsqd-font-size) * 4)",20:"calc(var(--tsqd-font-size) * 5)",24:"calc(var(--tsqd-font-size) * 6)",28:"calc(var(--tsqd-font-size) * 7)",32:"calc(var(--tsqd-font-size) * 8)",36:"calc(var(--tsqd-font-size) * 9)",40:"calc(var(--tsqd-font-size) * 10)",44:"calc(var(--tsqd-font-size) * 11)",48:"calc(var(--tsqd-font-size) * 12)",52:"calc(var(--tsqd-font-size) * 13)",56:"calc(var(--tsqd-font-size) * 14)",60:"calc(var(--tsqd-font-size) * 15)",64:"calc(var(--tsqd-font-size) * 16)",72:"calc(var(--tsqd-font-size) * 18)",80:"calc(var(--tsqd-font-size) * 20)",96:"calc(var(--tsqd-font-size) * 24)"},shadow:{xs:(e="rgb(0 0 0 / 0.1)")=>"0 1px 2px 0 rgb(0 0 0 / 0.05)",sm:(e="rgb(0 0 0 / 0.1)")=>`0 1px 3px 0 ${e}, 0 1px 2px -1px ${e}`,md:(e="rgb(0 0 0 / 0.1)")=>`0 4px 6px -1px ${e}, 0 2px 4px -2px ${e}`,lg:(e="rgb(0 0 0 / 0.1)")=>`0 10px 15px -3px ${e}, 0 4px 6px -4px ${e}`,xl:(e="rgb(0 0 0 / 0.1)")=>`0 20px 25px -5px ${e}, 0 8px 10px -6px ${e}`,"2xl":(e="rgb(0 0 0 / 0.25)")=>`0 25px 50px -12px ${e}`,inner:(e="rgb(0 0 0 / 0.05)")=>`inset 0 2px 4px 0 ${e}`,none:()=>"none"},zIndices:{hide:-1,auto:"auto",base:0,docked:10,dropdown:1e3,sticky:1100,banner:1200,overlay:1300,modal:1400,popover:1500,skipLink:1600,toast:1700,tooltip:1800}},nS=(0,l.vs)('<svg width=14 height=14 viewBox="0 0 14 14"fill=none xmlns=http://www.w3.org/2000/svg><path d="M13 13L9.00007 9M10.3333 5.66667C10.3333 8.244 8.244 10.3333 5.66667 10.3333C3.08934 10.3333 1 8.244 1 5.66667C1 3.08934 3.08934 1 5.66667 1C8.244 1 10.3333 3.08934 10.3333 5.66667Z"stroke=currentColor stroke-width=1.66667 stroke-linecap=round stroke-linejoin=round>'),nC=(0,l.vs)('<svg width=24 height=24 viewBox="0 0 24 24"fill=none xmlns=http://www.w3.org/2000/svg><path d="M9 3H15M3 6H21M19 6L18.2987 16.5193C18.1935 18.0975 18.1409 18.8867 17.8 19.485C17.4999 20.0118 17.0472 20.4353 16.5017 20.6997C15.882 21 15.0911 21 13.5093 21H10.4907C8.90891 21 8.11803 21 7.49834 20.6997C6.95276 20.4353 6.50009 20.0118 6.19998 19.485C5.85911 18.8867 5.8065 18.0975 5.70129 16.5193L5 6M10 10.5V15.5M14 10.5V15.5"stroke=currentColor stroke-width=2 stroke-linecap=round stroke-linejoin=round>'),nq=(0,l.vs)('<svg width=10 height=6 viewBox="0 0 10 6"fill=none xmlns=http://www.w3.org/2000/svg><path d="M1 1L5 5L9 1"stroke=currentColor stroke-width=1.66667 stroke-linecap=round stroke-linejoin=round>'),nE=(0,l.vs)('<svg width=12 height=12 viewBox="0 0 16 16"fill=none xmlns=http://www.w3.org/2000/svg><path d="M8 13.3333V2.66667M8 2.66667L4 6.66667M8 2.66667L12 6.66667"stroke=currentColor stroke-width=1.66667 stroke-linecap=round stroke-linejoin=round>'),nT=(0,l.vs)('<svg width=12 height=12 viewBox="0 0 16 16"fill=none xmlns=http://www.w3.org/2000/svg><path d="M8 2.66667V13.3333M8 13.3333L4 9.33333M8 13.3333L12 9.33333"stroke=currentColor stroke-width=1.66667 stroke-linecap=round stroke-linejoin=round>'),nM=(0,l.vs)('<svg viewBox="0 0 24 24"height=12 width=12 fill=none xmlns=http://www.w3.org/2000/svg><path d="M12 2v2m0 16v2M4 12H2m4.314-5.686L4.9 4.9m12.786 1.414L19.1 4.9M6.314 17.69 4.9 19.104m12.786-1.414 1.414 1.414M22 12h-2m-3 0a5 5 0 1 1-10 0 5 5 0 0 1 10 0Z"stroke=currentColor stroke-width=2 stroke-linecap=round stroke-linejoin=round>'),nF=(0,l.vs)('<svg viewBox="0 0 24 24"height=12 width=12 fill=none xmlns=http://www.w3.org/2000/svg><path d="M22 15.844a10.424 10.424 0 0 1-4.306.925c-5.779 0-10.463-4.684-10.463-10.462 0-1.536.33-2.994.925-4.307A10.464 10.464 0 0 0 2 11.538C2 17.316 6.684 22 12.462 22c4.243 0 7.896-2.526 9.538-6.156Z"stroke=currentColor stroke-width=2 stroke-linecap=round stroke-linejoin=round>'),nD=(0,l.vs)('<svg viewBox="0 0 24 24"height=12 width=12 fill=none xmlns=http://www.w3.org/2000/svg><path d="M8 21h8m-4-4v4m-5.2-4h10.4c1.68 0 2.52 0 3.162-.327a3 3 0 0 0 1.311-1.311C22 14.72 22 13.88 22 12.2V7.8c0-1.68 0-2.52-.327-3.162a3 3 0 0 0-1.311-1.311C19.72 3 18.88 3 17.2 3H6.8c-1.68 0-2.52 0-3.162.327a3 3 0 0 0-1.311 1.311C2 5.28 2 6.12 2 7.8v4.4c0 1.68 0 2.52.327 3.162a3 3 0 0 0 1.311 1.311C4.28 17 5.12 17 6.8 17Z"stroke=currentColor stroke-width=2 stroke-linecap=round stroke-linejoin=round>'),nz=(0,l.vs)('<svg stroke=currentColor fill=currentColor stroke-width=0 viewBox="0 0 24 24"height=1em width=1em xmlns=http://www.w3.org/2000/svg><path fill=none d="M0 0h24v24H0z"></path><path d="M1 9l2 2c4.97-4.97 13.03-4.97 18 0l2-2C16.93 2.93 7.08 2.93 1 9zm8 8l3 3 3-3a4.237 4.237 0 00-6 0zm-4-4l2 2a7.074 7.074 0 0110 0l2-2C15.14 9.14 8.87 9.14 5 13z">'),nL=(0,l.vs)('<svg stroke-width=0 viewBox="0 0 24 24"height=1em width=1em xmlns=http://www.w3.org/2000/svg><path fill=none d="M24 .01c0-.01 0-.01 0 0L0 0v24h24V.01zM0 0h24v24H0V0zm0 0h24v24H0V0z"></path><path d="M22.99 9C19.15 5.16 13.8 3.76 8.84 4.78l2.52 2.52c3.47-.17 6.99 1.05 9.63 3.7l2-2zm-4 4a9.793 9.793 0 00-4.49-2.56l3.53 3.53.96-.97zM2 3.05L5.07 6.1C3.6 6.82 2.22 7.78 1 9l1.99 2c1.24-1.24 2.67-2.16 4.2-2.77l2.24 2.24A9.684 9.684 0 005 13v.01L6.99 15a7.042 7.042 0 014.92-2.06L18.98 20l1.27-1.26L3.29 1.79 2 3.05zM9 17l3 3 3-3a4.237 4.237 0 00-6 0z">'),nO=(0,l.vs)('<svg width=24 height=24 viewBox="0 0 24 24"fill=none xmlns=http://www.w3.org/2000/svg><path d="M9.3951 19.3711L9.97955 20.6856C10.1533 21.0768 10.4368 21.4093 10.7958 21.6426C11.1547 21.8759 11.5737 22.0001 12.0018 22C12.4299 22.0001 12.8488 21.8759 13.2078 21.6426C13.5667 21.4093 13.8503 21.0768 14.024 20.6856L14.6084 19.3711C14.8165 18.9047 15.1664 18.5159 15.6084 18.26C16.0532 18.0034 16.5678 17.8941 17.0784 17.9478L18.5084 18.1C18.9341 18.145 19.3637 18.0656 19.7451 17.8713C20.1265 17.6771 20.4434 17.3763 20.6573 17.0056C20.8715 16.635 20.9735 16.2103 20.9511 15.7829C20.9286 15.3555 20.7825 14.9438 20.5307 14.5978L19.684 13.4344C19.3825 13.0171 19.2214 12.5148 19.224 12C19.2239 11.4866 19.3865 10.9864 19.6884 10.5711L20.5351 9.40778C20.787 9.06175 20.933 8.65007 20.9555 8.22267C20.978 7.79528 20.8759 7.37054 20.6618 7C20.4479 6.62923 20.131 6.32849 19.7496 6.13423C19.3681 5.93997 18.9386 5.86053 18.5129 5.90556L17.0829 6.05778C16.5722 6.11141 16.0577 6.00212 15.6129 5.74556C15.17 5.48825 14.82 5.09736 14.6129 4.62889L14.024 3.31444C13.8503 2.92317 13.5667 2.59072 13.2078 2.3574C12.8488 2.12408 12.4299 1.99993 12.0018 2C11.5737 1.99993 11.1547 2.12408 10.7958 2.3574C10.4368 2.59072 10.1533 2.92317 9.97955 3.31444L9.3951 4.62889C9.18803 5.09736 8.83798 5.48825 8.3951 5.74556C7.95032 6.00212 7.43577 6.11141 6.9251 6.05778L5.49066 5.90556C5.06499 5.86053 4.6354 5.93997 4.25397 6.13423C3.87255 6.32849 3.55567 6.62923 3.34177 7C3.12759 7.37054 3.02555 7.79528 3.04804 8.22267C3.07052 8.65007 3.21656 9.06175 3.46844 9.40778L4.3151 10.5711C4.61704 10.9864 4.77964 11.4866 4.77955 12C4.77964 12.5134 4.61704 13.0137 4.3151 13.4289L3.46844 14.5922C3.21656 14.9382 3.07052 15.3499 3.04804 15.7773C3.02555 16.2047 3.12759 16.6295 3.34177 17C3.55589 17.3706 3.8728 17.6712 4.25417 17.8654C4.63554 18.0596 5.06502 18.1392 5.49066 18.0944L6.92066 17.9422C7.43133 17.8886 7.94587 17.9979 8.39066 18.2544C8.83519 18.511 9.18687 18.902 9.3951 19.3711Z"stroke=currentColor stroke-width=2 stroke-linecap=round stroke-linejoin=round></path><path d="M12 15C13.6568 15 15 13.6569 15 12C15 10.3431 13.6568 9 12 9C10.3431 9 8.99998 10.3431 8.99998 12C8.99998 13.6569 10.3431 15 12 15Z"stroke=currentColor stroke-width=2 stroke-linecap=round stroke-linejoin=round>'),nA=(0,l.vs)('<svg width=24 height=24 viewBox="0 0 24 24"fill=none xmlns=http://www.w3.org/2000/svg><path d="M16 21H16.2C17.8802 21 18.7202 21 19.362 20.673C19.9265 20.3854 20.3854 19.9265 20.673 19.362C21 18.7202 21 17.8802 21 16.2V7.8C21 6.11984 21 5.27976 20.673 4.63803C20.3854 4.07354 19.9265 3.6146 19.362 3.32698C18.7202 3 17.8802 3 16.2 3H7.8C6.11984 3 5.27976 3 4.63803 3.32698C4.07354 3.6146 3.6146 4.07354 3.32698 4.63803C3 5.27976 3 6.11984 3 7.8V8M11.5 12.5L17 7M17 7H12M17 7V12M6.2 21H8.8C9.9201 21 10.4802 21 10.908 20.782C11.2843 20.5903 11.5903 20.2843 11.782 19.908C12 19.4802 12 18.9201 12 17.8V15.2C12 14.0799 12 13.5198 11.782 13.092C11.5903 12.7157 11.2843 12.4097 10.908 12.218C10.4802 12 9.92011 12 8.8 12H6.2C5.0799 12 4.51984 12 4.09202 12.218C3.71569 12.4097 3.40973 12.7157 3.21799 13.092C3 13.5198 3 14.0799 3 15.2V17.8C3 18.9201 3 19.4802 3.21799 19.908C3.40973 20.2843 3.71569 20.5903 4.09202 20.782C4.51984 21 5.07989 21 6.2 21Z"stroke=currentColor stroke-width=2 stroke-linecap=round stroke-linejoin=round>'),nI=(0,l.vs)('<svg width=24 height=24 viewBox="0 0 24 24"fill=none xmlns=http://www.w3.org/2000/svg><path class=copier d="M8 8V5.2C8 4.0799 8 3.51984 8.21799 3.09202C8.40973 2.71569 8.71569 2.40973 9.09202 2.21799C9.51984 2 10.0799 2 11.2 2H18.8C19.9201 2 20.4802 2 20.908 2.21799C21.2843 2.40973 21.5903 2.71569 21.782 3.09202C22 3.51984 22 4.0799 22 5.2V12.8C22 13.9201 22 14.4802 21.782 14.908C21.5903 15.2843 21.2843 15.5903 20.908 15.782C20.4802 16 19.9201 16 18.8 16H16M5.2 22H12.8C13.9201 22 14.4802 22 14.908 21.782C15.2843 21.5903 15.5903 21.2843 15.782 20.908C16 20.4802 16 19.9201 16 18.8V11.2C16 10.0799 16 9.51984 15.782 9.09202C15.5903 8.71569 15.2843 8.40973 14.908 8.21799C14.4802 8 13.9201 8 12.8 8H5.2C4.0799 8 3.51984 8 3.09202 8.21799C2.71569 8.40973 2.40973 8.71569 2.21799 9.09202C2 9.51984 2 10.0799 2 11.2V18.8C2 19.9201 2 20.4802 2.21799 20.908C2.40973 21.2843 2.71569 21.5903 3.09202 21.782C3.51984 22 4.07989 22 5.2 22Z"stroke-width=2 stroke-linecap=round stroke-linejoin=round stroke=currentColor>'),nK=(0,l.vs)('<svg width=24 height=24 viewBox="0 0 24 24"fill=none xmlns=http://www.w3.org/2000/svg><path d="M2.5 21.4998L8.04927 19.3655C8.40421 19.229 8.58168 19.1607 8.74772 19.0716C8.8952 18.9924 9.0358 18.901 9.16804 18.7984C9.31692 18.6829 9.45137 18.5484 9.72028 18.2795L21 6.99982C22.1046 5.89525 22.1046 4.10438 21 2.99981C19.8955 1.89525 18.1046 1.89524 17 2.99981L5.72028 14.2795C5.45138 14.5484 5.31692 14.6829 5.20139 14.8318C5.09877 14.964 5.0074 15.1046 4.92823 15.2521C4.83911 15.4181 4.77085 15.5956 4.63433 15.9506L2.5 21.4998ZM2.5 21.4998L4.55812 16.1488C4.7054 15.7659 4.77903 15.5744 4.90534 15.4867C5.01572 15.4101 5.1523 15.3811 5.2843 15.4063C5.43533 15.4351 5.58038 15.5802 5.87048 15.8703L8.12957 18.1294C8.41967 18.4195 8.56472 18.5645 8.59356 18.7155C8.61877 18.8475 8.58979 18.9841 8.51314 19.0945C8.42545 19.2208 8.23399 19.2944 7.85107 19.4417L2.5 21.4998Z"stroke=currentColor stroke-width=2 stroke-linecap=round stroke-linejoin=round>'),nP=(0,l.vs)('<svg width=24 height=24 viewBox="0 0 24 24"fill=none xmlns=http://www.w3.org/2000/svg><path d="M7.5 12L10.5 15L16.5 9M7.8 21H16.2C17.8802 21 18.7202 21 19.362 20.673C19.9265 20.3854 20.3854 19.9265 20.673 19.362C21 18.7202 21 17.8802 21 16.2V7.8C21 6.11984 21 5.27976 20.673 4.63803C20.3854 4.07354 19.9265 3.6146 19.362 3.32698C18.7202 3 17.8802 3 16.2 3H7.8C6.11984 3 5.27976 3 4.63803 3.32698C4.07354 3.6146 3.6146 4.07354 3.32698 4.63803C3 5.27976 3 6.11984 3 7.8V16.2C3 17.8802 3 18.7202 3.32698 19.362C3.6146 19.9265 4.07354 20.3854 4.63803 20.673C5.27976 21 6.11984 21 7.8 21Z"stroke-width=2 stroke-linecap=round stroke-linejoin=round>'),nB=(0,l.vs)('<svg width=24 height=24 viewBox="0 0 24 24"fill=none xmlns=http://www.w3.org/2000/svg><path d="M9 9L15 15M15 9L9 15M7.8 21H16.2C17.8802 21 18.7202 21 19.362 20.673C19.9265 20.3854 20.3854 19.9265 20.673 19.362C21 18.7202 21 17.8802 21 16.2V7.8C21 6.11984 21 5.27976 20.673 4.63803C20.3854 4.07354 19.9265 3.6146 19.362 3.32698C18.7202 3 17.8802 3 16.2 3H7.8C6.11984 3 5.27976 3 4.63803 3.32698C4.07354 3.6146 3.6146 4.07354 3.32698 4.63803C3 5.27976 3 6.11984 3 7.8V16.2C3 17.8802 3 18.7202 3.32698 19.362C3.6146 19.9265 4.07354 20.3854 4.63803 20.673C5.27976 21 6.11984 21 7.8 21Z"stroke=#F04438 stroke-width=2 stroke-linecap=round stroke-linejoin=round>'),nR=(0,l.vs)('<svg width=24 height=24 viewBox="0 0 24 24"fill=none stroke=currentColor stroke-width=2 xmlns=http://www.w3.org/2000/svg><rect class=list width=20 height=20 y=2 x=2 rx=2></rect><line class=list-item y1=7 y2=7 x1=6 x2=18></line><line class=list-item y2=12 y1=12 x1=6 x2=18></line><line class=list-item y1=17 y2=17 x1=6 x2=18>'),nH=(0,l.vs)('<svg viewBox="0 0 24 24"height=20 width=20 fill=none xmlns=http://www.w3.org/2000/svg><path d="M3 7.8c0-1.68 0-2.52.327-3.162a3 3 0 0 1 1.311-1.311C5.28 3 6.12 3 7.8 3h8.4c1.68 0 2.52 0 3.162.327a3 3 0 0 1 1.311 1.311C21 5.28 21 6.12 21 7.8v8.4c0 1.68 0 2.52-.327 3.162a3 3 0 0 1-1.311 1.311C18.72 21 17.88 21 16.2 21H7.8c-1.68 0-2.52 0-3.162-.327a3 3 0 0 1-1.311-1.311C3 18.72 3 17.88 3 16.2V7.8Z"stroke-width=2 stroke-linecap=round stroke-linejoin=round>'),nG=(0,l.vs)('<svg width=14 height=14 viewBox="0 0 24 24"fill=none xmlns=http://www.w3.org/2000/svg><path d="M7.5 12L10.5 15L16.5 9M22 12C22 17.5228 17.5228 22 12 22C6.47715 22 2 17.5228 2 12C2 6.47715 6.47715 2 12 2C17.5228 2 22 6.47715 22 12Z"stroke=currentColor stroke-width=2 stroke-linecap=round stroke-linejoin=round>'),nU=(0,l.vs)('<svg width=14 height=14 viewBox="0 0 24 24"fill=none xmlns=http://www.w3.org/2000/svg><path d="M12 2V6M12 18V22M6 12H2M22 12H18M19.0784 19.0784L16.25 16.25M19.0784 4.99994L16.25 7.82837M4.92157 19.0784L7.75 16.25M4.92157 4.99994L7.75 7.82837"stroke=currentColor stroke-width=2 stroke-linecap=round stroke-linejoin=round></path><animateTransform attributeName=transform attributeType=XML type=rotate from=0 to=360 dur=2s repeatCount=indefinite>'),nY=(0,l.vs)('<svg width=14 height=14 viewBox="0 0 24 24"fill=none xmlns=http://www.w3.org/2000/svg><path d="M15 9L9 15M9 9L15 15M22 12C22 17.5228 17.5228 22 12 22C6.47715 22 2 17.5228 2 12C2 6.47715 6.47715 2 12 2C17.5228 2 22 6.47715 22 12Z"stroke=currentColor stroke-width=2 stroke-linecap=round stroke-linejoin=round>'),nV=(0,l.vs)('<svg width=14 height=14 viewBox="0 0 24 24"fill=none xmlns=http://www.w3.org/2000/svg><path d="M9.5 15V9M14.5 15V9M22 12C22 17.5228 17.5228 22 12 22C6.47715 22 2 17.5228 2 12C2 6.47715 6.47715 2 12 2C17.5228 2 22 6.47715 22 12Z"stroke=currentColor stroke-width=2 stroke-linecap=round stroke-linejoin=round>'),nN=(0,l.vs)('<svg version=1.0 viewBox="0 0 633 633"><linearGradient x1=-666.45 x2=-666.45 y1=163.28 y2=163.99 gradientTransform="matrix(633 0 0 633 422177 -103358)"gradientUnits=userSpaceOnUse><stop stop-color=#6BDAFF offset=0></stop><stop stop-color=#F9FFB5 offset=.32></stop><stop stop-color=#FFA770 offset=.71></stop><stop stop-color=#FF7373 offset=1></stop></linearGradient><circle cx=316.5 cy=316.5 r=316.5></circle><defs><filter x=-137.5 y=412 width=454 height=396.9 filterUnits=userSpaceOnUse><feColorMatrix values="1 0 0 0 0  0 1 0 0 0  0 0 1 0 0  0 0 0 1 0"></feColorMatrix></filter></defs><mask x=-137.5 y=412 width=454 height=396.9 maskUnits=userSpaceOnUse><g><circle cx=316.5 cy=316.5 r=316.5 fill=#fff></circle></g></mask><g><ellipse cx=89.5 cy=610.5 rx=214.5 ry=186 fill=#015064 stroke=#00CFE2 stroke-width=25></ellipse></g><defs><filter x=316.5 y=412 width=454 height=396.9 filterUnits=userSpaceOnUse><feColorMatrix values="1 0 0 0 0  0 1 0 0 0  0 0 1 0 0  0 0 0 1 0"></feColorMatrix></filter></defs><mask x=316.5 y=412 width=454 height=396.9 maskUnits=userSpaceOnUse><g><circle cx=316.5 cy=316.5 r=316.5 fill=#fff></circle></g></mask><g><ellipse cx=543.5 cy=610.5 rx=214.5 ry=186 fill=#015064 stroke=#00CFE2 stroke-width=25></ellipse></g><defs><filter x=-137.5 y=450 width=454 height=396.9 filterUnits=userSpaceOnUse><feColorMatrix values="1 0 0 0 0  0 1 0 0 0  0 0 1 0 0  0 0 0 1 0"></feColorMatrix></filter></defs><mask x=-137.5 y=450 width=454 height=396.9 maskUnits=userSpaceOnUse><g><circle cx=316.5 cy=316.5 r=316.5 fill=#fff></circle></g></mask><g><ellipse cx=89.5 cy=648.5 rx=214.5 ry=186 fill=#015064 stroke=#00A8B8 stroke-width=25></ellipse></g><defs><filter x=316.5 y=450 width=454 height=396.9 filterUnits=userSpaceOnUse><feColorMatrix values="1 0 0 0 0  0 1 0 0 0  0 0 1 0 0  0 0 0 1 0"></feColorMatrix></filter></defs><mask x=316.5 y=450 width=454 height=396.9 maskUnits=userSpaceOnUse><g><circle cx=316.5 cy=316.5 r=316.5 fill=#fff></circle></g></mask><g><ellipse cx=543.5 cy=648.5 rx=214.5 ry=186 fill=#015064 stroke=#00A8B8 stroke-width=25></ellipse></g><defs><filter x=-137.5 y=486 width=454 height=396.9 filterUnits=userSpaceOnUse><feColorMatrix values="1 0 0 0 0  0 1 0 0 0  0 0 1 0 0  0 0 0 1 0"></feColorMatrix></filter></defs><mask x=-137.5 y=486 width=454 height=396.9 maskUnits=userSpaceOnUse><g><circle cx=316.5 cy=316.5 r=316.5 fill=#fff></circle></g></mask><g><ellipse cx=89.5 cy=684.5 rx=214.5 ry=186 fill=#015064 stroke=#007782 stroke-width=25></ellipse></g><defs><filter x=316.5 y=486 width=454 height=396.9 filterUnits=userSpaceOnUse><feColorMatrix values="1 0 0 0 0  0 1 0 0 0  0 0 1 0 0  0 0 0 1 0"></feColorMatrix></filter></defs><mask x=316.5 y=486 width=454 height=396.9 maskUnits=userSpaceOnUse><g><circle cx=316.5 cy=316.5 r=316.5 fill=#fff></circle></g></mask><g><ellipse cx=543.5 cy=684.5 rx=214.5 ry=186 fill=#015064 stroke=#007782 stroke-width=25></ellipse></g><defs><filter x=272.2 y=308 width=176.9 height=129.3 filterUnits=userSpaceOnUse><feColorMatrix values="1 0 0 0 0  0 1 0 0 0  0 0 1 0 0  0 0 0 1 0"></feColorMatrix></filter></defs><mask x=272.2 y=308 width=176.9 height=129.3 maskUnits=userSpaceOnUse><g><circle cx=316.5 cy=316.5 r=316.5 fill=#fff></circle></g></mask><g><line x1=436 x2=431 y1=403.2 y2=431.8 fill=none stroke=#000 stroke-linecap=round stroke-linejoin=bevel stroke-width=11></line><line x1=291 x2=280 y1=341.5 y2=403.5 fill=none stroke=#000 stroke-linecap=round stroke-linejoin=bevel stroke-width=11></line><line x1=332.9 x2=328.6 y1=384.1 y2=411.2 fill=none stroke=#000 stroke-linecap=round stroke-linejoin=bevel stroke-width=11></line><linearGradient x1=-670.75 x2=-671.59 y1=164.4 y2=164.49 gradientTransform="matrix(-184.16 -32.472 -11.461 64.997 -121359 -32126)"gradientUnits=userSpaceOnUse><stop stop-color=#EE2700 offset=0></stop><stop stop-color=#FF008E offset=1></stop></linearGradient><path d="m344.1 363 97.7 17.2c5.8 2.1 8.2 6.1 7.1 12.1s-4.7 9.2-11 9.9l-106-18.7-57.5-59.2c-3.2-4.8-2.9-9.1 0.8-12.8s8.3-4.4 13.7-2.1l55.2 53.6z"clip-rule=evenodd fill-rule=evenodd></path><line x1=428.2 x2=429.1 y1=384.5 y2=378 fill=none stroke=#fff stroke-linecap=round stroke-linejoin=bevel stroke-width=7></line><line x1=395.2 x2=396.1 y1=379.5 y2=373 fill=none stroke=#fff stroke-linecap=round stroke-linejoin=bevel stroke-width=7></line><line x1=362.2 x2=363.1 y1=373.5 y2=367.4 fill=none stroke=#fff stroke-linecap=round stroke-linejoin=bevel stroke-width=7></line><line x1=324.2 x2=328.4 y1=351.3 y2=347.4 fill=none stroke=#fff stroke-linecap=round stroke-linejoin=bevel stroke-width=7></line><line x1=303.2 x2=307.4 y1=331.3 y2=327.4 fill=none stroke=#fff stroke-linecap=round stroke-linejoin=bevel stroke-width=7></line></g><defs><filter x=73.2 y=113.8 width=280.6 height=317.4 filterUnits=userSpaceOnUse><feColorMatrix values="1 0 0 0 0  0 1 0 0 0  0 0 1 0 0  0 0 0 1 0"></feColorMatrix></filter></defs><mask x=73.2 y=113.8 width=280.6 height=317.4 maskUnits=userSpaceOnUse><g><circle cx=316.5 cy=316.5 r=316.5 fill=#fff></circle></g></mask><g><linearGradient x1=-672.16 x2=-672.16 y1=165.03 y2=166.03 gradientTransform="matrix(-100.18 48.861 97.976 200.88 -83342 -93.059)"gradientUnits=userSpaceOnUse><stop stop-color=#A17500 offset=0></stop><stop stop-color=#5D2100 offset=1></stop></linearGradient><path d="m192.3 203c8.1 37.3 14 73.6 17.8 109.1 3.8 35.4 2.8 75.1-3 119.2l61.2-16.7c-15.6-59-25.2-97.9-28.6-116.6s-10.8-51.9-22.1-99.6l-25.3 4.6"clip-rule=evenodd fill-rule=evenodd></path><g stroke=#2F8A00><linearGradient x1=-660.23 x2=-660.23 y1=166.72 y2=167.72 gradientTransform="matrix(92.683 4.8573 -2.0259 38.657 61680 -3088.6)"gradientUnits=userSpaceOnUse><stop stop-color=#2F8A00 offset=0></stop><stop stop-color=#90FF57 offset=1></stop></linearGradient><path d="m195 183.9s-12.6-22.1-36.5-29.9c-15.9-5.2-34.4-1.5-55.5 11.1 15.9 14.3 29.5 22.6 40.7 24.9 16.8 3.6 51.3-6.1 51.3-6.1z"clip-rule=evenodd fill-rule=evenodd stroke-width=13></path><linearGradient x1=-661.36 x2=-661.36 y1=164.18 y2=165.18 gradientTransform="matrix(110 5.7648 -6.3599 121.35 73933 -15933)"gradientUnits=userSpaceOnUse><stop stop-color=#2F8A00 offset=0></stop><stop stop-color=#90FF57 offset=1></stop></linearGradient><path d="m194.9 184.5s-47.5-8.5-83.2 15.7c-23.8 16.2-34.3 49.3-31.6 99.4 30.3-27.8 52.1-48.5 65.2-61.9 19.8-20.2 49.6-53.2 49.6-53.2z"clip-rule=evenodd fill-rule=evenodd stroke-width=13></path><linearGradient x1=-656.79 x2=-656.79 y1=165.15 y2=166.15 gradientTransform="matrix(62.954 3.2993 -3.5023 66.828 42156 -8754.1)"gradientUnits=userSpaceOnUse><stop stop-color=#2F8A00 offset=0></stop><stop stop-color=#90FF57 offset=1></stop></linearGradient><path d="m195 183.9c-0.8-21.9 6-38 20.6-48.2s29.8-15.4 45.5-15.3c-6.1 21.4-14.5 35.8-25.2 43.4s-24.4 14.2-40.9 20.1z"clip-rule=evenodd fill-rule=evenodd stroke-width=13></path><linearGradient x1=-663.07 x2=-663.07 y1=165.44 y2=166.44 gradientTransform="matrix(152.47 7.9907 -3.0936 59.029 101884 -4318.7)"gradientUnits=userSpaceOnUse><stop stop-color=#2F8A00 offset=0></stop><stop stop-color=#90FF57 offset=1></stop></linearGradient><path d="m194.9 184.5c31.9-30 64.1-39.7 96.7-29s50.8 30.4 54.6 59.1c-35.2-5.5-60.4-9.6-75.8-12.1-15.3-2.6-40.5-8.6-75.5-18z"clip-rule=evenodd fill-rule=evenodd stroke-width=13></path><linearGradient x1=-662.57 x2=-662.57 y1=164.44 y2=165.44 gradientTransform="matrix(136.46 7.1517 -5.2163 99.533 91536 -11442)"gradientUnits=userSpaceOnUse><stop stop-color=#2F8A00 offset=0></stop><stop stop-color=#90FF57 offset=1></stop></linearGradient><path d="m194.9 184.5c35.8-7.6 65.6-0.2 89.2 22s37.7 49 42.3 80.3c-39.8-9.7-68.3-23.8-85.5-42.4s-32.5-38.5-46-59.9z"clip-rule=evenodd fill-rule=evenodd stroke-width=13></path><linearGradient x1=-656.43 x2=-656.43 y1=163.86 y2=164.86 gradientTransform="matrix(60.866 3.1899 -8.7773 167.48 41560 -25168)"gradientUnits=userSpaceOnUse><stop stop-color=#2F8A00 offset=0></stop><stop stop-color=#90FF57 offset=1></stop></linearGradient><path d="m194.9 184.5c-33.6 13.8-53.6 35.7-60.1 65.6s-3.6 63.1 8.7 99.6c27.4-40.3 43.2-69.6 47.4-88s5.6-44.1 4-77.2z"clip-rule=evenodd fill-rule=evenodd stroke-width=13></path><path d="m196.5 182.3c-14.8 21.6-25.1 41.4-30.8 59.4s-9.5 33-11.1 45.1"fill=none stroke-linecap=round stroke-width=8></path><path d="m194.9 185.7c-24.4 1.7-43.8 9-58.1 21.8s-24.7 25.4-31.3 37.8"fill=none stroke-linecap=round stroke-width=8></path><path d="m204.5 176.4c29.7-6.7 52-8.4 67-5.1s26.9 8.6 35.8 15.9"fill=none stroke-linecap=round stroke-width=8></path><path d="m196.5 181.4c20.3 9.9 38.2 20.5 53.9 31.9s27.4 22.1 35.1 32"fill=none stroke-linecap=round stroke-width=8></path></g></g><defs><filter x=50.5 y=399 width=532 height=633 filterUnits=userSpaceOnUse><feColorMatrix values="1 0 0 0 0  0 1 0 0 0  0 0 1 0 0  0 0 0 1 0"></feColorMatrix></filter></defs><mask x=50.5 y=399 width=532 height=633 maskUnits=userSpaceOnUse><g><circle cx=316.5 cy=316.5 r=316.5 fill=#fff></circle></g></mask><g><linearGradient x1=-666.06 x2=-666.23 y1=163.36 y2=163.75 gradientTransform="matrix(532 0 0 633 354760 -102959)"gradientUnits=userSpaceOnUse><stop stop-color=#FFF400 offset=0></stop><stop stop-color=#3C8700 offset=1></stop></linearGradient><ellipse cx=316.5 cy=715.5 rx=266 ry=316.5></ellipse></g><defs><filter x=391 y=-24 width=288 height=283 filterUnits=userSpaceOnUse><feColorMatrix values="1 0 0 0 0  0 1 0 0 0  0 0 1 0 0  0 0 0 1 0"></feColorMatrix></filter></defs><mask x=391 y=-24 width=288 height=283 maskUnits=userSpaceOnUse><g><circle cx=316.5 cy=316.5 r=316.5 fill=#fff></circle></g></mask><g><linearGradient x1=-664.56 x2=-664.56 y1=163.79 y2=164.79 gradientTransform="matrix(227 0 0 227 151421 -37204)"gradientUnits=userSpaceOnUse><stop stop-color=#FFDF00 offset=0></stop><stop stop-color=#FF9D00 offset=1></stop></linearGradient><circle cx=565.5 cy=89.5 r=113.5></circle><linearGradient x1=-644.5 x2=-645.77 y1=342 y2=342 gradientTransform="matrix(30 0 0 1 19770 -253)"gradientUnits=userSpaceOnUse><stop stop-color=#FFA400 offset=0></stop><stop stop-color=#FF5E00 offset=1></stop></linearGradient><line x1=427 x2=397 y1=89 y2=89 fill=none stroke-linecap=round stroke-linejoin=bevel stroke-width=12></line><linearGradient x1=-641.56 x2=-642.83 y1=196.02 y2=196.07 gradientTransform="matrix(26.5 0 0 5.5 17439 -1025.5)"gradientUnits=userSpaceOnUse><stop stop-color=#FFA400 offset=0></stop><stop stop-color=#FF5E00 offset=1></stop></linearGradient><line x1=430.5 x2=404 y1=55.5 y2=50 fill=none stroke-linecap=round stroke-linejoin=bevel stroke-width=12></line><linearGradient x1=-643.73 x2=-645 y1=185.83 y2=185.9 gradientTransform="matrix(29 0 0 8 19107 -1361)"gradientUnits=userSpaceOnUse><stop stop-color=#FFA400 offset=0></stop><stop stop-color=#FF5E00 offset=1></stop></linearGradient><line x1=431 x2=402 y1=122 y2=130 fill=none stroke-linecap=round stroke-linejoin=bevel stroke-width=12></line><linearGradient x1=-638.94 x2=-640.22 y1=177.09 y2=177.39 gradientTransform="matrix(24 0 0 13 15783 -2145)"gradientUnits=userSpaceOnUse><stop stop-color=#FFA400 offset=0></stop><stop stop-color=#FF5E00 offset=1></stop></linearGradient><line x1=442 x2=418 y1=153 y2=166 fill=none stroke-linecap=round stroke-linejoin=bevel stroke-width=12></line><linearGradient x1=-633.42 x2=-634.7 y1=172.41 y2=173.31 gradientTransform="matrix(20 0 0 19 13137 -3096)"gradientUnits=userSpaceOnUse><stop stop-color=#FFA400 offset=0></stop><stop stop-color=#FF5E00 offset=1></stop></linearGradient><line x1=464 x2=444 y1=180 y2=199 fill=none stroke-linecap=round stroke-linejoin=bevel stroke-width=12></line><linearGradient x1=-619.05 x2=-619.52 y1=170.82 y2=171.82 gradientTransform="matrix(13.83 0 0 22.85 9050 -3703.4)"gradientUnits=userSpaceOnUse><stop stop-color=#FFA400 offset=0></stop><stop stop-color=#FF5E00 offset=1></stop></linearGradient><line x1=491.4 x2=477.5 y1=203 y2=225.9 fill=none stroke-linecap=round stroke-linejoin=bevel stroke-width=12></line><linearGradient x1=-578.5 x2=-578.63 y1=170.31 y2=171.31 gradientTransform="matrix(7.5 0 0 24.5 4860 -3953)"gradientUnits=userSpaceOnUse><stop stop-color=#FFA400 offset=0></stop><stop stop-color=#FF5E00 offset=1></stop></linearGradient><line x1=524.5 x2=517 y1=219.5 y2=244 fill=none stroke-linecap=round stroke-linejoin=bevel stroke-width=12></line><linearGradient x1=666.5 x2=666.5 y1=170.31 y2=171.31 gradientTransform="matrix(.5 0 0 24.5 231.5 -3944)"gradientUnits=userSpaceOnUse><stop stop-color=#FFA400 offset=0></stop><stop stop-color=#FF5E00 offset=1></stop></linearGradient><line x1=564.5 x2=565 y1=228.5 y2=253 fill=none stroke-linecap=round stroke-linejoin=bevel stroke-width=12>');function nj(){return nS()}function nQ(){return nC()}function nW(){return nq()}function n_(){return nE()}function nZ(){return nT()}function nX(){var e;return(e=nT()).style.setProperty("transform","rotate(90deg)"),e}function nJ(){var e;return(e=nT()).style.setProperty("transform","rotate(-90deg)"),e}function n0(){return nM()}function n1(){return nF()}function n2(){return nD()}function n5(){return nz()}function n3(){return nL()}function n4(){return nO()}function n6(){return nA()}function n7(){return nI()}function n9(){return nK()}function n8(e){var t,r;return r=(t=nP()).firstChild,(0,l.gb)(()=>(0,l.Bq)(r,"stroke","dark"===e.theme?"#12B76A":"#027A48")),t}function ie(){return nB()}function it(){return nR()}function ir(e){return[(0,l.a0)(l.wv,{get when(){return e.checked},get children(){var t=nP(),r=t.firstChild;return(0,l.gb)(()=>(0,l.Bq)(r,"stroke","dark"===e.theme?"#9B8AFB":"#6938EF")),t}}),(0,l.a0)(l.wv,{get when(){return!e.checked},get children(){var n=nH(),i=n.firstChild;return(0,l.gb)(()=>(0,l.Bq)(i,"stroke","dark"===e.theme?"#9B8AFB":"#6938EF")),n}})]}function ii(){return nG()}function io(){return nU()}function il(){return nY()}function ia(){return nV()}function is(){var e,t,r,n,i,o,a,s,d,u,c,g,f,p,h,v,y,b,m,w,x,k,$,S,C,q,E,T,M,F,D,z,L,O,A,I,K,P,B,R,H,G,U,Y,V,N,j,Q,W,_,Z,X,J,ee,et,er,en,ei,eo,el,ea,es,ed,eu,ec,eg,ef,ep,eh,ev,ey,eb,em,ew,ex,ek,e$,eS,eC,eq,eE,eT,eM,eF,eD,ez,eL,eO,eA;let eI=(0,l.Ds)();return i=(n=(r=(t=(e=nN()).firstChild).nextSibling).nextSibling).firstChild,a=(o=n.nextSibling).firstChild,u=(d=(s=o.nextSibling).nextSibling).firstChild,g=(c=d.nextSibling).firstChild,h=(p=(f=c.nextSibling).nextSibling).firstChild,y=(v=p.nextSibling).firstChild,w=(m=(b=v.nextSibling).nextSibling).firstChild,k=(x=m.nextSibling).firstChild,C=(S=($=x.nextSibling).nextSibling).firstChild,E=(q=S.nextSibling).firstChild,F=(M=(T=q.nextSibling).nextSibling).firstChild,z=(D=M.nextSibling).firstChild,A=(O=(L=D.nextSibling).nextSibling).firstChild,K=(I=O.nextSibling).firstChild,R=(B=(P=I.nextSibling).firstChild.nextSibling.nextSibling.nextSibling).nextSibling,G=(H=P.nextSibling).firstChild,Y=(U=H.nextSibling).firstChild,eo=(ei=(en=(er=(et=(ee=(J=(X=(Z=(_=(W=(Q=(j=(N=(V=U.nextSibling).firstChild).nextSibling).nextSibling.firstChild).nextSibling).nextSibling).nextSibling).nextSibling).nextSibling).nextSibling).nextSibling).nextSibling).nextSibling).nextSibling).nextSibling,ea=(el=V.nextSibling).firstChild,ed=(es=el.nextSibling).firstChild,eg=(ec=(eu=es.nextSibling).firstChild).nextSibling,ep=(ef=eu.nextSibling).firstChild,ev=(eh=ef.nextSibling).firstChild,eA=(eO=(eL=(ez=(eD=(eF=(eM=(eT=(eE=(eq=(eC=(eS=(e$=(ek=(ex=(ew=(em=(eb=(ey=eh.nextSibling).firstChild).nextSibling).nextSibling).nextSibling).nextSibling).nextSibling).nextSibling).nextSibling).nextSibling).nextSibling).nextSibling).nextSibling).nextSibling).nextSibling).nextSibling).nextSibling).nextSibling).nextSibling,(0,l.Bq)(t,"id",`a-${eI}`),(0,l.Bq)(r,"fill",`url(#a-${eI})`),(0,l.Bq)(i,"id",`am-${eI}`),(0,l.Bq)(o,"id",`b-${eI}`),(0,l.Bq)(a,"filter",`url(#am-${eI})`),(0,l.Bq)(s,"mask",`url(#b-${eI})`),(0,l.Bq)(u,"id",`ah-${eI}`),(0,l.Bq)(c,"id",`k-${eI}`),(0,l.Bq)(g,"filter",`url(#ah-${eI})`),(0,l.Bq)(f,"mask",`url(#k-${eI})`),(0,l.Bq)(h,"id",`ae-${eI}`),(0,l.Bq)(v,"id",`j-${eI}`),(0,l.Bq)(y,"filter",`url(#ae-${eI})`),(0,l.Bq)(b,"mask",`url(#j-${eI})`),(0,l.Bq)(w,"id",`ai-${eI}`),(0,l.Bq)(x,"id",`i-${eI}`),(0,l.Bq)(k,"filter",`url(#ai-${eI})`),(0,l.Bq)($,"mask",`url(#i-${eI})`),(0,l.Bq)(C,"id",`aj-${eI}`),(0,l.Bq)(q,"id",`h-${eI}`),(0,l.Bq)(E,"filter",`url(#aj-${eI})`),(0,l.Bq)(T,"mask",`url(#h-${eI})`),(0,l.Bq)(F,"id",`ag-${eI}`),(0,l.Bq)(D,"id",`g-${eI}`),(0,l.Bq)(z,"filter",`url(#ag-${eI})`),(0,l.Bq)(L,"mask",`url(#g-${eI})`),(0,l.Bq)(A,"id",`af-${eI}`),(0,l.Bq)(I,"id",`f-${eI}`),(0,l.Bq)(K,"filter",`url(#af-${eI})`),(0,l.Bq)(P,"mask",`url(#f-${eI})`),(0,l.Bq)(B,"id",`m-${eI}`),(0,l.Bq)(R,"fill",`url(#m-${eI})`),(0,l.Bq)(G,"id",`ak-${eI}`),(0,l.Bq)(U,"id",`e-${eI}`),(0,l.Bq)(Y,"filter",`url(#ak-${eI})`),(0,l.Bq)(V,"mask",`url(#e-${eI})`),(0,l.Bq)(N,"id",`n-${eI}`),(0,l.Bq)(j,"fill",`url(#n-${eI})`),(0,l.Bq)(Q,"id",`r-${eI}`),(0,l.Bq)(W,"fill",`url(#r-${eI})`),(0,l.Bq)(_,"id",`s-${eI}`),(0,l.Bq)(Z,"fill",`url(#s-${eI})`),(0,l.Bq)(X,"id",`q-${eI}`),(0,l.Bq)(J,"fill",`url(#q-${eI})`),(0,l.Bq)(ee,"id",`p-${eI}`),(0,l.Bq)(et,"fill",`url(#p-${eI})`),(0,l.Bq)(er,"id",`o-${eI}`),(0,l.Bq)(en,"fill",`url(#o-${eI})`),(0,l.Bq)(ei,"id",`l-${eI}`),(0,l.Bq)(eo,"fill",`url(#l-${eI})`),(0,l.Bq)(ea,"id",`al-${eI}`),(0,l.Bq)(es,"id",`d-${eI}`),(0,l.Bq)(ed,"filter",`url(#al-${eI})`),(0,l.Bq)(eu,"mask",`url(#d-${eI})`),(0,l.Bq)(ec,"id",`u-${eI}`),(0,l.Bq)(eg,"fill",`url(#u-${eI})`),(0,l.Bq)(ep,"id",`ad-${eI}`),(0,l.Bq)(eh,"id",`c-${eI}`),(0,l.Bq)(ev,"filter",`url(#ad-${eI})`),(0,l.Bq)(ey,"mask",`url(#c-${eI})`),(0,l.Bq)(eb,"id",`t-${eI}`),(0,l.Bq)(em,"fill",`url(#t-${eI})`),(0,l.Bq)(ew,"id",`v-${eI}`),(0,l.Bq)(ex,"stroke",`url(#v-${eI})`),(0,l.Bq)(ek,"id",`aa-${eI}`),(0,l.Bq)(e$,"stroke",`url(#aa-${eI})`),(0,l.Bq)(eS,"id",`w-${eI}`),(0,l.Bq)(eC,"stroke",`url(#w-${eI})`),(0,l.Bq)(eq,"id",`ac-${eI}`),(0,l.Bq)(eE,"stroke",`url(#ac-${eI})`),(0,l.Bq)(eT,"id",`ab-${eI}`),(0,l.Bq)(eM,"stroke",`url(#ab-${eI})`),(0,l.Bq)(eF,"id",`y-${eI}`),(0,l.Bq)(eD,"stroke",`url(#y-${eI})`),(0,l.Bq)(ez,"id",`x-${eI}`),(0,l.Bq)(eL,"stroke",`url(#x-${eI})`),(0,l.Bq)(eO,"id",`z-${eI}`),(0,l.Bq)(eA,"stroke",`url(#z-${eI})`),e}var id=(0,l.vs)('<span><svg width=16 height=16 viewBox="0 0 16 16"fill=none xmlns=http://www.w3.org/2000/svg><path d="M6 12L10 8L6 4"stroke-width=2 stroke-linecap=round stroke-linejoin=round>'),iu=(0,l.vs)('<button title="Copy object to clipboard">'),ic=(0,l.vs)('<button title="Remove all items"aria-label="Remove all items">'),ig=(0,l.vs)('<button title="Delete item"aria-label="Delete item">'),ip=(0,l.vs)('<button title="Toggle value"aria-label="Toggle value">'),ih=(0,l.vs)('<button title="Bulk Edit Data"aria-label="Bulk Edit Data">'),iv=(0,l.vs)("<div>"),iy=(0,l.vs)("<div><button> <span></span> <span> "),ib=(0,l.vs)("<input>"),im=(0,l.vs)("<span>"),iw=(0,l.vs)("<div><label>:"),ix=(0,l.vs)("<div><div><button> [<!>...<!>]"),ik=e=>{var t;let r=q(),n=x().shadowDOMTarget?R.bind({target:x().shadowDOMTarget}):R,i=(0,l.To)(()=>"dark"===r()?iD(n):iF(n));return t=id(),(0,l.gb)(()=>(0,l.s7)(t,H(i().expander,n`
          transform: rotate(${90*!!e.expanded}deg);
        `,e.expanded&&n`
            & svg {
              top: -1px;
            }
          `))),t},i$=e=>{var t;let r=q(),n=x().shadowDOMTarget?R.bind({target:x().shadowDOMTarget}):R,i=(0,l.To)(()=>"dark"===r()?iD(n):iF(n)),[o,a]=(0,l.n5)("NoCopy");return t=iu(),(0,l.q2)(t,"click","NoCopy"===o()?()=>{navigator.clipboard.writeText((0,l.As)(e.value)).then(()=>{a("SuccessCopy"),setTimeout(()=>{a("NoCopy")},1500)},e=>{a("ErrorCopy"),setTimeout(()=>{a("NoCopy")},1500)})}:void 0,!0),(0,l.Yr)(t,(0,l.a0)(l.dO,{get children(){return[(0,l.a0)(l.YG,{get when(){return"NoCopy"===o()},get children(){return(0,l.a0)(n7,{})}}),(0,l.a0)(l.YG,{get when(){return"SuccessCopy"===o()},get children(){return(0,l.a0)(n8,{get theme(){return r()}})}}),(0,l.a0)(l.YG,{get when(){return"ErrorCopy"===o()},get children(){return(0,l.a0)(ie,{})}})]}})),(0,l.gb)(e=>{var r=i().actionButton,n=`${"NoCopy"===o()?"Copy object to clipboard":"SuccessCopy"===o()?"Object copied to clipboard":"Error copying object to clipboard"}`;return r!==e.e&&(0,l.s7)(t,e.e=r),n!==e.t&&(0,l.Bq)(t,"aria-label",e.t=n),e},{e:void 0,t:void 0}),t},iS=e=>{var t;let r=q(),n=x().shadowDOMTarget?R.bind({target:x().shadowDOMTarget}):R,i=(0,l.To)(()=>"dark"===r()?iD(n):iF(n)),o=x().client;return(t=ic()).$$click=()=>{let t=e.activeQuery.state.data,r=(0,l.zt)(t,e.dataPath,[]);o.setQueryData(e.activeQuery.queryKey,r)},(0,l.Yr)(t,(0,l.a0)(it,{})),(0,l.gb)(()=>(0,l.s7)(t,i().actionButton)),t},iC=e=>{var t;let r=q(),n=x().shadowDOMTarget?R.bind({target:x().shadowDOMTarget}):R,i=(0,l.To)(()=>"dark"===r()?iD(n):iF(n)),o=x().client;return(t=ig()).$$click=()=>{let t=e.activeQuery.state.data,r=(0,l.Dc)(t,e.dataPath);o.setQueryData(e.activeQuery.queryKey,r)},(0,l.Yr)(t,(0,l.a0)(nQ,{})),(0,l.gb)(()=>(0,l.s7)(t,H(i().actionButton))),t},iq=e=>{var t;let r=q(),n=x().shadowDOMTarget?R.bind({target:x().shadowDOMTarget}):R,i=(0,l.To)(()=>"dark"===r()?iD(n):iF(n)),o=x().client;return(t=ip()).$$click=()=>{let t=e.activeQuery.state.data,r=(0,l.zt)(t,e.dataPath,!e.value);o.setQueryData(e.activeQuery.queryKey,r)},(0,l.Yr)(t,(0,l.a0)(ir,{get theme(){return r()},get checked(){return e.value}})),(0,l.gb)(()=>(0,l.s7)(t,H(i().actionButton,n`
          width: ${n$.size[3.5]};
          height: ${n$.size[3.5]};
        `))),t};function iE(e){return Symbol.iterator in e}function iT(e){var t;let r=q(),n=x().shadowDOMTarget?R.bind({target:x().shadowDOMTarget}):R,i=(0,l.To)(()=>"dark"===r()?iD(n):iF(n)),o=x().client,[a,s]=(0,l.n5)((e.defaultExpanded||[]).includes(e.label)),[d,u]=(0,l.n5)([]),c=(0,l.To)(()=>Array.isArray(e.value)?e.value.map((e,t)=>({label:t.toString(),value:e})):null!==e.value&&"object"==typeof e.value&&iE(e.value)&&"function"==typeof e.value[Symbol.iterator]?e.value instanceof Map?Array.from(e.value,([e,t])=>({label:e,value:t})):Array.from(e.value,(e,t)=>({label:t.toString(),value:e})):"object"==typeof e.value&&null!==e.value?Object.entries(e.value).map(([e,t])=>({label:e,value:t})):[]),g=(0,l.To)(()=>Array.isArray(e.value)?"array":null!==e.value&&"object"==typeof e.value&&iE(e.value)&&"function"==typeof e.value[Symbol.iterator]?"Iterable":"object"==typeof e.value&&null!==e.value?"object":typeof e.value),f=(0,l.To)(()=>(function(e,t){let r=0,n=[];for(;r<e.length;)n.push(e.slice(r,r+100)),r+=100;return n})(c(),0)),p=e.dataPath??[],h=(0,l.Ds)();return t=iv(),(0,l.Yr)(t,(0,l.a0)(l.wv,{get when(){return f().length},get children(){var v,y,b,m,w,k;return[(k=(w=(m=(b=(y=(v=iy()).firstChild).firstChild).nextSibling).nextSibling.nextSibling).firstChild,y.$$click=()=>s(e=>!e),(0,l.Yr)(y,(0,l.a0)(ik,{get expanded(){return a()}}),b),(0,l.Yr)(m,()=>e.label),(0,l.Yr)(w,()=>"iterable"===String(g()).toLowerCase()?"(Iterable) ":"",k),(0,l.Yr)(w,()=>c().length,k),(0,l.Yr)(w,()=>c().length>1?"items":"item",null),(0,l.Yr)(v,(0,l.a0)(l.wv,{get when(){return e.editable},get children(){var $=iv();return(0,l.Yr)($,(0,l.a0)(i$,{get value(){return e.value}}),null),(0,l.Yr)($,(0,l.a0)(l.wv,{get when(){return e.itemsDeletable&&void 0!==e.activeQuery},get children(){return(0,l.a0)(iC,{get activeQuery(){return e.activeQuery},dataPath:p})}}),null),(0,l.Yr)($,(0,l.a0)(l.wv,{get when(){return"array"===g()&&void 0!==e.activeQuery},get children(){return(0,l.a0)(iS,{get activeQuery(){return e.activeQuery},dataPath:p})}}),null),(0,l.Yr)($,(0,l.a0)(l.wv,{get when(){return(0,l.ph)(()=>!!e.onEdit)()&&!(0,l.lK)(e.value).meta},get children(){var S=ih();return S.$$click=()=>{e.onEdit?.()},(0,l.Yr)(S,(0,l.a0)(n9,{})),(0,l.gb)(()=>(0,l.s7)(S,i().actionButton)),S}}),null),(0,l.gb)(()=>(0,l.s7)($,i().actions)),$}}),null),(0,l.gb)(e=>{var t=i().expanderButtonContainer,r=i().expanderButton,n=a()?"true":"false",o=i().info;return t!==e.e&&(0,l.s7)(v,e.e=t),r!==e.t&&(0,l.s7)(y,e.t=r),n!==e.a&&(0,l.Bq)(y,"aria-expanded",e.a=n),o!==e.o&&(0,l.s7)(w,e.o=o),e},{e:void 0,t:void 0,a:void 0,o:void 0}),v),(0,l.a0)(l.wv,{get when(){return a()},get children(){return[(0,l.a0)(l.wv,{get when(){return 1===f().length},get children(){var C=iv();return(0,l.Yr)(C,(0,l.a0)(Q,{get each(){return c()},by:e=>e.label,children:t=>(0,l.a0)(iT,{get defaultExpanded(){return e.defaultExpanded},get label(){return t().label},get value(){return t().value},get editable(){return e.editable},get dataPath(){return[...p,t().label]},get activeQuery(){return e.activeQuery},get itemsDeletable(){return"array"===g()||"Iterable"===g()||"object"===g()}})})),(0,l.gb)(()=>(0,l.s7)(C,i().subEntry)),C}}),(0,l.a0)(l.wv,{get when(){return f().length>1},get children(){var E=iv();return(0,l.Yr)(E,(0,l.a0)(l.jK,{get each(){return f()},children:(t,r)=>{var n,o,a,s,c,g;return(g=(c=(s=(a=(o=(n=ix()).firstChild).firstChild).firstChild).nextSibling).nextSibling.nextSibling).nextSibling,a.$$click=()=>u(e=>e.includes(r)?e.filter(e=>e!==r):[...e,r]),(0,l.Yr)(a,(0,l.a0)(ik,{get expanded(){return d().includes(r)}}),s),(0,l.Yr)(a,100*r,c),(0,l.Yr)(a,100*r+100-1,g),(0,l.Yr)(o,(0,l.a0)(l.wv,{get when(){return d().includes(r)},get children(){var f=iv();return(0,l.Yr)(f,(0,l.a0)(Q,{get each(){return t()},by:e=>e.label,children:t=>(0,l.a0)(iT,{get defaultExpanded(){return e.defaultExpanded},get label(){return t().label},get value(){return t().value},get editable(){return e.editable},get dataPath(){return[...p,t().label]},get activeQuery(){return e.activeQuery}})})),(0,l.gb)(()=>(0,l.s7)(f,i().subEntry)),f}}),null),(0,l.gb)(e=>{var t=i().entry,r=i().expanderButton;return t!==e.e&&(0,l.s7)(o,e.e=t),r!==e.t&&(0,l.s7)(a,e.t=r),e},{e:void 0,t:void 0}),n}})),(0,l.gb)(()=>(0,l.s7)(E,i().subEntry)),E}})]}})]}}),null),(0,l.Yr)(t,(0,l.a0)(l.wv,{get when(){return 0===f().length},get children(){var T=iw(),M=T.firstChild,F=M.firstChild;return(0,l.Bq)(M,"for",h),(0,l.Yr)(M,()=>e.label,F),(0,l.Yr)(T,(0,l.a0)(l.wv,{get when(){return(0,l.ph)(()=>!!(e.editable&&void 0!==e.activeQuery))()&&("string"===g()||"number"===g()||"boolean"===g())},get fallback(){var D;return D=im(),(0,l.Yr)(D,()=>(0,l.KN)(e.value)),(0,l.gb)(()=>(0,l.s7)(D,i().value)),D},get children(){return[(0,l.a0)(l.wv,{get when(){return(0,l.ph)(()=>!!(e.editable&&void 0!==e.activeQuery))()&&("string"===g()||"number"===g())},get children(){var z=ib();return z.addEventListener("change",t=>{let r=e.activeQuery.state.data,n=(0,l.zt)(r,p,"number"===g()?t.target.valueAsNumber:t.target.value);o.setQueryData(e.activeQuery.queryKey,n)}),(0,l.Bq)(z,"id",h),(0,l.gb)(e=>{var t="number"===g()?"number":"text",r=H(i().value,i().editableInput);return t!==e.e&&(0,l.Bq)(z,"type",e.e=t),r!==e.t&&(0,l.s7)(z,e.t=r),e},{e:void 0,t:void 0}),(0,l.gb)(()=>z.value=e.value),z}}),(0,l.a0)(l.wv,{get when(){return"boolean"===g()},get children(){var L=im();return(0,l.Yr)(L,(0,l.a0)(iq,{get activeQuery(){return e.activeQuery},dataPath:p,get value(){return e.value}}),null),(0,l.Yr)(L,()=>(0,l.KN)(e.value),null),(0,l.gb)(()=>(0,l.s7)(L,H(i().value,i().actions,i().editableInput))),L}})]}}),null),(0,l.Yr)(T,(0,l.a0)(l.wv,{get when(){return e.editable&&e.itemsDeletable&&void 0!==e.activeQuery},get children(){return(0,l.a0)(iC,{get activeQuery(){return e.activeQuery},dataPath:p})}}),null),(0,l.gb)(e=>{var t=i().row,r=i().label;return t!==e.e&&(0,l.s7)(T,e.e=t),r!==e.t&&(0,l.s7)(M,e.t=r),e},{e:void 0,t:void 0}),T}}),null),(0,l.gb)(()=>(0,l.s7)(t,i().entry)),t}var iM=(e,t)=>{let{colors:r,font:n,size:i,border:o}=n$,l=(t,r)=>"light"===e?t:r;return{entry:t`
      & * {
        font-size: ${n.size.xs};
        font-family:
          ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas,
          'Liberation Mono', 'Courier New', monospace;
      }
      position: relative;
      outline: none;
      word-break: break-word;
    `,subEntry:t`
      margin: 0 0 0 0.5em;
      padding-left: 0.75em;
      border-left: 2px solid ${l(r.gray[300],r.darkGray[400])};
      /* outline: 1px solid ${r.teal[400]}; */
    `,expander:t`
      & path {
        stroke: ${r.gray[400]};
      }
      & svg {
        width: ${i[3]};
        height: ${i[3]};
      }
      display: inline-flex;
      align-items: center;
      transition: all 0.1s ease;
      /* outline: 1px solid ${r.blue[400]}; */
    `,expanderButtonContainer:t`
      display: flex;
      align-items: center;
      line-height: ${i[4]};
      min-height: ${i[4]};
      gap: ${i[2]};
    `,expanderButton:t`
      cursor: pointer;
      color: inherit;
      font: inherit;
      outline: inherit;
      height: ${i[5]};
      background: transparent;
      border: none;
      padding: 0;
      display: inline-flex;
      align-items: center;
      gap: ${i[1]};
      position: relative;
      /* outline: 1px solid ${r.green[400]}; */

      &:focus-visible {
        border-radius: ${o.radius.xs};
        outline: 2px solid ${r.blue[800]};
      }

      & svg {
        position: relative;
        left: 1px;
      }
    `,info:t`
      color: ${l(r.gray[500],r.gray[500])};
      font-size: ${n.size.xs};
      margin-left: ${i[1]};
      /* outline: 1px solid ${r.yellow[400]}; */
    `,label:t`
      color: ${l(r.gray[700],r.gray[300])};
      white-space: nowrap;
    `,value:t`
      color: ${l(r.purple[600],r.purple[400])};
      flex-grow: 1;
    `,actions:t`
      display: inline-flex;
      gap: ${i[2]};
      align-items: center;
    `,row:t`
      display: inline-flex;
      gap: ${i[2]};
      width: 100%;
      margin: ${i[.25]} 0px;
      line-height: ${i[4.5]};
      align-items: center;
    `,editableInput:t`
      border: none;
      padding: ${i[.5]} ${i[1]} ${i[.5]} ${i[1.5]};
      flex-grow: 1;
      border-radius: ${o.radius.xs};
      background-color: ${l(r.gray[200],r.darkGray[500])};

      &:hover {
        background-color: ${l(r.gray[300],r.darkGray[600])};
      }
    `,actionButton:t`
      background-color: transparent;
      color: ${l(r.gray[500],r.gray[500])};
      border: none;
      display: inline-flex;
      padding: 0px;
      align-items: center;
      justify-content: center;
      cursor: pointer;
      width: ${i[3]};
      height: ${i[3]};
      position: relative;
      z-index: 1;

      &:hover svg {
        color: ${l(r.gray[600],r.gray[400])};
      }

      &:focus-visible {
        border-radius: ${o.radius.xs};
        outline: 2px solid ${r.blue[800]};
        outline-offset: 2px;
      }
    `}},iF=e=>iM("light",e),iD=e=>iM("dark",e);(0,l.z_)(["click"]);var iz=(0,l.vs)('<div><div aria-hidden=true></div><button type=button aria-label="Open Tanstack query devtools"class=tsqd-open-btn>'),iL=(0,l.vs)("<div>"),iO=(0,l.vs)('<aside aria-label="Tanstack query devtools"><div></div><button aria-label="Close tanstack query devtools">'),iA=(0,l.vs)("<select name=tsqd-queries-filter-sort>"),iI=(0,l.vs)("<select name=tsqd-mutations-filter-sort>"),iK=(0,l.vs)("<span>Asc"),iP=(0,l.vs)("<span>Desc"),iB=(0,l.vs)('<button aria-label="Open in picture-in-picture mode"title="Open in picture-in-picture mode">'),iR=(0,l.vs)("<div>Settings"),iH=(0,l.vs)("<span>Position"),iG=(0,l.vs)("<span>Top"),iU=(0,l.vs)("<span>Bottom"),iY=(0,l.vs)("<span>Left"),iV=(0,l.vs)("<span>Right"),iN=(0,l.vs)("<span>Theme"),ij=(0,l.vs)("<span>Light"),iQ=(0,l.vs)("<span>Dark"),iW=(0,l.vs)("<span>System"),i_=(0,l.vs)("<span>Disabled Queries"),iZ=(0,l.vs)("<span>Show"),iX=(0,l.vs)("<span>Hide"),iJ=(0,l.vs)("<div><div class=tsqd-queries-container>"),i0=(0,l.vs)("<div><div class=tsqd-mutations-container>"),i1=(0,l.vs)('<div><div><div><button aria-label="Close Tanstack query devtools"><span>TANSTACK</span><span> v</span></button></div></div><div><div><div><input aria-label="Filter queries by query key"type=text placeholder=Filter name=tsqd-query-filter-input></div><div></div><button class=tsqd-query-filter-sort-order-btn></button></div><div><button aria-label="Clear query cache"></button><button>'),i2=(0,l.vs)("<option>Sort by "),i5=(0,l.vs)("<div class=tsqd-query-disabled-indicator>disabled"),i3=(0,l.vs)("<div class=tsqd-query-static-indicator>static"),i4=(0,l.vs)("<button><div></div><code class=tsqd-query-hash>"),i6=(0,l.vs)("<div role=tooltip id=tsqd-status-tooltip>"),i7=(0,l.vs)("<span>"),i9=(0,l.vs)("<button><span></span><span>"),i8=(0,l.vs)("<button><span></span> Error"),oe=(0,l.vs)('<div><span></span>Trigger Error<select><option value=""disabled selected>'),ot=(0,l.vs)('<div class="tsqd-query-details-explorer-container tsqd-query-details-data-explorer">'),or=(0,l.vs)("<form><textarea name=data></textarea><div><span></span><div><button type=button>Cancel</button><button>Save"),on=(0,l.vs)('<div><div>Query Details</div><div role=status aria-live=polite aria-atomic=true><div class=tsqd-query-details-summary><pre><code></code></pre><span></span></div><div class=tsqd-query-details-observers-count><span>Observers:</span><span></span></div><div class=tsqd-query-details-last-updated><span>Last Updated:</span><span></span></div></div><div>Actions</div><div><button><span></span>Refetch</button><button><span></span>Invalidate</button><button><span></span>Reset</button><button><span></span>Remove</button><button><span></span> Loading</button></div><div>Data </div><div>Query Explorer</div><div class="tsqd-query-details-explorer-container tsqd-query-details-query-explorer">'),oi=(0,l.vs)("<option>"),oo=(0,l.vs)('<div><div>Mutation Details</div><div role=status aria-live=polite aria-atomic=true><div class=tsqd-query-details-summary><pre><code></code></pre><span></span></div><div class=tsqd-query-details-last-updated><span>Submitted At:</span><span></span></div></div><div>Variables Details</div><div class="tsqd-query-details-explorer-container tsqd-query-details-query-explorer"></div><div>Context Details</div><div class="tsqd-query-details-explorer-container tsqd-query-details-query-explorer"></div><div>Data Explorer</div><div class="tsqd-query-details-explorer-container tsqd-query-details-query-explorer"></div><div>Mutations Explorer</div><div class="tsqd-query-details-explorer-container tsqd-query-details-query-explorer">'),[ol,oa]=(0,l.n5)(null),[os,od]=(0,l.n5)(null),[ou,oc]=(0,l.n5)(0),[og,of]=(0,l.n5)(!1),op=e=>{var t,r;let n,i=q(),o=x().shadowDOMTarget?R.bind({target:x().shadowDOMTarget}):R,a=(0,l.To)(()=>"dark"===i()?oA(o):oO(o)),s=(0,l.To)(()=>x().onlineManager);(0,l.Rc)(()=>{let e=s().subscribe(e=>{of(!e)});(0,l.Ki)(()=>{e()})});let d=S(),u=(0,l.To)(()=>x().buttonPosition||"bottom-right"),c=(0,l.To)(()=>"true"===e.localStore.open||"false"!==e.localStore.open&&(x().initialIsOpen||!1)),g=(0,l.To)(()=>e.localStore.position||x().position||v);(0,l.EH)(()=>{let t=n.parentElement,r=e.localStore.height||500,i=e.localStore.width||500,o=g();t.style.setProperty("--tsqd-panel-height",`${"top"===o?"-":""}${r}px`),t.style.setProperty("--tsqd-panel-width",`${"left"===o?"-":""}${i}px`)}),(0,l.Rc)(()=>{let e=()=>{let e=n.parentElement,t=getComputedStyle(e).fontSize;e.style.setProperty("--tsqd-font-size",t)};e(),window.addEventListener("focus",e),(0,l.Ki)(()=>{window.removeEventListener("focus",e)})});let f=(0,l.To)(()=>e.localStore.pip_open??"false");return[(0,l.a0)(l.wv,{get when(){return(0,l.ph)(()=>!!d().pipWindow)()&&"true"==f()},get children(){return(0,l.a0)(l.ZL,{get mount(){return d().pipWindow?.document.body},get children(){return(0,l.a0)(oh,{get children(){return(0,l.a0)(ob,e)}})}})}}),(t=iL(),"function"==typeof(r=n)?(0,l.Yx)(r,t):n=t,(0,l.Yr)(t,(0,l.a0)(V,{name:"tsqd-panel-transition",get children(){return(0,l.a0)(l.wv,{get when(){return(0,l.ph)(()=>!!(c()&&!d().pipWindow))()&&"false"==f()},get children(){return(0,l.a0)(oy,{get localStore(){return e.localStore},get setLocalStore(){return e.setLocalStore}})}})}}),null),(0,l.Yr)(t,(0,l.a0)(V,{name:"tsqd-button-transition",get children(){return(0,l.a0)(l.wv,{get when(){return!c()},get children(){var p=iz(),h=p.firstChild,y=h.nextSibling;return(0,l.Yr)(h,(0,l.a0)(is,{})),y.$$click=()=>e.setLocalStore("open","true"),(0,l.Yr)(y,(0,l.a0)(is,{})),(0,l.gb)(()=>(0,l.s7)(p,H(a().devtoolsBtn,a()[`devtoolsBtn-position-${u()}`],"tsqd-open-btn-container"))),p}})}}),null),(0,l.gb)(()=>(0,l.s7)(t,H(o`
            & .tsqd-panel-transition-exit-active,
            & .tsqd-panel-transition-enter-active {
              transition:
                opacity 0.3s,
                transform 0.3s;
            }

            & .tsqd-panel-transition-exit-to,
            & .tsqd-panel-transition-enter {
              ${"top"===g()||"bottom"===g()?"transform: translateY(var(--tsqd-panel-height));":"transform: translateX(var(--tsqd-panel-width));"}
            }

            & .tsqd-button-transition-exit-active,
            & .tsqd-button-transition-enter-active {
              transition:
                opacity 0.3s,
                transform 0.3s;
              opacity: 1;
            }

            & .tsqd-button-transition-exit-to,
            & .tsqd-button-transition-enter {
              transform: ${"relative"===u()?"none;":"top-left"===u()?"translateX(-72px);":"top-right"===u()?"translateX(72px);":"translateY(72px);"};
              opacity: 0;
            }
          `,"tsqd-transitions-container"))),t)]},oh=e=>{var t;let r=S(),n=q(),i=x().shadowDOMTarget?R.bind({target:x().shadowDOMTarget}):R,o=(0,l.To)(()=>"dark"===n()?oA(i):oO(i));return(0,l.EH)(()=>{let e=r().pipWindow,t=()=>{e&&oc(e.innerWidth)};e&&(e.addEventListener("resize",t),t()),(0,l.Ki)(()=>{e&&e.removeEventListener("resize",t)})}),(t=iL()).style.setProperty("--tsqd-font-size","16px"),t.style.setProperty("max-height","100vh"),t.style.setProperty("height","100vh"),t.style.setProperty("width","100vw"),(0,l.Yr)(t,()=>e.children),(0,l.gb)(()=>(0,l.s7)(t,H(o().panel,(()=>{let{colors:e}=n$,t=(e,t)=>"dark"===n()?t:e;return 796>ou()?i`
        flex-direction: column;
        background-color: ${t(e.gray[300],e.gray[600])};
      `:i`
      flex-direction: row;
      background-color: ${t(e.gray[200],e.darkGray[900])};
    `})(),{[i`
            min-width: min-content;
          `]:700>ou()},"tsqd-main-panel"))),t},ov=e=>{var t,r;let n,i=q(),o=x().shadowDOMTarget?R.bind({target:x().shadowDOMTarget}):R,a=(0,l.To)(()=>"dark"===i()?oA(o):oO(o));return(0,l.Rc)(()=>{W(n,({width:e},t)=>{t===n&&oc(e)})}),t=iL(),"function"==typeof(r=n)?(0,l.Yx)(r,t):n=t,t.style.setProperty("--tsqd-font-size","16px"),(0,l.Yr)(t,()=>e.children),(0,l.gb)(()=>(0,l.s7)(t,H(a().parentPanel,(()=>{let{colors:e}=n$,t=(e,t)=>"dark"===i()?t:e;return 796>ou()?o`
        flex-direction: column;
        background-color: ${t(e.gray[300],e.gray[600])};
      `:o`
      flex-direction: row;
      background-color: ${t(e.gray[200],e.darkGray[900])};
    `})(),{[o`
            min-width: min-content;
          `]:700>ou()},"tsqd-main-panel"))),t},oy=e=>{var t,r,n,i;let o,a=q(),s=x().shadowDOMTarget?R.bind({target:x().shadowDOMTarget}):R,d=(0,l.To)(()=>"dark"===a()?oA(s):oO(s)),[u,c]=(0,l.n5)(!1),g=(0,l.To)(()=>e.localStore.position||x().position||v);return(0,l.Rc)(()=>{W(o,({width:e},t)=>{t===o&&oc(e)})}),(0,l.EH)(()=>{let t=o.parentElement?.parentElement?.parentElement;if(!t)return;let r=e.localStore.position||v,n=(0,l.zZ)("padding",r),i="left"===e.localStore.position||"right"===e.localStore.position,a=(({padding:e,paddingTop:t,paddingBottom:r,paddingLeft:n,paddingRight:i})=>({padding:e,paddingTop:t,paddingBottom:r,paddingLeft:n,paddingRight:i}))(t.style);t.style[n]=`${i?e.localStore.width:e.localStore.height}px`,(0,l.Ki)(()=>{Object.entries(a).forEach(([e,r])=>{t.style[e]=r})})}),n=(r=(t=iO()).firstChild).nextSibling,"function"==typeof(i=o)?(0,l.Yx)(i,t):o=t,r.$$mousedown=t=>{let r=t.currentTarget.parentElement;if(!r)return;c(!0);let{height:n,width:i}=r.getBoundingClientRect(),o=t.clientX,a=t.clientY,s=0,d=(0,l.mO)(3.5),f=(0,l.mO)(12),p=t=>{if(t.preventDefault(),"left"===g()||"right"===g()){(s=Math.round(i+("right"===g()?o-t.clientX:t.clientX-o)))<f&&(s=f),e.setLocalStore("width",String(Math.round(s)));let n=r.getBoundingClientRect().width;Number(e.localStore.width)<n&&e.setLocalStore("width",String(n))}else(s=Math.round(n+("bottom"===g()?a-t.clientY:t.clientY-a)))<d&&(s=d,oa(null)),e.setLocalStore("height",String(Math.round(s)))},h=()=>{u()&&c(!1),document.removeEventListener("mousemove",p,!1),document.removeEventListener("mouseUp",h,!1)};document.addEventListener("mousemove",p,!1),document.addEventListener("mouseup",h,!1)},n.$$click=()=>e.setLocalStore("open","false"),(0,l.Yr)(n,(0,l.a0)(nW,{})),(0,l.Yr)(t,(0,l.a0)(ob,e),null),(0,l.gb)(i=>{var o=H(d().panel,d()[`panel-position-${g()}`],(()=>{let{colors:e}=n$,t=(e,t)=>"dark"===a()?t:e;return 796>ou()?s`
        flex-direction: column;
        background-color: ${t(e.gray[300],e.gray[600])};
      `:s`
      flex-direction: row;
      background-color: ${t(e.gray[200],e.darkGray[900])};
    `})(),{[s`
            min-width: min-content;
          `]:700>ou()&&("right"===g()||"left"===g())},"tsqd-main-panel"),u="bottom"===g()||"top"===g()?`${e.localStore.height||500}px`:"auto",c="right"===g()||"left"===g()?`${e.localStore.width||500}px`:"auto",f=H(d().dragHandle,d()[`dragHandle-position-${g()}`],"tsqd-drag-handle"),p=H(d().closeBtn,d()[`closeBtn-position-${g()}`],"tsqd-minimize-btn");return o!==i.e&&(0,l.s7)(t,i.e=o),u!==i.t&&(null!=(i.t=u)?t.style.setProperty("height",u):t.style.removeProperty("height")),c!==i.a&&(null!=(i.a=c)?t.style.setProperty("width",c):t.style.removeProperty("width")),f!==i.o&&(0,l.s7)(r,i.o=f),p!==i.i&&(0,l.s7)(n,i.i=p),i},{e:void 0,t:void 0,a:void 0,o:void 0,i:void 0}),t},ob=e=>{var t,r,n,i,o,a,s,d,u,c,g,f,p,h,v,y,w,k;let $;oE(),oF();let C=q(),E=x().shadowDOMTarget?R.bind({target:x().shadowDOMTarget}):R,T=(0,l.To)(()=>"dark"===C()?oA(E):oO(E)),F=S(),[D,z]=(0,l.n5)("queries"),L=(0,l.To)(()=>e.localStore.sort||b),O=(0,l.To)(()=>Number(e.localStore.sortOrder)||1),A=(0,l.To)(()=>e.localStore.mutationSort||m),I=(0,l.To)(()=>Number(e.localStore.mutationSortOrder)||1),K=(0,l.To)(()=>l.O$[L()]),P=(0,l.To)(()=>l.bs[A()]),B=(0,l.To)(()=>x().onlineManager),G=(0,l.To)(()=>x().client.getQueryCache()),U=(0,l.To)(()=>x().client.getMutationCache()),Y=oT(e=>e().getAll().length,!1),V=(0,l.To)((0,l.on)(()=>[Y(),e.localStore.filter,L(),O(),e.localStore.hideDisabledQueries],()=>{let t=G().getAll(),r=e.localStore.filter?t.filter(t=>M(t.queryHash,e.localStore.filter||"").passed):[...t];return"true"===e.localStore.hideDisabledQueries&&(r=r.filter(e=>!e.isDisabled())),K()?r.sort((e,t)=>K()(e,t)*O()):r})),N=oD(e=>e().getAll().length,!1),j=(0,l.To)((0,l.on)(()=>[N(),e.localStore.mutationFilter,A(),I()],()=>{let t=U().getAll(),r=e.localStore.mutationFilter?t.filter(t=>M(`${t.options.mutationKey?JSON.stringify(t.options.mutationKey)+" - ":""}${new Date(t.state.submittedAt).toLocaleString()}`,e.localStore.mutationFilter||"").passed):[...t];return P()?r.sort((e,t)=>P()(e,t)*I()):r})),W=e=>{let t=getComputedStyle($).getPropertyValue("--tsqd-font-size");e.style.setProperty("--tsqd-font-size",t)};return[(s=(a=(o=(i=(n=(r=(t=i1()).firstChild).firstChild).firstChild).firstChild).nextSibling).firstChild,g=(c=(u=(d=r.nextSibling).firstChild).firstChild).firstChild,p=(f=c.nextSibling).nextSibling,y=(v=(h=u.nextSibling).firstChild).nextSibling,"function"==typeof(w=$)?(0,l.Yx)(w,t):$=t,i.$$click=()=>{F().pipWindow||e.showPanelViewOnly?e.onClose&&e.onClose():e.setLocalStore("open","false")},(0,l.Yr)(a,()=>x().queryFlavor,s),(0,l.Yr)(a,()=>x().version,null),(0,l.Yr)(n,(0,l.a0)(rb.Root,{get class(){return H(T().viewToggle)},get value(){return D()},onChange:e=>{z(e),oa(null),od(null)},get children(){return[(0,l.a0)(rb.Item,{value:"queries",class:"tsqd-radio-toggle",get children(){return[(0,l.a0)(rb.ItemInput,{}),(0,l.a0)(rb.ItemControl,{get children(){return(0,l.a0)(rb.ItemIndicator,{})}}),(0,l.a0)(rb.ItemLabel,{title:"Toggle Queries View",children:"Queries"})]}}),(0,l.a0)(rb.Item,{value:"mutations",class:"tsqd-radio-toggle",get children(){return[(0,l.a0)(rb.ItemInput,{}),(0,l.a0)(rb.ItemControl,{get children(){return(0,l.a0)(rb.ItemIndicator,{})}}),(0,l.a0)(rb.ItemLabel,{title:"Toggle Mutations View",children:"Mutations"})]}})]}}),null),(0,l.Yr)(r,(0,l.a0)(l.wv,{get when(){return"queries"===D()},get children(){return(0,l.a0)(ox,{})}}),null),(0,l.Yr)(r,(0,l.a0)(l.wv,{get when(){return"mutations"===D()},get children(){return(0,l.a0)(ok,{})}}),null),(0,l.Yr)(c,(0,l.a0)(nj,{}),g),g.$$input=t=>{"queries"===D()?e.setLocalStore("filter",t.currentTarget.value):e.setLocalStore("mutationFilter",t.currentTarget.value)},(0,l.Yr)(f,(0,l.a0)(l.wv,{get when(){return"queries"===D()},get children(){var _=iA();return _.addEventListener("change",t=>{e.setLocalStore("sort",t.currentTarget.value)}),(0,l.Yr)(_,()=>Object.keys(l.O$).map(e=>{var t;return(t=i2()).firstChild,t.value=e,(0,l.Yr)(t,e,null),t})),(0,l.gb)(()=>_.value=L()),_}}),null),(0,l.Yr)(f,(0,l.a0)(l.wv,{get when(){return"mutations"===D()},get children(){var Z=iI();return Z.addEventListener("change",t=>{e.setLocalStore("mutationSort",t.currentTarget.value)}),(0,l.Yr)(Z,()=>Object.keys(l.bs).map(e=>{var t;return(t=i2()).firstChild,t.value=e,(0,l.Yr)(t,e,null),t})),(0,l.gb)(()=>Z.value=A()),Z}}),null),(0,l.Yr)(f,(0,l.a0)(nW,{}),null),p.$$click=()=>{"queries"===D()?e.setLocalStore("sortOrder",String(-1*O())):e.setLocalStore("mutationSortOrder",String(-1*I()))},(0,l.Yr)(p,(0,l.a0)(l.wv,{get when(){return("queries"===D()?O():I())===1},get children(){return[iK(),(0,l.a0)(n_,{})]}}),null),(0,l.Yr)(p,(0,l.a0)(l.wv,{get when(){return("queries"===D()?O():I())===-1},get children(){return[iP(),(0,l.a0)(nZ,{})]}}),null),v.$$click=()=>{"queries"===D()?(oz({type:"CLEAR_QUERY_CACHE"}),G().clear()):(oz({type:"CLEAR_MUTATION_CACHE"}),U().clear())},(0,l.Yr)(v,(0,l.a0)(nQ,{})),y.$$click=()=>{B().setOnline(!B().isOnline())},(0,l.Yr)(y,(k=(0,l.ph)(()=>!!og()),()=>k()?(0,l.a0)(n3,{}):(0,l.a0)(n5,{}))),(0,l.Yr)(h,(0,l.a0)(l.wv,{get when(){return(0,l.ph)(()=>!F().pipWindow)()&&!F().disabled},get children(){var X=iB();return X.$$click=()=>{F().requestPipWindow(Number(window.innerWidth),Number(e.localStore.height??500))},(0,l.Yr)(X,(0,l.a0)(n6,{})),(0,l.gb)(()=>(0,l.s7)(X,H(T().actionsBtn,"tsqd-actions-btn","tsqd-action-open-pip"))),X}}),null),(0,l.Yr)(h,(0,l.a0)(nm.Root,{gutter:4,get children(){return[(0,l.a0)(nm.Trigger,{get class(){return H(T().actionsBtn,"tsqd-actions-btn","tsqd-action-settings")},"aria-label":"Open settings menu",title:"Open settings menu",get children(){return(0,l.a0)(n4,{})}}),(0,l.a0)(nm.Portal,{ref:e=>W(e),get mount(){return(0,l.ph)(()=>!!F().pipWindow)()?F().pipWindow.document.body:document.body},get children(){return(0,l.a0)(nm.Content,{get class(){return H(T().settingsMenu,"tsqd-settings-menu")},get children(){var J;return[(J=iR(),(0,l.gb)(()=>(0,l.s7)(J,H(T().settingsMenuHeader,"tsqd-settings-menu-header"))),J),(0,l.a0)(l.wv,{get when(){return!e.showPanelViewOnly},get children(){return(0,l.a0)(nm.Sub,{overlap:!0,gutter:8,shift:-4,get children(){return[(0,l.a0)(nm.SubTrigger,{get class(){return H(T().settingsSubTrigger,"tsqd-settings-menu-sub-trigger","tsqd-settings-menu-sub-trigger-position")},get children(){return[iH(),(0,l.a0)(nW,{})]}}),(0,l.a0)(nm.Portal,{ref:e=>W(e),get mount(){return(0,l.ph)(()=>!!F().pipWindow)()?F().pipWindow.document.body:document.body},get children(){return(0,l.a0)(nm.SubContent,{get class(){return H(T().settingsMenu,"tsqd-settings-submenu")},get children(){return(0,l.a0)(nm.RadioGroup,{"aria-label":"Position settings",get value(){return e.localStore.position},onChange:t=>{e.setLocalStore("position",t)},get children(){return[(0,l.a0)(nm.RadioItem,{value:"top",get class(){return H(T().settingsSubButton,"tsqd-settings-menu-position-btn","tsqd-settings-menu-position-btn-top")},get children(){return[iG(),(0,l.a0)(n_,{})]}}),(0,l.a0)(nm.RadioItem,{value:"bottom",get class(){return H(T().settingsSubButton,"tsqd-settings-menu-position-btn","tsqd-settings-menu-position-btn-bottom")},get children(){return[iU(),(0,l.a0)(nZ,{})]}}),(0,l.a0)(nm.RadioItem,{value:"left",get class(){return H(T().settingsSubButton,"tsqd-settings-menu-position-btn","tsqd-settings-menu-position-btn-left")},get children(){return[iY(),(0,l.a0)(nX,{})]}}),(0,l.a0)(nm.RadioItem,{value:"right",get class(){return H(T().settingsSubButton,"tsqd-settings-menu-position-btn","tsqd-settings-menu-position-btn-right")},get children(){return[iV(),(0,l.a0)(nJ,{})]}})]}})}})}})]}})}}),(0,l.a0)(nm.Sub,{overlap:!0,gutter:8,shift:-4,get children(){return[(0,l.a0)(nm.SubTrigger,{get class(){return H(T().settingsSubTrigger,"tsqd-settings-menu-sub-trigger","tsqd-settings-menu-sub-trigger-position")},get children(){return[iN(),(0,l.a0)(nW,{})]}}),(0,l.a0)(nm.Portal,{ref:e=>W(e),get mount(){return(0,l.ph)(()=>!!F().pipWindow)()?F().pipWindow.document.body:document.body},get children(){return(0,l.a0)(nm.SubContent,{get class(){return H(T().settingsMenu,"tsqd-settings-submenu")},get children(){return(0,l.a0)(nm.RadioGroup,{get value(){return e.localStore.theme_preference},onChange:t=>{e.setLocalStore("theme_preference",t)},"aria-label":"Theme preference",get children(){return[(0,l.a0)(nm.RadioItem,{value:"light",get class(){return H(T().settingsSubButton,"tsqd-settings-menu-position-btn","tsqd-settings-menu-position-btn-top")},get children(){return[ij(),(0,l.a0)(n0,{})]}}),(0,l.a0)(nm.RadioItem,{value:"dark",get class(){return H(T().settingsSubButton,"tsqd-settings-menu-position-btn","tsqd-settings-menu-position-btn-bottom")},get children(){return[iQ(),(0,l.a0)(n1,{})]}}),(0,l.a0)(nm.RadioItem,{value:"system",get class(){return H(T().settingsSubButton,"tsqd-settings-menu-position-btn","tsqd-settings-menu-position-btn-left")},get children(){return[iW(),(0,l.a0)(n2,{})]}})]}})}})}})]}}),(0,l.a0)(nm.Sub,{overlap:!0,gutter:8,shift:-4,get children(){return[(0,l.a0)(nm.SubTrigger,{get class(){return H(T().settingsSubTrigger,"tsqd-settings-menu-sub-trigger","tsqd-settings-menu-sub-trigger-disabled-queries")},get children(){return[i_(),(0,l.a0)(nW,{})]}}),(0,l.a0)(nm.Portal,{ref:e=>W(e),get mount(){return(0,l.ph)(()=>!!F().pipWindow)()?F().pipWindow.document.body:document.body},get children(){return(0,l.a0)(nm.SubContent,{get class(){return H(T().settingsMenu,"tsqd-settings-submenu")},"aria-label":"Hide disabled queries setting",get children(){return(0,l.a0)(nm.RadioGroup,{get value(){return e.localStore.hideDisabledQueries},onChange:t=>e.setLocalStore("hideDisabledQueries",t),get children(){return[(0,l.a0)(nm.RadioItem,{value:"false",get class(){return H(T().settingsSubButton,"tsqd-settings-menu-position-btn","tsqd-settings-menu-position-btn-show")},get children(){return[iZ(),(0,l.a0)(l.wv,{get when(){return"true"!==e.localStore.hideDisabledQueries},get children(){return(0,l.a0)(ii,{})}})]}}),(0,l.a0)(nm.RadioItem,{value:"true",get class(){return H(T().settingsSubButton,"tsqd-settings-menu-position-btn","tsqd-settings-menu-position-btn-hide")},get children(){return[iX(),(0,l.a0)(l.wv,{get when(){return"true"===e.localStore.hideDisabledQueries},get children(){return(0,l.a0)(ii,{})}})]}})]}})}})}})]}})]}})}})]}}),null),(0,l.Yr)(t,(0,l.a0)(l.wv,{get when(){return"queries"===D()},get children(){var ee=iJ(),et=ee.firstChild;return(0,l.Yr)(et,(0,l.a0)(Q,{by:e=>e.queryHash,get each(){return V()},children:e=>(0,l.a0)(om,{get query(){return e()}})})),(0,l.gb)(()=>(0,l.s7)(ee,H(T().overflowQueryContainer,"tsqd-queries-overflow-container"))),ee}}),null),(0,l.Yr)(t,(0,l.a0)(l.wv,{get when(){return"mutations"===D()},get children(){var er=i0(),en=er.firstChild;return(0,l.Yr)(en,(0,l.a0)(Q,{by:e=>e.mutationId,get each(){return j()},children:e=>(0,l.a0)(ow,{get mutation(){return e()}})})),(0,l.gb)(()=>(0,l.s7)(er,H(T().overflowQueryContainer,"tsqd-mutations-overflow-container"))),er}}),null),(0,l.gb)(e=>{var s=H(T().queriesContainer,796>ou()&&(ol()||os())&&E`
              height: 50%;
              max-height: 50%;
            `,796>ou()&&!(ol()||os())&&E`
              height: 100%;
              max-height: 100%;
            `,"tsqd-queries-container"),b=H(T().row,"tsqd-header"),m=T().logoAndToggleContainer,w=H(T().logo,"tsqd-text-logo-container"),x=H(T().tanstackLogo,"tsqd-text-logo-tanstack"),k=H(T().queryFlavorLogo,"tsqd-text-logo-query-flavor"),$=H(T().row,"tsqd-filters-actions-container"),S=H(T().filtersContainer,"tsqd-filters-container"),C=H(T().filterInput,"tsqd-query-filter-textfield-container"),q=H("tsqd-query-filter-textfield"),M=H(T().filterSelect,"tsqd-query-filter-sort-container"),F=`Sort order ${("queries"===D()?O():I())===-1?"descending":"ascending"}`,z=("queries"===D()?O():I())===-1,L=H(T().actionsContainer,"tsqd-actions-container"),A=H(T().actionsBtn,"tsqd-actions-btn","tsqd-action-clear-cache"),K=`Clear ${D()} cache`,P=H(T().actionsBtn,og()&&T().actionsBtnOffline,"tsqd-actions-btn","tsqd-action-mock-offline-behavior"),B=`${og()?"Unset offline mocking behavior":"Mock offline behavior"}`,R=og(),G=`${og()?"Unset offline mocking behavior":"Mock offline behavior"}`;return s!==e.e&&(0,l.s7)(t,e.e=s),b!==e.t&&(0,l.s7)(r,e.t=b),m!==e.a&&(0,l.s7)(n,e.a=m),w!==e.o&&(0,l.s7)(i,e.o=w),x!==e.i&&(0,l.s7)(o,e.i=x),k!==e.n&&(0,l.s7)(a,e.n=k),$!==e.s&&(0,l.s7)(d,e.s=$),S!==e.h&&(0,l.s7)(u,e.h=S),C!==e.r&&(0,l.s7)(c,e.r=C),q!==e.d&&(0,l.s7)(g,e.d=q),M!==e.l&&(0,l.s7)(f,e.l=M),F!==e.u&&(0,l.Bq)(p,"aria-label",e.u=F),z!==e.c&&(0,l.Bq)(p,"aria-pressed",e.c=z),L!==e.w&&(0,l.s7)(h,e.w=L),A!==e.m&&(0,l.s7)(v,e.m=A),K!==e.f&&(0,l.Bq)(v,"title",e.f=K),P!==e.y&&(0,l.s7)(y,e.y=P),B!==e.g&&(0,l.Bq)(y,"aria-label",e.g=B),R!==e.p&&(0,l.Bq)(y,"aria-pressed",e.p=R),G!==e.b&&(0,l.Bq)(y,"title",e.b=G),e},{e:void 0,t:void 0,a:void 0,o:void 0,i:void 0,n:void 0,s:void 0,h:void 0,r:void 0,d:void 0,l:void 0,u:void 0,c:void 0,w:void 0,m:void 0,f:void 0,y:void 0,g:void 0,p:void 0,b:void 0}),(0,l.gb)(()=>g.value="queries"===D()?e.localStore.filter||"":e.localStore.mutationFilter||""),t),(0,l.a0)(l.wv,{get when(){return(0,l.ph)(()=>"queries"===D())()&&ol()},get children(){return(0,l.a0)(oS,{})}}),(0,l.a0)(l.wv,{get when(){return(0,l.ph)(()=>"mutations"===D())()&&os()},get children(){return(0,l.a0)(oC,{})}})]},om=e=>{let t=q(),r=x().shadowDOMTarget?R.bind({target:x().shadowDOMTarget}):R,n=(0,l.To)(()=>"dark"===t()?oA(r):oO(r)),{colors:i,alpha:o}=n$,a=(e,r)=>"dark"===t()?r:e,s=oT(t=>t().find({queryKey:e.query.queryKey})?.state,!0,t=>t.query.queryHash===e.query.queryHash),d=oT(t=>t().find({queryKey:e.query.queryKey})?.isDisabled()??!1,!0,t=>t.query.queryHash===e.query.queryHash),u=oT(t=>t().find({queryKey:e.query.queryKey})?.isStatic()??!1,!0,t=>t.query.queryHash===e.query.queryHash),c=oT(t=>t().find({queryKey:e.query.queryKey})?.isStale()??!1,!0,t=>t.query.queryHash===e.query.queryHash),g=oT(t=>t().find({queryKey:e.query.queryKey})?.getObserversCount()??0,!0,t=>t.query.queryHash===e.query.queryHash),f=(0,l.To)(()=>(0,l.MI)({queryState:s(),observerCount:g(),isStale:c()}));return(0,l.a0)(l.wv,{get when(){return s()},get children(){var p=i4(),h=p.firstChild,v=h.nextSibling;return p.$$click=()=>oa(e.query.queryHash===ol()?null:e.query.queryHash),(0,l.Yr)(h,g),(0,l.Yr)(v,()=>e.query.queryHash),(0,l.Yr)(p,(0,l.a0)(l.wv,{get when(){return d()},get children(){return i5()}}),null),(0,l.Yr)(p,(0,l.a0)(l.wv,{get when(){return u()},get children(){return i3()}}),null),(0,l.gb)(t=>{var s=H(n().queryRow,ol()===e.query.queryHash&&n().selectedQueryRow,"tsqd-query-row"),d=`Query key ${e.query.queryHash}`,u=H("gray"===f()?r`
        background-color: ${a(i[f()][200],i[f()][700])};
        color: ${a(i[f()][700],i[f()][300])};
      `:r`
      background-color: ${a(i[f()][200]+o[80],i[f()][900])};
      color: ${a(i[f()][800],i[f()][300])};
    `,"tsqd-query-observer-count");return s!==t.e&&(0,l.s7)(p,t.e=s),d!==t.t&&(0,l.Bq)(p,"aria-label",t.t=d),u!==t.a&&(0,l.s7)(h,t.a=u),t},{e:void 0,t:void 0,a:void 0}),p}})},ow=e=>{let t=q(),r=x().shadowDOMTarget?R.bind({target:x().shadowDOMTarget}):R,n=(0,l.To)(()=>"dark"===t()?oA(r):oO(r)),{colors:i,alpha:o}=n$,a=(e,r)=>"dark"===t()?r:e,s=oD(t=>{let r=t().getAll().find(t=>t.mutationId===e.mutation.mutationId);return r?.state}),d=oD(t=>{let r=t().getAll().find(t=>t.mutationId===e.mutation.mutationId);return!!r&&r.state.isPaused}),u=oD(t=>{let r=t().getAll().find(t=>t.mutationId===e.mutation.mutationId);return r?r.state.status:"idle"}),c=(0,l.To)(()=>(0,l.TH)({isPaused:d(),status:u()}));return(0,l.a0)(l.wv,{get when(){return s()},get children(){var g=i4(),f=g.firstChild,p=f.nextSibling;return g.$$click=()=>{od(e.mutation.mutationId===os()?null:e.mutation.mutationId)},(0,l.Yr)(f,(0,l.a0)(l.wv,{get when(){return"purple"===c()},get children(){return(0,l.a0)(ia,{})}}),null),(0,l.Yr)(f,(0,l.a0)(l.wv,{get when(){return"green"===c()},get children(){return(0,l.a0)(ii,{})}}),null),(0,l.Yr)(f,(0,l.a0)(l.wv,{get when(){return"red"===c()},get children(){return(0,l.a0)(il,{})}}),null),(0,l.Yr)(f,(0,l.a0)(l.wv,{get when(){return"yellow"===c()},get children(){return(0,l.a0)(io,{})}}),null),(0,l.Yr)(p,(0,l.a0)(l.wv,{get when(){return e.mutation.options.mutationKey},get children(){return[(0,l.ph)(()=>JSON.stringify(e.mutation.options.mutationKey))," -"," "]}}),null),(0,l.Yr)(p,()=>new Date(e.mutation.state.submittedAt).toLocaleString(),null),(0,l.gb)(t=>{var s=H(n().queryRow,os()===e.mutation.mutationId&&n().selectedQueryRow,"tsqd-query-row"),d=`Mutation submitted at ${new Date(e.mutation.state.submittedAt).toLocaleString()}`,u=H("gray"===c()?r`
        background-color: ${a(i[c()][200],i[c()][700])};
        color: ${a(i[c()][700],i[c()][300])};
      `:r`
      background-color: ${a(i[c()][200]+o[80],i[c()][900])};
      color: ${a(i[c()][800],i[c()][300])};
    `,"tsqd-query-observer-count");return s!==t.e&&(0,l.s7)(g,t.e=s),d!==t.t&&(0,l.Bq)(g,"aria-label",t.t=d),u!==t.a&&(0,l.s7)(f,t.a=u),t},{e:void 0,t:void 0,a:void 0}),g}})},ox=()=>{var e;let t=oT(e=>e().getAll().filter(e=>"stale"===(0,l.lR)(e)).length),r=oT(e=>e().getAll().filter(e=>"fresh"===(0,l.lR)(e)).length),n=oT(e=>e().getAll().filter(e=>"fetching"===(0,l.lR)(e)).length),i=oT(e=>e().getAll().filter(e=>"paused"===(0,l.lR)(e)).length),o=oT(e=>e().getAll().filter(e=>"inactive"===(0,l.lR)(e)).length),a=q(),s=x().shadowDOMTarget?R.bind({target:x().shadowDOMTarget}):R,d=(0,l.To)(()=>"dark"===a()?oA(s):oO(s));return e=iL(),(0,l.Yr)(e,(0,l.a0)(o$,{label:"Fresh",color:"green",get count(){return r()}}),null),(0,l.Yr)(e,(0,l.a0)(o$,{label:"Fetching",color:"blue",get count(){return n()}}),null),(0,l.Yr)(e,(0,l.a0)(o$,{label:"Paused",color:"purple",get count(){return i()}}),null),(0,l.Yr)(e,(0,l.a0)(o$,{label:"Stale",color:"yellow",get count(){return t()}}),null),(0,l.Yr)(e,(0,l.a0)(o$,{label:"Inactive",color:"gray",get count(){return o()}}),null),(0,l.gb)(()=>(0,l.s7)(e,H(d().queryStatusContainer,"tsqd-query-status-container"))),e},ok=()=>{var e;let t=oD(e=>e().getAll().filter(e=>"green"===(0,l.TH)({isPaused:e.state.isPaused,status:e.state.status})).length),r=oD(e=>e().getAll().filter(e=>"yellow"===(0,l.TH)({isPaused:e.state.isPaused,status:e.state.status})).length),n=oD(e=>e().getAll().filter(e=>"purple"===(0,l.TH)({isPaused:e.state.isPaused,status:e.state.status})).length),i=oD(e=>e().getAll().filter(e=>"red"===(0,l.TH)({isPaused:e.state.isPaused,status:e.state.status})).length),o=q(),a=x().shadowDOMTarget?R.bind({target:x().shadowDOMTarget}):R,s=(0,l.To)(()=>"dark"===o()?oA(a):oO(a));return e=iL(),(0,l.Yr)(e,(0,l.a0)(o$,{label:"Paused",color:"purple",get count(){return n()}}),null),(0,l.Yr)(e,(0,l.a0)(o$,{label:"Pending",color:"yellow",get count(){return r()}}),null),(0,l.Yr)(e,(0,l.a0)(o$,{label:"Success",color:"green",get count(){return t()}}),null),(0,l.Yr)(e,(0,l.a0)(o$,{label:"Error",color:"red",get count(){return i()}}),null),(0,l.gb)(()=>(0,l.s7)(e,H(s().queryStatusContainer,"tsqd-query-status-container"))),e},o$=e=>{var t,r,n,i;let o,a=q(),s=x().shadowDOMTarget?R.bind({target:x().shadowDOMTarget}):R,d=(0,l.To)(()=>"dark"===a()?oA(s):oO(s)),{colors:u,alpha:c}=n$,g=(e,t)=>"dark"===a()?t:e,[f,p]=(0,l.n5)(!1),[h,v]=(0,l.n5)(!1),y=(0,l.To)(()=>!(ol()&&1024>ou()&&ou()>796||796>ou()));return n=(r=(t=i9()).firstChild).nextSibling,"function"==typeof(i=o)?(0,l.Yx)(i,t):o=t,t.addEventListener("mouseleave",()=>{p(!1),v(!1)}),t.addEventListener("mouseenter",()=>p(!0)),t.addEventListener("blur",()=>v(!1)),t.addEventListener("focus",()=>v(!0)),(0,l.il)(t,(0,l.v6)({get disabled(){return y()},get class(){return H(d().queryStatusTag,!y()&&s`
            cursor: pointer;
            &:hover {
              background: ${g(u.gray[200],u.darkGray[400])}${c[80]};
            }
          `,"tsqd-query-status-tag",`tsqd-query-status-tag-${e.label.toLowerCase()}`)}},()=>f()||h()?{"aria-describedby":"tsqd-status-tooltip"}:{}),!1,!0),(0,l.Yr)(t,(0,l.a0)(l.wv,{get when(){return(0,l.ph)(()=>!y())()&&(f()||h())},get children(){var b=i6();return(0,l.Yr)(b,()=>e.label),(0,l.gb)(()=>(0,l.s7)(b,H(d().statusTooltip,"tsqd-query-status-tooltip"))),b}}),r),(0,l.Yr)(t,(0,l.a0)(l.wv,{get when(){return y()},get children(){var m=i7();return(0,l.Yr)(m,()=>e.label),(0,l.gb)(()=>(0,l.s7)(m,H(d().queryStatusTagLabel,"tsqd-query-status-tag-label"))),m}}),n),(0,l.Yr)(n,()=>e.count),(0,l.gb)(t=>{var i=H(s`
            width: ${n$.size[1.5]};
            height: ${n$.size[1.5]};
            border-radius: ${n$.border.radius.full};
            background-color: ${n$.colors[e.color][500]};
          `,"tsqd-query-status-tag-dot"),o=H(d().queryStatusCount,e.count>0&&"gray"!==e.color&&s`
              background-color: ${g(u[e.color][100],u[e.color][900])};
              color: ${g(u[e.color][700],u[e.color][300])};
            `,"tsqd-query-status-tag-count");return i!==t.e&&(0,l.s7)(r,t.e=i),o!==t.t&&(0,l.s7)(n,t.t=o),t},{e:void 0,t:void 0}),t},oS=()=>{let e=q(),t=x().shadowDOMTarget?R.bind({target:x().shadowDOMTarget}):R,r=(0,l.To)(()=>"dark"===e()?oA(t):oO(t)),{colors:n}=n$,i=(t,r)=>"dark"===e()?r:t,o=x().client,[a,s]=(0,l.n5)(!1),[d,u]=(0,l.n5)("view"),[c,g]=(0,l.n5)(!1),f=(0,l.To)(()=>x().errorTypes||[]),p=oT(e=>e().getAll().find(e=>e.queryHash===ol()),!1),h=oT(e=>e().getAll().find(e=>e.queryHash===ol()),!1),v=oT(e=>e().getAll().find(e=>e.queryHash===ol())?.state,!1),y=oT(e=>e().getAll().find(e=>e.queryHash===ol())?.state.data,!1),b=oT(e=>{let t=e().getAll().find(e=>e.queryHash===ol());return t?(0,l.lR)(t):"inactive"}),m=oT(e=>{let t=e().getAll().find(e=>e.queryHash===ol());return t?t.state.status:"pending"}),w=oT(e=>e().getAll().find(e=>e.queryHash===ol())?.getObserversCount()??0),k=(0,l.To)(()=>(0,l.ZZ)(b())),$=()=>{oz({type:"REFETCH",queryHash:p()?.queryHash});let e=p()?.fetch();e?.catch(()=>{})},S=e=>{let t=p();if(!t)return;oz({type:"TRIGGER_ERROR",queryHash:t.queryHash,metadata:{error:e?.name}});let r=e?.initializer(t)??Error("Unknown error from devtools"),n=t.options;t.setState({status:"error",error:r,fetchMeta:{...t.state.fetchMeta,__previousQueryOptions:n}})};return(0,l.EH)(()=>{"fetching"!==b()&&s(!1)}),(0,l.a0)(l.wv,{get when(){return(0,l.ph)(()=>!!p())()&&v()},get children(){var C=on(),E=C.firstChild,T=E.nextSibling,M=T.firstChild,F=M.firstChild,D=F.firstChild,z=F.nextSibling,L=M.nextSibling,O=L.firstChild.nextSibling,A=L.nextSibling.firstChild.nextSibling,I=T.nextSibling,K=I.nextSibling,P=K.firstChild,B=P.firstChild,G=P.nextSibling,U=G.firstChild,Y=G.nextSibling,V=Y.firstChild,N=Y.nextSibling,j=N.firstChild,Q=N.nextSibling,W=Q.firstChild,_=W.nextSibling,Z=K.nextSibling;Z.firstChild;var X=Z.nextSibling,J=X.nextSibling;return(0,l.Yr)(D,()=>(0,l.KN)(p().queryKey,!0)),(0,l.Yr)(z,b),(0,l.Yr)(O,w),(0,l.Yr)(A,()=>new Date(v().dataUpdatedAt).toLocaleTimeString()),P.$$click=$,G.$$click=()=>{oz({type:"INVALIDATE",queryHash:p()?.queryHash}),o.invalidateQueries(p())},Y.$$click=()=>{oz({type:"RESET",queryHash:p()?.queryHash}),o.resetQueries(p())},N.$$click=()=>{oz({type:"REMOVE",queryHash:p()?.queryHash}),o.removeQueries(p()),oa(null)},Q.$$click=()=>{if(p()?.state.data===void 0)s(!0),(()=>{let e=p();if(!e)return;oz({type:"RESTORE_LOADING",queryHash:e.queryHash});let t=e.state,r=e.state.fetchMeta?e.state.fetchMeta.__previousQueryOptions:null;e.cancel({silent:!0}),e.setState({...t,fetchStatus:"idle",fetchMeta:null}),r&&e.fetch(r)})();else{let e=p();if(!e)return;oz({type:"TRIGGER_LOADING",queryHash:e.queryHash});let t=e.options;e.fetch({...t,queryFn:()=>new Promise(()=>{}),gcTime:-1}),e.setState({data:void 0,status:"pending",fetchMeta:{...e.state.fetchMeta,__previousQueryOptions:t}})}},(0,l.Yr)(Q,()=>"pending"===m()?"Restore":"Trigger",_),(0,l.Yr)(K,(0,l.a0)(l.wv,{get when(){return 0===f().length||"error"===m()},get children(){var ee=i8(),et=ee.firstChild,er=et.nextSibling;return ee.$$click=()=>{p().state.error?(oz({type:"RESTORE_ERROR",queryHash:p()?.queryHash}),o.resetQueries(p())):S()},(0,l.Yr)(ee,()=>"error"===m()?"Restore":"Trigger",er),(0,l.gb)(e=>{var r=H(t`
                  color: ${i(n.red[500],n.red[400])};
                `,"tsqd-query-details-actions-btn","tsqd-query-details-action-error"),o="pending"===m(),a=t`
                  background-color: ${i(n.red[500],n.red[400])};
                `;return r!==e.e&&(0,l.s7)(ee,e.e=r),o!==e.t&&(ee.disabled=e.t=o),a!==e.a&&(0,l.s7)(et,e.a=a),e},{e:void 0,t:void 0,a:void 0}),ee}}),null),(0,l.Yr)(K,(0,l.a0)(l.wv,{get when(){return 0!==f().length&&"error"!==m()},get children(){var en=oe(),ei=en.firstChild,eo=ei.nextSibling.nextSibling;return eo.firstChild,eo.addEventListener("change",e=>{S(f().find(t=>t.name===e.currentTarget.value))}),(0,l.Yr)(eo,(0,l.a0)(l.a,{get each(){return f()},children:e=>{var t;return t=oi(),(0,l.Yr)(t,()=>e.name),(0,l.gb)(()=>t.value=e.name),t}}),null),(0,l.Yr)(en,(0,l.a0)(nW,{}),null),(0,l.gb)(e=>{var n=H(r().actionsSelect,"tsqd-query-details-actions-btn","tsqd-query-details-action-error-multiple"),i=t`
                  background-color: ${n$.colors.red[400]};
                `,o="pending"===m();return n!==e.e&&(0,l.s7)(en,e.e=n),i!==e.t&&(0,l.s7)(ei,e.t=i),o!==e.a&&(eo.disabled=e.a=o),e},{e:void 0,t:void 0,a:void 0}),en}}),null),(0,l.Yr)(Z,()=>"view"===d()?"Explorer":"Editor",null),(0,l.Yr)(C,(0,l.a0)(l.wv,{get when(){return"view"===d()},get children(){var el=ot();return(0,l.Yr)(el,(0,l.a0)(iT,{label:"Data",defaultExpanded:["Data"],get value(){return y()},editable:!0,onEdit:()=>u("edit"),get activeQuery(){return p()}})),(0,l.gb)(e=>null!=(e=n$.size[2])?el.style.setProperty("padding",e):el.style.removeProperty("padding")),el}}),X),(0,l.Yr)(C,(0,l.a0)(l.wv,{get when(){return"edit"===d()},get children(){var ea=or(),es=ea.firstChild,ed=es.nextSibling,eu=ed.firstChild,ec=eu.nextSibling,eg=ec.firstChild,ef=eg.nextSibling;return ea.addEventListener("submit",e=>{e.preventDefault();let t=new FormData(e.currentTarget).get("data");try{let e=JSON.parse(t);p().setState({...p().state,data:e}),u("view")}catch(e){g(!0)}}),es.addEventListener("focus",()=>g(!1)),(0,l.Yr)(eu,()=>c()?"Invalid Value":""),eg.$$click=()=>u("view"),(0,l.gb)(e=>{var o=H(r().devtoolsEditForm,"tsqd-query-details-data-editor"),a=r().devtoolsEditTextarea,s=c(),d=r().devtoolsEditFormActions,u=r().devtoolsEditFormError,g=r().devtoolsEditFormActionContainer,f=H(r().devtoolsEditFormAction,t`
                      color: ${i(n.gray[600],n.gray[300])};
                    `),p=H(r().devtoolsEditFormAction,t`
                      color: ${i(n.blue[600],n.blue[400])};
                    `);return o!==e.e&&(0,l.s7)(ea,e.e=o),a!==e.t&&(0,l.s7)(es,e.t=a),s!==e.a&&(0,l.Bq)(es,"data-error",e.a=s),d!==e.o&&(0,l.s7)(ed,e.o=d),u!==e.i&&(0,l.s7)(eu,e.i=u),g!==e.n&&(0,l.s7)(ec,e.n=g),f!==e.s&&(0,l.s7)(eg,e.s=f),p!==e.h&&(0,l.s7)(ef,e.h=p),e},{e:void 0,t:void 0,a:void 0,o:void 0,i:void 0,n:void 0,s:void 0,h:void 0}),(0,l.gb)(()=>es.value=JSON.stringify(y(),null,2)),ea}}),X),(0,l.Yr)(J,(0,l.a0)(iT,{label:"Query",defaultExpanded:["Query","queryKey"],get value(){return h()}})),(0,l.gb)(e=>{var o=H(r().detailsContainer,"tsqd-query-details-container"),s=H(r().detailsHeader,"tsqd-query-details-header"),d=H(r().detailsBody,"tsqd-query-details-summary-container"),u=H(r().queryDetailsStatus,"gray"===k()?t`
        background-color: ${i(n[k()][200],n[k()][700])};
        color: ${i(n[k()][700],n[k()][300])};
        border-color: ${i(n[k()][400],n[k()][600])};
      `:t`
      background-color: ${i(n[k()][100],n[k()][900])};
      color: ${i(n[k()][700],n[k()][300])};
      border-color: ${i(n[k()][400],n[k()][600])};
    `),c=H(r().detailsHeader,"tsqd-query-details-header"),g=H(r().actionsBody,"tsqd-query-details-actions-container"),f=H(t`
                color: ${i(n.blue[600],n.blue[400])};
              `,"tsqd-query-details-actions-btn","tsqd-query-details-action-refetch"),p="fetching"===b(),h=t`
                background-color: ${i(n.blue[600],n.blue[400])};
              `,v=H(t`
                color: ${i(n.yellow[600],n.yellow[400])};
              `,"tsqd-query-details-actions-btn","tsqd-query-details-action-invalidate"),y="pending"===m(),w=t`
                background-color: ${i(n.yellow[600],n.yellow[400])};
              `,x=H(t`
                color: ${i(n.gray[600],n.gray[300])};
              `,"tsqd-query-details-actions-btn","tsqd-query-details-action-reset"),$="pending"===m(),S=t`
                background-color: ${i(n.gray[600],n.gray[400])};
              `,q=H(t`
                color: ${i(n.pink[500],n.pink[400])};
              `,"tsqd-query-details-actions-btn","tsqd-query-details-action-remove"),M="fetching"===b(),F=t`
                background-color: ${i(n.pink[500],n.pink[400])};
              `,D=H(t`
                color: ${i(n.cyan[500],n.cyan[400])};
              `,"tsqd-query-details-actions-btn","tsqd-query-details-action-loading"),L=a(),O=t`
                background-color: ${i(n.cyan[500],n.cyan[400])};
              `,A=H(r().detailsHeader,"tsqd-query-details-header"),R=H(r().detailsHeader,"tsqd-query-details-header"),_=n$.size[2];return o!==e.e&&(0,l.s7)(C,e.e=o),s!==e.t&&(0,l.s7)(E,e.t=s),d!==e.a&&(0,l.s7)(T,e.a=d),u!==e.o&&(0,l.s7)(z,e.o=u),c!==e.i&&(0,l.s7)(I,e.i=c),g!==e.n&&(0,l.s7)(K,e.n=g),f!==e.s&&(0,l.s7)(P,e.s=f),p!==e.h&&(P.disabled=e.h=p),h!==e.r&&(0,l.s7)(B,e.r=h),v!==e.d&&(0,l.s7)(G,e.d=v),y!==e.l&&(G.disabled=e.l=y),w!==e.u&&(0,l.s7)(U,e.u=w),x!==e.c&&(0,l.s7)(Y,e.c=x),$!==e.w&&(Y.disabled=e.w=$),S!==e.m&&(0,l.s7)(V,e.m=S),q!==e.f&&(0,l.s7)(N,e.f=q),M!==e.y&&(N.disabled=e.y=M),F!==e.g&&(0,l.s7)(j,e.g=F),D!==e.p&&(0,l.s7)(Q,e.p=D),L!==e.b&&(Q.disabled=e.b=L),O!==e.T&&(0,l.s7)(W,e.T=O),A!==e.A&&(0,l.s7)(Z,e.A=A),R!==e.O&&(0,l.s7)(X,e.O=R),_!==e.I&&(null!=(e.I=_)?J.style.setProperty("padding",_):J.style.removeProperty("padding")),e},{e:void 0,t:void 0,a:void 0,o:void 0,i:void 0,n:void 0,s:void 0,h:void 0,r:void 0,d:void 0,l:void 0,u:void 0,c:void 0,w:void 0,m:void 0,f:void 0,y:void 0,g:void 0,p:void 0,b:void 0,T:void 0,A:void 0,O:void 0,I:void 0}),C}})},oC=()=>{let e=q(),t=x().shadowDOMTarget?R.bind({target:x().shadowDOMTarget}):R,r=(0,l.To)(()=>"dark"===e()?oA(t):oO(t)),{colors:n}=n$,i=(t,r)=>"dark"===e()?r:t,o=oD(e=>{let t=e().getAll().find(e=>e.mutationId===os());return!!t&&t.state.isPaused}),a=oD(e=>{let t=e().getAll().find(e=>e.mutationId===os());return t?t.state.status:"idle"}),s=(0,l.To)(()=>(0,l.TH)({isPaused:o(),status:a()})),d=oD(e=>e().getAll().find(e=>e.mutationId===os()),!1);return(0,l.a0)(l.wv,{get when(){return d()},get children(){var u=oo(),c=u.firstChild,g=c.nextSibling,f=g.firstChild,p=f.firstChild,h=p.firstChild,v=p.nextSibling,y=f.nextSibling.firstChild.nextSibling,b=g.nextSibling,m=b.nextSibling,w=m.nextSibling,k=w.nextSibling,$=k.nextSibling,S=$.nextSibling,C=S.nextSibling,E=C.nextSibling;return(0,l.Yr)(h,(0,l.a0)(l.wv,{get when(){return d().options.mutationKey},fallback:"No mutationKey found",get children(){return(0,l.KN)(d().options.mutationKey,!0)}})),(0,l.Yr)(v,(0,l.a0)(l.wv,{get when(){return"purple"===s()},children:"pending"}),null),(0,l.Yr)(v,(0,l.a0)(l.wv,{get when(){return"purple"!==s()},get children(){return a()}}),null),(0,l.Yr)(y,()=>new Date(d().state.submittedAt).toLocaleTimeString()),(0,l.Yr)(m,(0,l.a0)(iT,{label:"Variables",defaultExpanded:["Variables"],get value(){return d().state.variables}})),(0,l.Yr)(k,(0,l.a0)(iT,{label:"Context",defaultExpanded:["Context"],get value(){return d().state.context}})),(0,l.Yr)(S,(0,l.a0)(iT,{label:"Data",defaultExpanded:["Data"],get value(){return d().state.data}})),(0,l.Yr)(E,(0,l.a0)(iT,{label:"Mutation",defaultExpanded:["Mutation"],get value(){return d()}})),(0,l.gb)(e=>{var o=H(r().detailsContainer,"tsqd-query-details-container"),a=H(r().detailsHeader,"tsqd-query-details-header"),d=H(r().detailsBody,"tsqd-query-details-summary-container"),f=H(r().queryDetailsStatus,"gray"===s()?t`
        background-color: ${i(n[s()][200],n[s()][700])};
        color: ${i(n[s()][700],n[s()][300])};
        border-color: ${i(n[s()][400],n[s()][600])};
      `:t`
      background-color: ${i(n[s()][100],n[s()][900])};
      color: ${i(n[s()][700],n[s()][300])};
      border-color: ${i(n[s()][400],n[s()][600])};
    `),p=H(r().detailsHeader,"tsqd-query-details-header"),h=n$.size[2],y=H(r().detailsHeader,"tsqd-query-details-header"),x=n$.size[2],q=H(r().detailsHeader,"tsqd-query-details-header"),T=n$.size[2],M=H(r().detailsHeader,"tsqd-query-details-header"),F=n$.size[2];return o!==e.e&&(0,l.s7)(u,e.e=o),a!==e.t&&(0,l.s7)(c,e.t=a),d!==e.a&&(0,l.s7)(g,e.a=d),f!==e.o&&(0,l.s7)(v,e.o=f),p!==e.i&&(0,l.s7)(b,e.i=p),h!==e.n&&(null!=(e.n=h)?m.style.setProperty("padding",h):m.style.removeProperty("padding")),y!==e.s&&(0,l.s7)(w,e.s=y),x!==e.h&&(null!=(e.h=x)?k.style.setProperty("padding",x):k.style.removeProperty("padding")),q!==e.r&&(0,l.s7)($,e.r=q),T!==e.d&&(null!=(e.d=T)?S.style.setProperty("padding",T):S.style.removeProperty("padding")),M!==e.l&&(0,l.s7)(C,e.l=M),F!==e.u&&(null!=(e.u=F)?E.style.setProperty("padding",F):E.style.removeProperty("padding")),e},{e:void 0,t:void 0,a:void 0,o:void 0,i:void 0,n:void 0,s:void 0,h:void 0,r:void 0,d:void 0,l:void 0,u:void 0}),u}})},oq=new Map,oE=()=>{let e=(0,l.To)(()=>x().client.getQueryCache()),t=e().subscribe(t=>{(0,l.vA)(()=>{for(let[r,n]of oq.entries())n.shouldUpdate(t)&&n.setter(r(e))})});return(0,l.Ki)(()=>{oq.clear(),t()}),t},oT=(e,t=!0,r=()=>!0)=>{let n=(0,l.To)(()=>x().client.getQueryCache()),[i,o]=(0,l.n5)(e(n),t?void 0:{equals:!1});return(0,l.EH)(()=>{o(e(n))}),oq.set(e,{setter:o,shouldUpdate:r}),(0,l.Ki)(()=>{oq.delete(e)}),i},oM=new Map,oF=()=>{let e=(0,l.To)(()=>x().client.getMutationCache()),t=e().subscribe(()=>{for(let[t,r]of oM.entries())queueMicrotask(()=>{r(t(e))})});return(0,l.Ki)(()=>{oM.clear(),t()}),t},oD=(e,t=!0)=>{let r=(0,l.To)(()=>x().client.getMutationCache()),[n,i]=(0,l.n5)(e(r),t?void 0:{equals:!1});return(0,l.EH)(()=>{i(e(r))}),oM.set(e,i),(0,l.Ki)(()=>{oM.delete(e)}),n},oz=({type:e,queryHash:t,metadata:r})=>{let n=new CustomEvent("@tanstack/query-devtools-event",{detail:{type:e,queryHash:t,metadata:r},bubbles:!0,cancelable:!0});window.dispatchEvent(n)},oL=(e,t)=>{let{colors:r,font:n,size:i,alpha:o,shadow:l,border:a}=n$,s=(t,r)=>"light"===e?t:r;return{devtoolsBtn:t`
      z-index: 100000;
      position: fixed;
      padding: 4px;
      text-align: left;

      display: flex;
      align-items: center;
      justify-content: center;
      border-radius: 9999px;
      box-shadow: ${l.md()};
      overflow: hidden;

      & div {
        position: absolute;
        top: -8px;
        left: -8px;
        right: -8px;
        bottom: -8px;
        border-radius: 9999px;

        & svg {
          position: absolute;
          width: 100%;
          height: 100%;
        }
        filter: blur(6px) saturate(1.2) contrast(1.1);
      }

      &:focus-within {
        outline-offset: 2px;
        outline: 3px solid ${r.green[600]};
      }

      & button {
        position: relative;
        z-index: 1;
        padding: 0;
        border-radius: 9999px;
        background-color: transparent;
        border: none;
        height: 40px;
        display: flex;
        width: 40px;
        overflow: hidden;
        cursor: pointer;
        outline: none;
        & svg {
          position: absolute;
          width: 100%;
          height: 100%;
        }
      }
    `,panel:t`
      position: fixed;
      z-index: 9999;
      display: flex;
      gap: ${n$.size[.5]};
      & * {
        box-sizing: border-box;
        text-transform: none;
      }

      & *::-webkit-scrollbar {
        width: 7px;
      }

      & *::-webkit-scrollbar-track {
        background: transparent;
      }

      & *::-webkit-scrollbar-thumb {
        background: ${s(r.gray[300],r.darkGray[200])};
      }

      & *::-webkit-scrollbar-thumb:hover {
        background: ${s(r.gray[400],r.darkGray[300])};
      }
    `,parentPanel:t`
      z-index: 9999;
      display: flex;
      height: 100%;
      gap: ${n$.size[.5]};
      & * {
        box-sizing: border-box;
        text-transform: none;
      }

      & *::-webkit-scrollbar {
        width: 7px;
      }

      & *::-webkit-scrollbar-track {
        background: transparent;
      }

      & *::-webkit-scrollbar-thumb {
        background: ${s(r.gray[300],r.darkGray[200])};
      }

      & *::-webkit-scrollbar-thumb:hover {
        background: ${s(r.gray[400],r.darkGray[300])};
      }
    `,"devtoolsBtn-position-bottom-right":t`
      bottom: 12px;
      right: 12px;
    `,"devtoolsBtn-position-bottom-left":t`
      bottom: 12px;
      left: 12px;
    `,"devtoolsBtn-position-top-left":t`
      top: 12px;
      left: 12px;
    `,"devtoolsBtn-position-top-right":t`
      top: 12px;
      right: 12px;
    `,"devtoolsBtn-position-relative":t`
      position: relative;
    `,"panel-position-top":t`
      top: 0;
      right: 0;
      left: 0;
      max-height: 90%;
      min-height: ${i[14]};
      border-bottom: ${s(r.gray[400],r.darkGray[300])} 1px solid;
    `,"panel-position-bottom":t`
      bottom: 0;
      right: 0;
      left: 0;
      max-height: 90%;
      min-height: ${i[14]};
      border-top: ${s(r.gray[400],r.darkGray[300])} 1px solid;
    `,"panel-position-right":t`
      bottom: 0;
      right: 0;
      top: 0;
      border-left: ${s(r.gray[400],r.darkGray[300])} 1px solid;
      max-width: 90%;
    `,"panel-position-left":t`
      bottom: 0;
      left: 0;
      top: 0;
      border-right: ${s(r.gray[400],r.darkGray[300])} 1px solid;
      max-width: 90%;
    `,closeBtn:t`
      position: absolute;
      cursor: pointer;
      z-index: 5;
      display: flex;
      align-items: center;
      justify-content: center;
      outline: none;
      background-color: ${s(r.gray[50],r.darkGray[700])};
      &:hover {
        background-color: ${s(r.gray[200],r.darkGray[500])};
      }
      &:focus-visible {
        outline: 2px solid ${r.blue[600]};
      }
      & svg {
        color: ${s(r.gray[600],r.gray[400])};
        width: ${i[2]};
        height: ${i[2]};
      }
    `,"closeBtn-position-top":t`
      bottom: 0;
      right: ${i[2]};
      transform: translate(0, 100%);
      border-right: ${s(r.gray[400],r.darkGray[300])} 1px solid;
      border-left: ${s(r.gray[400],r.darkGray[300])} 1px solid;
      border-top: none;
      border-bottom: ${s(r.gray[400],r.darkGray[300])} 1px solid;
      border-radius: 0px 0px ${a.radius.sm} ${a.radius.sm};
      padding: ${i[.5]} ${i[1.5]} ${i[1]} ${i[1.5]};

      &::after {
        content: ' ';
        position: absolute;
        bottom: 100%;
        left: -${i[2.5]};
        height: ${i[1.5]};
        width: calc(100% + ${i[5]});
      }

      & svg {
        transform: rotate(180deg);
      }
    `,"closeBtn-position-bottom":t`
      top: 0;
      right: ${i[2]};
      transform: translate(0, -100%);
      border-right: ${s(r.gray[400],r.darkGray[300])} 1px solid;
      border-left: ${s(r.gray[400],r.darkGray[300])} 1px solid;
      border-top: ${s(r.gray[400],r.darkGray[300])} 1px solid;
      border-bottom: none;
      border-radius: ${a.radius.sm} ${a.radius.sm} 0px 0px;
      padding: ${i[1]} ${i[1.5]} ${i[.5]} ${i[1.5]};

      &::after {
        content: ' ';
        position: absolute;
        top: 100%;
        left: -${i[2.5]};
        height: ${i[1.5]};
        width: calc(100% + ${i[5]});
      }
    `,"closeBtn-position-right":t`
      bottom: ${i[2]};
      left: 0;
      transform: translate(-100%, 0);
      border-right: none;
      border-left: ${s(r.gray[400],r.darkGray[300])} 1px solid;
      border-top: ${s(r.gray[400],r.darkGray[300])} 1px solid;
      border-bottom: ${s(r.gray[400],r.darkGray[300])} 1px solid;
      border-radius: ${a.radius.sm} 0px 0px ${a.radius.sm};
      padding: ${i[1.5]} ${i[.5]} ${i[1.5]} ${i[1]};

      &::after {
        content: ' ';
        position: absolute;
        left: 100%;
        height: calc(100% + ${i[5]});
        width: ${i[1.5]};
      }

      & svg {
        transform: rotate(-90deg);
      }
    `,"closeBtn-position-left":t`
      bottom: ${i[2]};
      right: 0;
      transform: translate(100%, 0);
      border-left: none;
      border-right: ${s(r.gray[400],r.darkGray[300])} 1px solid;
      border-top: ${s(r.gray[400],r.darkGray[300])} 1px solid;
      border-bottom: ${s(r.gray[400],r.darkGray[300])} 1px solid;
      border-radius: 0px ${a.radius.sm} ${a.radius.sm} 0px;
      padding: ${i[1.5]} ${i[1]} ${i[1.5]} ${i[.5]};

      &::after {
        content: ' ';
        position: absolute;
        right: 100%;
        height: calc(100% + ${i[5]});
        width: ${i[1.5]};
      }

      & svg {
        transform: rotate(90deg);
      }
    `,queriesContainer:t`
      flex: 1 1 700px;
      background-color: ${s(r.gray[50],r.darkGray[700])};
      display: flex;
      flex-direction: column;
      & * {
        font-family: ui-sans-serif, Inter, system-ui, sans-serif, sans-serif;
      }
    `,dragHandle:t`
      position: absolute;
      transition: background-color 0.125s ease;
      &:hover {
        background-color: ${r.purple[400]}${s("",o[90])};
      }
      z-index: 4;
    `,"dragHandle-position-top":t`
      bottom: 0;
      width: 100%;
      height: 3px;
      cursor: ns-resize;
    `,"dragHandle-position-bottom":t`
      top: 0;
      width: 100%;
      height: 3px;
      cursor: ns-resize;
    `,"dragHandle-position-right":t`
      left: 0;
      width: 3px;
      height: 100%;
      cursor: ew-resize;
    `,"dragHandle-position-left":t`
      right: 0;
      width: 3px;
      height: 100%;
      cursor: ew-resize;
    `,row:t`
      display: flex;
      justify-content: space-between;
      align-items: center;
      padding: ${n$.size[2]} ${n$.size[2.5]};
      gap: ${n$.size[2.5]};
      border-bottom: ${s(r.gray[300],r.darkGray[500])} 1px solid;
      align-items: center;
      & > button {
        padding: 0;
        background: transparent;
        border: none;
        display: flex;
        gap: ${i[.5]};
        flex-direction: column;
      }
    `,logoAndToggleContainer:t`
      display: flex;
      gap: ${n$.size[3]};
      align-items: center;
    `,logo:t`
      cursor: pointer;
      display: flex;
      flex-direction: column;
      background-color: transparent;
      border: none;
      gap: ${n$.size[.5]};
      padding: 0px;
      &:hover {
        opacity: 0.7;
      }
      &:focus-visible {
        outline-offset: 4px;
        border-radius: ${a.radius.xs};
        outline: 2px solid ${r.blue[800]};
      }
    `,tanstackLogo:t`
      font-size: ${n.size.md};
      font-weight: ${n.weight.bold};
      line-height: ${n.lineHeight.xs};
      white-space: nowrap;
      color: ${s(r.gray[600],r.gray[300])};
    `,queryFlavorLogo:t`
      font-weight: ${n.weight.semibold};
      font-size: ${n.size.xs};
      background: linear-gradient(
        to right,
        ${s("#ea4037, #ff9b11","#dd524b, #e9a03b")}
      );
      background-clip: text;
      -webkit-background-clip: text;
      line-height: 1;
      -webkit-text-fill-color: transparent;
      white-space: nowrap;
    `,queryStatusContainer:t`
      display: flex;
      gap: ${n$.size[2]};
      height: min-content;
    `,queryStatusTag:t`
      display: flex;
      gap: ${n$.size[1.5]};
      box-sizing: border-box;
      height: ${n$.size[6.5]};
      background: ${s(r.gray[50],r.darkGray[500])};
      color: ${s(r.gray[700],r.gray[300])};
      border-radius: ${n$.border.radius.sm};
      font-size: ${n.size.sm};
      padding: ${n$.size[1]};
      padding-left: ${n$.size[1.5]};
      align-items: center;
      font-weight: ${n.weight.medium};
      border: ${s("1px solid "+r.gray[300],"1px solid transparent")};
      user-select: none;
      position: relative;
      &:focus-visible {
        outline-offset: 2px;
        outline: 2px solid ${r.blue[800]};
      }
    `,queryStatusTagLabel:t`
      font-size: ${n.size.xs};
    `,queryStatusCount:t`
      font-size: ${n.size.xs};
      padding: 0 5px;
      display: flex;
      align-items: center;
      justify-content: center;
      color: ${s(r.gray[500],r.gray[400])};
      background-color: ${s(r.gray[200],r.darkGray[300])};
      border-radius: 2px;
      font-variant-numeric: tabular-nums;
      height: ${n$.size[4.5]};
    `,statusTooltip:t`
      position: absolute;
      z-index: 1;
      background-color: ${s(r.gray[50],r.darkGray[500])};
      top: 100%;
      left: 50%;
      transform: translate(-50%, calc(${n$.size[2]}));
      padding: ${n$.size[.5]} ${n$.size[2]};
      border-radius: ${n$.border.radius.sm};
      font-size: ${n.size.xs};
      border: 1px solid ${s(r.gray[400],r.gray[600])};
      color: ${s(r.gray[600],r.gray[300])};

      &::before {
        top: 0px;
        content: ' ';
        display: block;
        left: 50%;
        transform: translate(-50%, -100%);
        position: absolute;
        border-color: transparent transparent
          ${s(r.gray[400],r.gray[600])} transparent;
        border-style: solid;
        border-width: 7px;
        /* transform: rotate(180deg); */
      }

      &::after {
        top: 0px;
        content: ' ';
        display: block;
        left: 50%;
        transform: translate(-50%, calc(-100% + 2px));
        position: absolute;
        border-color: transparent transparent
          ${s(r.gray[100],r.darkGray[500])} transparent;
        border-style: solid;
        border-width: 7px;
      }
    `,filtersContainer:t`
      display: flex;
      gap: ${n$.size[2]};
      & > button {
        cursor: pointer;
        padding: ${n$.size[.5]} ${n$.size[1.5]} ${n$.size[.5]}
          ${n$.size[2]};
        border-radius: ${n$.border.radius.sm};
        background-color: ${s(r.gray[100],r.darkGray[400])};
        border: 1px solid ${s(r.gray[300],r.darkGray[200])};
        color: ${s(r.gray[700],r.gray[300])};
        font-size: ${n.size.xs};
        display: flex;
        align-items: center;
        line-height: ${n.lineHeight.sm};
        gap: ${n$.size[1.5]};
        max-width: 160px;
        &:focus-visible {
          outline-offset: 2px;
          border-radius: ${a.radius.xs};
          outline: 2px solid ${r.blue[800]};
        }
        & svg {
          width: ${n$.size[3]};
          height: ${n$.size[3]};
          color: ${s(r.gray[500],r.gray[400])};
        }
      }
    `,filterInput:t`
      padding: ${i[.5]} ${i[2]};
      border-radius: ${n$.border.radius.sm};
      background-color: ${s(r.gray[100],r.darkGray[400])};
      display: flex;
      box-sizing: content-box;
      align-items: center;
      gap: ${n$.size[1.5]};
      max-width: 160px;
      min-width: 100px;
      border: 1px solid ${s(r.gray[300],r.darkGray[200])};
      height: min-content;
      color: ${s(r.gray[600],r.gray[400])};
      & > svg {
        width: ${i[3]};
        height: ${i[3]};
      }
      & input {
        font-size: ${n.size.xs};
        width: 100%;
        background-color: ${s(r.gray[100],r.darkGray[400])};
        border: none;
        padding: 0;
        line-height: ${n.lineHeight.sm};
        color: ${s(r.gray[700],r.gray[300])};
        &::placeholder {
          color: ${s(r.gray[700],r.gray[300])};
        }
        &:focus {
          outline: none;
        }
      }

      &:focus-within {
        outline-offset: 2px;
        border-radius: ${a.radius.xs};
        outline: 2px solid ${r.blue[800]};
      }
    `,filterSelect:t`
      padding: ${n$.size[.5]} ${n$.size[2]};
      border-radius: ${n$.border.radius.sm};
      background-color: ${s(r.gray[100],r.darkGray[400])};
      display: flex;
      align-items: center;
      gap: ${n$.size[1.5]};
      box-sizing: content-box;
      max-width: 160px;
      border: 1px solid ${s(r.gray[300],r.darkGray[200])};
      height: min-content;
      & > svg {
        color: ${s(r.gray[600],r.gray[400])};
        width: ${n$.size[2]};
        height: ${n$.size[2]};
      }
      & > select {
        appearance: none;
        color: ${s(r.gray[700],r.gray[300])};
        min-width: 100px;
        line-height: ${n.lineHeight.sm};
        font-size: ${n.size.xs};
        background-color: ${s(r.gray[100],r.darkGray[400])};
        border: none;
        &:focus {
          outline: none;
        }
      }
      &:focus-within {
        outline-offset: 2px;
        border-radius: ${a.radius.xs};
        outline: 2px solid ${r.blue[800]};
      }
    `,actionsContainer:t`
      display: flex;
      gap: ${n$.size[2]};
    `,actionsBtn:t`
      border-radius: ${n$.border.radius.sm};
      background-color: ${s(r.gray[100],r.darkGray[400])};
      border: 1px solid ${s(r.gray[300],r.darkGray[200])};
      width: ${n$.size[6.5]};
      height: ${n$.size[6.5]};
      justify-content: center;
      display: flex;
      align-items: center;
      gap: ${n$.size[1.5]};
      max-width: 160px;
      cursor: pointer;
      padding: 0;
      &:hover {
        background-color: ${s(r.gray[200],r.darkGray[500])};
      }
      & svg {
        color: ${s(r.gray[700],r.gray[300])};
        width: ${n$.size[3]};
        height: ${n$.size[3]};
      }
      &:focus-visible {
        outline-offset: 2px;
        border-radius: ${a.radius.xs};
        outline: 2px solid ${r.blue[800]};
      }
    `,actionsBtnOffline:t`
      & svg {
        stroke: ${s(r.yellow[700],r.yellow[500])};
        fill: ${s(r.yellow[700],r.yellow[500])};
      }
    `,overflowQueryContainer:t`
      flex: 1;
      overflow-y: auto;
      & > div {
        display: flex;
        flex-direction: column;
      }
    `,queryRow:t`
      display: flex;
      align-items: center;
      padding: 0;
      border: none;
      cursor: pointer;
      color: ${s(r.gray[700],r.gray[300])};
      background-color: ${s(r.gray[50],r.darkGray[700])};
      line-height: 1;
      &:focus {
        outline: none;
      }
      &:focus-visible {
        outline-offset: -2px;
        border-radius: ${a.radius.xs};
        outline: 2px solid ${r.blue[800]};
      }
      &:hover .tsqd-query-hash {
        background-color: ${s(r.gray[200],r.darkGray[600])};
      }

      & .tsqd-query-observer-count {
        padding: 0 ${n$.size[1]};
        user-select: none;
        min-width: ${n$.size[6.5]};
        align-self: stretch;
        display: flex;
        align-items: center;
        justify-content: center;
        font-size: ${n.size.xs};
        font-weight: ${n.weight.medium};
        border-bottom-width: 1px;
        border-bottom-style: solid;
        border-bottom: 1px solid ${s(r.gray[300],r.darkGray[700])};
      }
      & .tsqd-query-hash {
        user-select: text;
        font-size: ${n.size.xs};
        display: flex;
        align-items: center;
        min-height: ${n$.size[6]};
        flex: 1;
        padding: ${n$.size[1]} ${n$.size[2]};
        font-family:
          ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas,
          'Liberation Mono', 'Courier New', monospace;
        border-bottom: 1px solid ${s(r.gray[300],r.darkGray[400])};
        text-align: left;
        text-overflow: clip;
        word-break: break-word;
      }

      & .tsqd-query-disabled-indicator {
        align-self: stretch;
        display: flex;
        align-items: center;
        padding: 0 ${n$.size[2]};
        color: ${s(r.gray[800],r.gray[300])};
        background-color: ${s(r.gray[300],r.darkGray[600])};
        border-bottom: 1px solid ${s(r.gray[300],r.darkGray[400])};
        font-size: ${n.size.xs};
      }

      & .tsqd-query-static-indicator {
        align-self: stretch;
        display: flex;
        align-items: center;
        padding: 0 ${n$.size[2]};
        color: ${s(r.teal[800],r.teal[300])};
        background-color: ${s(r.teal[100],r.teal[900])};
        border-bottom: 1px solid ${s(r.teal[300],r.teal[700])};
        font-size: ${n.size.xs};
      }
    `,selectedQueryRow:t`
      background-color: ${s(r.gray[200],r.darkGray[500])};
    `,detailsContainer:t`
      flex: 1 1 700px;
      background-color: ${s(r.gray[50],r.darkGray[700])};
      color: ${s(r.gray[700],r.gray[300])};
      font-family: ui-sans-serif, Inter, system-ui, sans-serif, sans-serif;
      display: flex;
      flex-direction: column;
      overflow-y: auto;
      display: flex;
      text-align: left;
    `,detailsHeader:t`
      font-family: ui-sans-serif, Inter, system-ui, sans-serif, sans-serif;
      position: sticky;
      top: 0;
      z-index: 2;
      background-color: ${s(r.gray[200],r.darkGray[600])};
      padding: ${n$.size[1.5]} ${n$.size[2]};
      font-weight: ${n.weight.medium};
      font-size: ${n.size.xs};
      line-height: ${n.lineHeight.xs};
      text-align: left;
    `,detailsBody:t`
      margin: ${n$.size[1.5]} 0px ${n$.size[2]} 0px;
      & > div {
        display: flex;
        align-items: stretch;
        padding: 0 ${n$.size[2]};
        line-height: ${n.lineHeight.sm};
        justify-content: space-between;
        & > span {
          font-size: ${n.size.xs};
        }
        & > span:nth-child(2) {
          font-variant-numeric: tabular-nums;
        }
      }

      & > div:first-child {
        margin-bottom: ${n$.size[1.5]};
      }

      & code {
        font-family:
          ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas,
          'Liberation Mono', 'Courier New', monospace;
        margin: 0;
        font-size: ${n.size.xs};
        line-height: ${n.lineHeight.xs};
        max-width: 100%;
        white-space: pre-wrap;
        overflow-wrap: anywhere;
        word-break: break-word;
      }

      & pre {
        margin: 0;
        display: flex;
        align-items: center;
      }
    `,queryDetailsStatus:t`
      border: 1px solid ${r.darkGray[200]};
      border-radius: ${n$.border.radius.sm};
      font-weight: ${n.weight.medium};
      padding: ${n$.size[1]} ${n$.size[2.5]};
    `,actionsBody:t`
      flex-wrap: wrap;
      margin: ${n$.size[2]} 0px ${n$.size[2]} 0px;
      display: flex;
      gap: ${n$.size[2]};
      padding: 0px ${n$.size[2]};
      & > button {
        font-family: ui-sans-serif, Inter, system-ui, sans-serif, sans-serif;
        font-size: ${n.size.xs};
        padding: ${n$.size[1]} ${n$.size[2]};
        display: flex;
        border-radius: ${n$.border.radius.sm};
        background-color: ${s(r.gray[100],r.darkGray[600])};
        border: 1px solid ${s(r.gray[300],r.darkGray[400])};
        align-items: center;
        gap: ${n$.size[2]};
        font-weight: ${n.weight.medium};
        line-height: ${n.lineHeight.xs};
        cursor: pointer;
        &:focus-visible {
          outline-offset: 2px;
          border-radius: ${a.radius.xs};
          outline: 2px solid ${r.blue[800]};
        }
        &:hover {
          background-color: ${s(r.gray[200],r.darkGray[500])};
        }

        &:disabled {
          opacity: 0.6;
          cursor: not-allowed;
        }

        & > span {
          width: ${i[1.5]};
          height: ${i[1.5]};
          border-radius: ${n$.border.radius.full};
        }
      }
    `,actionsSelect:t`
      font-size: ${n.size.xs};
      padding: ${n$.size[.5]} ${n$.size[2]};
      display: flex;
      border-radius: ${n$.border.radius.sm};
      overflow: hidden;
      background-color: ${s(r.gray[100],r.darkGray[600])};
      border: 1px solid ${s(r.gray[300],r.darkGray[400])};
      align-items: center;
      gap: ${n$.size[2]};
      font-weight: ${n.weight.medium};
      line-height: ${n.lineHeight.sm};
      color: ${s(r.red[500],r.red[400])};
      cursor: pointer;
      position: relative;
      &:hover {
        background-color: ${s(r.gray[200],r.darkGray[500])};
      }
      & > span {
        width: ${i[1.5]};
        height: ${i[1.5]};
        border-radius: ${n$.border.radius.full};
      }
      &:focus-within {
        outline-offset: 2px;
        border-radius: ${a.radius.xs};
        outline: 2px solid ${r.blue[800]};
      }
      & select {
        position: absolute;
        top: 0;
        left: 0;
        width: 100%;
        height: 100%;
        appearance: none;
        background-color: transparent;
        border: none;
        color: transparent;
        outline: none;
      }

      & svg path {
        stroke: ${n$.colors.red[400]};
      }
      & svg {
        width: ${n$.size[2]};
        height: ${n$.size[2]};
      }
    `,settingsMenu:t`
      display: flex;
      & * {
        font-family: ui-sans-serif, Inter, system-ui, sans-serif, sans-serif;
      }
      flex-direction: column;
      gap: ${i[.5]};
      border-radius: ${n$.border.radius.sm};
      border: 1px solid ${s(r.gray[300],r.gray[700])};
      background-color: ${s(r.gray[50],r.darkGray[600])};
      font-size: ${n.size.xs};
      color: ${s(r.gray[700],r.gray[300])};
      z-index: 99999;
      min-width: 120px;
      padding: ${i[.5]};
    `,settingsSubTrigger:t`
      display: flex;
      align-items: center;
      justify-content: space-between;
      border-radius: ${n$.border.radius.xs};
      padding: ${n$.size[1]} ${n$.size[1]};
      cursor: pointer;
      background-color: transparent;
      border: none;
      color: ${s(r.gray[700],r.gray[300])};
      & svg {
        color: ${s(r.gray[600],r.gray[400])};
        transform: rotate(-90deg);
        width: ${n$.size[2]};
        height: ${n$.size[2]};
      }
      &:hover {
        background-color: ${s(r.gray[200],r.darkGray[500])};
      }
      &:focus-visible {
        outline-offset: 2px;
        outline: 2px solid ${r.blue[800]};
      }
      &.data-disabled {
        opacity: 0.6;
        cursor: not-allowed;
      }
    `,settingsMenuHeader:t`
      padding: ${n$.size[1]} ${n$.size[1]};
      font-weight: ${n.weight.medium};
      border-bottom: 1px solid ${s(r.gray[300],r.darkGray[400])};
      color: ${s(r.gray[500],r.gray[400])};
      font-size: ${n.size.xs};
    `,settingsSubButton:t`
      display: flex;
      align-items: center;
      justify-content: space-between;
      color: ${s(r.gray[700],r.gray[300])};
      font-size: ${n.size.xs};
      border-radius: ${n$.border.radius.xs};
      padding: ${n$.size[1]} ${n$.size[1]};
      cursor: pointer;
      background-color: transparent;
      border: none;
      & svg {
        color: ${s(r.gray[600],r.gray[400])};
      }
      &:hover {
        background-color: ${s(r.gray[200],r.darkGray[500])};
      }
      &:focus-visible {
        outline-offset: 2px;
        outline: 2px solid ${r.blue[800]};
      }
      &[data-checked] {
        background-color: ${s(r.purple[100],r.purple[900])};
        color: ${s(r.purple[700],r.purple[300])};
        & svg {
          color: ${s(r.purple[700],r.purple[300])};
        }
        &:hover {
          background-color: ${s(r.purple[100],r.purple[900])};
        }
      }
    `,viewToggle:t`
      border-radius: ${n$.border.radius.sm};
      background-color: ${s(r.gray[200],r.darkGray[600])};
      border: 1px solid ${s(r.gray[300],r.darkGray[200])};
      display: flex;
      padding: 0;
      font-size: ${n.size.xs};
      color: ${s(r.gray[700],r.gray[300])};
      overflow: hidden;

      &:has(:focus-visible) {
        outline: 2px solid ${r.blue[800]};
      }

      & .tsqd-radio-toggle {
        opacity: 0.5;
        display: flex;
        & label {
          display: flex;
          align-items: center;
          cursor: pointer;
          line-height: ${n.lineHeight.md};
        }

        & label:hover {
          background-color: ${s(r.gray[100],r.darkGray[500])};
        }
      }

      & > [data-checked] {
        opacity: 1;
        background-color: ${s(r.gray[100],r.darkGray[400])};
        & label:hover {
          background-color: ${s(r.gray[100],r.darkGray[400])};
        }
      }

      & .tsqd-radio-toggle:first-child {
        & label {
          padding: 0 ${n$.size[1.5]} 0 ${n$.size[2]};
        }
        border-right: 1px solid ${s(r.gray[300],r.darkGray[200])};
      }

      & .tsqd-radio-toggle:nth-child(2) {
        & label {
          padding: 0 ${n$.size[2]} 0 ${n$.size[1.5]};
        }
      }
    `,devtoolsEditForm:t`
      padding: ${i[2]};
      & > [data-error='true'] {
        outline: 2px solid ${s(r.red[200],r.red[800])};
        outline-offset: 2px;
        border-radius: ${a.radius.xs};
      }
    `,devtoolsEditTextarea:t`
      width: 100%;
      max-height: 500px;
      font-family: 'Fira Code', monospace;
      font-size: ${n.size.xs};
      border-radius: ${a.radius.sm};
      field-sizing: content;
      padding: ${i[2]};
      background-color: ${s(r.gray[100],r.darkGray[800])};
      color: ${s(r.gray[900],r.gray[100])};
      border: 1px solid ${s(r.gray[200],r.gray[700])};
      resize: none;
      &:focus {
        outline-offset: 2px;
        border-radius: ${a.radius.xs};
        outline: 2px solid ${s(r.blue[200],r.blue[800])};
      }
    `,devtoolsEditFormActions:t`
      display: flex;
      justify-content: space-between;
      gap: ${i[2]};
      align-items: center;
      padding-top: ${i[1]};
      font-size: ${n.size.xs};
    `,devtoolsEditFormError:t`
      color: ${s(r.red[700],r.red[500])};
    `,devtoolsEditFormActionContainer:t`
      display: flex;
      gap: ${i[2]};
    `,devtoolsEditFormAction:t`
      font-family: ui-sans-serif, Inter, system-ui, sans-serif, sans-serif;
      font-size: ${n.size.xs};
      padding: ${i[1]} ${n$.size[2]};
      display: flex;
      border-radius: ${a.radius.sm};
      background-color: ${s(r.gray[100],r.darkGray[600])};
      border: 1px solid ${s(r.gray[300],r.darkGray[400])};
      align-items: center;
      gap: ${i[2]};
      font-weight: ${n.weight.medium};
      line-height: ${n.lineHeight.xs};
      cursor: pointer;
      &:focus-visible {
        outline-offset: 2px;
        border-radius: ${a.radius.xs};
        outline: 2px solid ${r.blue[800]};
      }
      &:hover {
        background-color: ${s(r.gray[200],r.darkGray[500])};
      }

      &:disabled {
        opacity: 0.6;
        cursor: not-allowed;
      }
    `}},oO=e=>oL("light",e),oA=e=>oL("dark",e);(0,l.z_)(["click","mousedown","input"])}}]);
//# sourceMappingURL=39749-9d78be974b4e.js.map
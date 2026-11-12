performance.mark(`js-parse-end:BaseTanStackRouterDevtoolsPanel-B43j38ty-CQ3_tCR6.js`);import{dm as e,fm as t,um as n,wp as r}from"./main-D0KdNlO7.js";import{C as i,D as a,E as o,O as s,T as c,_ as l,a as u,b as d,c as f,d as p,f as m,g as h,i as g,l as _,m as v,o as y,p as b,r as x,s as S,u as C,w,x as T,y as E}from"./context-D56_tqst-VgMET_OM.js";var D=!0,O=`Invariant failed`;function k(e,t){if(!e){if(D)throw Error(O);var n=typeof t==`function`?t():t,r=n?`${O}: ${n}`:O;throw Error(r)}}var A={data:``},j=e=>{if(typeof window==`object`){let t=(e?e.querySelector(`#_goober`):window._goober)||Object.assign(document.createElement(`style`),{innerHTML:` `,id:`_goober`});return t.nonce=window.__nonce__,t.parentNode||(e||document.head).appendChild(t),t.firstChild}return e||A},M=/(?:([\u0080-\uFFFF\w-%@]+) *:? *([^{;]+?);|([^;}{]*?) *{)|(}\s*)/g,N=/\/\*[^]*?\*\/|  +/g,P=/\n+/g,F=(e,t)=>{let n=``,r=``,i=``;for(let a in e){let o=e[a];a[0]==`@`?a[1]==`i`?n=a+` `+o+`;`:r+=a[1]==`f`?F(o,a):a+`{`+F(o,a[1]==`k`?``:t)+`}`:typeof o==`object`?r+=F(o,t?t.replace(/([^,])+/g,e=>a.replace(/([^,]*:\S+\([^)]*\))|([^,])+/g,t=>/&/.test(t)?t.replace(/&/g,e):e?e+` `+t:t)):a):o!=null&&(a=/^--/.test(a)?a:a.replace(/[A-Z]/g,`-$&`).toLowerCase(),i+=F.p?F.p(a,o):a+`:`+o+`;`)}return n+(t&&i?t+`{`+i+`}`:i)+r},I={},L=e=>{if(typeof e==`object`){let t=``;for(let n in e)t+=n+L(e[n]);return t}return e},R=(e,t,n,r,i)=>{let a=L(e),o=I[a]||(I[a]=(e=>{let t=0,n=11;for(;t<e.length;)n=101*n+e.charCodeAt(t++)>>>0;return`go`+n})(a));if(!I[o]){let t=a===e?(e=>{let t,n,r=[{}];for(;t=M.exec(e.replace(N,``));)t[4]?r.shift():t[3]?(n=t[3].replace(P,` `).trim(),r.unshift(r[0][n]=r[0][n]||{})):r[0][t[1]]=t[2].replace(P,` `).trim();return r[0]})(e):e;I[o]=F(i?{[`@keyframes `+o]:t}:t,n?``:`.`+o)}let s=n&&I.g?I.g:null;return n&&(I.g=I[o]),((e,t,n,r)=>{r?t.data=t.data.replace(r,e):t.data.indexOf(e)===-1&&(t.data=n?e+t.data:t.data+e)})(I[o],t,r,s),o},ee=(e,t,n)=>e.reduce((e,r,i)=>{let a=t[i];if(a&&a.call){let e=a(n),t=e&&e.props&&e.props.className||/^go/.test(e)&&e;a=t?`.`+t:e&&typeof e==`object`?e.props?``:F(e,``):!1===e?``:e}return e+r+(a??``)},``);function z(e){let t=this||{},n=e.call?e(t.p):e;return R(n.unshift?n.raw?ee(n,[].slice.call(arguments,1),t.p):n.reduce((e,n)=>Object.assign(e,n&&n.call?n(t.p):n),{}):n,j(t.target),t.g,t.o,t.k)}z.bind({g:1}),z.bind({k:1});var B={colors:{inherit:`inherit`,current:`currentColor`,transparent:`transparent`,black:`#000000`,white:`#ffffff`,neutral:{50:`#f9fafb`,100:`#f2f4f7`,200:`#eaecf0`,300:`#d0d5dd`,400:`#98a2b3`,500:`#667085`,600:`#475467`,700:`#344054`,800:`#1d2939`,900:`#101828`},darkGray:{50:`#525c7a`,100:`#49536e`,200:`#414962`,300:`#394056`,400:`#313749`,500:`#292e3d`,600:`#212530`,700:`#191c24`,800:`#111318`,900:`#0b0d10`},gray:{50:`#f9fafb`,100:`#f2f4f7`,200:`#eaecf0`,300:`#d0d5dd`,400:`#98a2b3`,500:`#667085`,600:`#475467`,700:`#344054`,800:`#1d2939`,900:`#101828`},blue:{25:`#F5FAFF`,50:`#EFF8FF`,100:`#D1E9FF`,200:`#B2DDFF`,300:`#84CAFF`,400:`#53B1FD`,500:`#2E90FA`,600:`#1570EF`,700:`#175CD3`,800:`#1849A9`,900:`#194185`},green:{25:`#F6FEF9`,50:`#ECFDF3`,100:`#D1FADF`,200:`#A6F4C5`,300:`#6CE9A6`,400:`#32D583`,500:`#12B76A`,600:`#039855`,700:`#027A48`,800:`#05603A`,900:`#054F31`},red:{50:`#fef2f2`,100:`#fee2e2`,200:`#fecaca`,300:`#fca5a5`,400:`#f87171`,500:`#ef4444`,600:`#dc2626`,700:`#b91c1c`,800:`#991b1b`,900:`#7f1d1d`,950:`#450a0a`},yellow:{25:`#FFFCF5`,50:`#FFFAEB`,100:`#FEF0C7`,200:`#FEDF89`,300:`#FEC84B`,400:`#FDB022`,500:`#F79009`,600:`#DC6803`,700:`#B54708`,800:`#93370D`,900:`#7A2E0E`},purple:{25:`#FAFAFF`,50:`#F4F3FF`,100:`#EBE9FE`,200:`#D9D6FE`,300:`#BDB4FE`,400:`#9B8AFB`,500:`#7A5AF8`,600:`#6938EF`,700:`#5925DC`,800:`#4A1FB8`,900:`#3E1C96`},teal:{25:`#F6FEFC`,50:`#F0FDF9`,100:`#CCFBEF`,200:`#99F6E0`,300:`#5FE9D0`,400:`#2ED3B7`,500:`#15B79E`,600:`#0E9384`,700:`#107569`,800:`#125D56`,900:`#134E48`},pink:{25:`#fdf2f8`,50:`#fce7f3`,100:`#fbcfe8`,200:`#f9a8d4`,300:`#f472b6`,400:`#ec4899`,500:`#db2777`,600:`#be185d`,700:`#9d174d`,800:`#831843`,900:`#500724`},cyan:{25:`#ecfeff`,50:`#cffafe`,100:`#a5f3fc`,200:`#67e8f9`,300:`#22d3ee`,400:`#06b6d4`,500:`#0891b2`,600:`#0e7490`,700:`#155e75`,800:`#164e63`,900:`#083344`}},alpha:{100:`ff`,90:`e5`,80:`cc`,70:`b3`,60:`99`,50:`80`,40:`66`,30:`4d`,20:`33`,10:`1a`,0:`00`},font:{size:{"2xs":`calc(var(--tsrd-font-size) * 0.625)`,xs:`calc(var(--tsrd-font-size) * 0.75)`,sm:`calc(var(--tsrd-font-size) * 0.875)`,md:`var(--tsrd-font-size)`,lg:`calc(var(--tsrd-font-size) * 1.125)`,xl:`calc(var(--tsrd-font-size) * 1.25)`,"2xl":`calc(var(--tsrd-font-size) * 1.5)`,"3xl":`calc(var(--tsrd-font-size) * 1.875)`,"4xl":`calc(var(--tsrd-font-size) * 2.25)`,"5xl":`calc(var(--tsrd-font-size) * 3)`,"6xl":`calc(var(--tsrd-font-size) * 3.75)`,"7xl":`calc(var(--tsrd-font-size) * 4.5)`,"8xl":`calc(var(--tsrd-font-size) * 6)`,"9xl":`calc(var(--tsrd-font-size) * 8)`},lineHeight:{"3xs":`calc(var(--tsrd-font-size) * 0.75)`,"2xs":`calc(var(--tsrd-font-size) * 0.875)`,xs:`calc(var(--tsrd-font-size) * 1)`,sm:`calc(var(--tsrd-font-size) * 1.25)`,md:`calc(var(--tsrd-font-size) * 1.5)`,lg:`calc(var(--tsrd-font-size) * 1.75)`,xl:`calc(var(--tsrd-font-size) * 2)`,"2xl":`calc(var(--tsrd-font-size) * 2.25)`,"3xl":`calc(var(--tsrd-font-size) * 2.5)`,"4xl":`calc(var(--tsrd-font-size) * 2.75)`,"5xl":`calc(var(--tsrd-font-size) * 3)`,"6xl":`calc(var(--tsrd-font-size) * 3.25)`,"7xl":`calc(var(--tsrd-font-size) * 3.5)`,"8xl":`calc(var(--tsrd-font-size) * 3.75)`,"9xl":`calc(var(--tsrd-font-size) * 4)`},weight:{thin:`100`,extralight:`200`,light:`300`,normal:`400`,medium:`500`,semibold:`600`,bold:`700`,extrabold:`800`,black:`900`},fontFamily:{sans:`ui-sans-serif, Inter, system-ui, sans-serif, sans-serif`,mono:`ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, 'Liberation Mono', 'Courier New', monospace`}},breakpoints:{xs:`320px`,sm:`640px`,md:`768px`,lg:`1024px`,xl:`1280px`,"2xl":`1536px`},border:{radius:{none:`0px`,xs:`calc(var(--tsrd-font-size) * 0.125)`,sm:`calc(var(--tsrd-font-size) * 0.25)`,md:`calc(var(--tsrd-font-size) * 0.375)`,lg:`calc(var(--tsrd-font-size) * 0.5)`,xl:`calc(var(--tsrd-font-size) * 0.75)`,"2xl":`calc(var(--tsrd-font-size) * 1)`,"3xl":`calc(var(--tsrd-font-size) * 1.5)`,full:`9999px`}},size:{0:`0px`,.25:`calc(var(--tsrd-font-size) * 0.0625)`,.5:`calc(var(--tsrd-font-size) * 0.125)`,1:`calc(var(--tsrd-font-size) * 0.25)`,1.5:`calc(var(--tsrd-font-size) * 0.375)`,2:`calc(var(--tsrd-font-size) * 0.5)`,2.5:`calc(var(--tsrd-font-size) * 0.625)`,3:`calc(var(--tsrd-font-size) * 0.75)`,3.5:`calc(var(--tsrd-font-size) * 0.875)`,4:`calc(var(--tsrd-font-size) * 1)`,4.5:`calc(var(--tsrd-font-size) * 1.125)`,5:`calc(var(--tsrd-font-size) * 1.25)`,5.5:`calc(var(--tsrd-font-size) * 1.375)`,6:`calc(var(--tsrd-font-size) * 1.5)`,6.5:`calc(var(--tsrd-font-size) * 1.625)`,7:`calc(var(--tsrd-font-size) * 1.75)`,8:`calc(var(--tsrd-font-size) * 2)`,9:`calc(var(--tsrd-font-size) * 2.25)`,10:`calc(var(--tsrd-font-size) * 2.5)`,11:`calc(var(--tsrd-font-size) * 2.75)`,12:`calc(var(--tsrd-font-size) * 3)`,14:`calc(var(--tsrd-font-size) * 3.5)`,16:`calc(var(--tsrd-font-size) * 4)`,20:`calc(var(--tsrd-font-size) * 5)`,24:`calc(var(--tsrd-font-size) * 6)`,28:`calc(var(--tsrd-font-size) * 7)`,32:`calc(var(--tsrd-font-size) * 8)`,36:`calc(var(--tsrd-font-size) * 9)`,40:`calc(var(--tsrd-font-size) * 10)`,44:`calc(var(--tsrd-font-size) * 11)`,48:`calc(var(--tsrd-font-size) * 12)`,52:`calc(var(--tsrd-font-size) * 13)`,56:`calc(var(--tsrd-font-size) * 14)`,60:`calc(var(--tsrd-font-size) * 15)`,64:`calc(var(--tsrd-font-size) * 16)`,72:`calc(var(--tsrd-font-size) * 18)`,80:`calc(var(--tsrd-font-size) * 20)`,96:`calc(var(--tsrd-font-size) * 24)`},shadow:{xs:(e=`rgb(0 0 0 / 0.1)`)=>`0 1px 2px 0 rgb(0 0 0 / 0.05)`,sm:(e=`rgb(0 0 0 / 0.1)`)=>`0 1px 3px 0 ${e}, 0 1px 2px -1px ${e}`,md:(e=`rgb(0 0 0 / 0.1)`)=>`0 4px 6px -1px ${e}, 0 2px 4px -2px ${e}`,lg:(e=`rgb(0 0 0 / 0.1)`)=>`0 10px 15px -3px ${e}, 0 4px 6px -4px ${e}`,xl:(e=`rgb(0 0 0 / 0.1)`)=>`0 20px 25px -5px ${e}, 0 8px 10px -6px ${e}`,"2xl":(e=`rgb(0 0 0 / 0.25)`)=>`0 25px 50px -12px ${e}`,inner:(e=`rgb(0 0 0 / 0.05)`)=>`inset 0 2px 4px 0 ${e}`,none:()=>`none`},zIndices:{hide:-1,auto:`auto`,base:0,docked:10,dropdown:1e3,sticky:1100,banner:1200,overlay:1300,modal:1400,popover:1500,skipLink:1600,toast:1700,tooltip:1800}},te=e=>{let{colors:t,font:n,size:r,alpha:i,shadow:a,border:o}=B,{fontFamily:s,lineHeight:c,size:l}=n,u=e?z.bind({target:e}):z;return{devtoolsPanelContainer:u`
      direction: ltr;
      position: fixed;
      bottom: 0;
      right: 0;
      z-index: 99999;
      width: 100%;
      max-height: 90%;
      border-top: 1px solid ${t.gray[700]};
      transform-origin: top;
    `,devtoolsPanelContainerVisibility:e=>u`
        visibility: ${e?`visible`:`hidden`};
      `,devtoolsPanelContainerResizing:e=>e()?u`
          transition: none;
        `:u`
        transition: all 0.4s ease;
      `,devtoolsPanelContainerAnimation:(e,t)=>e?u`
          pointer-events: auto;
          transform: translateY(0);
        `:u`
        pointer-events: none;
        transform: translateY(${t}px);
      `,logo:u`
      cursor: pointer;
      display: flex;
      flex-direction: column;
      background-color: transparent;
      border: none;
      font-family: ${s.sans};
      gap: ${B.size[.5]};
      padding: 0px;
      &:hover {
        opacity: 0.7;
      }
      &:focus-visible {
        outline-offset: 4px;
        border-radius: ${o.radius.xs};
        outline: 2px solid ${t.blue[800]};
      }
    `,tanstackLogo:u`
      font-size: ${n.size.md};
      font-weight: ${n.weight.bold};
      line-height: ${n.lineHeight.xs};
      white-space: nowrap;
      color: ${t.gray[300]};
    `,routerLogo:u`
      font-weight: ${n.weight.semibold};
      font-size: ${n.size.xs};
      background: linear-gradient(to right, #84cc16, #10b981);
      background-clip: text;
      -webkit-background-clip: text;
      line-height: 1;
      -webkit-text-fill-color: transparent;
      white-space: nowrap;
    `,devtoolsPanel:u`
      display: flex;
      font-size: ${l.sm};
      font-family: ${s.sans};
      background-color: ${t.darkGray[700]};
      color: ${t.gray[300]};

      @media (max-width: 700px) {
        flex-direction: column;
      }
      @media (max-width: 600px) {
        font-size: ${l.xs};
      }
    `,dragHandle:u`
      position: absolute;
      left: 0;
      top: 0;
      width: 100%;
      height: 4px;
      cursor: row-resize;
      z-index: 100000;
      &:hover {
        background-color: ${t.purple[400]}${i[90]};
      }
    `,firstContainer:u`
      flex: 1 1 500px;
      min-height: 40%;
      max-height: 100%;
      overflow: auto;
      border-right: 1px solid ${t.gray[700]};
      display: flex;
      flex-direction: column;
    `,routerExplorerContainer:u`
      overflow-y: auto;
      flex: 1;
    `,routerExplorer:u`
      padding: ${B.size[2]};
    `,row:u`
      display: flex;
      align-items: center;
      padding: ${B.size[2]} ${B.size[2.5]};
      gap: ${B.size[2.5]};
      border-bottom: ${t.darkGray[500]} 1px solid;
      align-items: center;
    `,detailsHeader:u`
      font-family: ui-sans-serif, Inter, system-ui, sans-serif, sans-serif;
      position: sticky;
      top: 0;
      z-index: 2;
      background-color: ${t.darkGray[600]};
      padding: 0px ${B.size[2]};
      font-weight: ${n.weight.medium};
      font-size: ${n.size.xs};
      min-height: ${B.size[8]};
      line-height: ${n.lineHeight.xs};
      text-align: left;
      display: flex;
      align-items: center;
    `,maskedBadge:u`
      background: ${t.yellow[900]}${i[70]};
      color: ${t.yellow[300]};
      display: inline-block;
      padding: ${B.size[0]} ${B.size[2.5]};
      border-radius: ${o.radius.full};
      font-size: ${n.size.xs};
      font-weight: ${n.weight.normal};
      border: 1px solid ${t.yellow[300]};
    `,maskedLocation:u`
      color: ${t.yellow[300]};
    `,detailsContent:u`
      padding: ${B.size[1.5]} ${B.size[2]};
      display: flex;
      align-items: center;
      justify-content: space-between;
      font-size: ${n.size.xs};
    `,routeMatchesToggle:u`
      display: flex;
      align-items: center;
      border: 1px solid ${t.gray[500]};
      border-radius: ${o.radius.sm};
      overflow: hidden;
    `,routeMatchesToggleBtn:(e,r)=>{let a=[u`
        appearance: none;
        border: none;
        font-size: 12px;
        padding: 4px 8px;
        background: transparent;
        cursor: pointer;
        font-family: ${s.sans};
        font-weight: ${n.weight.medium};
      `];if(e){let e=u`
          background: ${t.darkGray[400]};
          color: ${t.gray[300]};
        `;a.push(e)}else{let e=u`
          color: ${t.gray[500]};
          background: ${t.darkGray[800]}${i[20]};
        `;a.push(e)}return r&&a.push(u`
          border-right: 1px solid ${B.colors.gray[500]};
        `),a},detailsHeaderInfo:u`
      flex: 1;
      justify-content: flex-end;
      display: flex;
      align-items: center;
      font-weight: ${n.weight.normal};
      color: ${t.gray[400]};
    `,matchRow:e=>{let n=[u`
        display: flex;
        border-bottom: 1px solid ${t.darkGray[400]};
        cursor: pointer;
        align-items: center;
        padding: ${r[1]} ${r[2]};
        gap: ${r[2]};
        font-size: ${l.xs};
        color: ${t.gray[300]};
      `];if(e){let e=u`
          background: ${t.darkGray[500]};
        `;n.push(e)}return n},matchIndicator:e=>{let n=[u`
        flex: 0 0 auto;
        width: ${r[3]};
        height: ${r[3]};
        background: ${t[e][900]};
        border: 1px solid ${t[e][500]};
        border-radius: ${o.radius.full};
        transition: all 0.25s ease-out;
        box-sizing: border-box;
      `];if(e===`gray`){let e=u`
          background: ${t.gray[700]};
          border-color: ${t.gray[400]};
        `;n.push(e)}return n},matchID:u`
      flex: 1;
      line-height: ${c.xs};
    `,ageTicker:e=>{let n=[u`
        display: flex;
        gap: ${r[1]};
        font-size: ${l.xs};
        color: ${t.gray[400]};
        font-variant-numeric: tabular-nums;
        line-height: ${c.xs};
      `];if(e){let e=u`
          color: ${t.yellow[400]};
        `;n.push(e)}return n},secondContainer:u`
      flex: 1 1 500px;
      min-height: 40%;
      max-height: 100%;
      overflow: auto;
      border-right: 1px solid ${t.gray[700]};
      display: flex;
      flex-direction: column;
    `,thirdContainer:u`
      flex: 1 1 500px;
      overflow: auto;
      display: flex;
      flex-direction: column;
      height: 100%;
      border-right: 1px solid ${t.gray[700]};

      @media (max-width: 700px) {
        border-top: 2px solid ${t.gray[700]};
      }
    `,fourthContainer:u`
      flex: 1 1 500px;
      min-height: 40%;
      max-height: 100%;
      overflow: auto;
      display: flex;
      flex-direction: column;
    `,routesContainer:u`
      overflow-x: auto;
      overflow-y: visible;
    `,routesRowContainer:(e,n)=>{let i=[u`
        display: flex;
        border-bottom: 1px solid ${t.darkGray[400]};
        align-items: center;
        padding: ${r[1]} ${r[2]};
        gap: ${r[2]};
        font-size: ${l.xs};
        color: ${t.gray[300]};
        cursor: ${n?`pointer`:`default`};
        line-height: ${c.xs};
      `];if(e){let e=u`
          background: ${t.darkGray[500]};
        `;i.push(e)}return i},routesRow:e=>{let n=[u`
        flex: 1 0 auto;
        display: flex;
        justify-content: space-between;
        align-items: center;
        font-size: ${l.xs};
        line-height: ${c.xs};
      `];if(!e){let e=u`
          color: ${t.gray[400]};
        `;n.push(e)}return n},routesRowInner:u`
      display: 'flex';
      align-items: 'center';
      flex-grow: 1;
      min-width: 0;
    `,routeParamInfo:u`
      color: ${t.gray[400]};
      font-size: ${l.xs};
      line-height: ${c.xs};
    `,nestedRouteRow:e=>u`
        margin-left: ${e?0:r[3.5]};
        border-left: ${e?``:`solid 1px ${t.gray[700]}`};
      `,code:u`
      font-size: ${l.xs};
      line-height: ${c.xs};
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
    `,matchesContainer:u`
      flex: 1 1 auto;
      overflow-y: auto;
    `,cachedMatchesContainer:u`
      flex: 1 1 auto;
      overflow-y: auto;
      max-height: 50%;
    `,historyContainer:u`
      display: flex;
      flex: 1 1 auto;
      overflow-y: auto;
      max-height: 50%;
    `,historyOverflowContainer:u`
      padding: ${r[1]} ${r[2]};
      font-size: ${B.font.size.xs};
    `,maskedBadgeContainer:u`
      flex: 1;
      justify-content: flex-end;
      display: flex;
    `,matchDetails:u`
      display: flex;
      flex-direction: column;
      padding: ${B.size[2]};
      font-size: ${B.font.size.xs};
      color: ${B.colors.gray[300]};
      line-height: ${B.font.lineHeight.sm};
    `,matchStatus:(e,t)=>{let n=t&&e===`success`?t===`beforeLoad`?`purple`:`blue`:{pending:`yellow`,success:`green`,error:`red`,notFound:`purple`,redirected:`gray`}[e];return u`
        display: flex;
        justify-content: center;
        align-items: center;
        height: 40px;
        border-radius: ${B.border.radius.sm};
        font-weight: ${B.font.weight.normal};
        background-color: ${B.colors[n][900]}${B.alpha[90]};
        color: ${B.colors[n][300]};
        border: 1px solid ${B.colors[n][600]};
        margin-bottom: ${B.size[2]};
        transition: all 0.25s ease-out;
      `},matchDetailsInfo:u`
      display: flex;
      justify-content: flex-end;
      flex: 1;
    `,matchDetailsInfoLabel:u`
      display: flex;
    `,mainCloseBtn:u`
      background: ${t.darkGray[700]};
      padding: ${r[1]} ${r[2]} ${r[1]} ${r[1.5]};
      border-radius: ${o.radius.md};
      position: fixed;
      z-index: 99999;
      display: inline-flex;
      width: fit-content;
      cursor: pointer;
      appearance: none;
      border: 0;
      gap: 8px;
      align-items: center;
      border: 1px solid ${t.gray[500]};
      font-size: ${n.size.xs};
      cursor: pointer;
      transition: all 0.25s ease-out;

      &:hover {
        background: ${t.darkGray[500]};
      }
    `,mainCloseBtnPosition:e=>u`
        ${e===`top-left`?`top: ${r[2]}; left: ${r[2]};`:``}
        ${e===`top-right`?`top: ${r[2]}; right: ${r[2]};`:``}
        ${e===`bottom-left`?`bottom: ${r[2]}; left: ${r[2]};`:``}
        ${e===`bottom-right`?`bottom: ${r[2]}; right: ${r[2]};`:``}
      `,mainCloseBtnAnimation:e=>e?u`
        opacity: 0;
        pointer-events: none;
        visibility: hidden;
      `:u`
          opacity: 1;
          pointer-events: auto;
          visibility: visible;
        `,routerLogoCloseButton:u`
      font-weight: ${n.weight.semibold};
      font-size: ${n.size.xs};
      background: linear-gradient(to right, #98f30c, #00f4a3);
      background-clip: text;
      -webkit-background-clip: text;
      line-height: 1;
      -webkit-text-fill-color: transparent;
      white-space: nowrap;
    `,mainCloseBtnDivider:u`
      width: 1px;
      background: ${B.colors.gray[600]};
      height: 100%;
      border-radius: 999999px;
      color: transparent;
    `,mainCloseBtnIconContainer:u`
      position: relative;
      width: ${r[5]};
      height: ${r[5]};
      background: pink;
      border-radius: 999999px;
      overflow: hidden;
    `,mainCloseBtnIconOuter:u`
      width: ${r[5]};
      height: ${r[5]};
      position: absolute;
      top: 50%;
      left: 50%;
      transform: translate(-50%, -50%);
      filter: blur(3px) saturate(1.8) contrast(2);
    `,mainCloseBtnIconInner:u`
      width: ${r[4]};
      height: ${r[4]};
      position: absolute;
      top: 50%;
      left: 50%;
      transform: translate(-50%, -50%);
    `,panelCloseBtn:u`
      position: absolute;
      cursor: pointer;
      z-index: 100001;
      display: flex;
      align-items: center;
      justify-content: center;
      outline: none;
      background-color: ${t.darkGray[700]};
      &:hover {
        background-color: ${t.darkGray[500]};
      }

      top: 0;
      right: ${r[2]};
      transform: translate(0, -100%);
      border-right: ${t.darkGray[300]} 1px solid;
      border-left: ${t.darkGray[300]} 1px solid;
      border-top: ${t.darkGray[300]} 1px solid;
      border-bottom: none;
      border-radius: ${o.radius.sm} ${o.radius.sm} 0px 0px;
      padding: ${r[1]} ${r[1.5]} ${r[.5]} ${r[1.5]};

      &::after {
        content: ' ';
        position: absolute;
        top: 100%;
        left: -${r[2.5]};
        height: ${r[1.5]};
        width: calc(100% + ${r[5]});
      }
    `,panelCloseBtnIcon:u`
      color: ${t.gray[400]};
      width: ${r[2]};
      height: ${r[2]};
    `,navigateButton:u`
      background: none;
      border: none;
      padding: 0 0 0 4px;
      margin: 0;
      color: ${t.gray[400]};
      font-size: ${l.md};
      cursor: pointer;
      line-height: 1;
      vertical-align: middle;
      margin-right: 0.5ch;
      flex-shrink: 0;
      &:hover {
        color: ${t.blue[300]};
      }
    `}};function V(){let[e]=v(te(a(u)));return e}var H=e=>{try{let t=localStorage.getItem(e);return typeof t==`string`?JSON.parse(t):void 0}catch{return}};function U(e,t){let[n,r]=v();return p(()=>{r(H(e)??(typeof t==`function`?t():t))}),[n,t=>{r(n=>{let r=t;typeof t==`function`&&(r=t(n));try{localStorage.setItem(e,JSON.stringify(r))}catch{}return r})}]}var ne=typeof window>`u`;function W(e){return e.isFetching&&e.status===`success`?e.isFetching===`beforeLoad`?`purple`:`blue`:{pending:`yellow`,success:`green`,error:`red`,notFound:`purple`,redirected:`gray`}[e.status]}function re(e,t){let n=e.find(e=>e.routeId===t.id);return n?W(n):`gray`}function ie(){let[e,t]=v(!1);return(ne?p:b)(()=>{t(!0)}),e}var ae=e=>{let t=Object.getOwnPropertyNames(Object(e)),n=typeof e==`bigint`?`${e.toString()}n`:e;try{return JSON.stringify(n,t)}catch{return`unable to stringify`}};function G(e,t=[e=>e]){return e.map((e,t)=>[e,t]).sort(([e,n],[r,i])=>{for(let n of t){let t=n(e),i=n(r);if(t===void 0){if(i===void 0)continue;return 1}if(t!==i)return t>i?1:-1}return n-i}).map(([e])=>e)}var K=c(`<span><svg xmlns=http://www.w3.org/2000/svg width=12 height=12 fill=none viewBox="0 0 24 24"><path stroke=currentColor stroke-linecap=round stroke-linejoin=round stroke-width=2 d="M9 18l6-6-6-6">`),q=c(`<div>`),oe=c(`<button><span> `),se=c(`<div><div><button> [<!> ... <!>]`),ce=c(`<button><span></span> 🔄 `),le=c(`<span>:`),ue=c(`<span>`),de=({expanded:e,style:t={}})=>{let n=he();return(()=>{var t=K(),a=t.firstChild;return b(o=>{var s=n().expander,c=r(n().expanderIcon(e));return s!==o.e&&_(t,o.e=s),c!==o.t&&i(a,`class`,o.t=c),o},{e:void 0,t:void 0}),t})()};function fe(e,t){if(t<1)return[];let n=0,r=[];for(;n<e.length;)r.push(e.slice(n,n+t)),n+=t;return r}function pe(e){return Symbol.iterator in e}function J({value:e,defaultExpanded:t,pageSize:n=100,filterSubEntries:i,...a}){let[o,s]=v(!!t),c=()=>s(e=>!e),u=m(()=>typeof e()),f=m(()=>{let n=[],r=e=>{let n=t===!0?{[e.label]:!0}:t?.[e.label];return{...e,value:()=>e.value,defaultExpanded:n}};return Array.isArray(e())?n=e().map((e,t)=>r({label:t.toString(),value:e})):e()!==null&&typeof e()==`object`&&pe(e())&&typeof e()[Symbol.iterator]==`function`?n=Array.from(e(),(e,t)=>r({label:t.toString(),value:e})):typeof e()==`object`&&e()!==null&&(n=Object.entries(e()).map(([e,t])=>r({label:e,value:t}))),i?i(n):n}),p=m(()=>fe(f(),n)),[h,g]=v([]),[y,x]=v(void 0),S=he(),w=()=>{x(e()())},T=t=>C(J,d({value:e,filterSubEntries:i},a,t));return(()=>{var t=q();return l(t,(()=>{var t=E(()=>!!p().length);return()=>t()?[(()=>{var e=oe(),t=e.firstChild,n=t.firstChild;return e.$$click=()=>c(),l(e,C(de,{get expanded(){return o()??!1}}),t),l(e,()=>a.label,t),l(t,()=>String(u).toLowerCase()===`iterable`?`(Iterable) `:``,n),l(t,()=>f().length,n),l(t,()=>f().length>1?`items`:`item`,null),b(n=>{var r=S().expandButton,i=S().info;return r!==n.e&&_(e,n.e=r),i!==n.t&&_(t,n.t=i),n},{e:void 0,t:void 0}),e})(),E(()=>E(()=>!!(o()??!1))()?E(()=>p().length===1)()?(()=>{var e=q();return l(e,()=>f().map((e,t)=>T(e))),b(()=>_(e,S().subEntries)),e})():(()=>{var e=q();return l(e,()=>p().map((e,t)=>(()=>{var i=se(),a=i.firstChild,o=a.firstChild,s=o.firstChild,c=s.nextSibling,u=c.nextSibling.nextSibling;return u.nextSibling,o.$$click=()=>g(e=>e.includes(t)?e.filter(e=>e!==t):[...e,t]),l(o,C(de,{get expanded(){return h().includes(t)}}),s),l(o,t*n,c),l(o,t*n+n-1,u),l(a,(()=>{var n=E(()=>!!h().includes(t));return()=>n()?(()=>{var t=q();return l(t,()=>e.map(e=>T(e))),b(()=>_(t,S().subEntries)),t})():null})(),null),b(e=>{var t=S().entry,n=r(S().labelButton,`labelButton`);return t!==e.e&&_(a,e.e=t),n!==e.t&&_(o,e.t=n),e},{e:void 0,t:void 0}),i})())),b(()=>_(e,S().subEntries)),e})():null)]:E(()=>u()===`function`)()?C(J,{get label(){return(()=>{var e=ce(),t=e.firstChild;return e.$$click=w,l(t,()=>a.label),b(()=>_(e,S().refreshValueBtn)),e})()},value:y,defaultExpanded:{}}):[(()=>{var e=le(),t=e.firstChild;return l(e,()=>a.label,t),e})(),` `,(()=>{var t=ue();return l(t,()=>ae(e())),b(()=>_(t,S().value)),t})()]})()),b(()=>_(t,S().entry)),t})()}var me=e=>{let{colors:t,font:n,size:r,alpha:i,shadow:a,border:o}=B,{fontFamily:s,lineHeight:c,size:l}=n,u=e?z.bind({target:e}):z;return{entry:u`
      font-family: ${s.mono};
      font-size: ${l.xs};
      line-height: ${c.sm};
      outline: none;
      word-break: break-word;
    `,labelButton:u`
      cursor: pointer;
      color: inherit;
      font: inherit;
      outline: inherit;
      background: transparent;
      border: none;
      padding: 0;
    `,expander:u`
      display: inline-flex;
      align-items: center;
      justify-content: center;
      width: ${r[3]};
      height: ${r[3]};
      padding-left: 3px;
      box-sizing: content-box;
    `,expanderIcon:e=>e?u`
          transform: rotate(90deg);
          transition: transform 0.1s ease;
        `:u`
        transform: rotate(0deg);
        transition: transform 0.1s ease;
      `,expandButton:u`
      display: flex;
      gap: ${r[1]};
      align-items: center;
      cursor: pointer;
      color: inherit;
      font: inherit;
      outline: inherit;
      background: transparent;
      border: none;
      padding: 0;
    `,value:u`
      color: ${t.purple[400]};
    `,subEntries:u`
      margin-left: ${r[2]};
      padding-left: ${r[2]};
      border-left: 2px solid ${t.darkGray[400]};
    `,info:u`
      color: ${t.gray[500]};
      font-size: ${l[`2xs`]};
      padding-left: ${r[1]};
    `,refreshValueBtn:u`
      appearance: none;
      border: 0;
      cursor: pointer;
      background: transparent;
      color: inherit;
      padding: 0;
      font-family: ${s.mono};
      font-size: ${l.xs};
    `}};function he(){let[e]=v(me(a(u)));return e}h([`click`]);var ge=c(`<div><div></div><div>/</div><div></div><div>/</div><div>`);function _e(e){let t=[`s`,`min`,`h`,`d`],n=[e/1e3,e/6e4,e/36e5,e/864e5],r=0;for(let e=1;e<n.length&&!(n[e]<1);e++)r=e;return new Intl.NumberFormat(navigator.language,{compactDisplay:`short`,notation:`compact`,maximumFractionDigits:0}).format(n[r])+t[r]}function Y({match:e,router:t}){let n=V();if(!e)return null;let i=t().looseRoutesById[e.routeId];if(!i.options.loader)return null;let a=Date.now()-e.updatedAt,o=i.options.staleTime??t().options.defaultStaleTime??0,s=i.options.gcTime??t().options.defaultGcTime??1800*1e3;return(()=>{var e=ge(),t=e.firstChild,i=t.nextSibling.nextSibling,c=i.nextSibling.nextSibling;return l(t,()=>_e(a)),l(i,()=>_e(o)),l(c,()=>_e(s)),b(()=>_(e,r(n().ageTicker(a>o)))),e})()}var ve=c(`<button type=button>➔`);function X({to:e,params:t,search:n,router:r}){let a=V();return(()=>{var o=ve();return o.$$click=i=>{i.stopPropagation(),r().navigate({to:e,params:t,search:n})},i(o,`title`,`Navigate to ${e}`),b(()=>_(o,a().navigateButton)),o})()}h([`click`]);var ye=c(`<button><div>TANSTACK</div><div>TanStack Router v1`),be=c(`<div style=display:flex;align-items:center;width:100%><div style=flex-grow:1;min-width:0>`),xe=c(`<code> `),Z=c(`<code>`),Se=c(`<div><div role=button><div>`),Q=c(`<div>`),Ce=c(`<div><ul>`),we=c(`<div><button><svg xmlns=http://www.w3.org/2000/svg width=10 height=6 fill=none viewBox="0 0 10 6"><path stroke=currentColor stroke-linecap=round stroke-linejoin=round stroke-width=1.667 d="M1 1l4 4 4-4"></path></svg></button><div><div></div><div><div></div></div></div><div><div><div><span>Pathname</span></div><div><code></code></div><div><div><button type=button>Routes</button><button type=button>Matches</button><button type=button>History</button></div><div><div>age / staleTime / gcTime</div></div></div><div>`),Te=c(`<div><span>masked`),Ee=c(`<div role=button><div>`),De=c(`<li><div>`),Oe=c(`<li>This panel displays the most recent 15 navigations.`),ke=c(`<div><div><div>Cached Matches</div><div>age / staleTime / gcTime</div></div><div>`),Ae=c(`<div><div>Match Details</div><div><div><div><div></div></div><div><div>ID:</div><div><code></code></div></div><div><div>State:</div><div></div></div><div><div>Last Updated:</div><div></div></div></div></div><div>Explorer</div><div>`),je=c(`<div>Loader Data`),Me=c(`<div><div><span>Search Params</span></div><div>`),Ne=c(`<span style=margin-left:0.5rem>`),Pe=c(`<button type=button aria-label="Copy value to clipboard"style=cursor:pointer>`),Fe=15;function Ie(e){let{className:t,...n}=e,i=V();return(()=>{var e=ye(),a=e.firstChild,o=a.nextSibling;return w(e,d(n,{get class(){return r(i().logo,t?t():``)}}),!1,!0),b(e=>{var t=i().tanstackLogo,n=i().routerLogo;return t!==e.e&&_(a,e.e=t),n!==e.t&&_(o,e.t=n),e},{e:void 0,t:void 0}),e})()}function $(e){return(()=>{var t=be(),n=t.firstChild;return l(t,()=>e.left,n),l(n,()=>e.children),l(t,()=>e.right,null),b(()=>_(t,e.class)),t})()}function Le({routerState:a,router:o,route:s,isRoot:c,activeId:u,setActiveId:d}){let f=V(),p=m(()=>a().pendingMatches||a().matches),h=m(()=>a().matches.find(e=>e.routeId===s.id)),g=m(()=>{try{if(h()?.params){let e=h()?.params,n=s.path||t(s.id);if(n.startsWith(`$`)){let t=n.slice(1);if(e[t])return`(${e[t]})`}}return``}catch{return``}}),v=m(()=>{if(c||!s.path)return;let t=Object.assign({},...p().map(e=>e.params)),n=e({path:s.fullPath,params:t,decoder:o().pathParamsDecoder});return n.isMissingParams?void 0:n.interpolatedPath});return(()=>{var e=Se(),m=e.firstChild,x=m.firstChild;return m.$$click=()=>{h()&&d(u()===s.id?``:s.id)},l(m,C($,{get class(){return r(f().routesRow(!!h()))},get left(){return C(y,{get when(){return v()},children:e=>C(X,{get to(){return e()},router:o})})},get right(){return C(Y,{get match(){return h()},router:o})},get children(){return[(()=>{var e=xe(),r=e.firstChild;return l(e,()=>c?n:s.path||t(s.id),r),b(()=>_(e,f().code)),e})(),(()=>{var e=Z();return l(e,g),b(()=>_(e,f().routeParamInfo)),e})()]}}),null),l(e,(()=>{var e=E(()=>!!s.children?.length);return()=>e()?(()=>{var e=Q();return l(e,()=>[...s.children].sort((e,t)=>e.rank-t.rank).map(e=>C(Le,{routerState:a,router:o,route:e,activeId:u,setActiveId:d}))),b(()=>_(e,f().nestedRouteRow(!!c))),e})():null})(),null),b(e=>{var t=`Open match details for ${s.id}`,n=r(f().routesRowContainer(s.id===u(),!!h())),a=r(f().matchIndicator(re(p(),s)));return t!==e.e&&i(m,`aria-label`,e.e=t),n!==e.t&&_(m,e.t=n),a!==e.a&&_(x,e.a=a),e},{e:void 0,t:void 0,a:void 0}),e})()}var Re=function({...e}){let{isOpen:t=!0,setIsOpen:a,handleDragStart:c,router:u,routerState:h,shadowDOMTarget:y,...T}=e,{onCloseClick:D}=s(),O=V(),{className:A,style:j,...M}=T;k(u,`No router was found for the TanStack Router Devtools. Please place the devtools in the <RouterProvider> component tree or pass the router instance to the devtools manually.`);let[N,P]=U(`tanstackRouterDevtoolsActiveTab`,`routes`),[F,I]=U(`tanstackRouterDevtoolsActiveRouteId`,``),[L,R]=v([]),[ee,z]=v(!1);p(()=>{let e=h().matches,t=e[e.length-1];if(!t)return;let n=o(()=>L()),r=n[0],i=r&&r.pathname===t.pathname&&JSON.stringify(r.search??{})===JSON.stringify(t.search??{});(!r||!i)&&(n.length>=Fe&&z(!0),R(e=>{let n=[t,...e];return n.splice(Fe),n}))});let B=m(()=>[...h().pendingMatches??[],...h().matches,...h().cachedMatches].find(e=>e.routeId===F()||e.id===F())),te=m(()=>Object.keys(h().location.search).length),H=m(()=>({...u(),state:h()})),ne=m(()=>Object.fromEntries(G(Object.keys(H()),[`state`,`routesById`,`routesByPath`,`options`,`manifest`].map(e=>t=>t!==e)).map(e=>[e,H()[e]]).filter(e=>typeof e[1]!=`function`&&![`__store`,`basepath`,`injectedHtml`,`subscribers`,`latestLoadPromise`,`navigateTimeout`,`resetNextScroll`,`tempLocationKey`,`latestLocation`,`routeTree`,`history`].includes(e[0])))),re=m(()=>B()?.loaderData),ie=m(()=>B()),ae=m(()=>h().location.search);return(()=>{var e=we(),t=e.firstChild,o=t.firstChild,s=t.nextSibling,p=s.firstChild,m=p.nextSibling,v=m.firstChild,y=s.nextSibling,T=y.firstChild,k=T.firstChild;k.firstChild;var R=k.nextSibling,z=R.firstChild,V=R.nextSibling,H=V.firstChild,U=H.firstChild,G=U.nextSibling,K=G.nextSibling,q=H.nextSibling,oe=V.nextSibling;return w(e,d({get class(){return r(O().devtoolsPanel,`TanStackRouterDevtoolsPanel`,A?A():``)},get style(){return j?j():``}},M),!1,!0),l(e,c?(()=>{var e=Q();return f(e,`mousedown`,c,!0),b(()=>_(e,O().dragHandle)),e})():null,t),t.$$click=e=>{a&&a(!1),D(e)},l(p,C(Ie,{"aria-hidden":!0,onClick:e=>{a&&a(!1),D(e)}})),l(v,C(J,{label:`Router`,value:ne,defaultExpanded:{state:{},context:{},options:{}},filterSubEntries:e=>e.filter(e=>typeof e.value()!=`function`)})),l(k,(()=>{var e=E(()=>!!h().location.maskedLocation);return()=>e()?(()=>{var e=Te(),t=e.firstChild;return b(n=>{var r=O().maskedBadgeContainer,i=O().maskedBadge;return r!==n.e&&_(e,n.e=r),i!==n.t&&_(t,n.t=i),n},{e:void 0,t:void 0}),e})():null})(),null),l(z,()=>h().location.pathname),l(R,(()=>{var e=E(()=>!!h().location.maskedLocation);return()=>e()?(()=>{var e=Z();return l(e,()=>h().location.maskedLocation?.pathname),b(()=>_(e,O().maskedLocation)),e})():null})(),null),U.$$click=()=>{P(`routes`)},G.$$click=()=>{P(`matches`)},K.$$click=()=>{P(`history`)},l(oe,C(S,{get children(){return[C(g,{get when(){return N()===`routes`},get children(){return C(Le,{routerState:h,router:u,get route(){return u().routeTree},isRoot:!0,activeId:F,setActiveId:I})}}),C(g,{get when(){return N()===`matches`},get children(){var e=Q();return l(e,()=>(h().pendingMatches?.length?h().pendingMatches:h().matches)?.map((e,t)=>(()=>{var t=Ee(),a=t.firstChild;return t.$$click=()=>I(F()===e.id?``:e.id),l(t,C($,{get left(){return C(X,{get to(){return e.pathname},get params(){return e.params},get search(){return e.search},router:u})},get right(){return C(Y,{match:e,router:u})},get children(){var t=Z();return l(t,()=>`${e.routeId===`__root__`?n:e.pathname}`),b(()=>_(t,O().matchID)),t}}),null),b(n=>{var o=`Open match details for ${e.id}`,s=r(O().matchRow(e===B())),c=r(O().matchIndicator(W(e)));return o!==n.e&&i(t,`aria-label`,n.e=o),s!==n.t&&_(t,n.t=s),c!==n.a&&_(a,n.a=c),n},{e:void 0,t:void 0,a:void 0}),t})())),e}}),C(g,{get when(){return N()===`history`},get children(){var e=Ce(),t=e.firstChild;return l(t,C(x,{get each(){return L()},children:(e,t)=>(()=>{var i=De(),a=i.firstChild;return l(i,C($,{get left(){return C(X,{get to(){return e.pathname},get params(){return e.params},get search(){return e.search},router:u})},get right(){return C(Y,{match:e,router:u})},get children(){var t=Z();return l(t,()=>`${e.routeId===`__root__`?n:e.pathname}`),b(()=>_(t,O().matchID)),t}}),null),b(n=>{var o=r(O().matchRow(e===B())),s=r(O().matchIndicator(t()===0?`green`:`gray`));return o!==n.e&&_(i,n.e=o),s!==n.t&&_(a,n.t=s),n},{e:void 0,t:void 0}),i})()}),null),l(t,(()=>{var e=E(()=>!!ee());return()=>e()?(()=>{var e=Oe();return b(()=>_(e,O().historyOverflowContainer)),e})():null})(),null),e}})]}})),l(y,(()=>{var e=E(()=>!!h().cachedMatches.length);return()=>e()?(()=>{var e=ke(),t=e.firstChild,n=t.firstChild.nextSibling,a=t.nextSibling;return l(a,()=>h().cachedMatches.map(e=>(()=>{var t=Ee(),n=t.firstChild;return t.$$click=()=>I(F()===e.id?``:e.id),l(t,C($,{get left(){return C(X,{get to(){return e.pathname},get params(){return e.params},get search(){return e.search},router:u})},get right(){return C(Y,{match:e,router:u})},get children(){var t=Z();return l(t,()=>`${e.id}`),b(()=>_(t,O().matchID)),t}}),null),b(a=>{var o=`Open match details for ${e.id}`,s=r(O().matchRow(e===B())),c=r(O().matchIndicator(W(e)));return o!==a.e&&i(t,`aria-label`,a.e=o),s!==a.t&&_(t,a.t=s),c!==a.a&&_(n,a.a=c),a},{e:void 0,t:void 0,a:void 0}),t})())),b(r=>{var i=O().cachedMatchesContainer,a=O().detailsHeader,o=O().detailsHeaderInfo;return i!==r.e&&_(e,r.e=i),a!==r.t&&_(t,r.t=a),o!==r.a&&_(n,r.a=o),r},{e:void 0,t:void 0,a:void 0}),e})():null})(),null),l(e,(()=>{var e=E(()=>!!(B()&&B()?.status));return()=>e()?(()=>{var e=Ae(),t=e.firstChild,n=t.nextSibling,r=n.firstChild,i=r.firstChild,a=i.firstChild,o=i.nextSibling,s=o.firstChild.nextSibling,c=s.firstChild,u=o.nextSibling,d=u.firstChild.nextSibling,f=u.nextSibling,p=f.firstChild.nextSibling,m=n.nextSibling,g=m.nextSibling;return l(a,(()=>{var e=E(()=>!!(B()?.status===`success`&&B()?.isFetching));return()=>e()?`fetching`:B()?.status})()),l(c,()=>B()?.id),l(d,(()=>{var e=E(()=>!!h().pendingMatches?.find(e=>e.id===B()?.id));return()=>e()?`Pending`:h().matches.find(e=>e.id===B()?.id)?`Active`:`Cached`})()),l(p,(()=>{var e=E(()=>!!B()?.updatedAt);return()=>e()?new Date(B()?.updatedAt).toLocaleTimeString():`N/A`})()),l(e,(()=>{var e=E(()=>!!re());return()=>e()?[(()=>{var e=je();return b(()=>_(e,O().detailsHeader)),e})(),(()=>{var e=Q();return l(e,C(J,{label:`loaderData`,value:re,defaultExpanded:{}})),b(()=>_(e,O().detailsContent)),e})()]:null})(),m),l(g,C(J,{label:`Match`,value:ie,defaultExpanded:{}})),b(n=>{var a=O().thirdContainer,c=O().detailsHeader,l=O().matchDetails,h=O().matchStatus(B()?.status,B()?.isFetching),v=O().matchDetailsInfoLabel,y=O().matchDetailsInfo,b=O().matchDetailsInfoLabel,x=O().matchDetailsInfo,S=O().matchDetailsInfoLabel,C=O().matchDetailsInfo,w=O().detailsHeader,T=O().detailsContent;return a!==n.e&&_(e,n.e=a),c!==n.t&&_(t,n.t=c),l!==n.a&&_(r,n.a=l),h!==n.o&&_(i,n.o=h),v!==n.i&&_(o,n.i=v),y!==n.n&&_(s,n.n=y),b!==n.s&&_(u,n.s=b),x!==n.h&&_(d,n.h=x),S!==n.r&&_(f,n.r=S),C!==n.d&&_(p,n.d=C),w!==n.l&&_(m,n.l=w),T!==n.u&&_(g,n.u=T),n},{e:void 0,t:void 0,a:void 0,o:void 0,i:void 0,n:void 0,s:void 0,h:void 0,r:void 0,d:void 0,l:void 0,u:void 0}),e})():null})(),null),l(e,(()=>{var e=E(()=>!!te());return()=>e()?(()=>{var e=Me(),t=e.firstChild;t.firstChild;var n=t.nextSibling;return l(t,typeof navigator<`u`?(()=>{var e=Ne();return l(e,C(ze,{getValue:()=>{let e=h().location.search;return JSON.stringify(e)}})),e})():null,null),l(n,C(J,{value:ae,get defaultExpanded(){return Object.keys(h().location.search).reduce((e,t)=>(e[t]={},e),{})}})),b(r=>{var i=O().fourthContainer,a=O().detailsHeader,o=O().detailsContent;return i!==r.e&&_(e,r.e=i),a!==r.t&&_(t,r.t=a),o!==r.a&&_(n,r.a=o),r},{e:void 0,t:void 0,a:void 0}),e})():null})(),null),b(e=>{var n=O().panelCloseBtn,a=O().panelCloseBtnIcon,c=O().firstContainer,l=O().row,u=O().routerExplorerContainer,d=O().routerExplorer,f=O().secondContainer,h=O().matchesContainer,g=O().detailsHeader,b=O().detailsContent,x=O().detailsHeader,S=O().routeMatchesToggle,C=N()===`routes`,w=r(O().routeMatchesToggleBtn(N()===`routes`,!0)),E=N()===`matches`,D=r(O().routeMatchesToggleBtn(N()===`matches`,!0)),A=N()===`history`,j=r(O().routeMatchesToggleBtn(N()===`history`,!1)),M=O().detailsHeaderInfo,P=r(O().routesContainer);return n!==e.e&&_(t,e.e=n),a!==e.t&&i(o,`class`,e.t=a),c!==e.a&&_(s,e.a=c),l!==e.o&&_(p,e.o=l),u!==e.i&&_(m,e.i=u),d!==e.n&&_(v,e.n=d),f!==e.s&&_(y,e.s=f),h!==e.h&&_(T,e.h=h),g!==e.r&&_(k,e.r=g),b!==e.d&&_(R,e.d=b),x!==e.l&&_(V,e.l=x),S!==e.u&&_(H,e.u=S),C!==e.c&&(U.disabled=e.c=C),w!==e.w&&_(U,e.w=w),E!==e.m&&(G.disabled=e.m=E),D!==e.f&&_(G,e.f=D),A!==e.y&&(K.disabled=e.y=A),j!==e.g&&_(K,e.g=j),M!==e.p&&_(q,e.p=M),P!==e.b&&_(oe,e.b=P),e},{e:void 0,t:void 0,a:void 0,o:void 0,i:void 0,n:void 0,s:void 0,h:void 0,r:void 0,d:void 0,l:void 0,u:void 0,c:void 0,w:void 0,m:void 0,f:void 0,y:void 0,g:void 0,p:void 0,b:void 0}),e})()};function ze({getValue:e}){let[t,n]=v(!1),r=null,a=async()=>{if(typeof navigator>`u`||!navigator.clipboard?.writeText){console.warn(`TanStack Router Devtools: Clipboard API unavailable`);return}try{let t=e();await navigator.clipboard.writeText(t),n(!0),r&&clearTimeout(r),r=setTimeout(()=>n(!1),2500)}catch(e){console.error(`TanStack Router Devtools: Failed to copy`,e)}};return T(()=>{r&&clearTimeout(r)}),(()=>{var e=Pe();return e.$$click=a,l(e,()=>t()?`✅`:`📋`),b(()=>i(e,`title`,t()?`Copied!`:`Copy`)),e})()}h([`click`,`mousedown`]);export{Re as BaseTanStackRouterDevtoolsPanel,Re as default,U as n,V as r,ie as t};
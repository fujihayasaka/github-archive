performance.mark(`js-parse-end:BaseTanStackRouterDevtoolsPanel-BbL4h7yi-Co-D2kG6.js`);import{t as e}from"./clsx-DnEFlO87.js";import{Jp as t,Kp as n,qp as r}from"./index-M6n1L9AM.js";import{C as i,D as a,E as o,O as s,T as c,_ as l,a as u,b as d,c as f,d as p,f as m,g as h,i as g,l as _,m as v,o as y,p as b,r as x,s as S,u as C,w,x as T,y as E}from"./context-D56_tqst-CP0oa09L.js";var D={data:``},O=e=>{if(typeof window==`object`){let t=(e?e.querySelector(`#_goober`):window._goober)||Object.assign(document.createElement(`style`),{innerHTML:` `,id:`_goober`});return t.nonce=window.__nonce__,t.parentNode||(e||document.head).appendChild(t),t.firstChild}return e||D},k=/(?:([\u0080-\uFFFF\w-%@]+) *:? *([^{;]+?);|([^;}{]*?) *{)|(}\s*)/g,A=/\/\*[^]*?\*\/|  +/g,j=/\n+/g,M=(e,t)=>{let n=``,r=``,i=``;for(let a in e){let o=e[a];a[0]==`@`?a[1]==`i`?n=a+` `+o+`;`:r+=a[1]==`f`?M(o,a):a+`{`+M(o,a[1]==`k`?``:t)+`}`:typeof o==`object`?r+=M(o,t?t.replace(/([^,])+/g,e=>a.replace(/([^,]*:\S+\([^)]*\))|([^,])+/g,t=>/&/.test(t)?t.replace(/&/g,e):e?e+` `+t:t)):a):o!=null&&(a=/^--/.test(a)?a:a.replace(/[A-Z]/g,`-$&`).toLowerCase(),i+=M.p?M.p(a,o):a+`:`+o+`;`)}return n+(t&&i?t+`{`+i+`}`:i)+r},N={},P=e=>{if(typeof e==`object`){let t=``;for(let n in e)t+=n+P(e[n]);return t}return e},F=(e,t,n,r,i)=>{let a=P(e),o=N[a]||(N[a]=(e=>{let t=0,n=11;for(;t<e.length;)n=101*n+e.charCodeAt(t++)>>>0;return`go`+n})(a));if(!N[o]){let t=a===e?(e=>{let t,n,r=[{}];for(;t=k.exec(e.replace(A,``));)t[4]?r.shift():t[3]?(n=t[3].replace(j,` `).trim(),r.unshift(r[0][n]=r[0][n]||{})):r[0][t[1]]=t[2].replace(j,` `).trim();return r[0]})(e):e;N[o]=M(i?{[`@keyframes `+o]:t}:t,n?``:`.`+o)}let s=n&&N.g?N.g:null;return n&&(N.g=N[o]),((e,t,n,r)=>{r?t.data=t.data.replace(r,e):t.data.indexOf(e)===-1&&(t.data=n?e+t.data:t.data+e)})(N[o],t,r,s),o},I=(e,t,n)=>e.reduce((e,r,i)=>{let a=t[i];if(a&&a.call){let e=a(n),t=e&&e.props&&e.props.className||/^go/.test(e)&&e;a=t?`.`+t:e&&typeof e==`object`?e.props?``:M(e,``):!1===e?``:e}return e+r+(a??``)},``);function L(e){let t=this||{},n=e.call?e(t.p):e;return F(n.unshift?n.raw?I(n,[].slice.call(arguments,1),t.p):n.reduce((e,n)=>Object.assign(e,n&&n.call?n(t.p):n),{}):n,O(t.target),t.g,t.o,t.k)}L.bind({g:1}),L.bind({k:1});var R={colors:{inherit:`inherit`,current:`currentColor`,transparent:`transparent`,black:`#000000`,white:`#ffffff`,neutral:{50:`#f9fafb`,100:`#f2f4f7`,200:`#eaecf0`,300:`#d0d5dd`,400:`#98a2b3`,500:`#667085`,600:`#475467`,700:`#344054`,800:`#1d2939`,900:`#101828`},darkGray:{50:`#525c7a`,100:`#49536e`,200:`#414962`,300:`#394056`,400:`#313749`,500:`#292e3d`,600:`#212530`,700:`#191c24`,800:`#111318`,900:`#0b0d10`},gray:{50:`#f9fafb`,100:`#f2f4f7`,200:`#eaecf0`,300:`#d0d5dd`,400:`#98a2b3`,500:`#667085`,600:`#475467`,700:`#344054`,800:`#1d2939`,900:`#101828`},blue:{25:`#F5FAFF`,50:`#EFF8FF`,100:`#D1E9FF`,200:`#B2DDFF`,300:`#84CAFF`,400:`#53B1FD`,500:`#2E90FA`,600:`#1570EF`,700:`#175CD3`,800:`#1849A9`,900:`#194185`},green:{25:`#F6FEF9`,50:`#ECFDF3`,100:`#D1FADF`,200:`#A6F4C5`,300:`#6CE9A6`,400:`#32D583`,500:`#12B76A`,600:`#039855`,700:`#027A48`,800:`#05603A`,900:`#054F31`},red:{50:`#fef2f2`,100:`#fee2e2`,200:`#fecaca`,300:`#fca5a5`,400:`#f87171`,500:`#ef4444`,600:`#dc2626`,700:`#b91c1c`,800:`#991b1b`,900:`#7f1d1d`,950:`#450a0a`},yellow:{25:`#FFFCF5`,50:`#FFFAEB`,100:`#FEF0C7`,200:`#FEDF89`,300:`#FEC84B`,400:`#FDB022`,500:`#F79009`,600:`#DC6803`,700:`#B54708`,800:`#93370D`,900:`#7A2E0E`},purple:{25:`#FAFAFF`,50:`#F4F3FF`,100:`#EBE9FE`,200:`#D9D6FE`,300:`#BDB4FE`,400:`#9B8AFB`,500:`#7A5AF8`,600:`#6938EF`,700:`#5925DC`,800:`#4A1FB8`,900:`#3E1C96`},teal:{25:`#F6FEFC`,50:`#F0FDF9`,100:`#CCFBEF`,200:`#99F6E0`,300:`#5FE9D0`,400:`#2ED3B7`,500:`#15B79E`,600:`#0E9384`,700:`#107569`,800:`#125D56`,900:`#134E48`},pink:{25:`#fdf2f8`,50:`#fce7f3`,100:`#fbcfe8`,200:`#f9a8d4`,300:`#f472b6`,400:`#ec4899`,500:`#db2777`,600:`#be185d`,700:`#9d174d`,800:`#831843`,900:`#500724`},cyan:{25:`#ecfeff`,50:`#cffafe`,100:`#a5f3fc`,200:`#67e8f9`,300:`#22d3ee`,400:`#06b6d4`,500:`#0891b2`,600:`#0e7490`,700:`#155e75`,800:`#164e63`,900:`#083344`}},alpha:{100:`ff`,90:`e5`,80:`cc`,70:`b3`,60:`99`,50:`80`,40:`66`,30:`4d`,20:`33`,10:`1a`,0:`00`},font:{size:{"2xs":`calc(var(--tsrd-font-size) * 0.625)`,xs:`calc(var(--tsrd-font-size) * 0.75)`,sm:`calc(var(--tsrd-font-size) * 0.875)`,md:`var(--tsrd-font-size)`,lg:`calc(var(--tsrd-font-size) * 1.125)`,xl:`calc(var(--tsrd-font-size) * 1.25)`,"2xl":`calc(var(--tsrd-font-size) * 1.5)`,"3xl":`calc(var(--tsrd-font-size) * 1.875)`,"4xl":`calc(var(--tsrd-font-size) * 2.25)`,"5xl":`calc(var(--tsrd-font-size) * 3)`,"6xl":`calc(var(--tsrd-font-size) * 3.75)`,"7xl":`calc(var(--tsrd-font-size) * 4.5)`,"8xl":`calc(var(--tsrd-font-size) * 6)`,"9xl":`calc(var(--tsrd-font-size) * 8)`},lineHeight:{"3xs":`calc(var(--tsrd-font-size) * 0.75)`,"2xs":`calc(var(--tsrd-font-size) * 0.875)`,xs:`calc(var(--tsrd-font-size) * 1)`,sm:`calc(var(--tsrd-font-size) * 1.25)`,md:`calc(var(--tsrd-font-size) * 1.5)`,lg:`calc(var(--tsrd-font-size) * 1.75)`,xl:`calc(var(--tsrd-font-size) * 2)`,"2xl":`calc(var(--tsrd-font-size) * 2.25)`,"3xl":`calc(var(--tsrd-font-size) * 2.5)`,"4xl":`calc(var(--tsrd-font-size) * 2.75)`,"5xl":`calc(var(--tsrd-font-size) * 3)`,"6xl":`calc(var(--tsrd-font-size) * 3.25)`,"7xl":`calc(var(--tsrd-font-size) * 3.5)`,"8xl":`calc(var(--tsrd-font-size) * 3.75)`,"9xl":`calc(var(--tsrd-font-size) * 4)`},weight:{thin:`100`,extralight:`200`,light:`300`,normal:`400`,medium:`500`,semibold:`600`,bold:`700`,extrabold:`800`,black:`900`},fontFamily:{sans:`ui-sans-serif, Inter, system-ui, sans-serif, sans-serif`,mono:`ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, 'Liberation Mono', 'Courier New', monospace`}},breakpoints:{xs:`320px`,sm:`640px`,md:`768px`,lg:`1024px`,xl:`1280px`,"2xl":`1536px`},border:{radius:{none:`0px`,xs:`calc(var(--tsrd-font-size) * 0.125)`,sm:`calc(var(--tsrd-font-size) * 0.25)`,md:`calc(var(--tsrd-font-size) * 0.375)`,lg:`calc(var(--tsrd-font-size) * 0.5)`,xl:`calc(var(--tsrd-font-size) * 0.75)`,"2xl":`calc(var(--tsrd-font-size) * 1)`,"3xl":`calc(var(--tsrd-font-size) * 1.5)`,full:`9999px`}},size:{0:`0px`,.25:`calc(var(--tsrd-font-size) * 0.0625)`,.5:`calc(var(--tsrd-font-size) * 0.125)`,1:`calc(var(--tsrd-font-size) * 0.25)`,1.5:`calc(var(--tsrd-font-size) * 0.375)`,2:`calc(var(--tsrd-font-size) * 0.5)`,2.5:`calc(var(--tsrd-font-size) * 0.625)`,3:`calc(var(--tsrd-font-size) * 0.75)`,3.5:`calc(var(--tsrd-font-size) * 0.875)`,4:`calc(var(--tsrd-font-size) * 1)`,4.5:`calc(var(--tsrd-font-size) * 1.125)`,5:`calc(var(--tsrd-font-size) * 1.25)`,5.5:`calc(var(--tsrd-font-size) * 1.375)`,6:`calc(var(--tsrd-font-size) * 1.5)`,6.5:`calc(var(--tsrd-font-size) * 1.625)`,7:`calc(var(--tsrd-font-size) * 1.75)`,8:`calc(var(--tsrd-font-size) * 2)`,9:`calc(var(--tsrd-font-size) * 2.25)`,10:`calc(var(--tsrd-font-size) * 2.5)`,11:`calc(var(--tsrd-font-size) * 2.75)`,12:`calc(var(--tsrd-font-size) * 3)`,14:`calc(var(--tsrd-font-size) * 3.5)`,16:`calc(var(--tsrd-font-size) * 4)`,20:`calc(var(--tsrd-font-size) * 5)`,24:`calc(var(--tsrd-font-size) * 6)`,28:`calc(var(--tsrd-font-size) * 7)`,32:`calc(var(--tsrd-font-size) * 8)`,36:`calc(var(--tsrd-font-size) * 9)`,40:`calc(var(--tsrd-font-size) * 10)`,44:`calc(var(--tsrd-font-size) * 11)`,48:`calc(var(--tsrd-font-size) * 12)`,52:`calc(var(--tsrd-font-size) * 13)`,56:`calc(var(--tsrd-font-size) * 14)`,60:`calc(var(--tsrd-font-size) * 15)`,64:`calc(var(--tsrd-font-size) * 16)`,72:`calc(var(--tsrd-font-size) * 18)`,80:`calc(var(--tsrd-font-size) * 20)`,96:`calc(var(--tsrd-font-size) * 24)`},shadow:{xs:(e=`rgb(0 0 0 / 0.1)`)=>`0 1px 2px 0 rgb(0 0 0 / 0.05)`,sm:(e=`rgb(0 0 0 / 0.1)`)=>`0 1px 3px 0 ${e}, 0 1px 2px -1px ${e}`,md:(e=`rgb(0 0 0 / 0.1)`)=>`0 4px 6px -1px ${e}, 0 2px 4px -2px ${e}`,lg:(e=`rgb(0 0 0 / 0.1)`)=>`0 10px 15px -3px ${e}, 0 4px 6px -4px ${e}`,xl:(e=`rgb(0 0 0 / 0.1)`)=>`0 20px 25px -5px ${e}, 0 8px 10px -6px ${e}`,"2xl":(e=`rgb(0 0 0 / 0.25)`)=>`0 25px 50px -12px ${e}`,inner:(e=`rgb(0 0 0 / 0.05)`)=>`inset 0 2px 4px 0 ${e}`,none:()=>`none`},zIndices:{hide:-1,auto:`auto`,base:0,docked:10,dropdown:1e3,sticky:1100,banner:1200,overlay:1300,modal:1400,popover:1500,skipLink:1600,toast:1700,tooltip:1800}},ee=e=>{let{colors:t,font:n,size:r,alpha:i,shadow:a,border:o}=R,{fontFamily:s,lineHeight:c,size:l}=n,u=e?L.bind({target:e}):L;return{devtoolsPanelContainer:u`
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
      gap: ${R.size[.5]};
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
      padding: ${R.size[2]};
    `,row:u`
      display: flex;
      align-items: center;
      padding: ${R.size[2]} ${R.size[2.5]};
      gap: ${R.size[2.5]};
      border-bottom: ${t.darkGray[500]} 1px solid;
      align-items: center;
    `,detailsHeader:u`
      font-family: ui-sans-serif, Inter, system-ui, sans-serif, sans-serif;
      position: sticky;
      top: 0;
      z-index: 2;
      background-color: ${t.darkGray[600]};
      padding: 0px ${R.size[2]};
      font-weight: ${n.weight.medium};
      font-size: ${n.size.xs};
      min-height: ${R.size[8]};
      line-height: ${n.lineHeight.xs};
      text-align: left;
      display: flex;
      align-items: center;
    `,maskedBadge:u`
      background: ${t.yellow[900]}${i[70]};
      color: ${t.yellow[300]};
      display: inline-block;
      padding: ${R.size[0]} ${R.size[2.5]};
      border-radius: ${o.radius.full};
      font-size: ${n.size.xs};
      font-weight: ${n.weight.normal};
      border: 1px solid ${t.yellow[300]};
    `,maskedLocation:u`
      color: ${t.yellow[300]};
    `,detailsContent:u`
      padding: ${R.size[1.5]} ${R.size[2]};
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
          border-right: 1px solid ${R.colors.gray[500]};
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
      font-size: ${R.font.size.xs};
    `,maskedBadgeContainer:u`
      flex: 1;
      justify-content: flex-end;
      display: flex;
    `,matchDetails:u`
      display: flex;
      flex-direction: column;
      padding: ${R.size[2]};
      font-size: ${R.font.size.xs};
      color: ${R.colors.gray[300]};
      line-height: ${R.font.lineHeight.sm};
    `,matchStatus:(e,t)=>{let n=t&&e===`success`?t===`beforeLoad`?`purple`:`blue`:{pending:`yellow`,success:`green`,error:`red`,notFound:`purple`,redirected:`gray`}[e];return u`
        display: flex;
        justify-content: center;
        align-items: center;
        height: 40px;
        border-radius: ${R.border.radius.sm};
        font-weight: ${R.font.weight.normal};
        background-color: ${R.colors[n][900]}${R.alpha[90]};
        color: ${R.colors[n][300]};
        border: 1px solid ${R.colors[n][600]};
        margin-bottom: ${R.size[2]};
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
      background: ${R.colors.gray[600]};
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
    `}};function z(){let[e]=v(ee(a(u)));return e}var B=e=>{try{let t=localStorage.getItem(e);return typeof t==`string`?JSON.parse(t):void 0}catch{return}};function V(e,t){let[n,r]=v();return p(()=>{r(B(e)??(typeof t==`function`?t():t))}),[n,t=>{r(n=>{let r=t;typeof t==`function`&&(r=t(n));try{localStorage.setItem(e,JSON.stringify(r))}catch{}return r})}]}var H=typeof window>`u`;function te(e){return e.isFetching&&e.status===`success`?e.isFetching===`beforeLoad`?`purple`:`blue`:{pending:`yellow`,success:`green`,error:`red`,notFound:`purple`,redirected:`gray`}[e.status]}function U(e,t){let n=e.find(e=>e.routeId===t.id);return n?te(n):`gray`}function W(){let[e,t]=v(!1);return(H?p:b)(()=>{t(!0)}),e}var ne=Symbol.for(`tanstack.rsc.stream`),G=Symbol.for(`tanstack.rsc.renderable`),K=Symbol.for(`tanstack.rsc.slotUsages`);function re(e){let t=e.length;for(;t>0&&e[t-1]===void 0;)t--;return t===0||t===e.length?e:e.slice(0,t)}var q=e=>(typeof e==`object`||typeof e==`function`)&&e!==null&&ne in e,ie=e=>{if(!q(e))return null;let t=e;return G in t&&t[G]===!0?`renderableValue`:`compositeSource`},J=e=>{if(!q(e))return[];let t=e,n=[];if(K in t){let e=t[K];if(Array.isArray(e))for(let t of e){let e=t?.slot;typeof e==`string`&&!n.includes(e)&&n.push(e)}}return n},Y=e=>{if(!q(e))return[];let t=e;if(!(K in t))return[];let n=t[K];return Array.isArray(n)?n.filter(e=>e&&typeof e==`object`&&typeof e.slot==`string`&&(e.args===void 0||Array.isArray(e.args))):[]},ae=e=>{let t=Y(e),n={};for(let e of t){let t=re(e.args??[]),r=n[e.slot]??(n[e.slot]={count:0,invocations:[]});r.count++,r.invocations.push(t)}return n},X=e=>{if(e===`React element`)return`React element`;let t=ie(e);if(t===`compositeSource`){let t=J(e);return t.length>0?`RSC composite source (${t.length} ${t.length===1?`slot`:`slots`})`:`RSC composite source`}if(t===`renderableValue`)return`RSC renderable value`;let n=Object.getOwnPropertyNames(Object(e)),r=typeof e==`bigint`?`${e.toString()}n`:e;try{return JSON.stringify(r,n)}catch{return`unable to stringify`}};function oe(e,t=[e=>e]){return e.map((e,t)=>[e,t]).sort(([e,n],[r,i])=>{for(let n of t){let t=n(e),i=n(r);if(t===void 0){if(i===void 0)continue;return 1}if(t!==i)return t>i?1:-1}return n-i}).map(([e])=>e)}var se=c(`<span><svg xmlns=http://www.w3.org/2000/svg width=12 height=12 fill=none viewBox="0 0 24 24"><path stroke=currentColor stroke-linecap=round stroke-linejoin=round stroke-width=2 d="M9 18l6-6-6-6">`),Z=c(`<div>`),ce=c(`<button><span>:</span><span>`),le=c(`<div><span>slots</span><div>`),ue=c(`<span>:`),de=c(`<span>`),fe=c(`<button><span> `),pe=c(`<div><div><button> [<!> ... <!>]`),me=c(`<button><span></span> 🔄 `),he=({expanded:t,style:n={}})=>{let r=be();return(()=>{var n=se(),a=n.firstChild;return b(o=>{var s=r().expander,c=e(r().expanderIcon(t));return s!==o.e&&_(n,o.e=s),c!==o.t&&i(a,`class`,o.t=c),o},{e:void 0,t:void 0}),n})()};function ge(e,t){if(t<1)return[];let n=0,r=[];for(;n<e.length;)r.push(e.slice(n,n+t)),n+=t;return r}function _e(e){return Symbol.iterator in e}function ve(e){if(!e||typeof e!=`object`)return!1;let t=Object.getPrototypeOf(e);return t===Object.prototype||t===null}function Q({value:t,defaultExpanded:n,pageSize:r=100,filterSubEntries:i,...a}){let[o,s]=v(!!n),c=()=>s(e=>!e),u=m(()=>typeof t()),f=m(()=>{let e=[],r=e=>{let t=n===!0?{[e.label]:!0}:n?.[e.label];return{...e,value:()=>e.value,defaultExpanded:t}};if(Array.isArray(t())&&t().length===2&&t()[0]===`React element`&&ve(t()[1])){let n=t();e=[r({label:`0`,value:n[0]}),...Object.entries(n[1]).map(([e,t])=>r({label:e,value:t}))]}else Array.isArray(t())?e=t().map((e,t)=>r({label:t.toString(),value:e})):t()!==null&&typeof t()==`object`&&_e(t())&&typeof t()[Symbol.iterator]==`function`?e=Array.from(t(),(e,t)=>r({label:t.toString(),value:e})):typeof t()==`object`&&t()!==null&&(e=Object.entries(t()).map(([e,t])=>r({label:e,value:t})));return i?i(e):e}),p=m(()=>ge(f(),r)),[h,g]=v([]),[y,x]=v(void 0),S=be(),w=()=>{x(t()())},T=e=>C(Q,d({value:t,filterSubEntries:i},a,e)),D=m(()=>ie(t())),O=m(()=>J(t())),k=m(()=>ae(t())),A=m(()=>D()===`compositeSource`&&O().length>0);return(()=>{var n=Z();return l(n,(()=>{var n=E(()=>D()!==null);return()=>n()?E(()=>!!A())()?[(()=>{var e=ce(),n=e.firstChild,r=n.firstChild,i=n.nextSibling;return e.$$click=()=>c(),l(e,C(he,{get expanded(){return o()??!1}}),n),l(n,()=>a.label,r),l(i,()=>X(t())),b(t=>{var n=S().expandButton,r=S().compositeComponent;return n!==t.e&&_(e,t.e=n),r!==t.t&&_(i,t.t=r),t},{e:void 0,t:void 0}),e})(),E(()=>E(()=>!!(o()??!1))()?(()=>{var e=le(),t=e.firstChild,n=t.nextSibling;return l(n,()=>O().map(e=>{let t=k()[e];return t?C(Q,{label:`${e}:`,value:()=>t.invocations.map(e=>e.length===1?e[0]:e)}):null})),b(r=>{var i=S().rscMetaRow,a=S().rscMetaLabel,o=S().subEntries;return i!==r.e&&_(e,r.e=i),a!==r.t&&_(t,r.t=a),o!==r.a&&_(n,r.a=o),r},{e:void 0,t:void 0,a:void 0}),e})():null)]:[(()=>{var e=ue(),t=e.firstChild;return l(e,()=>a.label,t),e})(),` `,(()=>{var e=de();return l(e,()=>X(t())),b(()=>_(e,D()===`compositeSource`?S().compositeComponent:S().renderableComponent)),e})()]:E(()=>!!p().length)()?[(()=>{var e=fe(),t=e.firstChild,n=t.firstChild;return e.$$click=()=>c(),l(e,C(he,{get expanded(){return o()??!1}}),t),l(e,()=>a.label,t),l(t,()=>String(u).toLowerCase()===`iterable`?`(Iterable) `:``,n),l(t,()=>f().length,n),l(t,()=>f().length>1?`items`:`item`,null),b(n=>{var r=S().expandButton,i=S().info;return r!==n.e&&_(e,n.e=r),i!==n.t&&_(t,n.t=i),n},{e:void 0,t:void 0}),e})(),E(()=>E(()=>!!(o()??!1))()?E(()=>p().length===1)()?(()=>{var e=Z();return l(e,()=>f().map((e,t)=>T(e))),b(()=>_(e,S().subEntries)),e})():(()=>{var t=Z();return l(t,()=>p().map((t,n)=>(()=>{var i=pe(),a=i.firstChild,o=a.firstChild,s=o.firstChild,c=s.nextSibling,u=c.nextSibling.nextSibling;return u.nextSibling,o.$$click=()=>g(e=>e.includes(n)?e.filter(e=>e!==n):[...e,n]),l(o,C(he,{get expanded(){return h().includes(n)}}),s),l(o,n*r,c),l(o,n*r+r-1,u),l(a,(()=>{var e=E(()=>!!h().includes(n));return()=>e()?(()=>{var e=Z();return l(e,()=>t.map(e=>T(e))),b(()=>_(e,S().subEntries)),e})():null})(),null),b(t=>{var n=S().entry,r=e(S().labelButton,`labelButton`);return n!==t.e&&_(a,t.e=n),r!==t.t&&_(o,t.t=r),t},{e:void 0,t:void 0}),i})())),b(()=>_(t,S().subEntries)),t})():null)]:E(()=>u()===`function`)()?C(Q,{get label(){return(()=>{var e=me(),t=e.firstChild;return e.$$click=w,l(t,()=>a.label),b(()=>_(e,S().refreshValueBtn)),e})()},value:y,defaultExpanded:{}}):[(()=>{var e=ue(),t=e.firstChild;return l(e,()=>a.label,t),e})(),` `,(()=>{var e=de();return l(e,()=>X(t())),b(()=>_(e,S().value)),e})()]})()),b(()=>_(n,S().entry)),n})()}var ye=e=>{let{colors:t,font:n,size:r,border:i}=R,{fontFamily:a,lineHeight:o,size:s}=n,c=e?L.bind({target:e}):L;return{entry:c`
      font-family: ${a.mono};
      font-size: ${s.xs};
      line-height: ${o.sm};
      outline: none;
      word-break: break-word;
    `,labelButton:c`
      cursor: pointer;
      color: inherit;
      font: inherit;
      outline: inherit;
      background: transparent;
      border: none;
      padding: 0;
    `,expander:c`
      display: inline-flex;
      align-items: center;
      justify-content: center;
      width: ${r[3]};
      height: ${r[3]};
      padding-left: 3px;
      box-sizing: content-box;
    `,expanderIcon:e=>e?c`
          transform: rotate(90deg);
          transition: transform 0.1s ease;
        `:c`
        transform: rotate(0deg);
        transition: transform 0.1s ease;
      `,expandButton:c`
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
    `,value:c`
      color: ${t.purple[400]};
    `,compositeComponent:c`
      display: inline-flex;
      align-items: center;
      padding: 1px ${r[1]};
      border-radius: ${i.radius.full};
      border: 1px solid ${t.darkGray[500]};
      background: ${t.darkGray[700]};
      color: ${t.cyan[300]};
      font-style: normal;
      font-weight: ${n.weight.medium};
    `,renderableComponent:c`
      display: inline-flex;
      align-items: center;
      padding: 1px ${r[1]};
      border-radius: ${i.radius.full};
      border: 1px solid ${t.darkGray[500]};
      background: ${t.darkGray[700]};
      color: ${t.teal[300]};
      font-style: normal;
      font-weight: ${n.weight.medium};
    `,rscMetaRow:c`
      display: flex;
      gap: ${r[1]};
      align-items: flex-start;
      margin-left: calc(${r[3]} + ${r[1]});
      margin-top: ${r[.5]};
      flex-wrap: wrap;
    `,rscMetaLabel:c`
      color: ${t.gray[500]};
      font-size: ${s[`2xs`]};
      text-transform: uppercase;
      letter-spacing: 0.06em;
      padding-top: 2px;
    `,rscChipRow:c`
      display: flex;
      gap: ${r[1]};
      flex-wrap: wrap;
    `,rscChip:c`
      display: inline-flex;
      align-items: center;
      gap: ${r[.5]};
      padding: 1px ${r[1]};
      border-radius: ${i.radius.full};
      border: 1px solid ${t.darkGray[500]};
      background: ${t.darkGray[800]};
      color: ${t.gray[200]};
      font-size: ${s[`2xs`]};
      line-height: ${o.xs};
    `,rscChipName:c`
      color: ${t.gray[100]};
    `,rscChipMeta:c`
      color: ${t.gray[400]};
      font-size: ${s[`2xs`]};
    `,subEntries:c`
      margin-left: ${r[2]};
      padding-left: ${r[2]};
      border-left: 2px solid ${t.darkGray[400]};
    `,info:c`
      color: ${t.gray[500]};
      font-size: ${s[`2xs`]};
      padding-left: ${r[1]};
    `,refreshValueBtn:c`
      appearance: none;
      border: 0;
      cursor: pointer;
      background: transparent;
      color: inherit;
      padding: 0;
      font-family: ${a.mono};
      font-size: ${s.xs};
    `}};function be(){let[e]=v(ye(a(u)));return e}h([`click`]);var xe=c(`<div><div></div><div>/</div><div></div><div>/</div><div>`);function Se(e){let t=[`s`,`min`,`h`,`d`],n=[e/1e3,e/6e4,e/36e5,e/864e5],r=0;for(let e=1;e<n.length&&!(n[e]<1);e++)r=e;return new Intl.NumberFormat(navigator.language,{compactDisplay:`short`,notation:`compact`,maximumFractionDigits:0}).format(n[r])+t[r]}function Ce({match:t,router:n}){let r=z();if(!t)return null;let i=n().looseRoutesById[t.routeId];if(!i.options.loader)return null;let a=Date.now()-t.updatedAt,o=i.options.staleTime??n().options.defaultStaleTime??0,s=i.options.gcTime??n().options.defaultGcTime??1800*1e3;return(()=>{var t=xe(),n=t.firstChild,i=n.nextSibling.nextSibling,c=i.nextSibling.nextSibling;return l(n,()=>Se(a)),l(i,()=>Se(o)),l(c,()=>Se(s)),b(()=>_(t,e(r().ageTicker(a>o)))),t})()}var we=c(`<button type=button>➔`);function Te({to:e,params:t,search:n,router:r}){let a=z();return(()=>{var o=we();return o.$$click=i=>{i.stopPropagation(),r().navigate({to:e,params:t,search:n})},i(o,`title`,`Navigate to ${e}`),b(()=>_(o,a().navigateButton)),o})()}h([`click`]);var Ee=c(`<button><div>TANSTACK</div><div>TanStack Router v1`),De=c(`<div style=display:flex;align-items:center;width:100%><div style=flex-grow:1;min-width:0>`),Oe=c(`<code> `),$=c(`<code>`),ke=c(`<div><div role=button><div>`),Ae=c(`<div>`),je=c(`<div><ul>`),Me=c(`<div><button><svg xmlns=http://www.w3.org/2000/svg width=10 height=6 fill=none viewBox="0 0 10 6"><path stroke=currentColor stroke-linecap=round stroke-linejoin=round stroke-width=1.667 d="M1 1l4 4 4-4"></path></svg></button><div><div></div><div><div></div></div></div><div><div><div><span>Pathname</span></div><div><code></code></div><div><div><button type=button>Routes</button><button type=button>Matches</button><button type=button>History</button></div><div><div>age / staleTime / gcTime</div></div></div><div>`),Ne=c(`<div><span>masked`),Pe=c(`<div role=button><div>`),Fe=c(`<li><div>`),Ie=c(`<li>This panel displays the most recent 15 navigations.`),Le=c(`<div><div><div>Cached Matches</div><div>age / staleTime / gcTime</div></div><div>`),Re=c(`<div><div>Match Details</div><div><div><div><div></div></div><div><div>ID:</div><div><code></code></div></div><div><div>State:</div><div></div></div><div><div>Last Updated:</div><div></div></div></div></div><div>Explorer</div><div>`),ze=c(`<div>Loader Data`),Be=c(`<div><div><span>Search Params</span></div><div>`),Ve=c(`<span style=margin-left:0.5rem>`),He=c(`<button type=button aria-label="Copy value to clipboard"style=cursor:pointer>`),Ue=15;function We(t){let{className:n,...r}=t,i=z();return(()=>{var t=Ee(),a=t.firstChild,o=a.nextSibling;return w(t,d(r,{get class(){return e(i().logo,n?n():``)}}),!1,!0),b(e=>{var t=i().tanstackLogo,n=i().routerLogo;return t!==e.e&&_(a,e.e=t),n!==e.t&&_(o,e.t=n),e},{e:void 0,t:void 0}),t})()}function Ge(e){return(()=>{var t=De(),n=t.firstChild;return l(t,()=>e.left,n),l(n,()=>e.children),l(t,()=>e.right,null),b(()=>_(t,e.class)),t})()}function Ke({routerState:a,pendingMatches:o,router:s,route:c,isRoot:u,activeId:d,setActiveId:f}){let p=z(),h=m(()=>o().length?o():a().matches),g=m(()=>a().matches.find(e=>e.routeId===c.id)),v=m(()=>{try{if(g()?.params){let e=g()?.params,n=c.path||t(c.id);if(n.startsWith(`$`)){let t=n.slice(1);if(e[t])return`(${e[t]})`}}return``}catch{return``}}),x=m(()=>{if(u||!c.path)return;let e=Object.assign({},...h().map(e=>e.params)),t=r({path:c.fullPath,params:e,decoder:s().pathParamsDecoder});return t.isMissingParams?void 0:t.interpolatedPath});return(()=>{var r=ke(),m=r.firstChild,S=m.firstChild;return m.$$click=()=>{g()&&f(d()===c.id?``:c.id)},l(m,C(Ge,{get class(){return e(p().routesRow(!!g()))},get left(){return C(y,{get when(){return x()},children:e=>C(Te,{get to(){return e()},router:s})})},get right(){return C(Ce,{get match(){return g()},router:s})},get children(){return[(()=>{var e=Oe(),r=e.firstChild;return l(e,()=>u?n:c.path||t(c.id),r),b(()=>_(e,p().code)),e})(),(()=>{var e=$();return l(e,v),b(()=>_(e,p().routeParamInfo)),e})()]}}),null),l(r,(()=>{var e=E(()=>!!c.children?.length);return()=>e()?(()=>{var e=Ae();return l(e,()=>[...c.children].sort((e,t)=>e.rank-t.rank).map(e=>C(Ke,{routerState:a,pendingMatches:o,router:s,route:e,activeId:d,setActiveId:f}))),b(()=>_(e,p().nestedRouteRow(!!u))),e})():null})(),null),b(t=>{var n=`Open match details for ${c.id}`,r=e(p().routesRowContainer(c.id===d(),!!g())),a=e(p().matchIndicator(U(h(),c)));return n!==t.e&&i(m,`aria-label`,t.e=n),r!==t.t&&_(m,t.t=r),a!==t.a&&_(S,t.a=a),t},{e:void 0,t:void 0,a:void 0}),r})()}var qe=function({...t}){let{isOpen:r=!0,setIsOpen:a,handleDragStart:c,router:u,routerState:h,shadowDOMTarget:y,...D}=t,{onCloseClick:O}=s(),k=z(),{className:A,style:j,...M}=D,[N,P]=V(`tanstackRouterDevtoolsActiveTab`,`routes`),[F,I]=V(`tanstackRouterDevtoolsActiveRouteId`,``),[L,R]=v([]),[ee,B]=v(!1),H,U;if(`subscribe`in u().stores.pendingMatches){let[e,t]=v([]);H=e;let[n,r]=v([]);U=n,p(()=>{let e=u().stores.pendingMatches;t(e.get());let n=e.subscribe(()=>{t(e.get())});T(()=>n.unsubscribe())}),p(()=>{let e=u().stores.cachedMatches;r(e.get());let t=e.subscribe(()=>{r(e.get())});T(()=>t.unsubscribe())})}else H=()=>u().stores.pendingMatches.get(),U=()=>u().stores.cachedMatches.get();p(()=>{let e=h().matches,t=e[e.length-1];if(!t)return;let n=o(()=>L()),r=n[0],i=r&&r.pathname===t.pathname&&JSON.stringify(r.search??{})===JSON.stringify(t.search??{});(!r||!i)&&(n.length>=Ue&&B(!0),R(e=>{let n=[t,...e];return n.splice(Ue),n}))});let W=m(()=>[...H(),...h().matches,...U()].find(e=>e.routeId===F()||e.id===F())),ne=m(()=>Object.keys(h().location.search).length),G=m(()=>({...u(),state:h()})),K=m(()=>Object.fromEntries(oe(Object.keys(G()),[`state`,`routesById`,`routesByPath`,`options`,`manifest`].map(e=>t=>t!==e)).map(e=>[e,G()[e]]).filter(e=>typeof e[1]!=`function`&&![`stores`,`basepath`,`injectedHtml`,`subscribers`,`latestLoadPromise`,`navigateTimeout`,`resetNextScroll`,`tempLocationKey`,`latestLocation`,`routeTree`,`history`].includes(e[0])))),re=m(()=>W()?.loaderData),q=m(()=>W()),ie=m(()=>h().location.search);return(()=>{var t=Me(),r=t.firstChild,o=r.firstChild,s=r.nextSibling,p=s.firstChild,m=p.nextSibling,v=m.firstChild,y=s.nextSibling,T=y.firstChild,D=T.firstChild;D.firstChild;var R=D.nextSibling,z=R.firstChild,B=R.nextSibling,V=B.firstChild,G=V.firstChild,J=G.nextSibling,Y=J.nextSibling,ae=V.nextSibling,X=B.nextSibling;return w(t,d({get class(){return e(k().devtoolsPanel,`TanStackRouterDevtoolsPanel`,A?A():``)},get style(){return j?j():``}},M),!1,!0),l(t,c?(()=>{var e=Ae();return f(e,`mousedown`,c,!0),b(()=>_(e,k().dragHandle)),e})():null,r),r.$$click=e=>{a&&a(!1),O(e)},l(p,C(We,{"aria-hidden":!0,onClick:e=>{a&&a(!1),O(e)}})),l(v,C(Q,{label:`Router`,value:K,defaultExpanded:{state:{},context:{},options:{}},filterSubEntries:e=>e.filter(e=>typeof e.value()!=`function`)})),l(D,(()=>{var e=E(()=>!!h().location.maskedLocation);return()=>e()?(()=>{var e=Ne(),t=e.firstChild;return b(n=>{var r=k().maskedBadgeContainer,i=k().maskedBadge;return r!==n.e&&_(e,n.e=r),i!==n.t&&_(t,n.t=i),n},{e:void 0,t:void 0}),e})():null})(),null),l(z,()=>h().location.pathname),l(R,(()=>{var e=E(()=>!!h().location.maskedLocation);return()=>e()?(()=>{var e=$();return l(e,()=>h().location.maskedLocation?.pathname),b(()=>_(e,k().maskedLocation)),e})():null})(),null),G.$$click=()=>{P(`routes`)},J.$$click=()=>{P(`matches`)},Y.$$click=()=>{P(`history`)},l(X,C(S,{get children(){return[C(g,{get when(){return N()===`routes`},get children(){return C(Ke,{routerState:h,pendingMatches:H,router:u,get route(){return u().routeTree},isRoot:!0,activeId:F,setActiveId:I})}}),C(g,{get when(){return N()===`matches`},get children(){var t=Ae();return l(t,()=>(H().length?H():h().matches).map((t,r)=>(()=>{var r=Pe(),a=r.firstChild;return r.$$click=()=>I(F()===t.id?``:t.id),l(r,C(Ge,{get left(){return C(Te,{get to(){return t.pathname},get params(){return t.params},get search(){return t.search},router:u})},get right(){return C(Ce,{match:t,router:u})},get children(){var e=$();return l(e,()=>`${t.routeId===`__root__`?n:t.pathname}`),b(()=>_(e,k().matchID)),e}}),null),b(n=>{var o=`Open match details for ${t.id}`,s=e(k().matchRow(t===W())),c=e(k().matchIndicator(te(t)));return o!==n.e&&i(r,`aria-label`,n.e=o),s!==n.t&&_(r,n.t=s),c!==n.a&&_(a,n.a=c),n},{e:void 0,t:void 0,a:void 0}),r})())),t}}),C(g,{get when(){return N()===`history`},get children(){var t=je(),r=t.firstChild;return l(r,C(x,{get each(){return L()},children:(t,r)=>(()=>{var i=Fe(),a=i.firstChild;return l(i,C(Ge,{get left(){return C(Te,{get to(){return t.pathname},get params(){return t.params},get search(){return t.search},router:u})},get right(){return C(Ce,{match:t,router:u})},get children(){var e=$();return l(e,()=>`${t.routeId===`__root__`?n:t.pathname}`),b(()=>_(e,k().matchID)),e}}),null),b(n=>{var o=e(k().matchRow(t===W())),s=e(k().matchIndicator(r()===0?`green`:`gray`));return o!==n.e&&_(i,n.e=o),s!==n.t&&_(a,n.t=s),n},{e:void 0,t:void 0}),i})()}),null),l(r,(()=>{var e=E(()=>!!ee());return()=>e()?(()=>{var e=Ie();return b(()=>_(e,k().historyOverflowContainer)),e})():null})(),null),t}})]}})),l(y,(()=>{var t=E(()=>!!U().length);return()=>t()?(()=>{var t=Le(),n=t.firstChild,r=n.firstChild.nextSibling,a=n.nextSibling;return l(a,()=>U().map(t=>(()=>{var n=Pe(),r=n.firstChild;return n.$$click=()=>I(F()===t.id?``:t.id),l(n,C(Ge,{get left(){return C(Te,{get to(){return t.pathname},get params(){return t.params},get search(){return t.search},router:u})},get right(){return C(Ce,{match:t,router:u})},get children(){var e=$();return l(e,()=>`${t.id}`),b(()=>_(e,k().matchID)),e}}),null),b(a=>{var o=`Open match details for ${t.id}`,s=e(k().matchRow(t===W())),c=e(k().matchIndicator(te(t)));return o!==a.e&&i(n,`aria-label`,a.e=o),s!==a.t&&_(n,a.t=s),c!==a.a&&_(r,a.a=c),a},{e:void 0,t:void 0,a:void 0}),n})())),b(e=>{var i=k().cachedMatchesContainer,a=k().detailsHeader,o=k().detailsHeaderInfo;return i!==e.e&&_(t,e.e=i),a!==e.t&&_(n,e.t=a),o!==e.a&&_(r,e.a=o),e},{e:void 0,t:void 0,a:void 0}),t})():null})(),null),l(t,(()=>{var e=E(()=>!!(W()&&W()?.status));return()=>e()?(()=>{var e=Re(),t=e.firstChild,n=t.nextSibling,r=n.firstChild,i=r.firstChild,a=i.firstChild,o=i.nextSibling,s=o.firstChild.nextSibling,c=s.firstChild,u=o.nextSibling,d=u.firstChild.nextSibling,f=u.nextSibling,p=f.firstChild.nextSibling,m=n.nextSibling,g=m.nextSibling;return l(a,(()=>{var e=E(()=>!!(W()?.status===`success`&&W()?.isFetching));return()=>e()?`fetching`:W()?.status})()),l(c,()=>W()?.id),l(d,(()=>{var e=E(()=>!!H().find(e=>e.id===W()?.id));return()=>e()?`Pending`:h().matches.find(e=>e.id===W()?.id)?`Active`:`Cached`})()),l(p,(()=>{var e=E(()=>!!W()?.updatedAt);return()=>e()?new Date(W()?.updatedAt).toLocaleTimeString():`N/A`})()),l(e,(()=>{var e=E(()=>!!re());return()=>e()?[(()=>{var e=ze();return b(()=>_(e,k().detailsHeader)),e})(),(()=>{var e=Ae();return l(e,C(Q,{label:`loaderData`,value:re,defaultExpanded:{}})),b(()=>_(e,k().detailsContent)),e})()]:null})(),m),l(g,C(Q,{label:`Match`,value:q,defaultExpanded:{}})),b(n=>{var a=k().thirdContainer,c=k().detailsHeader,l=k().matchDetails,h=k().matchStatus(W()?.status,W()?.isFetching),v=k().matchDetailsInfoLabel,y=k().matchDetailsInfo,b=k().matchDetailsInfoLabel,x=k().matchDetailsInfo,S=k().matchDetailsInfoLabel,C=k().matchDetailsInfo,w=k().detailsHeader,T=k().detailsContent;return a!==n.e&&_(e,n.e=a),c!==n.t&&_(t,n.t=c),l!==n.a&&_(r,n.a=l),h!==n.o&&_(i,n.o=h),v!==n.i&&_(o,n.i=v),y!==n.n&&_(s,n.n=y),b!==n.s&&_(u,n.s=b),x!==n.h&&_(d,n.h=x),S!==n.r&&_(f,n.r=S),C!==n.d&&_(p,n.d=C),w!==n.l&&_(m,n.l=w),T!==n.u&&_(g,n.u=T),n},{e:void 0,t:void 0,a:void 0,o:void 0,i:void 0,n:void 0,s:void 0,h:void 0,r:void 0,d:void 0,l:void 0,u:void 0}),e})():null})(),null),l(t,(()=>{var e=E(()=>!!ne());return()=>e()?(()=>{var e=Be(),t=e.firstChild;t.firstChild;var n=t.nextSibling;return l(t,typeof navigator<`u`?(()=>{var e=Ve();return l(e,C(Je,{getValue:()=>{let e=h().location.search;return JSON.stringify(e)}})),e})():null,null),l(n,C(Q,{value:ie,get defaultExpanded(){return Object.keys(h().location.search).reduce((e,t)=>(e[t]={},e),{})}})),b(r=>{var i=k().fourthContainer,a=k().detailsHeader,o=k().detailsContent;return i!==r.e&&_(e,r.e=i),a!==r.t&&_(t,r.t=a),o!==r.a&&_(n,r.a=o),r},{e:void 0,t:void 0,a:void 0}),e})():null})(),null),b(t=>{var n=k().panelCloseBtn,a=k().panelCloseBtnIcon,c=k().firstContainer,l=k().row,u=k().routerExplorerContainer,d=k().routerExplorer,f=k().secondContainer,h=k().matchesContainer,g=k().detailsHeader,b=k().detailsContent,x=k().detailsHeader,S=k().routeMatchesToggle,C=N()===`routes`,w=e(k().routeMatchesToggleBtn(N()===`routes`,!0)),E=N()===`matches`,O=e(k().routeMatchesToggleBtn(N()===`matches`,!0)),A=N()===`history`,j=e(k().routeMatchesToggleBtn(N()===`history`,!1)),M=k().detailsHeaderInfo,P=e(k().routesContainer);return n!==t.e&&_(r,t.e=n),a!==t.t&&i(o,`class`,t.t=a),c!==t.a&&_(s,t.a=c),l!==t.o&&_(p,t.o=l),u!==t.i&&_(m,t.i=u),d!==t.n&&_(v,t.n=d),f!==t.s&&_(y,t.s=f),h!==t.h&&_(T,t.h=h),g!==t.r&&_(D,t.r=g),b!==t.d&&_(R,t.d=b),x!==t.l&&_(B,t.l=x),S!==t.u&&_(V,t.u=S),C!==t.c&&(G.disabled=t.c=C),w!==t.w&&_(G,t.w=w),E!==t.m&&(J.disabled=t.m=E),O!==t.f&&_(J,t.f=O),A!==t.y&&(Y.disabled=t.y=A),j!==t.g&&_(Y,t.g=j),M!==t.p&&_(ae,t.p=M),P!==t.b&&_(X,t.b=P),t},{e:void 0,t:void 0,a:void 0,o:void 0,i:void 0,n:void 0,s:void 0,h:void 0,r:void 0,d:void 0,l:void 0,u:void 0,c:void 0,w:void 0,m:void 0,f:void 0,y:void 0,g:void 0,p:void 0,b:void 0}),t})()};function Je({getValue:e}){let[t,n]=v(!1),r=null,a=async()=>{if(typeof navigator>`u`||!navigator.clipboard?.writeText){console.warn(`TanStack Router Devtools: Clipboard API unavailable`);return}try{let t=e();await navigator.clipboard.writeText(t),n(!0),r&&clearTimeout(r),r=setTimeout(()=>n(!1),2500)}catch(e){console.error(`TanStack Router Devtools: Failed to copy`,e)}};return T(()=>{r&&clearTimeout(r)}),(()=>{var e=He();return e.$$click=a,l(e,()=>t()?`✅`:`📋`),b(()=>i(e,`title`,t()?`Copied!`:`Copy`)),e})()}h([`click`,`mousedown`]);export{qe as BaseTanStackRouterDevtoolsPanel,qe as default,V as n,z as r,W as t};
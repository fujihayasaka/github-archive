"use strict";(globalThis.webpackChunk_github_ui_github_ui=globalThis.webpackChunk_github_ui_github_ui||[]).push([["26917"],{261828(e,t,r){r.r(t),r.d(t,{markdownEnrichmentSuccess:()=>d,showMarkdownRenderError:()=>s});var a=r(906997),o=r(221403),n=r(821744),i=r(159836);let l=new WeakMap;function d(e){let t=e.closest(".js-render-needs-enrichment");t&&(t.classList.remove("render-error"),l.get(t)?.setLoading(!1))}function s(e,t){let r=e.closest(".js-render-needs-enrichment");return!!r&&(r.classList.add("render-error"),r.querySelector(".js-render-block-actions")?.remove(),l.get(r)?.setError(!0,t))}function c(e,t,r){let o=r.identifier??"",n=new URL(e,window.location.origin);for(let[e,r]of Object.entries(t))n.searchParams.append(e,`${r}`);return n.hash=o,(0,a.qy)`
    <div
      class="render-container color-bg-transparent js-render-target p-0"
      data-identity="${o}"
      data-host="${n.origin}"
      data-type="${r.type}"
    >
      <iframe
        title="File display"
        role="presentation"
        class="render-viewer"
        src="${String(n)}"
        name="${o}"
        data-content="${r.contentJson}"
        sandbox="allow-scripts allow-same-origin allow-top-navigation allow-popups"
      >
      </iframe>
    </div>
  `}(0,o.lB)(".js-render-needs-enrichment",{constructor:HTMLElement,initialize:function(e){var t,r;let o,n,d={color_mode:(0,i.PT)()},s=e.getAttribute("data-type"),u=e.getAttribute("data-src"),h=e.getAttribute("data-identity"),p=e.getElementsByClassName("js-render-enrichment-target")[0],m=e.getElementsByClassName("js-render-enrichment-loader")[0],g=p.closest("details"),f=document.createElement("div");f.classList.add("js-render-enrichment-fallback"),e.appendChild(f);let v=p.firstElementChild;f.appendChild(v);let b={setLoading(e){m.hidden=!e},setError:(e,t)=>(b.setLoading(!1),!1!==e&&(v.classList.toggle("render-plaintext-hidden",!e),!!t&&((0,a.XX)([t,v],f),!0)))};l.set(e,b);let y=p.getAttribute("data-plain"),w=p.getAttribute("data-json");if(null==w||null==y)throw b.setError(!0,(0,a.qy)`<p class="flash flash-error">Unable to render rich display</p>`),Error(`Expected to see input data for type: ${s}`);let x=c(u,d,{type:s,identifier:h,contentJson:w}),L=c(u,d,{type:s,identifier:`${h}-fullscreen`,contentJson:w}),k=(t=()=>{(0,a.XX)(L,p.getElementsByClassName("Box-body")[0])},r={type:s},o=(0,a.qy)`<clipboard-copy
    aria-label="Copy ${r.type} code"
    .value=${y}
    class="btn my-2 js-clipboard-copy p-0 d-inline-flex tooltipped-no-delay"
    role="button"
    data-copy-feedback="Copied!"
    data-tooltip-direction="s"
  >
    <svg
      aria-hidden="true"
      height="16"
      viewBox="0 0 16 16"
      version="1.1"
      width="16"
      class="octicon octicon-copy js-clipboard-copy-icon m-2"
    >
      <path
        fill-rule="evenodd"
        d="M0 6.75C0 5.784.784 5 1.75 5h1.5a.75.75 0 010 1.5h-1.5a.25.25 0 00-.25.25v7.5c0 .138.112.25.25.25h7.5a.25.25 0 00.25-.25v-1.5a.75.75 0 011.5 0v1.5A1.75 1.75 0 019.25 16h-7.5A1.75 1.75 0 010 14.25v-7.5z"
      ></path>
      <path
        fill-rule="evenodd"
        d="M5 1.75C5 .784 5.784 0 6.75 0h7.5C15.216 0 16 .784 16 1.75v7.5A1.75 1.75 0 0114.25 11h-7.5A1.75 1.75 0 015 9.25v-7.5zm1.75-.25a.25.25 0 00-.25.25v7.5c0 .138.112.25.25.25h7.5a.25.25 0 00.25-.25v-7.5a.25.25 0 00-.25-.25h-7.5z"
      ></path>
    </svg>
    <svg
      aria-hidden="true"
      height="16"
      viewBox="0 0 16 16"
      version="1.1"
      width="16"
      class="octicon octicon-check js-clipboard-check-icon color-fg-success d-none m-2"
    >
      <path
        fill-rule="evenodd"
        d="M13.78 4.22a.75.75 0 010 1.06l-7.25 7.25a.75.75 0 01-1.06 0L2.22 9.28a.75.75 0 011.06-1.06L6 10.94l6.72-6.72a.75.75 0 011.06 0z"
      ></path>
    </svg>
  </clipboard-copy>`,n=(0,a.qy)`
    <details class="details-reset details-overlay details-overlay-dark" style="display: contents">
      <summary
        role="button"
        aria-label="Open dialog"
        class="btn my-2 mr-2 p-0 d-inline-flex"
        aria-haspopup="dialog"
        @click="${t}"
      >
        <svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor" class="octicon m-2">
          <path
            fill-rule="evenodd"
            d="M3.72 3.72a.75.75 0 011.06 1.06L2.56 7h10.88l-2.22-2.22a.75.75 0 011.06-1.06l3.5 3.5a.75.75 0 010 1.06l-3.5 3.5a.75.75 0 11-1.06-1.06l2.22-2.22H2.56l2.22 2.22a.75.75 0 11-1.06 1.06l-3.5-3.5a.75.75 0 010-1.06l3.5-3.5z"
          ></path>
        </svg>
      </summary>
      <details-dialog
        class="Box Box--overlay render-full-screen d-flex flex-column anim-fade-in fast"
        aria-label="${r.type} rendered container"
      >
        <div>
          <button
            aria-label="Close dialog"
            data-close-dialog=""
            type="button"
            data-view-component="true"
            class="Link--muted btn-link position-absolute render-full-screen-close"
          >
            <svg
              width="24"
              height="24"
              viewBox="0 0 24 24"
              fill="currentColor"
              style="display:inline-block;vertical-align:text-bottom"
              class="octicon octicon-x"
            >
              <path
                fill-rule="evenodd"
                d="M5.72 5.72a.75.75 0 011.06 0L12 10.94l5.22-5.22a.75.75 0 111.06 1.06L13.06 12l5.22 5.22a.75.75 0 11-1.06 1.06L12 13.06l-5.22 5.22a.75.75 0 01-1.06-1.06L10.94 12 5.72 6.78a.75.75 0 010-1.06z"
              ></path>
            </svg>
          </button>
          <div class="Box-body border-0" role="presentation"></div>
        </div>
      </details-dialog>
    </details>
  `,(0,a.qy)`<div
    class="js-render-block-actions position-absolute top-0 pr-2 right-0 d-flex flex-justify-end flex-items-center"
  >
    ${n}${o}
  </div>`);g&&!g.open?g.addEventListener("toggle",()=>{g.open&&(0,a.XX)([k,x],p)},{once:!0}):(0,a.XX)([k,x],p)}}),(0,n.on)("preview:toggle:off",".js-previewable-comment-form",function(e){let t=e.currentTarget.querySelector(".js-render-needs-enrichment"),r=t?.querySelector(".js-render-enrichment-target");r&&(r.textContent="")}),(0,n.on)("preview:rendered",".js-previewable-comment-form",function(e){let t=e.currentTarget.querySelector(".js-render-needs-enrichment");t&&l.get(t)?.setLoading(!1)})},159836(e,t,r){r.d(t,{OQ:()=>i,PA:()=>d,PT:()=>u,Px:()=>s,to:()=>c});var a=r(401289),o=r(17005);function n(){(0,o.TV)("preferred_color_mode",i())}function i(){return l("dark")?"dark":l("light")?"light":void 0}function l(e){return window.matchMedia&&window.matchMedia(`(prefers-color-scheme: ${e})`).matches}function d(e){let t=document.querySelector("html[data-color-mode]");t&&t.setAttribute("data-color-mode",e)}function s(e,t){let r=document.querySelector("html[data-color-mode]");r&&r.setAttribute(`data-${t}-theme`,e)}function c(e){let t=document.querySelector("html[data-color-mode]");if(t)return t.getAttribute(`data-${e}-theme`)}function u(e="light"){let t=function(){let e=document.querySelector("html[data-color-mode]");if(e)return e.getAttribute("data-color-mode")}();return("auto"===t?i():t)??e}(async()=>{if(await a.G,n(),window.matchMedia){let e=window.matchMedia("(prefers-color-scheme: dark)");e?.addEventListener?e.addEventListener("change",n):e.addListener(n)}})()}}]);
//# sourceMappingURL=chunk-26917-cb9dcff692ac4cec-99dec5b3f88f1939.js.map
/**
 * @lit-labs/ssr-dom-shim creates a few globals, which isn't allowed in our SSR environment.
 * We shouldn't need to render custom elements server-side, so we are simply shimming this shim
 * to avoid the added globals.
 */

export const HTMLElement = Object
export const customElements = {
  get() {
    return true
  },
}

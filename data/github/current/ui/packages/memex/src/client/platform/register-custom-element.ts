export function registerCustomElement(
  tagName: string,
  elementClass: CustomElementConstructor,
  options?: ElementDefinitionOptions,
) {
  if (typeof window === 'undefined') return
  if (!window.customElements.get(tagName)) {
    window.customElements.define(tagName, elementClass, options)
  }
}

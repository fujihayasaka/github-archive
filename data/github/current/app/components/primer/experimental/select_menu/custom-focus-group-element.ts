import {controller} from '@github/catalyst'
import {FocusKeys, focusZone} from '@primer/behaviors'
import type {FocusZoneSettings} from '@primer/behaviors'

@controller
class CustomFocusGroupElement extends HTMLElement {
  #abortController: AbortController | null = null
  #focusZoneAbortController: AbortController | null = null

  connectedCallback() {
    this.#abortController = new AbortController()
    this.setupFocusZone()

    // observe for changes to the focusable elements
    const observer = new MutationObserver(mutations => {
      for (const mutation of mutations) {
        if (mutation.type === 'attributes' && mutation.attributeName === 'hidden') {
          const newValue = (mutation.target as HTMLElement).hidden
          if (newValue === null || newValue === false) {
            this.setupFocusZone()
          }
        }
      }
    })
    // observer.observe when nearest parent tabPanel is hidden
    const tabPanel = this.closest('[role="tabpanel"]')
    if (tabPanel) {
      observer.observe(tabPanel, {
        attributes: true,
        attributeFilter: ['hidden'],
      })
    }
  }

  disconnectedCallback() {
    this.#abortController?.abort()
  }

  setupFocusZone() {
    if (this.#focusZoneAbortController) {
      this.#focusZoneAbortController.abort()
    }
    this.#focusZoneAbortController = focusZone(this, {
      bindKeys: FocusKeys.ArrowAll | FocusKeys.HomeAndEnd,
      focusableElementFilter: element => {
        return !element.closest('[hidden]')
      },
    } as FocusZoneSettings)
  }
}

if (!window.customElements.get('custom-focus-group')) {
  window.CustomFocusGroupElement = CustomFocusGroupElement
  window.customElements.define('custom-focus-group', CustomFocusGroupElement)
}

declare global {
  interface Window {
    CustomFocusGroupElement: typeof CustomFocusGroupElement
  }
}

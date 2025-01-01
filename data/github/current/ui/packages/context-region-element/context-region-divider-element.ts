import {attr, controller} from '@github/catalyst'
import {html, render} from '@github-ui/jtml-shimmed'

@controller
export class ContextRegionDividerElement extends HTMLElement {
  @attr preRendered = false

  render() {
    return render(
      html`
        <span class="AppHeader-context-item-separator">
          <span class="sr-only">/</span>
          <svg width="16" height="16" viewBox="0 0 16 16" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">
            <path d="M10.956 1.27994L6.06418 14.7201L5 14.7201L9.89181 1.27994L10.956 1.27994Z" fill="currentcolor" />
          </svg>
        </span>
      `,
      this,
    )
  }

  connectedCallback() {
    if (!this.preRendered) {
      this.render()
    }
  }
}

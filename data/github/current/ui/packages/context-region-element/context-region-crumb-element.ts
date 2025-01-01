import {attr, controller, target} from '@github/catalyst'
import type {ContextRegionDividerElement} from './context-region-divider-element'
import {html, render} from '@github-ui/jtml-shimmed'

@controller
export class ContextRegionCrumbElement extends HTMLElement {
  @attr isCompact: boolean = false
  @attr isResponsive: boolean = false
  @attr preRendered: boolean = false

  @attr declare label: string
  @attr declare href: string
  @attr declare crumbId: string

  @target declare labelElement: HTMLElement
  @target declare prefixIcon: HTMLElement
  @target declare trailingIcon: HTMLElement
  @target declare linkElement: HTMLElement
  @target declare dividerElement: ContextRegionDividerElement
  @target declare tooltip: HTMLElement

  cachedWidth: number = 0

  render() {
    if (!this.crumbId) {
      this.generateCrumbId()
    }

    const labelClasses = ['AppHeader-context-item-label']

    // legacy compact mode
    if (this.isCompact) {
      labelClasses.push('Truncate-text')
    }

    if (this.href) {
      if (!this.preRendered) {
        this.renderLink(labelClasses)
      }

      // if responsive mode is enabled, all crumb links will have tooltips available when overflowing
      // only the last crumb can overflow, but since crumbs can be added and removed client-side,
      // each crumb will have a tooltip at the ready in case it becomes overflowing
      if (this.isResponsive) {
        this.renderTooltip()

        if (this.preRendered && this.dividerElement) {
          // tooltips must be positioned directly after the link element in the document
          this.linkElement.after(this.tooltip)
        }
      }
    }

    // if the crumb is not a link, we render it as a span element (and these don't have tooltips because they are not interactive)
    if (!this.preRendered && !this.href) {
      this.renderSpan(labelClasses)
    }

    if (!this.preRendered && !this.isCompact) {
      this.renderDivider()
    }
  }

  renderLink(classNames: string[]) {
    render(
      html`
        <a
          id="${this.crumbId}-link"
          class="AppHeader-context-item"
          data-target="context-region-crumb.linkElement"
          href="${this.href}"
        >
          <span class="${classNames.join(' ')}" data-target="context-region-crumb.labelElement"> ${this.label} </span>
        </a>
      `,
      this,
    )
  }

  renderSpan(classNames: string[]) {
    render(
      html`
        <span class="AppHeader-context-item" data-target="context-region-crumb.linkElement">
          <span class="${classNames.join(' ')}" data-target="context-region-crumb.labelElement"> ${this.label} </span>
        </span>
      `,
      this,
    )
  }

  renderDivider() {
    render(
      html`<context-region-divider data-target="context-region-crumb.dividerElement"></context-region-divider>`,
      this,
    )
  }

  renderTooltip() {
    render(
      html`
        <tool-tip
          data-target="context-region-crumb.tooltip"
          for="${this.crumbId}-link"
          popover="manual"
          class="sr-only"
          position="absolute"
          data-type="label"
          data-direction="s"
          hidden
        >
          ${this.label}
        </tool-tip>
      `,
      this,
    )
  }

  generateCrumbId() {
    if (this.crumbId) return

    const label = this.label
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, '-')
      .replace(/^-|-$/g, '')

    const crumbId = `dynamic-crumb-${Math.random().toString(36).substring(2, 9)}-${label}`
    this.crumbId = crumbId
  }

  get potentialWidth() {
    return this.cachedWidth || this.getBoundingClientRect().width
  }

  getCurrentWidth() {
    // cache the potential width of the crumb so we have it available when the crumb is hidden
    this.cachedWidth = this.getBoundingClientRect().width
    return this.cachedWidth
  }

  isOverflowing() {
    return this.labelElement?.scrollWidth > this.labelElement?.clientWidth
  }

  activateTooltip() {
    if (this.tooltip && this.isOverflowing()) {
      this.tooltip.removeAttribute('hidden')
    } else {
      this.tooltip?.setAttribute('hidden', 'true')
    }
  }

  connectedCallback() {
    this.setAttribute('role', 'listitem')
    this.setAttribute('data-targets', 'context-region.crumbs')

    this.render()

    this.cachedWidth = this.getBoundingClientRect().width
  }

  attributeChangedCallback(name: string, oldValue: string | null, newValue: string | null) {
    if (name === 'data-label' && oldValue !== newValue) {
      if (this.labelElement) {
        this.labelElement.textContent = this.label
      }
    }

    if (name === 'data-href' && oldValue !== newValue) {
      if (this.linkElement) {
        this.linkElement.setAttribute('href', this.href)
      }
    }
  }
}

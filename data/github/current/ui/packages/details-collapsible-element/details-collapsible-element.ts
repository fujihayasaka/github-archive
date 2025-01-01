import {controller, target} from '@github/catalyst'

/**
 * A generic Catalyst element for use with any <details> element that toggles
 * between expanded and collapsed on click. This element ensures the markup is
 * properly accessible by updating the aria-label and aria-expanded attributes.
 *
 * aria-label values default to "Expand" and "Collapse". To override those values,
 * use the `data-aria-label-open` and `data-aria-label-closed` attributes
 * on the summaryElement target.
 *
 * @example
 * ```html
 * <details-collapsible>
 *   <details open=true data-target="details-collapsible.detailsElement">
 *     <summary
 *       aria-expanded="true"
 *       aria-label="Collapse me"
 *       data-target="details-collapsible.summaryElement"
 *       data-action="click:details-collapsible#toggle"
 *       data-aria-label-closed="Expand me"
 *       data-aria-label-open="Collapse me"
 *     >
 *       Click me
 *     </summary>
 *     <div>Contents</div>
 *   </details>
 * </details-collapsible>
 * ```
 */

@controller
export class DetailsCollapsibleElement extends HTMLElement {
  @target declare detailsElement: HTMLDetailsElement
  @target declare summaryElement: HTMLElement

  toggle() {
    const detailsElementIsOpen = this.detailsElement.hasAttribute('open')
    if (detailsElementIsOpen) {
      const ariaLabelClosed = this.summaryElement.getAttribute('data-aria-label-closed') || 'Expand'
      this.summaryElement.setAttribute('aria-label', ariaLabelClosed)
      this.summaryElement.setAttribute('aria-expanded', 'false')
    } else {
      const ariaLabelOpen = this.summaryElement.getAttribute('data-aria-label-open') || 'Collapse'
      this.summaryElement.setAttribute('aria-label', ariaLabelOpen)
      this.summaryElement.setAttribute('aria-expanded', 'true')
    }
  }
}

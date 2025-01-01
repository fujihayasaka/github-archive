/*
 *  Used to show hidden items in a grid of items. For instance if
 *  you have a grid of 9 items and you want to display only 3 along
 *  with a button which on click will disappear and make the remaining
 *  6 items visible.
 *
 *  ```
 *  <unveil-container>
 *   <div>...</div>
 *   <div>...</div>
 *   <div>...</div>
 *   <div data-targets="unveil-container.unveilItems" hidden>...</div>
 *   <div data-targets="unveil-container.unveilItems" hidden>...</div>
 *   <div data-targets="unveil-container.unveilItems" hidden>...</div>
 *   <div data-targets="unveil-container.unveilItems" hidden>...</div>
 *   <div data-targets="unveil-container.unveilItems" hidden>...</div>
 *   <div data-targets="unveil-container.unveilItems" hidden>...</div>
 *
 *   <button type="button" data-target="unveil-container.unveilElement" data-action="click:unveil-container#unveil">Show All Items</button>
 *  </unveil-container>
 *  ```
 */
import {controller, target, targets} from '@github/catalyst'

@controller
export class UnveilContainerElement extends HTMLElement {
  @target declare unveilElement: HTMLElement
  @targets declare unveilItems: HTMLElement[]

  show() {
    this.handleUnveilElement(true)

    for (const item of this.unveilItems) {
      if (item.hasAttribute('hidden')) {
        item.removeAttribute('hidden')
        item.setAttribute('data-unveiled', 'hidden')
      } else {
        // eslint-disable-next-line github/no-d-none
        item.classList.remove('d-none')
        item.setAttribute('data-unveiled', 'class')
      }
    }

    if (document.body.classList.contains('intent-mouse')) return

    // Focus the first element that was previously hidden
    const firstHiddenItem = this.unveilItems[0]

    if (firstHiddenItem === undefined) return

    const focusableElement =
      firstHiddenItem.hasAttribute('tabindex') ||
      firstHiddenItem.tagName === 'A' ||
      firstHiddenItem.tagName === 'BUTTON' ||
      firstHiddenItem.tagName === 'SUMMARY'
        ? firstHiddenItem
        : (firstHiddenItem.querySelector('[tabindex], a, button, summary') as HTMLElement)

    focusableElement?.focus()
  }

  hide() {
    this.handleUnveilElement(false)
    this.unveilElement?.setAttribute('aria-expanded', 'false')

    for (const item of this.unveilItems) {
      if (item.getAttribute('data-unveiled') === 'hidden') {
        item.setAttribute('hidden', '')
      } else {
        // eslint-disable-next-line github/no-d-none
        item.classList.add('d-none')
      }
    }
  }

  unveil() {
    this.unveilElement.remove()
    this.show()
  }

  toggleUnveil() {
    const firstItem = this.unveilItems[0]
    if (!firstItem) return
    // eslint-disable-next-line github/no-d-none
    if (firstItem.hasAttribute('hidden') || firstItem.classList.contains('d-none')) {
      this.show()
      return
    }

    this.hide()
  }

  private handleUnveilElement(expanded: boolean) {
    if (!this.unveilElement) return
    this.unveilElement.setAttribute('aria-expanded', expanded.toString())

    const attribute = expanded ? 'data-expanded-copy' : 'data-collapsed-copy'
    const oppositeAttribute = expanded ? 'data-collapsed-copy' : 'data-expanded-copy'

    if (!this.unveilElement.hasAttribute(oppositeAttribute))
      this.unveilElement.setAttribute(oppositeAttribute, this.unveilElement.textContent || '')
    if (this.unveilElement.hasAttribute(attribute))
      this.unveilElement.textContent = this.unveilElement.getAttribute(attribute)
  }
}

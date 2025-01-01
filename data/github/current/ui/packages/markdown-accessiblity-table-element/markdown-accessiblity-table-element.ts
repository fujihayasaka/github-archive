import {controller} from '@github/catalyst'
import {makeTablesTabbable} from './utils'

@controller
export class MarkdownAccessiblityTableElement extends HTMLElement {
  connectedCallback() {
    initializeOberserver(this)
  }
}

function initializeOberserver(containerRef: HTMLElement) {
  const table = containerRef.querySelector('table')
  if (!table) {
    return
  }

  const resizeObserver = new ResizeObserver(entries => {
    for (const entry of entries) {
      makeTablesTabbable(entry.target)
    }
  })

  // Make sure tabindex hasn't already been set by some unknown source
  if (table.getAttribute('tabindex') === null) {
    resizeObserver.observe(table)
  }
}

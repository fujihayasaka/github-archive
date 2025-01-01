import {controller, target} from '@github/catalyst'

@controller
export class DocumentDropzoneElement extends HTMLElement {
  @target declare dropContainer: HTMLElement

  dragging: number | null = null
  // Ignore image or link drags from within the page itself. Allow them to be
  // dragged onto the desktop, but ignore any drops back onto the page.
  ignorePageElementDrag = false
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  events: {[key: string]: (e: any) => void} = {}

  connectedCallback() {
    this.events = {
      dragstart: this.dragStartHandler.bind(this),
      dragend: this.dragEndHandler.bind(this),
      dragenter: this.dragEnterHandler.bind(this),
      dragover: this.dragEnterHandler.bind(this),
      dragleave: this.bodyDragLeaveHandler.bind(this),
      drop: this.dropHandler.bind(this),
    }

    for (const [event, fn] of Object.entries(this.events)) {
      const el = event === 'drop' ? this : document.body
      el.addEventListener(event, fn)
    }
  }

  disconnectedCallback() {
    for (const [event, fn] of Object.entries(this.events)) {
      const el = event === 'drop' ? this : document.body
      el.removeEventListener(event, fn)
    }
  }

  hasFile(transfer: DataTransfer): boolean {
    return Array.from(transfer.types).indexOf('Files') >= 0
  }

  // Highlight textarea and change drop cursor. Ensure drop target styles
  // are cleared after dragging back outside of window.
  dragEnterHandler(event: DragEvent) {
    if (this.ignorePageElementDrag) return

    if (this.dragging) {
      window.clearTimeout(this.dragging)
    }
    this.dragging = window.setTimeout(() => this.dropContainer.classList.remove('dragover'), 200)

    const transfer = event.dataTransfer
    if (!transfer || !this.hasFile(transfer)) return

    transfer.dropEffect = 'copy'
    this.dropContainer.classList.add('dragover')

    event.stopPropagation()
    event.preventDefault()
  }

  bodyDragLeaveHandler(event: DragEvent) {
    // Ignore leave events from children to prevent flicker.
    if (!(event.target instanceof DocumentDropzoneElement)) return
    this.dropContainer.classList.remove('dragover')
  }

  dropHandler(event: DragEvent) {
    this.dropContainer.classList.remove('dragover')
    document.body.classList.remove('dragover')

    const transfer = event.dataTransfer
    if (!transfer || !this.hasFile(transfer)) return

    this.dropContainer.dispatchEvent(
      new CustomEvent('document:drop', {
        bubbles: true,
        cancelable: true,
        detail: {transfer},
      }),
    )

    event.stopPropagation()
    event.preventDefault()
  }

  dragStartHandler() {
    this.ignorePageElementDrag = true
  }

  dragEndHandler() {
    this.ignorePageElementDrag = false
  }
}

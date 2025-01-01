import {controller, target} from '@github/catalyst'

@controller
export class DiscussionSpotlightContainerElement extends HTMLElement {
  @target mainLink: HTMLAnchorElement | undefined

  openDiscussionLink(event: PointerEvent) {
    if (event.target instanceof HTMLElement && event.target.tagName === 'A') return

    const noTextSelected = !this.#anyTextSelected()
    const metaKeyPressed = this.#isMetaKeyPressed(event)

    if (noTextSelected && !metaKeyPressed) {
      this.mainLink?.click()
    }
  }

  #anyTextSelected() {
    const selection = window.getSelection()
    return selection !== null && selection.toString()
  }

  #isMetaKeyPressed(event: PointerEvent | KeyboardEvent) {
    const useCtrlKeyAsMeta = !navigator.userAgent.match(/Macintosh/)
    // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
    return useCtrlKeyAsMeta ? event.ctrlKey : event.metaKey
  }
}

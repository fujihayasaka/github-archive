import { controller, target } from '@github/catalyst'
import MarkdownToolbarElement from '@github/markdown-toolbar-element'

@controller
export class MarkdownEditorElement extends HTMLElement {
  @target toolbar: MarkdownToolbarElement

  showToolbar() {
    this.toolbar && (this.toolbar.hidden = false)
  }

  hideToolbar() {
    this.toolbar && (this.toolbar.hidden = true)
  }
}

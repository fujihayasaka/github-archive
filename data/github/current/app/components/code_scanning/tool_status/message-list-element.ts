import {controller, targets, target, attr} from '@github/catalyst'

@controller
class MessageListElement extends HTMLElement {
  @attr expanded = false

  @targets declare messages: HTMLElement[]
  @target declare more: HTMLElement
  @target declare less: HTMLElement
  @target declare toggle: HTMLElement

  connectedCallback() {
    if (this.messages.length > 2) {
      this.toggle.hidden = false
      this.update(this.expanded)
    }
  }

  update(toggled: boolean) {
    for (const message of this.messages.slice(2)) {
      message.hidden = !toggled
    }

    this.more.hidden = toggled
    this.less.hidden = !toggled
  }

  toggleMessages() {
    this.update((this.expanded = !this.expanded))
  }
}

@controller
class ToggleMessageElement extends HTMLElement {
  @attr expanded = false

  @target declare description: HTMLElement
  @target declare handle: HTMLElement

  connectedCallback() {
    this.update(this.expanded)
  }

  update(expand: boolean) {
    this.description.hidden = !expand

    const handleIcon = this.handle.querySelector('svg')
    if (handleIcon) {
      if (expand) {
        handleIcon.style.transform = `rotate(90deg)`
      } else {
        handleIcon.style.transform = `rotate(0)`
      }
    }
  }

  toggleMessage() {
    this.update((this.expanded = !this.expanded))
  }
}

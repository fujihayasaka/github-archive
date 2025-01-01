import {controller, target} from '@github/catalyst'

import prettyCron from '../../assets/modules/github/editor/pretty-cron'

@controller
export class PrettyCronElement extends HTMLElement {
  declare cron: string
  @target declare placeholder: HTMLElement
  @target declare richContent: HTMLElement
  @target declare human: HTMLElement

  connectedCallback() {
    this.cron = this.getAttribute('data-cron')!
    this.human.textContent = prettyCron(this.cron, {capitalize: true})
    this.placeholder.hidden = true
    this.richContent.hidden = false
  }
}

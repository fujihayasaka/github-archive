import {controller, target} from '@github/catalyst'

@controller
export class ExpandableRoleRowElement extends HTMLElement {
  @target declare permissionDetails: HTMLElement
  @target declare showDetailsButton: HTMLButtonElement
  @target declare hideDetailsButton: HTMLButtonElement

  showDetails() {
    this.permissionDetails.hidden = false
    this.hideDetailsButton.hidden = false
    this.showDetailsButton.hidden = true
  }

  hideDetails() {
    this.permissionDetails.hidden = true
    this.hideDetailsButton.hidden = true
    this.showDetailsButton.hidden = false
  }
}

import {controller, target} from '@github/catalyst'

@controller
export class UserDrawerSidePanelElement extends HTMLElement {
  @target declare statusDialog: HTMLDialogElement

  openDialog() {
    this.statusDialog.showModal()
  }
}

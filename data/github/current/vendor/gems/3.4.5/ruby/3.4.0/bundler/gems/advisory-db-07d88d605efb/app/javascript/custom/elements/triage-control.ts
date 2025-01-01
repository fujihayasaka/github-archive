import { controller, targets } from '@github/catalyst'
import { install, uninstall } from '@github/hotkey'

@controller
export class TriageControlElement extends HTMLElement {
  @targets triageButtons: HTMLButtonElement[]
  @targets dialogButtons: HTMLButtonElement[]

  connectedCallback() {
    toggleButtons(this.triageButtons, true)
  }

  switchContext(event: CustomEvent) {
    const dialog = event.target! as HTMLDetailsElement
    const dialogButtons = this.dialogButtons.filter(
      (button) => button.closest('details') === dialog,
    )

    toggleButtons(this.triageButtons, !dialog.open)
    toggleButtons(dialogButtons, dialog.open)
  }
}

function toggleButtons(
  buttons: HTMLButtonElement[] | NodeListOf<HTMLButtonElement>,
  active: boolean,
) {
  for (const button of buttons) {
    if (active) {
      install(button, button.getAttribute('data-shortcut')!)
      button.setAttribute('tabindex', '0')
    } else {
      uninstall(button)
      button.setAttribute('tabindex', '-1')
    }
  }
}

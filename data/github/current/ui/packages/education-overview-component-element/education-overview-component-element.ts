import {controller} from '@github/catalyst'

@controller
export class EducationOverviewComponentElement extends HTMLElement {
  connectedCallback() {
    const educationDialog = document.getElementById('education-benefits-dialog')
    if (educationDialog) {
      educationDialog.addEventListener('close', () => {
        window.location.reload()
      })
    }
  }
}

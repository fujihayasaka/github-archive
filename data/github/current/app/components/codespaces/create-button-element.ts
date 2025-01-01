import {controller, target} from '@github/catalyst'

@controller
class CreateButtonElement extends HTMLElement {
  @target declare createButton: HTMLButtonElement
  @target declare dropdownButton: HTMLButtonElement
  @target declare selectionDetails: HTMLDetailsElement
  @target declare basicOptionsCheck: SVGElement
  @target declare advancedOptionsCheck: SVGElement
  @target declare configureAndCreateLink: HTMLAnchorElement
  @target declare loadingVscode: HTMLElement | undefined
  @target declare vscodePoller: HTMLElement | undefined

  // eslint-disable-next-line @eslint-react/hooks-extra/no-useless-custom-hooks
  useBasicCreation(): void {
    this.createButton.hidden = false
    this.configureAndCreateLink.hidden = true
    this.basicOptionsCheck.classList.remove('v-hidden')
    this.advancedOptionsCheck.classList.add('v-hidden')
    this.selectionDetails.open = false
  }

  // eslint-disable-next-line @eslint-react/hooks-extra/no-useless-custom-hooks
  useAdvancedCreation(): void {
    this.createButton.hidden = true
    this.configureAndCreateLink.hidden = false
    this.basicOptionsCheck.classList.add('v-hidden')
    this.advancedOptionsCheck.classList.remove('v-hidden')
    this.selectionDetails.open = false
  }

  toggleLoadingVscode() {
    if (this.loadingVscode) {
      const isHidden = this.loadingVscode.hidden
      const children = this.children
      for (let i = 0; i < children.length; i++) {
        ;(children[i] as HTMLElement).hidden = isHidden
      }
      this.loadingVscode.hidden = !isHidden
    }
  }

  pollForVscode(event: CustomEvent) {
    if (this.vscodePoller) {
      this.toggleLoadingVscode()
      const pollingUrl = (event.currentTarget as HTMLElement).getAttribute('data-src')
      if (pollingUrl) this.vscodePoller.setAttribute('src', pollingUrl)
    }
  }
}

import {controller, target} from '@github/catalyst'

@controller
class DependabotUpdatesPausedElement extends HTMLElement {
  @target declare bannerDismissal: HTMLElement

  dismissBanner() {
    this.bannerDismissal.toggleAttribute('hidden')
  }
}

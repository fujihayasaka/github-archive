import {controller, target} from '@github/catalyst'

@controller
export class LicensingApplyCouponCodeElement extends HTMLElement {
  @target declare couponCodeSection: HTMLElement

  toggleCouponCode(event: Event) {
    const checkbox = event.target as HTMLInputElement
    if (this.couponCodeSection) {
      this.couponCodeSection.hidden = !checkbox.checked
    }
  }
}

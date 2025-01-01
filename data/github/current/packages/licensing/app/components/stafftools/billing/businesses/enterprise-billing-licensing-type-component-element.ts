import {controller, target} from '@github/catalyst'

@controller
class EnterpriseBillingLicensingTypeComponentElement extends HTMLElement {
  @target declare meteredPlanCheckbox: HTMLInputElement
  @target declare seatCount: HTMLInputElement
  @target declare seatsContainer: HTMLElement
  #hideSeatscontainer: boolean

  toggleSeats() {
    this.#hideSeatscontainer = this.meteredPlanCheckbox.checked
    this.#renderOutput()
  }

  #renderOutput = () => {
    this.seatsContainer.hidden = this.#hideSeatscontainer
    if (this.#hideSeatscontainer) {
      this.seatCount.value = '0'
    }
  }
}

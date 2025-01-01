import {attr, controller, target} from '@github/catalyst'

@controller
class VariablesPaginationElement extends HTMLElement {
  @target declare countText: HTMLElement
  @target declare submitContainer: HTMLElement
  @target declare spinner: HTMLElement

  @attr declare totalCount: number
  @attr declare pageSize: number
  @attr page = 1

  updateCount() {
    this.page++
    const variablesCount = this.page * this.pageSize
    let variablesCountText = variablesCount.toString()
    if (variablesCount >= this.totalCount) {
      variablesCountText = `all ${this.totalCount}`
    }

    const message = `${variablesCountText} of ${this.totalCount} variables. `
    this.countText.textContent = message
    this.submitContainer.hidden = false
    this.spinner.hidden = true
  }

  showSpinner() {
    this.submitContainer.hidden = true
    this.spinner.hidden = false
  }
}

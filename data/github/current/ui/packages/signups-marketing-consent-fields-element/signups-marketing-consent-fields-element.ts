import {controller, attr, target} from '@github/catalyst'
import type {SelectPanelElement} from '@primer/view-components/app/components/primer/alpha/select_panel_element'
import type {ItemActivatedEvent} from '@primer/view-components/app/components/primer/shared_events'

@controller
export class SignupsMarketingConsentFieldsElement extends HTMLElement {
  @attr declare actorCountryCode: string
  @target declare panel: SelectPanelElement
  @target declare marketingOptInContainer: HTMLDivElement
  @target declare marketingConsentCheckbox: HTMLInputElement

  connectedCallback() {
    if (this.panel) this.panel.addEventListener('itemActivated', this.handleItemSelect)
    this.prepopulateCountry()
  }

  disconnectedCallback() {
    if (this.panel) this.panel.removeEventListener('itemActivated', this.handleItemSelect)
  }

  private prepopulateCountry() {
    if (!this.actorCountryCode || !this.panel) return
    const {actorCountryCode, panel} = this

    const countryElement = panel.getItemById(actorCountryCode)
    if (countryElement) panel.checkItem(countryElement)
  }

  // Toggle visibility and enablement of marketing consent section based on selected country
  private handleItemSelect = (event: CustomEvent): void => {
    const customEvent = event as CustomEvent<ItemActivatedEvent>
    const selectedItem = customEvent.detail.item
    const button = selectedItem.querySelector('button')
    const selectedValue = button?.getAttribute('data-value')
    if (!selectedValue) return

    const excludedCountries = ['CA', 'CN', 'KR']
    const isExcluded = excludedCountries.includes(selectedValue)
    this.marketingOptInContainer.hidden = isExcluded
    this.marketingConsentCheckbox.disabled = isExcluded
  }
}

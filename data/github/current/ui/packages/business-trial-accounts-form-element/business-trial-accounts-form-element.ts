import {controller, target} from '@github/catalyst'

@controller
export class BusinessTrialAccountsFormElement extends HTMLElement {
  @target declare nameField: HTMLInputElement | undefined
  @target declare nameError: HTMLElement | undefined
  @target declare slugField: HTMLInputElement | undefined
  @target declare slugError: HTMLElement | undefined
  @target declare shortcodeField: HTMLInputElement | undefined
  @target declare shortcodeError: HTMLElement | undefined
  @target declare industryField: HTMLSelectElement | undefined
  @target declare industryError: HTMLElement | undefined
  @target declare employeesSizeField: HTMLSelectElement | undefined
  @target declare employeesSizeError: HTMLElement | undefined
  @target declare countryCodeField: HTMLSelectElement | undefined
  @target declare countryCodeError: HTMLElement | undefined
  @target declare emuIdpField: HTMLInputElement | undefined
  @target declare emuIdpError: HTMLElement | undefined
  @target declare billingFullNameField: HTMLInputElement | undefined
  @target declare billingFullNameError: HTMLElement | undefined
  @target declare billingEmailField: HTMLInputElement | undefined
  @target declare billingEmailError: HTMLElement | undefined
  @target declare featuresDisabledWarningCheckbox: HTMLInputElement | undefined
  @target declare businessOwnedCheckbox: HTMLInputElement | undefined
  @target declare trialTermsError: HTMLElement | undefined
  @target declare dataHostingCheckbox: HTMLInputElement | undefined
  @target declare dataHostingRegionFieldContainer: HTMLElement | undefined
  @target declare slugFieldContainer: HTMLElement | undefined
  @target declare shortcodeFieldContainer: HTMLElement | undefined
  @target declare subdomainFieldContainer: HTMLElement | undefined
  @target declare dataHostingRegionField: HTMLSelectElement | undefined
  @target declare dataHostingRegionError: HTMLElement | undefined
  @target declare subdomainField: HTMLInputElement | undefined
  @target declare subdomainError: HTMLElement | undefined

  connectedCallback() {
    this.nameField?.addEventListener('input', () => {
      if (this.nameError) this.nameError.hidden = true
    })

    this.slugField?.addEventListener('input', () => {
      if (this.slugError) this.slugError.hidden = true
    })

    this.shortcodeField?.addEventListener('input', () => {
      if (this.shortcodeError) this.shortcodeError.hidden = true
    })

    this.industryField?.addEventListener('input', () => {
      if (this.industryError) this.industryError.hidden = true
    })

    this.employeesSizeField?.addEventListener('input', () => {
      if (this.employeesSizeError) this.employeesSizeError.hidden = true
    })

    this.countryCodeField?.addEventListener('input', () => {
      if (this.countryCodeError) this.countryCodeError.hidden = true
    })

    this.emuIdpField?.addEventListener('input', () => {
      if (this.emuIdpError) this.emuIdpError.hidden = true
    })

    this.billingFullNameField?.addEventListener('input', () => {
      if (this.billingFullNameError) this.billingFullNameError.hidden = true
    })

    this.billingEmailField?.addEventListener('input', () => {
      if (this.billingEmailError) this.billingEmailError.hidden = true
    })

    this.dataHostingRegionField?.addEventListener('input', () => {
      if (this.dataHostingRegionError) this.dataHostingRegionError.hidden = true
    })

    this.subdomainField?.addEventListener('input', () => {
      if (this.subdomainError) this.subdomainError.hidden = true
    })

    const hideTrialTermsError = () => {
      if (this.featuresDisabledWarningCheckbox?.checked && this.businessOwnedCheckbox?.checked) {
        if (this.trialTermsError) this.trialTermsError.hidden = true
      }
    }

    this.featuresDisabledWarningCheckbox?.addEventListener('change', hideTrialTermsError)
    this.businessOwnedCheckbox?.addEventListener('change', hideTrialTermsError)

    this.dataHostingCheckbox?.addEventListener('change', () => {
      if (this.dataHostingCheckbox?.checked) {
        if (this.dataHostingRegionFieldContainer) this.dataHostingRegionFieldContainer.hidden = false
        if (this.slugFieldContainer) this.slugFieldContainer.hidden = true
        if (this.shortcodeFieldContainer) this.shortcodeFieldContainer.hidden = true
        if (this.subdomainFieldContainer) this.subdomainFieldContainer.hidden = false
      } else {
        if (this.dataHostingRegionFieldContainer) this.dataHostingRegionFieldContainer.hidden = true
        if (this.slugFieldContainer) this.slugFieldContainer.hidden = false
        if (this.shortcodeFieldContainer) this.shortcodeFieldContainer.hidden = false
        if (this.subdomainFieldContainer) this.subdomainFieldContainer.hidden = true
      }
    })
  }
}

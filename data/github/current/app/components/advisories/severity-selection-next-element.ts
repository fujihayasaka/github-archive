import {controller, target} from '@github/catalyst'
import {debounce} from '@github/mini-throttle/decorators'
import {validate} from '../../assets/modules/github/behaviors/html-validation'
import type SeverityScoreElement from './severity-score-element'
import type CvssCalculatorElement from './cvss-calculator-element'

// FYI: Selection is a misnomer.  Do not be confused!  There is a selection control inside this.
// This an editor for all Severity information for an advisory, including a selection for a Severity field and
// CVSS vector string inputs, and calculators.  These are all dependent on each other.  This controller manages that.
@controller
export default class SeveritySelectionNextElement extends HTMLElement {
  // The expander around the calculator.  The selection element collapses and expands it based on other state in the selection.
  @target declare cvssCalculatorExpander: HTMLDetailsElement
  @target declare cvss3Calculator: CvssCalculatorElement
  @target declare cvss4Calculator: CvssCalculatorElement

  // A read-only final result of all severity edits summarized for the user, sometimes rendering "pending" text.
  // TODO: Is pending really needed? Can we remove the concept and just show 0?
  @target declare severityScore: SeverityScoreElement

  // A seleciton control which allows the user to select an authoritiative severity value, which overrides other
  // severity inputs. There is a special option in the drop-down which allows a user to enter CVSS instead.
  // Overlap with the name of the controller is incidental.
  @target declare severitySelect: HTMLSelectElement

  // This is the container that is 1-1 with the form data for the CVSS vector string.
  // The actual input is within vectorStringInput. Error output for this field is in vectorStringError.
  @target declare vectorStringField: HTMLElement
  @target declare vectorStringError: HTMLElement
  @target declare vectorStringInput: HTMLInputElement

  cvssCalculator() {
    return this.severitySelect.value === 'cvss_v3' ? this.cvss3Calculator : this.cvss4Calculator
  }

  buildCVSSErrorMessage(vectorString: string): string {
    if (vectorString === '') {
      return this.vectorStringError.getAttribute('data-empty-cvss-error-message') || ''
    }

    const cvssPattern = this.cvssCalculator().isCvssV4
      ? /^CVSS:4\.\d+(\/[^:]+:[^:]+){11}$/
      : /^CVSS:3\.\d+(\/[^:]+:[^:]+){8}$/

    if (!cvssPattern.test(vectorString)) {
      return this.vectorStringError.getAttribute('data-error-message') || ''
    }

    // Further check whether the typed code pairs are valid
    const keyValuePairs: string[] = vectorString.split('/').slice(1)

    for (const keyValuePair of keyValuePairs) {
      const [metricCode, value] = keyValuePair.split(':')

      if (!this.cvssCalculator().metricValidationHash[metricCode!]) {
        const errorText = this.vectorStringError.getAttribute('data-invalid-metric-error-message') || ''
        return errorText.replace('{}', metricCode!)
      }

      if (!this.cvssCalculator().metricValidationHash[metricCode!]![value!]) {
        const errorText = this.vectorStringError.getAttribute('data-invalid-metric-value-error-message') || ''
        return errorText.replace('{}', value!).replace('{}', metricCode!)
      }
    }

    return ''
  }

  connectedCallback() {
    // When you press the browser back button after submitting an advisory with a vector string,
    // or you edit an existing advisory, it renders the CVSS calculator collapsed.  We need to
    // bring it up.  The unselected select is not populated with the CVSS option until this method
    // is over, so to make things work we have to delay the check for the selected value.
    setTimeout(() => {
      if (this.severitySelect.value === 'cvss_v3' || this.severitySelect.value === 'cvss_v4') {
        this.toggleSeverityCalculator(this.severitySelect.value)
      } else if (this.severitySelect.value) {
        // Initialize simple severity label and score range on load
        this.severityScore.severity = this.severitySelect.value
      }
    }, 0)

    this.handleVectorStringInput()
  }

  setDefaultVectorString() {
    const previousVectorStringValue = this.vectorStringInput.value

    // User selected one of the "Assess severity using CVSS" options
    if (this.getAttribute('data-cvss-select-action') === 'true') {
      const selectedCalculator = this.cvssCalculator()

      // User selected one of the "Assess severity using CVSS" options after the calculator was already open or
      // they toggled it open when there was a previous, non-default vector string set
      if (this.cvssCalculatorExpander.hasAttribute('open') && previousVectorStringValue) {
        this.vectorStringInput.value = previousVectorStringValue
        this.vectorStringInput.setAttribute('data-previous-value', this.vectorStringInput.value)

        selectedCalculator.vectorString = this.vectorStringInput.value
      } else if (!this.cvssCalculatorExpander.hasAttribute('open') && previousVectorStringValue) {
        // User toggled the calculator closed after using one of the "Assess severity by CVSS" options

        // If the user entered an invalid vector string and then toggles the calculator closed, we want to reset the
        // vector string to the default value and remove the error message
        if (!this.isValidCVSS(previousVectorStringValue)) {
          this.vectorStringInput.value = selectedCalculator.defaultVectorString || ''
          this.hideFormGroupError(this.vectorStringField)
        } else {
          this.vectorStringInput.value = previousVectorStringValue
        }

        this.vectorStringInput.setAttribute('data-previous-value', this.vectorStringInput.value)

        selectedCalculator.vectorString = this.vectorStringInput.value
      } else if (this.cvssCalculatorExpander.hasAttribute('open') && !previousVectorStringValue) {
        // User selected one of the "Assess severity using CVSS" options after the calculator was already open or
        // another "Assess severity using CVSS" had previosly been selected
        this.vectorStringInput.value = selectedCalculator.defaultVectorString || ''
        this.vectorStringInput.setAttribute('data-previous-value', this.vectorStringInput.value)

        selectedCalculator.vectorString = this.vectorStringInput.value

        this.toggleSeverityCalculator(this.severitySelect.value)
      } else if (!this.cvssCalculatorExpander.hasAttribute('open') && !previousVectorStringValue) {
        // User selected one of the "Assess severity using CVSS" options while the calculator was not open
        this.vectorStringInput.value = selectedCalculator.defaultVectorString || ''
        this.vectorStringInput.setAttribute('data-previous-value', this.vectorStringInput.value)

        selectedCalculator.vectorString = this.vectorStringInput.value

        this.toggleSeverityCalculator(this.severitySelect.value)
      }

      return
    } else if (this.getAttribute('data-severity-select-action') === 'true') {
      // User selected a non-CVSS severity option
      if (
        this.severitySelect.value !== '' &&
        this.severitySelect.value !== 'cvss_v3' &&
        this.severitySelect.value !== 'cvss_v4'
      ) {
        this.toggleSeverityCalculator(this.severitySelect.value)
      }
    } else {
      // User toggled the calculator
      let toggledCalculator = this.cvssCalculator().isCvssV4 ? this.cvss3Calculator : this.cvss4Calculator

      if (
        !this.isValidCVSS(previousVectorStringValue) ||
        previousVectorStringValue?.startsWith('CVSS:3.0') ||
        previousVectorStringValue?.startsWith('CVSS:3.1')
      ) {
        toggledCalculator = this.cvss3Calculator
      } else if (previousVectorStringValue?.startsWith('CVSS:4.0')) {
        toggledCalculator = this.cvss4Calculator
      }

      // If the user entered an invalid vector string and then toggles the calculator closed, we want to reset the
      // vector string to the default value and remove the error message
      if (!this.isValidCVSS(previousVectorStringValue)) {
        this.vectorStringInput.value = toggledCalculator.defaultVectorString || ''
        this.hideFormGroupError(this.vectorStringField)
      }

      // User toggled the calculator open after a previous vector string had been set
      if (this.cvssCalculatorExpander.hasAttribute('open') && previousVectorStringValue) {
        this.vectorStringInput.value = previousVectorStringValue
        this.vectorStringInput.setAttribute('data-previous-value', this.vectorStringInput.value)

        toggledCalculator.vectorString = this.vectorStringInput.value
        this.severitySelect.value = toggledCalculator.isCvssV4 ? 'cvss_v4' : 'cvss_v3'

        this.toggleSeverityCalculator(this.severitySelect.value)
      } else if (this.cvssCalculatorExpander.hasAttribute('open')) {
        // User toggled the calculator open when no previous vector string had been set
        this.vectorStringInput.value = toggledCalculator.defaultVectorString || ''
        this.vectorStringInput.setAttribute('data-previous-value', this.vectorStringInput.value)

        toggledCalculator.vectorString = this.vectorStringInput.value
        this.severitySelect.value = toggledCalculator.isCvssV4 ? 'cvss_v4' : 'cvss_v3'

        this.toggleSeverityCalculator(this.severitySelect.value)
      }

      return
    }
  }

  toggleSeverityCalculator(value: string) {
    if (value === 'cvss_v3') {
      this.cvss3Calculator.hidden = false
      this.cvss4Calculator.hidden = true
      this.updateVectorStringInputCvssVersion(value)
    } else if (value === 'cvss_v4') {
      this.cvss3Calculator.hidden = true
      this.cvss4Calculator.hidden = false
      this.updateVectorStringInputCvssVersion(value)
    } else {
      this.cvss3Calculator.hidden = true
      this.cvss4Calculator.hidden = true
      this.updateVectorStringInputCvssVersion('cvss_v3')
    }

    if (value === 'cvss_v3' || value === 'cvss_v4') {
      if (
        this.vectorStringInput.hasAttribute('data-previous-value') &&
        this.vectorStringInput.value !== this.cvss3Calculator.defaultVectorString &&
        this.vectorStringInput.value !== this.cvss4Calculator.defaultVectorString
      ) {
        this.vectorStringInput.value = this.vectorStringInput.getAttribute('data-previous-value')!

        // TODO : Is it necessary to call both of these here?
        // See comments beginning here: https://github.com/github/github/pull/335178#discussion_r1714388363
        this.handleVectorStringInput()
        this.handleVectorStringBlur()
      } else if (
        this.vectorStringInput.value === this.cvss3Calculator.defaultVectorString ||
        this.vectorStringInput.value === this.cvss4Calculator.defaultVectorString
      ) {
        // If we switch between the v3 and v4 "Assess by CVSS" options, we need to reset the severity score
        this.severityScore.setPending()
      }

      this.showSeverityCalculator()
    } else {
      if (this.vectorStringInput.value !== '') {
        this.vectorStringInput.setAttribute('data-previous-value', this.vectorStringInput.value)

        this.vectorStringInput.value = ''
      }

      if (value === '') {
        this.severityScore.setPending()
      } else {
        this.severityScore.severity = value
      }

      this.hideSeverityCalculator()
    }
  }

  // Used when the user or code modifies the CVSS calculator using the user interface controls
  async handleCalculatorSelectionChanged(customEvent: CustomEvent<{userInitiated: boolean}>) {
    if (customEvent.detail.userInitiated) {
      this.vectorStringInput.removeAttribute('data-previous-value')
      this.regenerateVectorString()
      this.hideFormGroupError(this.vectorStringField)

      // Only compute the score if all of the metric controls have been selected
      if (this.isValidCVSS(this.vectorStringInput.value)) {
        this.vectorStringInput.setCustomValidity('')

        await this.severityScore.calculateScore(this.vectorStringInput.value)
      } else {
        this.vectorStringInput.setCustomValidity(this.vectorStringErrorMessage)
        this.severityScore.setPending()
      }

      validate(this.vectorStringInput.form!)
    }
  }

  handleSeveritySelectChange(event: Event) {
    const {value} = event.target as HTMLSelectElement

    this.vectorStringInput.value = ''

    if (value === 'cvss_v3' || value === 'cvss_v4') {
      this.setAttribute('data-cvss-select-action', 'true')
    } else {
      this.setAttribute('data-severity-select-action', 'true')
    }

    this.setDefaultVectorString()
  }

  // TODO : Rename this method to follow Catalyst conventions and reflect
  // intent instead of reading like an event handler.
  // See the comments starting here: https://github.com/github/github/pull/335178#discussion_r1714366344
  async handleVectorStringBlur() {
    // Don't update the score if a severity was already manually selected and no vector string input was given
    if (
      this.severitySelect.value !== 'cvss_v3' &&
      this.severitySelect.value !== 'cvss_v4' &&
      this.vectorStringInput.value === ''
    )
      return

    if (this.cvssCalculator() === this.cvss3Calculator) {
      this.severitySelect.value = 'cvss_v3'
    } else {
      this.severitySelect.value = 'cvss_v4'
    }

    if (this.validateVectorStringInput()) {
      await this.severityScore.calculateScore(this.vectorStringInput.value)
    } else {
      this.severityScore.setPending()
    }
  }

  // TODO : Rename this method to follow Catalyst conventions and reflect
  // intent instead of reading like an event handler.
  // See the comments starting here: https://github.com/github/github/pull/335178#discussion_r1714366344
  @debounce(100)
  handleVectorStringInput() {
    const newVectorString: string = this.vectorStringInput.value

    this.severitySelect.setAttribute('data-previous-value', this.severitySelect.value)
    this.vectorStringInput.setAttribute('data-previous-value', this.vectorStringInput.value)

    if (this.vectorStringInput.value.startsWith('CVSS:3.0') || this.vectorStringInput.value.startsWith('CVSS:3.1')) {
      // When a user edits an existing advisory with a CVSS v4 vector string and pastes a CVSS v3
      // vector string into the input, we need to switch to the v3 calculator
      if (this.cvssCalculator() === this.cvss4Calculator) {
        this.cvss3Calculator.hidden = false
        this.cvss4Calculator.hidden = true
      }

      this.severitySelect.value = 'cvss_v3'

      this.updateVectorStringInputCvssVersion('cvss_v3')
    } else if (this.vectorStringInput.value.startsWith('CVSS:4.0')) {
      // When a user edits an existing advisory with a CVSS v3 vector string and pastes a CVSS v4
      // vector string into the input, we need to switch to the v4 calculator
      if (this.cvssCalculator() === this.cvss3Calculator) {
        this.cvss3Calculator.hidden = true
        this.cvss4Calculator.hidden = false
      }

      this.severitySelect.value = 'cvss_v4'

      this.updateVectorStringInputCvssVersion('cvss_v4')
    }

    this.cvssCalculator().vectorString = newVectorString
  }

  hideFormGroupError(formGroup: HTMLElement) {
    if (formGroup.classList.contains('errored')) {
      formGroup.classList.remove('errored')
    }
  }

  hideSeverityCalculator() {
    this.cvssCalculatorExpander.removeAttribute('open')
    this.cvss3Calculator.hidden = true
    this.cvss4Calculator.hidden = true

    this.vectorStringInput.required = false

    this.hideFormGroupError(this.vectorStringField)
    this.vectorStringInput.setCustomValidity('')

    validate(this.vectorStringInput.form!)
  }

  isValidCVSS(vectorString: string): boolean {
    return this.buildCVSSErrorMessage(vectorString) === ''
  }

  regenerateVectorString() {
    this.vectorStringInput.value = this.cvssCalculator().vectorString
  }

  resetSeveritySelectElement() {
    for (let optionIndex = 0; optionIndex < this.severitySelect.options.length; optionIndex++) {
      const severitySelectOption = this.severitySelect.options[optionIndex]!

      if (severitySelectOption.defaultSelected) {
        this.severitySelect.selectedIndex = optionIndex

        break
      }
    }
  }

  showFormGroupError(formGroup: HTMLElement) {
    if (!formGroup.classList.contains('errored')) {
      formGroup.classList.add('errored')
    }
  }

  showSeverityCalculator() {
    this.cvssCalculatorExpander.setAttribute('open', '')

    this.vectorStringInput.required = true

    if (this.vectorStringInput.value !== '') {
      this.validateVectorStringInput()
    }
  }

  // Updates the name and ID of the vector string input to make sure the form prefix
  // uses the correct CVSS version
  updateVectorStringInputCvssVersion(cvss_version: string) {
    const current_name_value = this.vectorStringInput.name
    const updated_name_value = current_name_value.replace(/cvss_v\d/, `${cvss_version}`)

    const current_id_value = this.vectorStringInput.id
    const updated_id_value = current_id_value.replace(/cvss_v\d/, `${cvss_version}`)

    this.vectorStringInput.name = updated_name_value
    this.vectorStringInput.id = updated_id_value
  }

  // Returns true if a vector string is typed and valid
  validateVectorStringInput(): boolean {
    const error: string = this.buildCVSSErrorMessage(this.vectorStringInput.value)

    if (!error) {
      this.hideFormGroupError(this.vectorStringField)
      this.vectorStringInput.setCustomValidity('')
    } else {
      this.vectorStringError.textContent = error

      this.showFormGroupError(this.vectorStringField)
      this.vectorStringInput.setCustomValidity(this.vectorStringErrorMessage)
    }

    validate(this.vectorStringInput.form!)

    return !error
  }

  get vectorStringErrorMessage() {
    return (
      this.vectorStringError.getAttribute('data-error-message') ||
      // eslint-disable-next-line i18n-text/no-en
      'Please fill out this field with a valid vector string'
    )
  }
}

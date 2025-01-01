import {controller, targets} from '@github/catalyst'
import type CvssV4SingleMetricSelectionElement from './cvss-calculator-metric-element'

@controller
export default class CvssCalculatorElement extends HTMLElement {
  // Each individual metric tracked in here
  @targets declare singleMetricSelections: CvssV4SingleMetricSelectionElement[]

  public get vectorString(): string {
    let vectorString = this.cvssVersionPreamble

    for (const metricSelectionNextElement of this.singleMetricSelections) {
      const metricCode = metricSelectionNextElement.metricCode
      const selectedValue = metricSelectionNextElement.selectedValue || '_'

      vectorString += `/${metricCode}:${selectedValue}`
    }

    return vectorString
  }

  private get cvssVersionPreamble() {
    return this.getAttribute('data-cvss-version-preamble')!
  }

  public get metricValidationHash() {
    return JSON.parse(this.getAttribute('data-validation-json-hash')!)
  }

  public get defaultVectorString() {
    return this.getAttribute('data-default-vector-string')
  }

  public get isCvssV4() {
    return this.getAttribute('data-is-cvss-v4') === 'true'
  }

  public set vectorString(vectorString: string) {
    const keyValuePairs: string[] = vectorString.split('/').slice(1)
    const metricSelections: {[index: string]: string} = keyValuePairs.reduce((selectionHash, keyValuePair) => {
      const [metricCode, value] = keyValuePair.split(':')

      return {
        ...selectionHash,
        [metricCode!]: value,
      }
    }, {})

    for (const metricSelectionNextElement of this.singleMetricSelections) {
      const metricCode: string = metricSelectionNextElement.metricCode!
      const selectionCode = metricSelections[metricCode]!

      metricSelectionNextElement.selectFromCode(selectionCode)
    }
  }

  async handleMetricSelectionChange(customEvent: CustomEvent<{userInitiated: boolean}>) {
    const userInitiated = customEvent.detail.userInitiated
    this.dispatchEvent(
      new CustomEvent<{userInitiated: boolean}>('vectorStringSelectionChange', {detail: {userInitiated}}),
    )
  }
}

import {controller, target, targets} from '@github/catalyst'
import type MetricSelectionElement from './metric-selection-element'

@controller
export default class SeverityCalculatorElement extends HTMLElement {
  @target declare detailsElement: HTMLDetailsElement
  @targets declare metricSelectionElements: MetricSelectionElement[]

  collapse() {
    this.detailsElement.removeAttribute('open')
  }

  deselectAll() {
    for (const metricSelectionElement of this.metricSelectionElements) {
      metricSelectionElement.deselect()
    }
  }

  expand() {
    this.detailsElement.setAttribute('open', '')
  }

  hide() {
    this.hidden = true
  }

  show() {
    this.hidden = false
  }
}

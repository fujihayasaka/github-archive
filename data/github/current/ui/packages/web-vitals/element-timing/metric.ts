import {getSelector} from '../get-selector'

export class ElementTimingMetric {
  name = 'ElementTiming' as const
  value: number
  identifier: string
  attribution: {
    element?: string
  }

  declare app: string

  constructor(value: number, element: Element, identifier: string) {
    this.value = value
    this.identifier = identifier
    this.attribution = {
      element: getSelector(element),
    }
  }
}

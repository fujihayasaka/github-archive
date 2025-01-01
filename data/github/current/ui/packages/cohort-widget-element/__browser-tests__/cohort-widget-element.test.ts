import {beforeEach, describe, it, assert, fixture, html} from '@github-ui/browser-tests'
import {CohortWidgetElement} from '../cohort-widget-element'

describe('cohort-widget-element', () => {
  let container: CohortWidgetElement

  beforeEach(async function () {
    container = await fixture(html`<cohort-widget></cohort-widget>`)
  })

  it('isConnected', () => {
    assert.isTrue(container.isConnected)
    assert.instanceOf(container, CohortWidgetElement)
  })
})

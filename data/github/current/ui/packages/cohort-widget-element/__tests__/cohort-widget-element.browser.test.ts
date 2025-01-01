import {beforeEach, describe, it} from '@github-ui/tests'
import {assert, fixture, html} from '@github-ui/tests/browser'
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

// eslint-disable-next-line import/no-extraneous-dependencies
import {assert, fixture, html} from '@github-ui/tests/browser'
// eslint-disable-next-line import/no-extraneous-dependencies
import {beforeEach, describe, it} from '@github-ui/tests'
import {EducationOverviewComponentElement} from '../education-overview-component-element'

describe('education-overview-component-element', () => {
  let container: EducationOverviewComponentElement

  beforeEach(async function () {
    container = await fixture(html`<education-overview-component></education-overview-component>`)
  })

  it('isConnected', () => {
    assert.isTrue(container.isConnected)
    assert.instanceOf(container, EducationOverviewComponentElement)
  })
})

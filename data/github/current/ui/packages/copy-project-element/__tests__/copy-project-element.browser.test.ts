import {beforeEach, describe, it} from '@github-ui/tests'
import {assert, fixture, html} from '@github-ui/tests/browser'
import {CopyProjectElement} from '../copy-project-element'

describe('copy-project-element', () => {
  let container: CopyProjectElement

  beforeEach(async function () {
    container = await fixture(html`<copy-project></copy-project>`)
  })

  it('isConnected', () => {
    assert.isTrue(container.isConnected)
    assert.instanceOf(container, CopyProjectElement)
  })
})

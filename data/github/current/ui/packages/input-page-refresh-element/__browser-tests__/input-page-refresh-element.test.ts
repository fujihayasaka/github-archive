import {beforeEach, describe, it, assert, fixture, html} from '@github-ui/browser-tests'
import {InputPageRefreshElement} from '../input-page-refresh-element'

describe('input-page-refresh-element', () => {
  let container: InputPageRefreshElement

  beforeEach(async function () {
    container = await fixture(html`<input-page-refresh></input-page-refresh>`)
  })

  it('isConnected', () => {
    assert.isTrue(container.isConnected)
    assert.instanceOf(container, InputPageRefreshElement)
  })
})

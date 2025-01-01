import {beforeEach, describe, it, assert, fixture, html} from '@github-ui/browser-tests'
import {StafftoolsTopicsTableElement} from '../stafftools-topics-table-element'

describe('stafftools-topics-table-element', () => {
  let container: StafftoolsTopicsTableElement

  beforeEach(async function () {
    container = await fixture(html`<stafftools-topics-table></stafftools-topics-table>`)
  })

  it('isConnected', () => {
    assert.isTrue(container.isConnected)
    assert.instanceOf(container, StafftoolsTopicsTableElement)
  })
})

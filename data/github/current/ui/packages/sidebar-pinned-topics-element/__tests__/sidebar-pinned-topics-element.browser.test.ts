import {beforeEach, describe, it} from '@github-ui/tests'
import {assert, fixture, html} from '@github-ui/tests/browser'
import {SidebarPinnedTopicsElement} from '../sidebar-pinned-topics-element'

describe('sidebar-pinned-topics-element', () => {
  let container: SidebarPinnedTopicsElement

  beforeEach(async function () {
    container = await fixture(html`<sidebar-pinned-topics></sidebar-pinned-topics>`)
  })

  it('isConnected', () => {
    assert.isTrue(container.isConnected)
    assert.instanceOf(container, SidebarPinnedTopicsElement)
  })
})

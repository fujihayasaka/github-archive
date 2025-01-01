import {beforeEach, describe, it, assert, fixture, html} from '@github-ui/browser-tests'
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

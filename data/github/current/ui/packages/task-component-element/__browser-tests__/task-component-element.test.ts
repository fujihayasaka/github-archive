import {beforeEach, describe, it, assert, fixture, html} from '@github-ui/browser-tests'
import {TaskComponentElement} from '../task-component-element'

describe('task-component-element', () => {
  let container: TaskComponentElement

  beforeEach(async function () {
    container = await fixture(html`<task-component></task-component>`)
  })

  it('isConnected', () => {
    assert.isTrue(container.isConnected)
    assert.instanceOf(container, TaskComponentElement)
  })
})

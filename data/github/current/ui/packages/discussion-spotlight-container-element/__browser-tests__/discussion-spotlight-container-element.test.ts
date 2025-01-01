import {beforeEach, describe, it, assert, fixture, html} from '@github-ui/browser-tests'
import {DiscussionSpotlightContainerElement} from '../discussion-spotlight-container-element'
import {stub} from 'sinon'

// Run these tests via:
// npm run test:watch ui/packages/discussion-spotlight-container-element/__browser-tests__/discussion-spotlight-container-element.test.ts
describe('discussion-spotlight-container-element', () => {
  let container: DiscussionSpotlightContainerElement

  beforeEach(async function () {
    container = await fixture(
      html`<discussion-spotlight-container>
        <div data-action="click:discussion-spotlight-container#openDiscussionLink">
          <a href="/some/url" data-target="discussion-spotlight-container.mainLink">The main link</a>
          <p>Some other text you might click and want to visit the pinned discussion</p>
        </div>
      </discussion-spotlight-container>`,
    )
  })

  it('isConnected', () => {
    assert.isTrue(container.isConnected)
    assert.instanceOf(container, DiscussionSpotlightContainerElement)
    assert.instanceOf(container.mainLink, HTMLAnchorElement)
  })

  it('clicking the container navigates to the main link', () => {
    const mainLinkClickStub = stub(container.mainLink!, 'click')
    container.querySelector('div')?.click()
    assert.isTrue(mainLinkClickStub.calledOnce)
  })

  it('clicking another element in the container navigates to the main link', () => {
    const mainLinkClickStub = stub(container.mainLink!, 'click')
    container.querySelector('p')?.click()
    assert.isTrue(mainLinkClickStub.calledOnce)
  })

  it('clicking in the container does not navigate to the main link when text is selected', () => {
    const mainLinkClickStub = stub(container.mainLink!, 'click')
    const paragraph = container.querySelector('p')!
    const selection = container.ownerDocument.getSelection()
    const range = container.ownerDocument.createRange()
    range.selectNodeContents(paragraph)
    selection?.removeAllRanges()
    selection?.addRange(range)

    container.querySelector('div')?.click()

    assert.isFalse(mainLinkClickStub.called, 'should not have fired click on link when text is selected')
  })
})

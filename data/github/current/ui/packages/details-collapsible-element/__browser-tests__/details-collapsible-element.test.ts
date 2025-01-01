import {beforeEach, describe, it, assert, fixture, html} from '@github-ui/browser-tests'
import {DetailsCollapsibleElement} from '../details-collapsible-element'

describe('details-collapsible-element', () => {
  let container: DetailsCollapsibleElement

  beforeEach(async function () {
    container = await fixture(html`
      <details-collapsible>
        <details open="true" data-target="details-collapsible.detailsElement">
          <summary
            aria-expanded="true"
            aria-label="Collapse me"
            data-target="details-collapsible.summaryElement"
            data-action="click:details-collapsible#toggle"
            data-aria-label-closed="Expand me"
            data-aria-label-open="Collapse me"
          >
            Click me
          </summary>
          <div>Contents</div>
        </details>
      </details-collapsible>
    `)
  })

  it('isConnected', () => {
    assert.isTrue(container.isConnected)
    assert.instanceOf(container, DetailsCollapsibleElement)
  })
})

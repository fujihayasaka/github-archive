import {beforeEach, describe, it, assert, fixture, html} from '@github-ui/browser-tests'
import {TestCatalystPackageElement} from '../test-catalyst-package-element'

describe('test-catalyst-package-element', () => {
  let container: TestCatalystPackageElement

  beforeEach(async function () {
    container = await fixture(html`<test-catalyst-package></test-catalyst-package>`)
  })

  it('isConnected', () => {
    assert.isTrue(container.isConnected)
    assert.instanceOf(container, TestCatalystPackageElement)
  })
})

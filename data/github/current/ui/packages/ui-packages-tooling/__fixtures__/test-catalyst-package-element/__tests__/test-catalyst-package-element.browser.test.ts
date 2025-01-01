import {assert, fixture, html} from '@github-ui/tests/browser'
import {beforeEach, describe, it} from '@github-ui/tests'
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

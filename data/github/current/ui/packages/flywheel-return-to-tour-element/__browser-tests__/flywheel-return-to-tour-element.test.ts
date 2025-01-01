import {beforeEach, describe, it, assert, fixture, html} from '@github-ui/browser-tests'
import {FlywheelReturnToTourElement} from '../flywheel-return-to-tour-element'

describe('flywheel-return-to-tour-element', () => {
  let container: FlywheelReturnToTourElement

  beforeEach(async function () {
    container = await fixture(html`<flywheel-return-to-tour></flywheel-return-to-tour>`)
  })

  it('isConnected', () => {
    assert.isTrue(container.isConnected)
    assert.instanceOf(container, FlywheelReturnToTourElement)
  })
})

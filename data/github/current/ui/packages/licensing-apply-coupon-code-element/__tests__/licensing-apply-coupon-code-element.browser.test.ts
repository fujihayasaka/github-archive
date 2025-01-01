import {beforeEach, describe, it} from '@github-ui/tests'
import {assert, fixture, html} from '@github-ui/tests/browser'
import {LicensingApplyCouponCodeElement} from '../licensing-apply-coupon-code-element'

describe('licensing-apply-coupon-code-element', () => {
  let container: LicensingApplyCouponCodeElement

  beforeEach(async function () {
    container = await fixture(html`
      <licensing-apply-coupon-code>
        <input
          type="checkbox"
          name="apply_coupon_code"
          data-action="change:licensing-apply-coupon-code#toggleCouponCode"
        />
        <div data-target="licensing-apply-coupon-code.couponCodeSection" hidden>
          <input type="text" name="coupon_code" />
        </div>
      </licensing-apply-coupon-code>
    `)
  })

  it('isConnected', () => {
    assert.isTrue(container.isConnected)
    assert.instanceOf(container, LicensingApplyCouponCodeElement)
  })

  it('shows hidden section when checkbox is checked', async () => {
    const checkbox = container.querySelector('input[type="checkbox"]') as HTMLInputElement
    const hiddenSection = container.querySelector(
      '[data-target="licensing-apply-coupon-code.couponCodeSection"]',
    ) as HTMLElement

    assert.isTrue(hiddenSection.hidden, 'section should be hidden initially')

    checkbox.checked = true
    checkbox.dispatchEvent(new Event('change'))

    assert.isFalse(hiddenSection.hidden, 'section should be visible when checkbox is checked')
  })
})

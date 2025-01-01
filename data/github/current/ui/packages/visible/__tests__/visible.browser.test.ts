import {beforeEach, describe, it} from '@github-ui/tests'
import {assert, fixture, html} from '@github-ui/tests/browser'
import visible from '../visible'

describe('github/visible', function () {
  beforeEach(function () {
    fixture(html`
      <div class="js-test js-hidden" style="display:none;"></div>
      <div class="js-test js-hidden" style="display:none;"></div>
      <div class="js-test js-visible"></div>
    `)
  })

  it('finds only visible elements', function () {
    assert.equal(1, Array.from(document.querySelectorAll<HTMLElement>('.js-test')).filter(visible).length)
  })

  it('can be used as a visible predicate', function () {
    const selector = document.querySelector<HTMLElement>('.js-visible')

    assert.isNotNull(selector)
    assert.isOk(visible(selector))
  })

  it('can be used as a hidden predicate', function () {
    const selector = document.querySelector<HTMLElement>('.js-hidden')

    assert.isNotNull(selector)
    assert.isOk(!visible(selector))
  })
})

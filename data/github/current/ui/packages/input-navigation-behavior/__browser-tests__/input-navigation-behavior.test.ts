import {beforeEach, describe, it, assert, fixture, html} from '@github-ui/browser-tests'
import {clear, focus, refocus} from '../input-navigation-behavior'

describe('Navigation Behavior', function () {
  let container: HTMLElement

  beforeEach(async function () {
    container = await fixture(html`
      <ul class="js-navigation-container">
        <li class="js-navigation-item">One</li>
        <li class="js-navigation-item">Two</li>
        <li class="js-navigation-item">Three</li>
      </ul>
    `)
  })

  it('focus activates container', function () {
    assert.isOk(!container.classList.contains('js-active-navigation-container'))
    focus(container, container)
    assert.isOk(container.classList.contains('js-active-navigation-container'))
  })

  it('focus adds attribute to first item', function () {
    assert.isOk(!container.querySelector('.navigation-focus'))
    focus(container, container)
    assert.isOk(container.querySelector('.navigation-focus'))
  })

  it('clear current focus', function () {
    focus(container, container)
    assert.isOk(container.querySelector('.navigation-focus'))
    clear(container)
    assert.isOk(!container.querySelector('.navigation-focus'))
  })

  it('refocus adds class to first item', function () {
    assert.isOk(!container.querySelector('.navigation-focus'))
    refocus(container, container)
    assert.isOk(container.querySelector('.navigation-focus'))
  })

  it('focus empty container', function () {
    container.textContent = ''
    assert.isOk(!container.classList.contains('js-active-navigation-container'))
    focus(container, container)
    assert.isOk(container.classList.contains('js-active-navigation-container'))
  })

  it('focus fires navigation:focus event', function () {
    let focused = false
    container.addEventListener('navigation:focus', () => (focused = true), {once: true})
    focus(container, container)
    assert.isOk(focused)
  })

  it('canceling focus event prevents class from being added', function () {
    assert.isOk(!container.querySelector('.navigation-focus'))
    container.addEventListener('navigation:focus', event => event.preventDefault(), {once: true})
    focus(container, container)
    assert.isOk(!container.querySelector('.navigation-focus'))
  })
})

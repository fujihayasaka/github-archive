import {beforeEach, describe, it, assert, fixture, html} from '@github-ui/browser-tests'
import {onInput, onKey} from '../onfocus'
// eslint-disable-next-line no-restricted-imports
import {fire} from 'delegated-events'

describe('focused keyboard', function () {
  let input: HTMLInputElement | null

  beforeEach(async function () {
    const container = await fixture(html`<div id="doc"><input class="foo" /></div>`)
    input = container.querySelector('input')
  })

  if (navigator.userAgent.match('Firefox')) {
    return
  }

  it('onKey', function () {
    return new Promise<void>(resolve => {
      onKey('keydown', 'input.foo', function (event) {
        const target = event.target as HTMLInputElement

        assert.isNotNull(target)
        assert.isOk(target.matches('input.foo'))
        assert.equal(event.type, 'keydown')

        // We are explicitly testing for the 'a' key here, so we need to disable the eslint rule
        // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
        assert.equal(event.key, 'a')
        resolve()
      })

      assert.isNotNull(input)
      input!.focus()
      input!.dispatchEvent(new KeyboardEvent('keydown', {key: 'a'}))
    })
  })

  it('onInput', function () {
    return new Promise<void>(resolve => {
      onInput('input.foo', function (event) {
        const target = event.target as HTMLInputElement

        assert.isNotNull(target)
        assert.isOk(target.matches('input.foo'))
        assert.equal(event.type, 'input')
        resolve()
      })

      assert.isNotNull(input)
      input!.focus()
      fire(input!, 'input')
    })
  })
})

import {beforeEach, describe, it} from '@github-ui/tests'
import {assert, fixture, html} from '@github-ui/tests/browser'
import {VisiblePasswordElement} from '../visible-password-element'

describe('visible-password-element', () => {
  let container: VisiblePasswordElement

  beforeEach(async function () {
    container = await fixture(html`<visible-password></visible-password>`)
  })

  it('isConnected', () => {
    assert.isTrue(container.isConnected)
    assert.instanceOf(container, VisiblePasswordElement)
  })

  it('it should not break when input is undefined', async () => {
    container = await fixture(
      html`<visible-password>
        <button data-target="visible-password.showButton" />
        <button data-target="visible-password.hideButton" />
      </visible-password>`,
    )
    assert.doesNotThrow(() => container.show())
    assert.doesNotThrow(() => container.hide())
  })

  it('it should not break when showButton is undefined', async () => {
    container = await fixture(
      html`<visible-password>
        <input type="password" data-target="visible-password.input" />
        <button data-target="visible-password.hideButton" />
      </visible-password>`,
    )
    assert.doesNotThrow(() => container.show())
    assert.doesNotThrow(() => container.hide())
  })

  it('it should not break when hideButton is undefined', async () => {
    container = await fixture(
      html`<visible-password>
        <input type="password" data-target="visible-password.input" />
        <button data-target="visible-password.showButton" />
      </visible-password>`,
    )
    assert.doesNotThrow(() => container.show())
    assert.doesNotThrow(() => container.hide())
  })

  it('it should toggle the input type to text and hide the buttons when show is called', async () => {
    container = await fixture(
      html`<visible-password>
        <input type="password" data-target="visible-password.input" />
        <button data-target="visible-password.showButton" />
        <button data-target="visible-password.hideButton" />
      </visible-password>`,
    )
    container.show()

    assert.equal(container.input?.type, 'text')
    assert.equal(container.showButton?.hidden, true)
    assert.equal(container.hideButton?.hidden, false)
  })

  it('it should toggle the input type to text and hide the buttons when hide is called', async () => {
    container = await fixture(
      html`<visible-password>
        <input type="password" data-target="visible-password.input" />
        <button data-target="visible-password.showButton" />
        <button data-target="visible-password.hideButton" />
      </visible-password>`,
    )
    container.hide()

    assert.equal(container.input?.type, 'password')
    assert.equal(container.showButton?.hidden, false)
    assert.equal(container.hideButton?.hidden, true)
  })
})

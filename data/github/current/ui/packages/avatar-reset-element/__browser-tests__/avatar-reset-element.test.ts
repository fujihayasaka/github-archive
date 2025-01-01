import {beforeEach, afterEach, describe, it, assert, fixture, html, waitUntil} from '@github-ui/browser-tests'
import {AvatarResetElement} from '../avatar-reset-element'
import {setupWorker, type SetupWorker} from 'msw/browser'
import {http} from 'msw'

describe('avatar-reset-element', () => {
  let worker: SetupWorker
  let container: AvatarResetElement
  let gravatarInfoLoaded = false

  beforeEach(async function () {
    worker = setupWorker(
      http.get('/gravatar', () => {
        return new Response(JSON.stringify({has_gravatar: true}))
      }),
    )
    worker.events.on('response:mocked', () => {
      gravatarInfoLoaded = true
    })

    await worker.start()
    container = await fixture(html`<avatar-reset></avatar-reset>`)
  })

  afterEach(function () {
    gravatarInfoLoaded = false
    worker.stop()
  })

  it('isConnected', () => {
    assert.isTrue(container.isConnected)
    assert.instanceOf(container, AvatarResetElement)
  })

  it('does not change text if gravatar is disabled', async () => {
    container = await fixture(
      html`<avatar-reset data-url="/gravatar" data-gravatar-text="test">
        <button data-target="avatar-reset.removeButton">Remove</button>
      </avatar-reset>`,
    )

    assert.equal(container.removeButton.textContent, 'Remove')
  })

  it('does not change text if data-url is missing', async () => {
    container = await fixture(
      html`<avatar-reset data-gravatar-text="test" data-gravatar-enabled>
        <button data-target="avatar-reset.removeButton">Remove</button>
      </avatar-reset>`,
    )

    assert.equal(container.removeButton.textContent, 'Remove')
  })

  it('does not change text if data-gravatar-text is missing', async () => {
    container = await fixture(
      html`<avatar-reset data-url="/gravatar" data-gravatar-enabled>
        <button data-target="avatar-reset.removeButton">Remove</button>
      </avatar-reset>`,
    )

    assert.equal(container.removeButton.textContent, 'Remove')
  })

  it('does not change text if user does not have a gravatar', async () => {
    worker.use(
      http.get('/gravatar', () => {
        return new Response(JSON.stringify({has_gravatar: false}))
      }),
    )
    container = await fixture(
      html`<avatar-reset data-url="/gravatar" data-gravatar-text="test" data-gravatar-enabled>
        <button data-target="avatar-reset.removeButton">Remove</button>
      </avatar-reset>`,
    )

    await waitUntil(() => gravatarInfoLoaded, 'expected fetch gravatar info to be completed')
    assert.equal(container.removeButton.textContent, 'Remove')
  })

  it('changes text when user has gravatar', async () => {
    container = await fixture(
      html`<avatar-reset data-url="/gravatar" data-gravatar-text="test" data-gravatar-enabled>
        <button data-target="avatar-reset.removeButton">Remove</button>
      </avatar-reset>`,
    )

    await waitUntil(() => gravatarInfoLoaded, 'expected fetch gravatar info to be completed')
    assert.equal(container.removeButton.textContent, 'test')
  })
})

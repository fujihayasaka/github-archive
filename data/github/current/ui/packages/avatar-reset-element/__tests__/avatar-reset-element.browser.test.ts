import {beforeEach, afterEach, describe, it} from '@github-ui/tests'
import {assert, fixture, html, waitUntil} from '@github-ui/tests/browser'
import {msw, http} from '@github-ui/tests/msw'
import {AvatarResetElement} from '../avatar-reset-element'

describe('avatar-reset-element', () => {
  let container: AvatarResetElement
  let gravatarInfoLoaded = false
  let mswListener: (event: {request: Request}) => void

  beforeEach(async function () {
    msw.use(
      http.get('/gravatar', () => {
        return new Response(JSON.stringify({has_gravatar: true}))
      }),
    )
    mswListener = ({request}) => {
      if (request.url.includes('/gravatar')) {
        gravatarInfoLoaded = true
      }
    }
    msw.events.on('response:mocked', mswListener)

    container = await fixture(html`<avatar-reset></avatar-reset>`)
  })

  afterEach(function () {
    gravatarInfoLoaded = false
    msw.events.removeListener('response:mocked', mswListener)
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
    msw.use(
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
    await waitUntil(
      () => container.removeButton.textContent === 'test',
      'Expected to find `button` element with text "test"',
    )
  })
})

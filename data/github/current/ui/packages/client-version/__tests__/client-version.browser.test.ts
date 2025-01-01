import {it, describe, beforeAll} from '@github-ui/tests'
import {assert} from '@github-ui/tests/browser'

beforeAll(async function () {
  const version = document.createElement('meta')
  version.setAttribute('name', 'release')
  version.setAttribute('content', '12345')
  document.head.appendChild(version)
})

describe('client-version', () => {
  it('gets the client version once', async () => {
    // async import to avoid starting the module before the meta tag is added
    const {getClientVersion} = await import('../client-version')
    assert.equal(getClientVersion(), '12345')

    document.querySelector<HTMLMetaElement>('meta[name="release"]')?.setAttribute('content', '54321')
    assert.equal(getClientVersion(), '12345')
  })
})

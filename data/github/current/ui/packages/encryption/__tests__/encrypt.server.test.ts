import {describe, expect, it} from '@github-ui/tests'

import {encrypt} from '../encrypt'
import {newKeyPair, unseal} from '../test-helpers'

describe('encrypt', () => {
  it('can encrypt a value', async () => {
    const recipient = newKeyPair()

    const sealed = await encrypt(recipient.publicKey, 'test')

    const unsealed = unseal(sealed, recipient)

    const decoder = new TextDecoder()
    expect(decoder.decode(unsealed!)).toBe('test')
  })
})

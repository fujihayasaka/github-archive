import {describe, expect, it} from '@github-ui/tests'

import {encrypt} from '../encrypt'
import {newKeyPair, unseal} from '../test-helpers'
import {encode} from '../utils'

describe('encrypt', () => {
  it('can encrypt a value', async () => {
    const recipient = newKeyPair()

    const sealed = await encrypt(recipient.publicKey, 'test')

    const unsealed = unseal(sealed, recipient)

    const decoder = new TextDecoder()
    expect(decoder.decode(unsealed!)).toBe('test')
  })

  it('can encrypt with publicKey as base64', async () => {
    const recipient = newKeyPair()

    const sealed = await encrypt(encode(recipient.publicKey), 'test')

    const unsealed = unseal(sealed, recipient)

    const decoder = new TextDecoder()
    expect(decoder.decode(unsealed!)).toBe('test')
  })
})

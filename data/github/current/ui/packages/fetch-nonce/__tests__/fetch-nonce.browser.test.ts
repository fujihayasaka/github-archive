import {it, describe, beforeEach} from '@github-ui/tests'
import {assert} from '@github-ui/tests/browser'
import {addValidNonce, fetchNonces, getFetchNonce, getFetchNonceHeaders} from '../fetch-nonce'

beforeEach(async function () {
  fetchNonces.clear()
  addValidNonce('12345')
})

describe('fetch-nonce', () => {
  it('gets the nonce', async () => {
    assert.equal(getFetchNonce(), '12345')
    assert.deepEqual(Array.from(fetchNonces), ['12345'])
  })

  it('adds a valid nonce', async () => {
    addValidNonce('54321')
    assert.deepEqual(Array.from(fetchNonces), ['12345', '54321'])
  })

  describe('getFetchNonceHeaders', () => {
    it('does not add X-Fetch-Nonce-To-Validate if not validating a nonce', async () => {
      const headers = getFetchNonceHeaders()
      assert.deepEqual(headers, {
        'X-Fetch-Nonce': '12345',
      })
    })

    it('only adds one nonce to X-Fetch-Nonce when not validating a nonce', async () => {
      addValidNonce('54321')
      const headers = getFetchNonceHeaders()
      assert.deepEqual(headers, {
        'X-Fetch-Nonce': '12345',
      })
    })

    it('adds X-Fetch-Nonce-To-Validate when validating nonce', async () => {
      const headers = getFetchNonceHeaders('54321')
      assert.deepEqual(headers, {
        'X-Fetch-Nonce': '12345',
        'X-Fetch-Nonce-To-Validate': '54321',
      })
    })

    it('only adds matching X-Fetch-Nonce as header', async () => {
      addValidNonce('54321')

      const headers = getFetchNonceHeaders('54321')
      assert.deepEqual(headers, {
        'X-Fetch-Nonce': '54321',
        'X-Fetch-Nonce-To-Validate': '54321',
      })
    })

    it('adds all valid nonces as header if it doesnt match', async () => {
      addValidNonce('54321')

      const headers = getFetchNonceHeaders('invalid')
      assert.deepEqual(headers, {
        'X-Fetch-Nonce': '12345,54321',
        'X-Fetch-Nonce-To-Validate': 'invalid',
      })
    })
  })
})

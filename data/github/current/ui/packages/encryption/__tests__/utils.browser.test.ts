import {expect, it} from '@github-ui/tests'

import {decode, encode} from '../utils'

const abc_as_bytes = new Uint8Array([65, 66, 67]) // ABC
const abc_as_base64 = 'QUJD'

it('can encode a value', () => {
  expect(encode(abc_as_bytes)).toEqual(abc_as_base64)
})

it('can decode a value', () => {
  expect(decode(abc_as_base64)).toEqual(abc_as_bytes)
})

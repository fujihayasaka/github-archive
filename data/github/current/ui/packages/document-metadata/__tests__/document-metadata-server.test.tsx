/***
 * @jest-environment node
 */
// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {setTitle} from '../document-metadata'
import {announce} from '@github-ui/aria-live'

jest.mock('@github-ui/aria-live', () => ({
  announce: jest.fn(),
}))

describe('setTitle in server', () => {
  it('should not raise an error', () => {
    expect(() => setTitle('foo')).not.toThrow()
  })

  it("doesn't call announce", () => {
    setTitle('foo')

    expect(announce).not.toHaveBeenCalled()
  })
})

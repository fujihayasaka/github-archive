import {applyInsertBeforePatch} from '../insert-before-patch'
import {isFeatureEnabled} from '@github-ui/feature-flags'

jest.mock('@github-ui/feature-flags', () => ({
  isFeatureEnabled: jest.fn(),
}))

const mockedIsFeatureEnabled = jest.mocked(isFeatureEnabled)
const originalInsertBefore = Node.prototype.insertBefore

/**
 * This is the JSDOM error equivalent of the chrome error:
 * Failed to execute 'insertBefore' on 'Node': The node before which the new node is to be inserted is not a child of this node.
 */
const NotFoundError = 'The child can not be found in the parent.'

describe('insert-before-patch', () => {
  beforeEach(() => {
    Node.prototype.insertBefore = originalInsertBefore
  })

  describe('with feature flag disabled', () => {
    it('should not patch the function', () => {
      mockedIsFeatureEnabled.mockReturnValue(false)

      applyInsertBeforePatch()

      expect(Node.prototype.insertBefore).toBe(originalInsertBefore)
    })
  })

  describe('with feature flag enabled', () => {
    beforeEach(() => {
      mockedIsFeatureEnabled.mockReturnValue(true)
    })

    it('should patch the function', () => {
      applyInsertBeforePatch()

      expect(Node.prototype.insertBefore).not.toBe(originalInsertBefore)
    })

    it('should not error when used correctly', () => {
      applyInsertBeforePatch()

      const parent = document.createElement('div')
      const childNode = document.createElement('div')
      parent.appendChild(childNode)
      const nodeToInsert = document.createElement('div')

      expect(() => parent.insertBefore(nodeToInsert, childNode)).not.toThrow(NotFoundError)
    })

    it('should throw an error if stacktrace doesnt include react-dom', () => {
      applyInsertBeforePatch()

      const parent = document.createElement('div')
      const nonChildNode = document.createElement('div')
      const nodeToInsert = document.createElement('div')

      expect(() => parent.insertBefore(nodeToInsert, nonChildNode)).toThrow(NotFoundError)
    })

    it('should not throw an error if stacktrace includes react-dom', () => {
      const mockedThrowFunction = () => {
        const error = new Error(NotFoundError)
        error.stack = `at Node.insertBefore(/assets/environment-deadbeef.js:1:4866)
        at oH(/assets/react-lib-deadbeef.js:25:84971)
        at oq(/assets/react-lib-deadbeef.js:25:86212)
        at oQ(/assets/react-lib-deadbeef.js:25:86672)
        at oq(/assets/react-lib-deadbeef.js:25:86362)
        at oQ(/assets/react-lib-deadbeef.js:25:86475)
        at oq(/assets/react-lib-deadbeef.js:25:86362)
        at oQ(/assets/react-lib-deadbeef.js:25:86672)
        at oq(/assets/react-lib-deadbeef.js:25:86362)
        at oQ(/assets/react-lib-deadbeef.js:25:86475)`

        throw error
      }

      Node.prototype.insertBefore = mockedThrowFunction
      applyInsertBeforePatch()

      const parent = document.createElement('div')
      const nonChildNode = document.createElement('div')
      const nodeToInsert = document.createElement('div')

      expect(() => parent.insertBefore(nodeToInsert, nonChildNode)).not.toThrow(NotFoundError)
    })
  })
})

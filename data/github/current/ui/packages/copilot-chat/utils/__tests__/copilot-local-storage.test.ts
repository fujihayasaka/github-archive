import {copilotLocalStorage} from '../copilot-local-storage'

describe('CopilotLocalStorage', () => {
  beforeEach(() => {
    // Clear all mocks before each test
    localStorage.clear()
  })

  describe('addRequestID', () => {
    it('adds a request ID to local storage', () => {
      const requestID = 'test-request-id'
      const messageID = 'test-message-id'

      copilotLocalStorage.addRequestID(messageID, requestID)

      // Verify we can get the ID back
      const retrievedID = copilotLocalStorage.getRequestID(messageID)
      expect(retrievedID).toBe(requestID)
    })

    it('preserves existing request IDs when adding a new one', () => {
      const existingMessageID = 'existing-message'
      const existingRequestID = 'existing-id'
      const newMessageID = 'new-message'
      const newRequestID = 'new-id'

      // Add existing ID
      copilotLocalStorage.addRequestID(existingMessageID, existingRequestID)

      // Add new ID
      copilotLocalStorage.addRequestID(newMessageID, newRequestID)

      // Verify both IDs are preserved
      expect(copilotLocalStorage.getRequestID(existingMessageID)).toBe(existingRequestID)
      expect(copilotLocalStorage.getRequestID(newMessageID)).toBe(newRequestID)
    })
  })

  describe('getRequestID', () => {
    it('returns undefined when the message has no request ID and array is empty', () => {
      const messageID = 'nonexistent-message'

      const result = copilotLocalStorage.getRequestID(messageID)

      expect(result).toBeUndefined()
    })

    it('returns undefined when message not found in array', () => {
      const messageID = 'nonexistent-message'
      const otherRequestID = 'other-request-id'
      const otherMessageID = 'other-message'
      copilotLocalStorage.addRequestID(otherMessageID, otherRequestID)
      const result = copilotLocalStorage.getRequestID(messageID)
      expect(result).toBeUndefined()
    })

    it('returns the request ID for a specific message', () => {
      const requestID = 'test-request-id'
      const messageID = 'test-message'

      copilotLocalStorage.addRequestID(messageID, requestID)

      const result = copilotLocalStorage.getRequestID(messageID)

      expect(result).toBe(requestID)
    })

    it('returns the most recent request ID when multiple exist for a message', () => {
      const messageID = 'test-message'
      const oldRequestID = 'old-request-id'
      const newRequestID = 'new-request-id'

      copilotLocalStorage.addRequestID(messageID, oldRequestID)
      copilotLocalStorage.addRequestID(messageID, newRequestID)

      const result = copilotLocalStorage.getRequestID(messageID)

      // The latest added ID should be returned
      expect(result).toBe(newRequestID)
    })

    it('limits storage to the maximum number of entries', () => {
      // Access the private field via any to test the limit
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const maxCount = (copilotLocalStorage as any).MAX_MESSAGE_REQUEST_ID_STORAGE_COUNT

      // Add one more than the maximum allowed
      for (let i = 0; i < maxCount + 1; i++) {
        copilotLocalStorage.addRequestID(`message-${i}`, `request-${i}`)
      }

      // The first entry should be removed
      expect(copilotLocalStorage.getRequestID('message-0')).toBeUndefined()
      // The last entry should still be there
      expect(copilotLocalStorage.getRequestID(`message-${maxCount}`)).toBe(`request-${maxCount}`)
    })
  })

  describe('localstorage data validation', () => {
    it('Parses an empty state correctly', () => {
      // eslint-disable-next-line @typescript-eslint/no-unsafe-call, @typescript-eslint/no-explicit-any
      expect((copilotLocalStorage as any).retrieveAndValidateRequestIDs()).toEqual([])
    })

    it('Gracefully handles invalid JSON', () => {
      jest.spyOn(Storage.prototype, 'getItem').mockReturnValue('invalid json')
      // eslint-disable-next-line @typescript-eslint/no-unsafe-call, @typescript-eslint/no-explicit-any
      expect((copilotLocalStorage as any).retrieveAndValidateRequestIDs()).toEqual([])
    })
    it('Handles invalid data in array', () => {
      const invalidData = JSON.stringify([{messageID: 123, requestID: 456}])
      jest.spyOn(Storage.prototype, 'getItem').mockReturnValue(invalidData)
      // eslint-disable-next-line @typescript-eslint/no-unsafe-call, @typescript-eslint/no-explicit-any
      expect((copilotLocalStorage as any).retrieveAndValidateRequestIDs()).toEqual([])
    })
    it('Handles some invalid entries in array', () => {
      const invalidData = JSON.stringify([
        {messageID: 'valid-message', requestID: 'valid-request'},
        {messageID: 123, requestID: 'invalid-request'},
      ])
      jest.spyOn(Storage.prototype, 'getItem').mockReturnValue(invalidData)
      // eslint-disable-next-line @typescript-eslint/no-unsafe-call, @typescript-eslint/no-explicit-any
      expect((copilotLocalStorage as any).retrieveAndValidateRequestIDs()).toEqual([
        {messageID: 'valid-message', requestID: 'valid-request'},
      ])
    })
  })
})

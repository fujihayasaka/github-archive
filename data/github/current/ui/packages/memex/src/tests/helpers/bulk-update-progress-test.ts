import {waitFor} from '@testing-library/react'

import {BulkUpdateProgressSingleton} from '../../client/state-providers/column-values/bulk-update-progress'

describe('BulkUpdateProgressSingleton', () => {
  beforeEach(() => {
    BulkUpdateProgressSingleton.reset()
  })

  describe('pending', () => {
    it('tracks the most recent request', () => {
      // Simulate an existing request
      const firstOutstandingTimeout = jest.fn()
      const secondOutstandingTimeout = jest.fn()
      BulkUpdateProgressSingleton.outstandingTimeouts.push({cancel: firstOutstandingTimeout})
      BulkUpdateProgressSingleton.outstandingTimeouts.push({cancel: secondOutstandingTimeout})
      BulkUpdateProgressSingleton.requestId = '1'
      BulkUpdateProgressSingleton.percentage = 50

      expect(BulkUpdateProgressSingleton.pending('2')).toBe(true)
      expect(firstOutstandingTimeout).toHaveBeenCalled()
      expect(secondOutstandingTimeout).toHaveBeenCalled()
      expect(BulkUpdateProgressSingleton.requestId).toEqual('2')
      expect(BulkUpdateProgressSingleton.percentage).toEqual(0)
    })

    it('does not track a new request without an ID', () => {
      expect(BulkUpdateProgressSingleton.pending('1')).toBe(true)
      expect(BulkUpdateProgressSingleton.pending(undefined)).toBe(false)
      expect(BulkUpdateProgressSingleton.requestId).toEqual('1')
    })
  })

  describe('progress', () => {
    it('tracks the monotonically-increasing progress percentage of the current request', () => {
      BulkUpdateProgressSingleton.pending('1')

      // Progress should not dip below 0
      expect(BulkUpdateProgressSingleton.progress('1', -5)).toBe(0)

      expect(BulkUpdateProgressSingleton.progress('1', 10)).toBe(10)
      expect(BulkUpdateProgressSingleton.progress('1', 20)).toBe(20)

      // Progress should not decrease
      expect(BulkUpdateProgressSingleton.progress('1', 15)).toBe(20)
      expect(BulkUpdateProgressSingleton.progress('1', 100)).toBe(100)

      // Progress should not increase past 100
      expect(BulkUpdateProgressSingleton.progress('1', 110)).toBe(100)
    })

    it('ignores progress for a request that does not match the ongoing request', () => {
      BulkUpdateProgressSingleton.pending('1')
      expect(BulkUpdateProgressSingleton.progress('1', 10)).toBe(10)

      // Unrelated request should not affect progress
      expect(BulkUpdateProgressSingleton.progress('2', 20)).toBeUndefined()

      // Previous request should not have interfered with the original one
      expect(BulkUpdateProgressSingleton.progress('1', 20)).toBe(20)
    })
  })

  describe('complete', () => {
    it('resets state when completing the current request', async () => {
      const clearPersistedToast = jest.fn()
      clearPersistedToast.mockReturnValue({cancel: () => {}})

      // Simulate a request in progress
      BulkUpdateProgressSingleton.pending('1')
      BulkUpdateProgressSingleton.progress('1', 50)
      expect(BulkUpdateProgressSingleton.requestId).toEqual('1')
      expect(BulkUpdateProgressSingleton.percentage).toEqual(50)

      expect(BulkUpdateProgressSingleton.complete('1', 0, clearPersistedToast)).toBe(true)

      expect(clearPersistedToast).toHaveBeenCalled()
      expect(BulkUpdateProgressSingleton.outstandingTimeouts).toHaveLength(2)
      await waitFor(() => expect(BulkUpdateProgressSingleton.requestId).toBeUndefined(), {timeout: 100})
      await waitFor(() => expect(BulkUpdateProgressSingleton.percentage).toBe(0), {timeout: 100})
    })

    it('does not complete a request that is not already ongoing', () => {
      // Simulate a request in progress
      BulkUpdateProgressSingleton.pending('1')
      BulkUpdateProgressSingleton.progress('1', 50)
      expect(BulkUpdateProgressSingleton.requestId).toEqual('1')
      expect(BulkUpdateProgressSingleton.percentage).toEqual(50)
      expect(BulkUpdateProgressSingleton.outstandingTimeouts).toHaveLength(0)

      expect(BulkUpdateProgressSingleton.complete('2', 0, () => ({cancel: () => {}}))).toBe(false)

      expect(BulkUpdateProgressSingleton.requestId).toEqual('1')
      expect(BulkUpdateProgressSingleton.percentage).toEqual(50)
      expect(BulkUpdateProgressSingleton.outstandingTimeouts).toHaveLength(0)
    })
  })
})

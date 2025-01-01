import {canBlock, canUnblock, getCommentActionsLabel} from '../comment-actions'

describe('comment-actions', () => {
  describe('canBlock', () => {
    it('should return false if there is no author', () => {
      expect(
        canBlock({viewerCanBlockFromOrg: false, pendingBlock: false, pendingUnblock: false, hasAuthor: false}),
      ).toBe(false)
    })

    it('should return false if pendingBlock is true', () => {
      expect(canBlock({viewerCanBlockFromOrg: true, pendingBlock: true, pendingUnblock: false, hasAuthor: true})).toBe(
        false,
      )
    })

    it('should return true if pendingUnblock is true, and pendingBlock is false', () => {
      expect(canBlock({viewerCanBlockFromOrg: true, pendingBlock: false, pendingUnblock: true, hasAuthor: true})).toBe(
        true,
      )
    })

    it('should return viewerCanBlockFromOrg if no pending actions', () => {
      expect(canBlock({viewerCanBlockFromOrg: true, pendingBlock: false, pendingUnblock: false, hasAuthor: true})).toBe(
        true,
      )
      expect(
        canBlock({viewerCanBlockFromOrg: false, pendingBlock: false, pendingUnblock: false, hasAuthor: true}),
      ).toBe(false)
    })
  })

  describe('canUnblock', () => {
    it('should return false if there is no author', () => {
      expect(
        canUnblock({viewerCanUnblockFromOrg: false, pendingBlock: false, pendingUnblock: false, hasAuthor: false}),
      ).toBe(false)
    })

    it('should return false if pendingUnblock is true', () => {
      expect(
        canUnblock({viewerCanUnblockFromOrg: true, pendingBlock: false, pendingUnblock: true, hasAuthor: true}),
      ).toBe(false)
    })

    it('should return true if pendingBlock is true, and pendingUnblock is false', () => {
      expect(
        canUnblock({viewerCanUnblockFromOrg: true, pendingBlock: true, pendingUnblock: false, hasAuthor: true}),
      ).toBe(true)
    })

    it('should return viewerCanUnblockFromOrg if no pending actions', () => {
      expect(
        canUnblock({viewerCanUnblockFromOrg: true, pendingBlock: false, pendingUnblock: false, hasAuthor: true}),
      ).toBe(true)
      expect(
        canUnblock({viewerCanUnblockFromOrg: false, pendingBlock: false, pendingUnblock: false, hasAuthor: true}),
      ).toBe(false)
    })
  })

  describe('getCommentActionsLabel', () => {
    it('should return the body if it is less than the truncation limit', () => {
      const body = 'Short comment'
      expect(getCommentActionsLabel(body)).toBe(`Comment actions for comment: "${body}"`)
    })

    it('should return truncated body if it exceeds the truncation limit', () => {
      const body = 'A'.repeat(130)
      const expected = `${'A'.repeat(120)}... (truncated)`
      expect(getCommentActionsLabel(body)).toBe(`Comment actions for comment: "${expected}"`)
    })
  })
})

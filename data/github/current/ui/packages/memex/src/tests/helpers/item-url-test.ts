import {getIssueItemIdentifier, isIssueOrPullRequestUrl} from '../../client/helpers/item-url'

describe('issue url', () => {
  describe('getItemIdentifier', () => {
    it('should return undefined if the url is not an issue url (empty)', () => {
      const result = getIssueItemIdentifier('')
      expect(result).toBeUndefined()
    })

    it('should return undefined if the url is not an issue url (no match)', () => {
      const result = getIssueItemIdentifier('github.com')
      expect(result).toBeUndefined()
    })

    it('should return undefined if the url is not an issue url (no number)', () => {
      const result = getIssueItemIdentifier('github.com/owner/repo/issues/abc')
      expect(result).toBeUndefined()
    })

    it('should return undefined item identifier if an issue url (no number)', () => {
      const result = getIssueItemIdentifier('github.com/owner/repo/issues/123')
      expect(result).toMatchObject({
        owner: 'owner',
        repo: 'repo',
        number: 123,
      })
    })
  })

  describe('isIssueOrPullRequestUrl', () => {
    it('returns true for valid issue URL', () => {
      expect(isIssueOrPullRequestUrl('https://github.com/github/github/issues/1')).toBe(true)
      expect(isIssueOrPullRequestUrl('https://github.localhost/github/github/issues/1')).toBe(true)
      expect(isIssueOrPullRequestUrl('https://monalisa.review-lab.github.com/github/github/issues/1')).toBe(true)
      expect(isIssueOrPullRequestUrl('https://staffship-01.ghe.com/github/github/issues/1')).toBe(true)
      expect(isIssueOrPullRequestUrl('https://me.io/github/github/issues/1')).toBe(true)
    })

    it('returns true for valid pull URL', () => {
      expect(isIssueOrPullRequestUrl('https://github.com/github/github/pull/1')).toBe(true)
      expect(isIssueOrPullRequestUrl('https://github.localhost/github/github/pull/1')).toBe(true)
      expect(isIssueOrPullRequestUrl('https://monalisa.review-lab.github.com/github/github/pull/1')).toBe(true)
      expect(isIssueOrPullRequestUrl('https://staffship-01.ghe.com/github/github/pull/1')).toBe(true)
      expect(isIssueOrPullRequestUrl('https://me.io/github/github/pull/1')).toBe(true)
    })

    it('returns false for invalid issue URL', () => {
      expect(isIssueOrPullRequestUrl('/github/github/issues/1')).toBe(false)
      expect(isIssueOrPullRequestUrl('https://github.localhost/github/github/issues/x')).toBe(false)
      expect(
        isIssueOrPullRequestUrl('AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAH'),
      ).toBe(false)
      expect(isIssueOrPullRequestUrl('/github/github/pull/1')).toBe(false)
      expect(isIssueOrPullRequestUrl('https://github.localhost/github/github/pulls/x')).toBe(false)
      expect(isIssueOrPullRequestUrl('https://staffship-01.ghe.com/github/github/pulls/1')).toBe(false)
      expect(
        isIssueOrPullRequestUrl('AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAH'),
      ).toBe(false)
    })
  })
})

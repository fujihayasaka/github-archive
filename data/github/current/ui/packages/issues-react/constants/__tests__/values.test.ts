import {VALUES} from '../values'

describe('VALUES.maxIssuesListItems', () => {
  const {maxIssuesListItems} = VALUES

  describe('when logged in', () => {
    it('should return MAX_ES_ISSUES when bypassEsLimits is true and isPrsOnly is false', () => {
      const result = maxIssuesListItems(true, false, true)
      expect(result).toBe(50000)
    })

    it('should return MAX_ES_PRS when bypassEsLimits is true and isPrsOnly is true', () => {
      const result = maxIssuesListItems(true, true, true)
      expect(result).toBe(10000)
    })

    it('should return MAX_ES_DEFAULT when bypassEsLimits is false', () => {
      const result = maxIssuesListItems(false, false, true)
      expect(result).toBe(1000)
    })

    it('should return MAX_ES_DEFAULT when bypassEsLimits is false and isPrsOnly is true', () => {
      const result = maxIssuesListItems(false, true, true)
      expect(result).toBe(1000)
    })
  })

  describe('when not logged in', () => {
    it('should return MAX_ES_DEFAULT when bypassEsLimits is true and isPrsOnly is false', () => {
      const result = maxIssuesListItems(true, false, false)
      expect(result).toBe(1000)
    })

    it('should return MAX_ES_DEFAULT when bypassEsLimits is true and isPrsOnly is true', () => {
      const result = maxIssuesListItems(true, true, false)
      expect(result).toBe(1000)
    })

    it('should return MAX_ES_DEFAULT when bypassEsLimits is false', () => {
      const result = maxIssuesListItems(false, false, false)
      expect(result).toBe(1000)
    })

    it('should return MAX_ES_DEFAULT when bypassEsLimits is false and isPrsOnly is true', () => {
      const result = maxIssuesListItems(false, true, false)
      expect(result).toBe(1000)
    })
  })
})

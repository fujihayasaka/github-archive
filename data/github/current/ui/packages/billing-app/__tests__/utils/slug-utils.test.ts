import {getSlugFromName} from '../../utils/slug-utils'

describe('slugUtils', () => {
  describe('getSlugFromName', () => {
    it('should match Ruby parameterize behavior', () => {
      const testCases = [
        {input: 'R&D - ISM KACE', expected: 'r-d-ism-kace'},
        {input: 'Sales & Marketing', expected: 'sales-marketing'},
        {input: 'IT/Operations', expected: 'it-operations'},
        {input: 'R&D', expected: 'r-d'},
        {input: 'Finance & Accounting', expected: 'finance-accounting'},
        {input: 'Product Development - Web', expected: 'product-development-web'},
        {input: 'Customer Success (Enterprise)', expected: 'customer-success-enterprise'},
      ]

      for (const {input, expected} of testCases) {
        expect(getSlugFromName(input)).toBe(expected)
      }
    })

    it('should handle edge cases', () => {
      expect(getSlugFromName('')).toBe('')
      expect(getSlugFromName('   ')).toBe('')
      expect(getSlugFromName(null as unknown as string)).toBe('')
      expect(getSlugFromName(undefined as unknown as string)).toBe('')
      expect(getSlugFromName('---Test---')).toBe('test')
      expect(getSlugFromName('Multiple   Spaces')).toBe('multiple-spaces')
      expect(getSlugFromName('Special!@#$%^&*()Characters')).toBe('special-characters')
    })

    it('should support custom separators', () => {
      expect(getSlugFromName('Product Marketing', '_')).toBe('product_marketing')
      expect(getSlugFromName('R&D Team', '.')).toBe('r.d.team')
      expect(getSlugFromName('Sales & Marketing', '|')).toBe('sales|marketing')
      expect(getSlugFromName('IT/Operations Department', ' ')).toBe('it operations department')
      expect(getSlugFromName('Finance & Accounting', ' ').replace(/\s/g, '')).toBe('financeaccounting')
    })

    it('should support case preservation', () => {
      expect(getSlugFromName('Product Marketing', '-', true)).toBe('Product-Marketing')
      expect(getSlugFromName('R&D Team', '-', true)).toBe('R-D-Team')
      expect(getSlugFromName('JavaScript/TypeScript', '_', true)).toBe('JavaScript_TypeScript')
      expect(getSlugFromName('API & Backend Services', '.', true)).toBe('API.Backend.Services')
    })

    it('should handle Unicode characters', () => {
      expect(getSlugFromName('Café & Bistro')).toBe('cafe-bistro')
      expect(getSlugFromName('Naïve Résumé')).toBe('naive-resume')
      expect(getSlugFromName("École d'été")).toBe('ecole-d-ete')
      expect(getSlugFromName('Zürich Office')).toBe('zurich-office')

      // Test with case preservation
      expect(getSlugFromName('Café & Bistro', '-', true)).toBe('Cafe-Bistro')
      expect(getSlugFromName('Naïve Résumé', '_', true)).toBe('Naive_Resume')
    })

    it('should escape special characters in custom separators', () => {
      // Test separators that need escaping in regex
      expect(getSlugFromName('Test String', '+')).toBe('test+string')
      expect(getSlugFromName('Test String', '*')).toBe('test*string')
      expect(getSlugFromName('Test String', '?')).toBe('test?string')
      expect(getSlugFromName('Test String', '^')).toBe('test^string')
      expect(getSlugFromName('Test String', '$')).toBe('test$string')
      expect(getSlugFromName('Test String', '[')).toBe('test[string')
      expect(getSlugFromName('Test String', ']')).toBe('test]string')
    })
  })
})

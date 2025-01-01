import {supportsJsonSchemaStructuredOutput} from '../model-capability'

describe('model capability', () => {
  describe('supportsJsonSchemaStructuredOutput', () => {
    it('returns true for gpt-4o', () => {
      expect(supportsJsonSchemaStructuredOutput({name: 'gpt-4o'})).toBe(true)
    })

    it('returns true for grok-3-mini', () => {
      expect(supportsJsonSchemaStructuredOutput({name: 'grok-3-mini'})).toBe(true)
    })

    it('returns true for grok-3', () => {
      expect(supportsJsonSchemaStructuredOutput({name: 'grok-3'})).toBe(true)
    })

    it('returns false for other models', () => {
      expect(supportsJsonSchemaStructuredOutput({name: 'o1'})).toBe(false)
    })
  })
})

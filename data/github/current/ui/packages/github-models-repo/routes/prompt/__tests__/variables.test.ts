import {replaceVars, referencedVariables} from '../variables'

describe('variables', () => {
  describe('replaceVars', () => {
    it('replace variables in the string', () => {
      const str = 'Hello, {{name}}! Welcome to {{place}}.'
      const variables = {
        name: 'Alice',
        place: 'Wonderland',
      }
      const result = replaceVars(str, variables)
      expect(result).toBe('Hello, Alice! Welcome to Wonderland.')
    })

    it('ignore missing variables', () => {
      const str = 'Hello, {{name}}! Welcome to {{place}}.'
      const variables = {
        name: 'Alice',
      }
      const result = replaceVars(str, variables)
      expect(result).toBe('Hello, Alice! Welcome to {{place}}.')
    })

    it('handle empty string', () => {
      const str = ''
      const variables = {
        name: 'Alice',
        place: 'Wonderland',
      }
      const result = replaceVars(str, variables)
      expect(result).toBe('')
    })

    it('handles incomplete variable placeholders', () => {
      const str = 'Hello, {{name}}! Welcome to {{place}, great to {{see you.'
      const variables = {
        name: 'Alice',
        place: 'Wonderland',
      }
      const result = replaceVars(str, variables)
      expect(result).toBe('Hello, Alice! Welcome to {{place}, great to {{see you.')
    })
  })

  describe('referencedVariables', () => {
    it('extracts single variable from string', () => {
      const str = 'Hello, {{name}}!'
      const result = referencedVariables(str)
      expect(result).toEqual(['name'])
    })

    it('extracts multiple variables from string', () => {
      const str = 'Hello, {{name}}! Welcome to {{place}}.'
      const result = referencedVariables(str)
      expect(result).toEqual(['name', 'place'])
    })

    it('returns empty array for string with no variables', () => {
      const str = 'Hello, world! No variables here.'
      const result = referencedVariables(str)
      expect(result).toEqual([])
    })

    it('returns empty array for empty string', () => {
      const str = ''
      const result = referencedVariables(str)
      expect(result).toEqual([])
    })

    it('returns unique variables when duplicates exist', () => {
      const str = 'Hello, {{name}}! Nice to meet you, {{name}}. Visit {{place}}.'
      const result = referencedVariables(str)
      expect(result).toEqual(['name', 'place'])
    })

    it('ignores incomplete variable placeholders', () => {
      const str = 'Hello, {{name}}! Welcome to {{place, nice to {{see}} you.'
      const result = referencedVariables(str)
      expect(result).toEqual(['name', 'see'])
    })
  })
})

import {
  replaceVars,
  referencedVariables,
  autocompletionVariablesInPrompt,
  filterAndCleanRowVariables,
} from '../variables'
import type {PromptConfig} from '../prompts'

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

    it('can replace one variable with another', () => {
      const str = 'Hello, {{name}}! Welcome to {{place}}.'
      const variables = {
        name: '{{title}}',
        place: '{{city}}',
      }
      const result = replaceVars(str, variables)
      expect(result).toBe('Hello, {{title}}! Welcome to {{city}}.')
    })

    it('handles multiple instances of the same variable', () => {
      const str = 'Hello, {{name}}! I like the name {{name}}. Welcome to {{place}}.'
      const variables = {
        name: '{{title}}',
        place: '{{city}}',
      }
      const result = replaceVars(str, variables)
      expect(result).toBe('Hello, {{title}}! I like the name {{title}}. Welcome to {{city}}.')
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

  describe('autocompletionVariablesInPrompt', () => {
    it('returns variables from prompt messages with {{}} format', () => {
      const prompt: PromptConfig = {
        messages: [
          {role: 'system', message: 'You are a {{role}} assistant', timestamp: new Date()},
          {role: 'user', message: 'Tell me about {{topic}}', timestamp: new Date()},
        ],
      }
      const result = autocompletionVariablesInPrompt(prompt)
      expect(result).toEqual(['{{role}}', '{{topic}}', '{{expected}}', '{{completion}}'])
    })

    it('always includes expected and completion variables', () => {
      const prompt: PromptConfig = {
        messages: [
          {role: 'system', message: 'You are a helpful assistant', timestamp: new Date()},
          {role: 'user', message: 'Hello world', timestamp: new Date()},
        ],
      }
      const result = autocompletionVariablesInPrompt(prompt)
      expect(result).toEqual(['{{expected}}', '{{completion}}'])
    })

    it('does not duplicate expected and completion if already present', () => {
      const prompt: PromptConfig = {
        messages: [
          {role: 'system', message: 'Compare {{expected}} with {{completion}}', timestamp: new Date()},
          {role: 'user', message: 'Analyze the {{input}}', timestamp: new Date()},
        ],
      }
      const result = autocompletionVariablesInPrompt(prompt)
      expect(result).toEqual(['{{expected}}', '{{completion}}', '{{input}}'])
    })

    it('handles empty messages array', () => {
      const prompt: PromptConfig = {
        messages: [],
      }
      const result = autocompletionVariablesInPrompt(prompt)
      expect(result).toEqual(['{{expected}}', '{{completion}}'])
    })

    it('handles prompt with undefined messages', () => {
      const prompt: PromptConfig = {} as PromptConfig
      const result = autocompletionVariablesInPrompt(prompt)
      expect(result).toEqual(['{{expected}}', '{{completion}}'])
    })

    it('returns unique variables from multiple messages', () => {
      const prompt: PromptConfig = {
        messages: [
          {role: 'system', message: 'You are a {{role}} assistant for {{domain}}', timestamp: new Date()},
          {role: 'user', message: 'Tell me about {{topic}} in {{domain}}', timestamp: new Date()},
          {role: 'assistant', message: 'Based on {{topic}}, here is the answer', timestamp: new Date()},
        ],
      }
      const result = autocompletionVariablesInPrompt(prompt)
      expect(result).toEqual(['{{role}}', '{{domain}}', '{{topic}}', '{{expected}}', '{{completion}}'])
    })

    it('handles variables with different formats but only returns valid {{}} format', () => {
      const prompt: PromptConfig = {
        messages: [
          {
            role: 'system',
            message: 'You are a {{valid}} assistant using ${invalid} and {also_invalid}',
            timestamp: new Date(),
          },
          {role: 'user', message: 'Tell me about {{another_valid}}', timestamp: new Date()},
        ],
      }
      const result = autocompletionVariablesInPrompt(prompt)
      expect(result).toEqual(['{{valid}}', '{{another_valid}}', '{{expected}}', '{{completion}}'])
    })
  })

  describe('filterAndCleanRowVariables', () => {
    it('filters variables to only include those in currentVariables list', () => {
      const rows = [
        {id: '1', name: 'Alice', age: '25', city: 'New York', country: 'USA'},
        {id: '2', name: 'Bob', age: '30', city: 'London', country: 'UK'},
      ]
      const currentVariables = ['name', 'city']
      const result = filterAndCleanRowVariables(rows, currentVariables)
      expect(result).toEqual([
        {name: 'Alice', city: 'New York'},
        {name: 'Bob', city: 'London'},
      ])
    })

    it('removes id property from rows', () => {
      const rows = [
        {id: '1', name: 'Alice', age: '25'},
        {id: '2', name: 'Bob', age: '30'},
      ]
      const currentVariables = ['name', 'age']
      const result = filterAndCleanRowVariables(rows, currentVariables)
      expect(result).toEqual([
        {name: 'Alice', age: '25'},
        {name: 'Bob', age: '30'},
      ])
    })

    it('handles empty currentVariables array', () => {
      const rows = [
        {id: '1', name: 'Alice', age: '25'},
        {id: '2', name: 'Bob', age: '30'},
      ]
      const currentVariables: string[] = []
      const result = filterAndCleanRowVariables(rows, currentVariables)
      expect(result).toEqual([{}, {}])
    })

    it('handles rows with no matching variables', () => {
      const rows = [
        {id: '1', name: 'Alice', age: '25'},
        {id: '2', name: 'Bob', age: '30'},
      ]
      const currentVariables = ['height', 'weight']
      const result = filterAndCleanRowVariables(rows, currentVariables)
      expect(result).toEqual([{}, {}])
    })

    it('preserves string values as-is', () => {
      const rows = [{id: '1', name: 'Alice', score: '95.5', active: 'true'}]
      const currentVariables = ['name', 'score', 'active']
      const result = filterAndCleanRowVariables(rows, currentVariables)
      expect(result).toEqual([{name: 'Alice', score: '95.5', active: 'true'}])
    })
  })
})

import {parseMarkdownPrompt} from '../prompts'
import type {Message} from '../types'

describe('parseMarkdownPrompt', () => {
  test('parses prompt with all fields', () => {
    const prompt = parseMarkdownPrompt(
      'prompt.prompt.md',
      `---
name: My Prompt
description: A prompt for testing
model: gpt-4o
model_parameters:
  temperature: 0.5
test_data:
  - input: 'some input'
    expected: 'some output'
random_key: random value
---

system:
Some system prompt

user:
Some user prompt`,
    )

    expect(prompt).toBeDefined()
    expect(prompt.path).toBe('prompt.prompt.md')
    expect(prompt.name).toBe('My Prompt')
    expect(prompt.description).toBe('A prompt for testing')
    expect(prompt.model).toBe('gpt-4o')
    expect(prompt.modelParameters).toEqual({temperature: 0.5})
    expect(prompt.messages).toEqual<Message[]>([
      {
        timestamp: expect.any(Date),
        role: 'system',
        message: 'Some system prompt',
      },
      {
        timestamp: expect.any(Date),
        role: 'user',
        message: 'Some user prompt',
      },
    ])
    expect(prompt.testData).toEqual([
      {
        input: 'some input',
        expected: 'some output',
      },
    ])
    expect(prompt.metadata).toEqual({
      random_key: 'random value',
    })
  })

  test('parses prompt with no message', () => {
    const prompt = parseMarkdownPrompt(
      'empty.prompt.md',
      `---
model: gpt-4o
---
`,
    )

    expect(prompt).toBeDefined()
    expect(prompt.model).toBe('gpt-4o')
    expect(prompt.messages).toBeUndefined()
  })

  test('parses prompt without front matter', () => {
    const prompt = parseMarkdownPrompt(
      'prompt.prompt.md',
      `user:
Some prompt`,
    )

    expect(prompt).toBeDefined()
    expect(prompt.model).toBeUndefined()
    expect(prompt.messages).toEqual<Message[]>([
      {
        timestamp: expect.any(Date),
        role: 'user',
        message: 'Some prompt',
      },
    ])
  })

  test('parses multi-line prompt message', () => {
    const prompt = parseMarkdownPrompt(
      'prompt.prompt.md',
      `---
model: gpt-4o
---
user:
Some
prompt`,
    )

    expect(prompt).toBeDefined()
    expect(prompt.model).toBe('gpt-4o')
    expect(prompt.messages).toEqual<Message[]>([
      {
        timestamp: expect.any(Date),
        role: 'user',
        message: 'Some\nprompt',
      },
    ])
  })

  test('parses prompt message with no role as user message', () => {
    const prompt = parseMarkdownPrompt(
      'prompt.prompt.md',
      `---
model: gpt-4o
---
Some prompt`,
    )

    expect(prompt).toBeDefined()
    expect(prompt.model).toBe('gpt-4o')
    expect(prompt.messages).toEqual<Message[]>([
      {
        timestamp: expect.any(Date),
        role: 'user',
        message: 'Some prompt',
      },
    ])
  })

  test('throws error for malformed prompt', () => {
    expect(() => {
      parseMarkdownPrompt(
        'prompt.prompt.md',
        `---
model: gpt-4o
---
user:
system:
Some system prompt`,
      )
    }).toThrow('Invalid prompt format')
  })

  test('throws error for incorrect formatted fields', () => {
    // Throw an error if the name is not a string
    expect(() => {
      parseMarkdownPrompt(
        'prompt.prompt.md',
        `---
name: 123
---
`,
      )
    }).toThrow('Name must be a string')

    // Throw an error if the description is not a string
    expect(() => {
      parseMarkdownPrompt(
        'prompt.prompt.md',
        `---
description: 123
---
`,
      )
    }).toThrow('Description must be a string')

    // Throw an error if model is not a string
    expect(() => {
      parseMarkdownPrompt(
        'prompt.prompt.md',
        `---
model: 123
---
`,
      )
    }).toThrow('Model must be a string')

    // Throw an error if modelParameters is not an object
    expect(() => {
      parseMarkdownPrompt(
        'prompt.prompt.md',
        `---
model_parameters: 123
---
`,
      )
    }).toThrow('Model parameters must be an object')

    //  Throw an error if testData is not an array
    expect(() => {
      parseMarkdownPrompt(
        'prompt.prompt.md',
        `---
test_data: 123
---
`,
      )
    }).toThrow('Test data must be an array')

    // Throw an error if testData is not an array of PromptTestData
    expect(() => {
      parseMarkdownPrompt(
        'prompt.prompt.md',
        `---
test_data:
  - input: 'some input'
    output: 'some output'
---
`,
      )
    }).toThrow('Test data at index 0 must have input and expected properties that are strings')
  })
})

import {mockModel} from '../../../test-utils/mock-data'
import type {PromptConfig} from '../prompts'
import {parsePrompt, promptToYaml} from '../prompts'
import type {Message} from '../types'

const mockModels = [mockModel({id: 'gpt-4o', name: 'gpt-4o', friendly_name: 'gpt-4o', original_name: 'gpt-4o'})]

describe('parsePrompt', () => {
  test('parses prompt with all fields', () => {
    const prompt = parsePrompt(
      'prompt.prompt.yml',
      `name: My Prompt
description: A prompt for testing
model: gpt-4o
modelParameters:
  temperature: 0.5
testData:
  - input: 'some input'
    expected: 'some output'
messages:
  - role: system
    content: Some system prompt
  - role: user
    content: Some user prompt
evaluators:
  - name: string evaluator
    string:
      endsWith: foobar
  - name: custom evaluator
    llm:
      modelId: 'azureml://registries/azure-openai/models/gpt-4o/versions/2024-11-20'
      prompt: 'is {{completion}} a nice message?'
      choices:
        - choice: no
          score: 0
        - choice: yes
          score: 1
      systemPrompt: only ever respond with 'yes' or 'no'
  - name: Similarity
    uses: github/similarity
`,
    )

    expect(prompt).toBeDefined()
    expect(prompt.path).toBe('prompt.prompt.yml')
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
    expect(prompt.evaluators).toEqual([
      {
        config: {
          name: 'string evaluator',
          string: {endsWith: 'foobar'},
        },
      },
      {
        config: {
          name: 'custom evaluator',
          llm: {
            modelId: 'azureml://registries/azure-openai/models/gpt-4o/versions/2024-11-20',
            prompt: 'is {{completion}} a nice message?',
            choices: [
              {choice: 'no', score: 0},
              {choice: 'yes', score: 1},
            ],
            systemPrompt: "only ever respond with 'yes' or 'no'",
          },
        },
      },
      {
        config: {
          name: 'Similarity',
          uses: 'github/similarity',
        },
      },
    ])
  })

  test('parses multi-line prompt message', () => {
    const prompt = parsePrompt(
      'prompt.prompt.yml',
      `model: gpt-4o
messages:
  - role: system
    content: System prompt
  - role: user
    content: |
      Some
      prompt`,
    )

    expect(prompt).toBeDefined()
    expect(prompt.model).toBe('gpt-4o')
    expect(prompt.messages).toEqual<Message[]>([
      {
        timestamp: expect.any(Date),
        role: 'system',
        message: 'System prompt',
      },
      {
        timestamp: expect.any(Date),
        role: 'user',
        message: 'Some\nprompt\n',
      },
    ])
  })

  test('parses empty file', () => {
    const prompt = parsePrompt('prompt.prompt.yml', '')

    expect(prompt).toBeDefined()
  })

  test('throws error for incorrect formatted fields', () => {
    // Throw an error if the name is not a string
    expect(() => {
      parsePrompt('prompt.prompt.yml', `name: 123`)
    }).toThrow('name must be a `string` type')

    // Throw an error if the description is not a string
    expect(() => {
      parsePrompt('prompt.prompt.yml', `description: 123`)
    }).toThrow('description must be a `string` type')

    // Throw an error if model is not a string
    expect(() => {
      parsePrompt('prompt.prompt.yml', `model: 123`)
    }).toThrow('model must be a `string` type')

    // Throw an error if modelParameters is not an object
    expect(() => {
      parsePrompt('prompt.prompt.yml', `modelParameters: 123`)
    }).toThrow('modelParameters must be a `object` type')

    //  Throw an error if testData is not an array
    expect(() => {
      parsePrompt('prompt.prompt.yml', `testData: 123`)
    }).toThrow('testData must be a `array` type')

    expect(() => {
      parsePrompt(
        'prompt.prompt.yml',
        `testData:
  - input: 'some input'
    output: 'some output'
`,
      )
    }).not.toThrow('testData now accepts arbitrary properties, so this should not throw')
  })

  test('flexible parse schemas for testData', () => {
    // allow null as a field for testData
    const emptyTestData = parsePrompt('prompt.prompt.yml', `testData:`)
    expect(emptyTestData).toBeDefined()

    // allow when testData only has input
    const onlyInput = parsePrompt(
      'prompt.prompt.yml',
      `testData:
        - input: 'test'`,
    )
    expect(onlyInput).toBeDefined()

    // allow when testData only has expected
    const onlyExpected = parsePrompt(
      'prompt.prompt.yml',
      `testData:
        - expected: 'testt'`,
    )
    expect(onlyExpected).toBeDefined()
  })
})

describe('promptToYaml', () => {
  test('converts prompt with all fields to yaml', () => {
    const yaml = promptToYaml(
      {
        name: 'My Prompt',
        description: 'A prompt for testing',
        model: 'gpt-4o',
        modelParameters: {temperature: 0.5},
        messages: [
          {
            timestamp: new Date('2022-01-01T00:00:00Z'),
            role: 'system',
            message: 'Some system prompt',
          },
          {
            timestamp: new Date('2022-01-01T00:00:00Z'),
            role: 'user',
            message: 'Some user prompt',
          },
        ],
        testData: [
          {
            input: 'some input',
            expected: 'some output',
          },
        ],
      },
      mockModels,
    )

    expect(yaml).toMatchSnapshot()
  })

  test('converts prompt with no messages to yaml', () => {
    const yaml = promptToYaml(
      {
        model: 'gpt-4o',
        messages: [],
      },
      mockModels,
    )

    expect(yaml).toMatchSnapshot()
  })
})

describe('original input can be re-generated', () => {
  let spy: jest.SpyInstance
  beforeAll(() => {
    const mockDate = new Date(1466424490000)
    spy = jest.spyOn(global, 'Date').mockImplementation(() => mockDate)
  })

  afterAll(() => {
    spy.mockRestore()
  })

  test('consistently converts PromptConfig to yaml and back to PromptConfig', () => {
    const pc = {
      path: 'prompt.prompt.yml',
      name: 'My Prompt',
      description: 'A prompt for testing',
      model: 'openai/gpt-4o',
      modelParameters: {temperature: 0.5},
      messages: [
        {
          timestamp: new Date(),
          role: 'system',
          message: 'Some system prompt',
        },
        {
          timestamp: new Date(),
          role: 'user',
          message: 'Some user prompt',
        },
      ],
      testData: [
        {
          input: 'some input',
          expected: 'some output',
        },
      ],
    } as PromptConfig

    const yaml = promptToYaml(pc, mockModels)
    const parsed = parsePrompt('prompt.prompt.yml', yaml)

    expect(parsed).toEqual(pc)
  })

  test('consistently converts yaml to PromptConfig and back to yaml', () => {
    const originalYaml = `name: My Prompt
description: A prompt for testing
model: openai/gpt-4o
modelParameters:
  temperature: 0.5
testData:
  - input: some input
    expected: some output
randomKey: random value
messages:
  - role: system
    content: Some system prompt
  - role: user
    content: Some user prompt
`

    const parsed = parsePrompt('prompt.prompt.yml', originalYaml)
    const generatedMarkdown = promptToYaml(parsed, mockModels)

    expect(generatedMarkdown).toBe(originalYaml)
  })
})

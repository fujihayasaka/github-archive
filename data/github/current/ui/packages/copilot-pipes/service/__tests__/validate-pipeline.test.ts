import type {Pipeline} from '../../types/app'
import {validatePipeline} from '../validate-pipeline'

test('valid pipeline', () => {
  const errors = validatePipeline(haikuGenerator)
  expect(errors).toHaveLength(0)
})

test('pipeline with cycle', () => {
  const errors = validatePipeline(circularAnalysis)
  expect(errors).toHaveLength(1)
  expect(errors[0]?.error).toContain('cycle')
  expect(errors[0]?.involvedNodes).toHaveLength(3)
  expect(errors[0]?.involvedNodes).toContain('2')
  expect(errors[0]?.involvedNodes).toContain('3')
  expect(errors[0]?.involvedNodes).toContain('4')
})

test('reference to nonexistent node', () => {
  const errors = validatePipeline(invalidReference)
  expect(errors).toHaveLength(1)
  expect(errors[0]?.error).toContain('nonexistent node')
})

test('disconnected pipeline', () => {
  const errors = validatePipeline(disconnected)
  expect(errors).toHaveLength(1)
  expect(errors[0]?.error).toContain('unreachable nodes')
})

test('pipeline title required', () => {
  const noTitle = {...haikuGenerator, title: undefined} as unknown as Pipeline
  const errors = validatePipeline(noTitle)
  expect(errors).toHaveLength(1)
  expect(errors[0]?.error).toContain('title')
})

test('pipeline nodes required', () => {
  const noNodes = {...haikuGenerator, nodes: []}
  const errors = validatePipeline(noNodes)
  expect(errors).toHaveLength(1)
  expect(errors[0]?.error).toContain('nodes')
})

test('node title required', () => {
  const nodeWithoutTitle = {
    ...haikuGenerator,
    nodes: [
      {
        ...haikuGenerator.nodes[0],
        title: undefined,
      },
    ],
  } as unknown as Pipeline
  const errors = validatePipeline(nodeWithoutTitle)
  expect(errors).toHaveLength(1)
  expect(errors[0]?.error).toContain('title')
})

test('range input', () => {
  const nodeWithoutID = {
    ...haikuGenerator,
    nodes: [
      {
        ...haikuGenerator.nodes[0],
        inputType: {type: 'range', min: 5, max: undefined},
      },
    ],
  } as unknown as Pipeline
  const errors = validatePipeline(nodeWithoutID)
  expect(errors).toHaveLength(1)
  expect(errors[0]?.error).toContain('range')
  expect(errors[0]?.error).toContain('max')
})

test('boolean input', () => {
  const nodeWithoutID = {
    ...haikuGenerator,
    nodes: [
      {
        ...haikuGenerator.nodes[0],
        inputType: {type: 'boolean', content: 'neither true nor false'},
      },
    ],
  } as unknown as Pipeline
  const errors = validatePipeline(nodeWithoutID)
  expect(errors).toHaveLength(1)
  expect(errors[0]?.error).toContain('true')
  expect(errors[0]?.error).toContain('false')
})

test('select input', () => {
  const nodeWithoutID = {
    ...haikuGenerator,
    nodes: [
      {
        ...haikuGenerator.nodes[0],
        inputType: {type: 'select', content: 'D', options: ['A', 'B', 'C']},
      },
    ],
  } as unknown as Pipeline
  const errors = validatePipeline(nodeWithoutID)
  expect(errors).toHaveLength(1)
  expect(errors[0]?.error).toContain('select')
  expect(errors[0]?.error).toContain('options')
})

const haikuGenerator: Pipeline = {
  id: 'haiku',
  title: 'Haiku Writer',
  nodes: [
    {
      id: '1',
      title: 'Topic',
      description: 'The topic of the haiku',
      type: 'text',
      content: 'Puppies',
      inputType: {type: 'text'},
    },
    {
      id: '2',
      title: 'Prompt',
      description: 'Writes a haiku',
      type: 'prompt',
      content: 'Write a haiku about {{1}}.',
    },
  ],
}

const circularAnalysis: Pipeline = {
  id: 'cycles',
  title: 'Cycles',
  nodes: [
    {
      id: '1',
      title: 'Topic',
      description: 'topic',
      type: 'text',
      content: 'GitHub',
      inputType: {type: 'text'},
    },
    {
      id: '2',
      title: 'Prompt',
      description: 'Writes an essay',
      type: 'prompt',
      content: 'Write an essay about {{1}}. Make it very different from {{4}}.',
    },
    {
      id: '3',
      title: 'Topic guess',
      description: 'guesses the essay topic',
      type: 'prompt',
      content: 'Summarize in a few words the topic of this essay: {{2}}',
    },
    {
      id: '4',
      title: 'Second essay',
      description: 'Writes an essay about the topic guess',
      type: 'prompt',
      content: 'Write an essay about {{3}}.',
    },
  ],
}

const invalidReference: Pipeline = {
  ...haikuGenerator,
  nodes: haikuGenerator.nodes.map(n =>
    n.id === '2'
      ? {
          id: '2',
          title: 'Prompt',
          description: 'Writes a haiku',
          type: 'prompt',
          content: 'Write a haiku about {{1}} and also {{42}}.',
        }
      : n,
  ),
}

const disconnected: Pipeline = {
  ...haikuGenerator,
  nodes: haikuGenerator.nodes.map(n =>
    n.id === '2'
      ? {
          id: '2',
          title: 'Prompt',
          description: 'Writes a haiku',
          type: 'prompt',
          content: 'Write a haiku about anything.',
        }
      : n,
  ),
}

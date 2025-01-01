import type {PipesAction} from '../../state/pipes-action'
import {defaultExecutionState} from '../../state/pipes-state'
import type {Pipeline} from '../../types/app'
import {SYSTEM_PROMPT} from '../../utils/utils'
import {ChatCompletionsClient} from '../chat-completions-client'
import {GraphQLClient} from '../graphql-client'
import {PipelineRunner} from '../pipeline-runner'
import {IndexedDBPipesStorage} from '../pipes-storage'

jest.spyOn(GraphQLClient.prototype, 'getGraphQLResponse').mockImplementation(async query => ({data: {query}}))

jest.spyOn(ChatCompletionsClient.prototype, 'getChatCompletion').mockImplementation(async function* (messages) {
  // Extract content from all messages to match the old behavior
  const messageContents = messages.map(m => m.content).join('\n\n')
  yield `Response to: ${messageContents}`
})

jest.spyOn(IndexedDBPipesStorage.prototype, 'getExecutionState').mockImplementation(async () => defaultExecutionState)

beforeEach(() => jest.clearAllMocks())

/**
 * Asserts that the actions contain the expected number of UPDATE_NODE_VALUE calls.
 * Each node should have its value updated, plus one for each prompt node since they have partial results.
 */
const assertExpectedUpdateValueCalls = (actions: PipesAction[], loop: Pipeline) =>
  expect(actions.filter(a => a.type === 'UPDATE_NODE_VALUE')).toHaveLength(
    loop.nodes.length + loop.nodes.filter(n => n.type === 'prompt').length,
  )

const assertTotalActions = (actions: PipesAction[], loop: Pipeline) =>
  expect(actions).toHaveLength(5 * loop.nodes.length + loop.nodes.filter(n => n.type === 'prompt').length)

test('runs a simple pipeline', async () => {
  const runner = new PipelineRunner(
    haikuGenerator,
    0,
    new IndexedDBPipesStorage(),
    new GraphQLClient(''),
    new ChatCompletionsClient('', []),
  )

  const actions: PipesAction[] = []

  await runner.run(action => actions.push(action))

  // Each node has pending set to true and then false
  expect(actions.filter(a => a.type === 'SET_PENDING')).toHaveLength(haikuGenerator.nodes.length * 2)
  // Each node has running set to true and then false
  expect(actions.filter(a => a.type === 'SET_RUNNING')).toHaveLength(haikuGenerator.nodes.length * 2)
  assertExpectedUpdateValueCalls(actions, haikuGenerator)
  assertTotalActions(actions, haikuGenerator)

  // Output node value
  // @ts-expect-error For some reason `find` is not narrowing the type here
  expect(actions.find(a => a.type === 'UPDATE_NODE_VALUE' && a.nodeId === '2')!.value).toBe(
    `Response to: ${SYSTEM_PROMPT}\n\nWrite a haiku about Puppies.`,
  )
})

test('does not run a node more than once', async () => {
  const runner = new PipelineRunner(
    poetryAnalyzer,
    0,
    new IndexedDBPipesStorage(),
    new GraphQLClient(''),
    new ChatCompletionsClient('', []),
  )

  const actions: PipesAction[] = []

  await runner.run(action => actions.push(action))

  // Each node has running set to true exactly once, even if multiple nodes depend on it
  expect(actions.filter(a => a.type === 'SET_RUNNING' && a.running)).toHaveLength(poetryAnalyzer.nodes.length)
})

test('runs a pipeline with multiple outputs', async () => {
  const runner = new PipelineRunner(
    multiplePoemGenerator,
    0,
    new IndexedDBPipesStorage(),
    new GraphQLClient(''),
    new ChatCompletionsClient('', []),
  )

  const actions: PipesAction[] = []

  await runner.run(action => actions.push(action))

  // Each node has pending set to true and then false
  expect(actions.filter(a => a.type === 'SET_PENDING')).toHaveLength(multiplePoemGenerator.nodes.length * 2)
  // Each node has running set to true and then false
  expect(actions.filter(a => a.type === 'SET_RUNNING')).toHaveLength(multiplePoemGenerator.nodes.length * 2)
  assertExpectedUpdateValueCalls(actions, multiplePoemGenerator)
  assertTotalActions(actions, multiplePoemGenerator)

  // Output node value
  // @ts-expect-error For some reason `find` is not narrowing the type here
  expect(actions.find(a => a.type === 'UPDATE_NODE_VALUE' && a.nodeId === '2')!.value).toBe(
    `Response to: ${SYSTEM_PROMPT}\n\nWrite a haiku about Puppies.`,
  )
  // @ts-expect-error For some reason `find` is not narrowing the type here
  expect(actions.find(a => a.type === 'UPDATE_NODE_VALUE' && a.nodeId === '3')!.value).toBe(
    `Response to: ${SYSTEM_PROMPT}\n\nWrite a sonnet about Puppies.`,
  )
})

test('stops when it hits an error', async () => {
  jest.spyOn(ChatCompletionsClient.prototype, 'getChatCompletion').mockImplementation(async function* (messages) {
    if (messages.some(m => m.content.includes('sonnet'))) {
      throw new Error('This is an error!')
    }
    yield `Response to: ${messages.pop()?.content ?? ''}`
  })
  const runner = new PipelineRunner(
    {
      ...poetryAnalyzer,
      nodes: [
        ...poetryAnalyzer.nodes,
        {
          id: '6',
          title: 'Analysis',
          description: 'Analyzes three poems',
          type: 'prompt',
          content: 'Write a short summary of this analysis: {{5}}',
        },
      ],
    },
    0,
    new IndexedDBPipesStorage(),
    new GraphQLClient(''),
    new ChatCompletionsClient('', []),
  )

  const actions: PipesAction[] = []

  await runner.run(action => actions.push(action))

  // Node 3 (the sonnet) should have an error
  const errors = actions.filter(a => a.type === 'UPDATE_NODE_ERROR')
  expect(errors).toHaveLength(1)
  expect(errors[0]?.nodeId).toBe('3')

  // Node 5 (the comparative analysis) should never run because it depends on the sonnet
  const set5running = actions.find(a => a.type === 'SET_RUNNING' && a.running && a.nodeId === '5')
  expect(set5running).toBeUndefined()

  // Node 6 (the summary) should never run because it depends on the analysis
  const set6running = actions.find(a => a.type === 'SET_RUNNING' && a.running && a.nodeId === '6')
  expect(set6running).toBeUndefined()
})

const haikuGenerator: Pipeline = {
  updatedAt: '2025-01-01T00:00:00Z',
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

const multiplePoemGenerator: Pipeline = {
  updatedAt: '2025-01-01T00:00:00Z',
  id: 'multiple-poems',
  title: 'Poem Writer',
  nodes: [
    {
      id: '1',
      title: 'Topic',
      description: 'The topic of the poems',
      type: 'text',
      content: 'Puppies',
      inputType: {type: 'text'},
    },
    {
      id: '2',
      title: 'Haiku',
      description: 'Writes a haiku',
      type: 'prompt',
      content: 'Write a haiku about {{1}}.',
    },
    {
      id: '3',
      title: 'Sonnet',
      description: 'Writes a sonnet',
      type: 'prompt',
      content: 'Write a sonnet about {{1}}.',
    },
  ],
}

const poetryAnalyzer: Pipeline = {
  updatedAt: '2025-01-01T00:00:00Z',
  id: 'poetryAnalyzer',
  title: 'Poetry Analyzer',
  nodes: [
    {
      id: '1',
      title: 'Topic',
      description: 'The topic of the poems',
      type: 'text',
      content: 'Puppies',
      inputType: {type: 'text'},
    },
    {
      id: '2',
      title: 'Haiku',
      description: 'Writes a haiku',
      type: 'prompt',
      content: 'Write a haiku about {{1}}.',
    },
    {
      id: '3',
      title: 'Sonnet',
      description: 'Writes a sonnet',
      type: 'prompt',
      content: 'Write a sonnet about {{1}}.',
    },
    {
      id: '4',
      title: 'Limerick',
      description: 'Writes a limerick',
      type: 'prompt',
      content: 'Write a limerick about {{1}}.',
    },
    {
      id: '5',
      title: 'Analysis',
      description: 'Analyzes three poems',
      type: 'prompt',
      content: 'Conduct a brief analysis of three poems:\n\n{{2}}\n\n{{3}}\n\n{{4}}',
    },
  ],
}

import type {PipesAction} from '../../state/pipes-action'
import {defaultExecutionState} from '../../state/pipes-state'
import type {Pipeline} from '../../types/app'
import {ChatCompletionsClient} from '../chat-completions-client'
import {GraphQLClient} from '../graphql-client'
import {PipelineRunner} from '../pipeline-runner'
import {IndexedDBPipesStorage} from '../pipes-storage'

jest.spyOn(GraphQLClient.prototype, 'getGraphQLResponse').mockImplementation(async query => ({data: {query}}))

jest
  .spyOn(ChatCompletionsClient.prototype, 'getChatCompletion')
  .mockImplementation(async messages => `Response to: ${messages.pop()?.content ?? ''}`)

jest.spyOn(IndexedDBPipesStorage.prototype, 'getExecutionState').mockImplementation(async () => defaultExecutionState)

beforeEach(() => jest.clearAllMocks())

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
  // Each node has its value updated
  expect(actions.filter(a => a.type === 'UPDATE_NODE_VALUE')).toHaveLength(haikuGenerator.nodes.length)
  // No other expected actions
  expect(actions).toHaveLength(5 * haikuGenerator.nodes.length)

  // Output node value
  // @ts-expect-error For some reason `find` is not narrowing the type here
  expect(actions.find(a => a.type === 'UPDATE_NODE_VALUE' && a.nodeId === '2')!.value).toBe(
    'Response to: Write a haiku about Puppies.\n\n Respond with just the content, no intro, no explanation, etc.',
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
  // Each node has its value updated
  expect(actions.filter(a => a.type === 'UPDATE_NODE_VALUE')).toHaveLength(multiplePoemGenerator.nodes.length)
  // No other expected actions
  expect(actions).toHaveLength(5 * multiplePoemGenerator.nodes.length)

  // Output node value
  // @ts-expect-error For some reason `find` is not narrowing the type here
  expect(actions.find(a => a.type === 'UPDATE_NODE_VALUE' && a.nodeId === '2')!.value).toBe(
    'Response to: Write a haiku about Puppies.\n\n Respond with just the content, no intro, no explanation, etc.',
  )
  // @ts-expect-error For some reason `find` is not narrowing the type here
  expect(actions.find(a => a.type === 'UPDATE_NODE_VALUE' && a.nodeId === '3')!.value).toBe(
    'Response to: Write a sonnet about Puppies.\n\n Respond with just the content, no intro, no explanation, etc.',
  )
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

const multiplePoemGenerator: Pipeline = {
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

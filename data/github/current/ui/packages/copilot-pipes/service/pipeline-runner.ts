import type {PipesAction} from '../state/pipes-action'
import type {Node, NodeValue, Pipeline, PipelineGraph} from '../types/app'
import {getOutputNodes, getPipelineGraph} from '../utils/pipes'
import {replaceVariablesInNode} from '../utils/utils'
import type {ChatCompletionsClient} from './chat-completions-client'
import type {GraphQLClient} from './graphql-client'
import {NodeRunner} from './node-runner'
import type {PipesStorage} from './pipes-storage'

type ProgressCallback = (action: PipesAction) => void

export class PipelineRunner {
  readonly #storage: PipesStorage
  readonly #graphQLClient: GraphQLClient
  readonly #chatClient: ChatCompletionsClient

  readonly #pipeline: Pipeline
  readonly #iteration: number
  readonly #graph: PipelineGraph
  readonly #nodePromises: Map<string, Promise<NodeValue>>

  constructor(
    pipeline: Pipeline,
    iteration: number,
    storage: PipesStorage,
    gqlClient: GraphQLClient,
    chatClient: ChatCompletionsClient,
  ) {
    this.#storage = storage
    this.#graphQLClient = gqlClient
    this.#chatClient = chatClient

    this.#pipeline = pipeline
    this.#iteration = iteration
    this.#graph = getPipelineGraph(pipeline)
    this.#nodePromises = new Map()
  }

  public async run(onProgress: ProgressCallback): Promise<void> {
    const outputNodes = getOutputNodes(this.#pipeline)
    if (outputNodes.length === 0) throw new Error('No output node')
    await Promise.all(outputNodes.map(node => this.runNodeUnlessRunning(node, onProgress)))
  }

  private async runNodeUnlessRunning(node: Node, onProgress: ProgressCallback): Promise<NodeValue> {
    const existing = this.#nodePromises.get(node.id)
    if (existing) return existing

    const promise = this.runNode(node, onProgress)
    this.#nodePromises.set(node.id, promise)

    return promise
  }

  private async runNode(node: Node, onProgress: ProgressCallback): Promise<NodeValue> {
    const executionState = await this.#storage.getExecutionState(this.#pipeline.id, this.#iteration)
    const existingValue = executionState?.nodes[node.id]?.value
    if (existingValue) return existingValue

    onProgress({type: 'SET_PENDING', nodeId: node.id, pending: true, iteration: this.#iteration})
    const predecessorIDs = new Set(this.#graph.edges.filter(e => e.to === node.id).map(e => e.from))
    const predecessors = [...predecessorIDs].map(id => this.#pipeline.nodes.find(n => n.id === id)).filter(n => !!n)

    // Recurse
    const predecessorValues: Array<[string, NodeValue]> = await Promise.all(
      predecessors.map(async p => [p.id, await this.runNodeUnlessRunning(p, onProgress)]),
    )
    const predecessorValueMap = Object.fromEntries(predecessorValues)

    const filledNode = replaceVariablesInNode(node, predecessorValueMap)
    const runner = new NodeRunner(filledNode, this.#graphQLClient, this.#chatClient)

    onProgress({type: 'SET_PENDING', nodeId: node.id, pending: false, iteration: this.#iteration})
    onProgress({type: 'SET_RUNNING', nodeId: node.id, running: true, iteration: this.#iteration})
    try {
      const out = await runner.run()
      onProgress({
        type: 'UPDATE_NODE_VALUE',
        pipelineId: this.#pipeline.id,
        nodeId: node.id,
        value: out,
        iteration: this.#iteration,
      })
      onProgress({type: 'SET_RUNNING', nodeId: node.id, running: false, iteration: this.#iteration})
      return out
    } catch (e) {
      onProgress({
        type: 'UPDATE_NODE_ERROR',
        pipelineId: this.#pipeline.id,
        nodeId: node.id,
        error: getErrorMessage(e),
        iteration: this.#iteration,
      })
      return null
    }
  }
}

function getErrorMessage(e: unknown) {
  if (e instanceof Error) return e.message
  if (typeof e === 'string') return e
  if (typeof e === 'object') return JSON.stringify(e)
  return ''
}

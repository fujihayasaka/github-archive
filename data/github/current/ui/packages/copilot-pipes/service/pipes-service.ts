import type {Pipeline} from '../types/app'
import type {PipesStorage} from './pipes-storage'
import {PipelineRunner} from './pipeline-runner'
import type {PipesAction} from '../state/pipes-action'
import type {GraphQLClient} from './graphql-client'
import type {ChatCompletionsClient} from './chat-completions-client'
import {validatePipeline} from './validate-pipeline'
import type {ExecutionState} from '../state/pipes-state'

export class PipesService {
  readonly #storage: PipesStorage
  readonly #graphQLClient: GraphQLClient
  readonly #chatClient: ChatCompletionsClient

  constructor(storage: PipesStorage, gqlClient: GraphQLClient, chatClient: ChatCompletionsClient) {
    this.#storage = storage
    this.#graphQLClient = gqlClient
    this.#chatClient = chatClient
  }

  async getPipeline(threadID: string): Promise<Pipeline | null> {
    return this.#storage.getPipeline(threadID)
  }

  async updatePipeline(threadID: string, pipeline: Pipeline): Promise<Pipeline> {
    return this.#storage.updatePipeline(threadID, pipeline)
  }

  async getExecutionState(pipelineID: string, iteration?: number): Promise<ExecutionState | null> {
    return this.#storage.getExecutionState(pipelineID, iteration)
  }

  async updateExecutionState(pipelineID: string, iteration: number, state: ExecutionState): Promise<ExecutionState> {
    return this.#storage.updateExecutionState(pipelineID, iteration, state)
  }

  async runPipeline(pipeline: Pipeline, iteration: number, onProgress: (action: PipesAction) => void): Promise<void> {
    const errors = validatePipeline(pipeline)
    if (errors.length > 0) return

    const runner = new PipelineRunner(pipeline, iteration, this.#storage, this.#graphQLClient, this.#chatClient)
    return runner.run(onProgress)
  }
}

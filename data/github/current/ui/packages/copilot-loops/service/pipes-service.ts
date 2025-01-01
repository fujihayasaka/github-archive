import type {Pipeline} from '../types/app'
import type {PipesStorage, LoopVersion, LoopOperationResult} from './pipes-storage'
import {PipelineRunner} from './pipeline-runner'
import type {PipesAction} from '../state/pipes-action'
import type {GraphQLClient} from './graphql-client'
import type {ChatCompletionsClient} from './chat-completions-client'
import {validatePipeline} from './validate-pipeline'
import type {ExecutionState} from '../state/pipes-state'
import type {GraphQLSuccessfulResult} from '../utils/graphql'
import {compareDateStrings} from '../utils/dates'
import {removeLoopThreadId} from '../utils/loop-thread-storage'

export class PipesService {
  readonly #storage: PipesStorage
  readonly #graphQLClient: GraphQLClient
  readonly #chatClient: ChatCompletionsClient
  readonly #activeRunners: Map<string, PipelineRunner> = new Map()

  constructor(storage: PipesStorage, gqlClient: GraphQLClient, chatClient: ChatCompletionsClient) {
    this.#storage = storage
    this.#graphQLClient = gqlClient
    this.#chatClient = chatClient
  }

  async getGraphQLResponse(query: string): Promise<GraphQLSuccessfulResult | undefined> {
    return this.#graphQLClient.getGraphQLResponse(query)
  }

  async getLoop(loopID: string, version: LoopVersion = 'draft'): Promise<Pipeline | null> {
    return this.#storage.getLoop(loopID, version)
  }

  async getAllLoops(version: LoopVersion = 'latest'): Promise<Pipeline[]> {
    const loops = await this.#storage.getAllLoops(version)

    // Sort by updatedAt date in descending order
    return loops.sort((a, b) => compareDateStrings(b.updatedAt, a.updatedAt))
  }

  async createLoop(loopOrId: Pipeline | string): Promise<LoopOperationResult> {
    return this.#storage.createLoop(loopOrId)
  }

  async updateLoop(
    loopID: string,
    updateFn: (existingLoop: Pipeline | null) => Pipeline,
  ): Promise<LoopOperationResult> {
    return this.#storage.updateLoop(loopID, updateFn)
  }

  async deleteLoop(loopID: string): Promise<LoopOperationResult> {
    // clean up local storage
    removeLoopThreadId(loopID)

    return this.#storage.deleteLoop(loopID)
  }

  async saveLoop(loopID: string): Promise<LoopOperationResult> {
    return this.#storage.saveLoop(loopID)
  }

  async revertLoop(loopID: string): Promise<LoopOperationResult> {
    return this.#storage.revertLoop(loopID)
  }

  async getExecutionState(loopID: string, iteration?: number): Promise<ExecutionState | null> {
    return this.#storage.getExecutionState(loopID, iteration)
  }

  async updateExecutionState(loopID: string, iteration: number, state: ExecutionState): Promise<ExecutionState> {
    return this.#storage.updateExecutionState(loopID, iteration, state)
  }

  async runPipeline(pipeline: Pipeline, iteration: number, onProgress: (action: PipesAction) => void): Promise<void> {
    const errors = validatePipeline(pipeline)
    if (errors.length > 0) return

    const runner = new PipelineRunner(pipeline, iteration, this.#storage, this.#graphQLClient, this.#chatClient)

    // Store the runner with a unique key combining pipeline ID and iteration
    const runnerKey = this.createRunnerKey(pipeline.id, iteration)
    this.#activeRunners.set(runnerKey, runner)

    try {
      return await runner.run(onProgress)
    } finally {
      // Clean up runner reference when done
      this.#activeRunners.delete(runnerKey)
    }
  }

  stopPipeline(pipelineId: string, iteration: number, onProgress: (action: PipesAction) => void): void {
    const runnerKey = this.createRunnerKey(pipelineId, iteration)
    const runner = this.#activeRunners.get(runnerKey)
    if (!runner) return

    runner.stop(onProgress)
    this.#activeRunners.delete(runnerKey)
  }

  private createRunnerKey(pipelineId: string, iteration: number): string {
    return `${pipelineId}:${iteration}`
  }
}

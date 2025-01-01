import type {Node, NodeValue} from '../types/app'
import type {ChatCompletionsClient} from './chat-completions-client'
import type {GraphQLClient} from './graphql-client'
import {nodeHandlerRegistry} from './node-handler-registry'
import type {NodeExecutionContext} from '../types/node-handler-interface'

export class NodeRunner {
  readonly #node: Node
  readonly #graphQLClient: GraphQLClient
  readonly #chatClient: ChatCompletionsClient

  constructor(node: Node, gqlClient: GraphQLClient, chatClient: ChatCompletionsClient) {
    this.#node = node
    this.#graphQLClient = gqlClient
    this.#chatClient = chatClient
  }

  async run(signal?: AbortSignal, onPartialResult?: (result: string) => void): Promise<NodeValue> {
    const context: NodeExecutionContext = {
      graphQLClient: this.#graphQLClient,
      chatClient: this.#chatClient,
      signal,
      onPartialResult,
    }

    return nodeHandlerRegistry.executeNode(this.#node, context)
  }
}

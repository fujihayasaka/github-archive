import type {Node, NodeValue} from '../types/app'
import {createNodePromptChat} from '../utils/utils'
import type {ChatCompletionsClient} from './chat-completions-client'
import type {GraphQLClient} from './graphql-client'

export class NodeRunner {
  readonly #node: Node
  readonly #graphQLClient: GraphQLClient
  readonly #chatClient: ChatCompletionsClient

  constructor(node: Node, gqlClient: GraphQLClient, chatClient: ChatCompletionsClient) {
    this.#node = node
    this.#graphQLClient = gqlClient
    this.#chatClient = chatClient
  }

  async run(): Promise<NodeValue> {
    switch (this.#node.type) {
      case 'prompt': {
        const messages = await createNodePromptChat(this.#node)
        return this.#chatClient.getChatCompletion(messages)
      }
      case 'github-graphql':
        return JSON.stringify(await this.#graphQLClient.getGraphQLResponse(this.#node.content))
      default:
        return this.#node.content
    }
  }
}

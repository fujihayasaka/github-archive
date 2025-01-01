import type {Icon} from '@primer/octicons-react'
import type {IconColor} from '@github-ui/pacer/Icon'
import type {Node, NodeValue, NodeType} from './app'
import type {ChatCompletionsClient} from '../service/chat-completions-client'
import type {GraphQLClient} from '../service/graphql-client'

/**
 * Context object that contains all dependencies needed for node execution
 */
export interface NodeExecutionContext {
  graphQLClient: GraphQLClient
  chatClient: ChatCompletionsClient
  signal?: AbortSignal
  onPartialResult?: (result: string) => void
}

/**
 * Unified interface that combines metadata and execution logic for a node type
 */
export interface NodeHandler<T extends Node = Node> {
  readonly type: NodeType
  readonly metadata: NodeHandlerMetadata<T>
  execute(node: T, context: NodeExecutionContext): Promise<NodeValue>
}

/**
 * Metadata interface that extends the original NodeTypeInfo concept
 */
export interface NodeHandlerMetadata<T extends Node = Node> {
  color?: IconColor
  contentFields?: Array<keyof T>
  description: (node?: T) => string
  featureFlag?: string
  icon: (node?: T) => Icon
  isExecutable?: boolean
  requiresCodeEvaluation?: boolean
  label: (node?: T) => string
  type: NodeType
  outputLabel?: string
}

/**
 * Helper function to get default content for nodes that don't need complex execution
 */
export function getDefaultNodeContent<T extends Node>(node: T): NodeValue {
  return node.content
}

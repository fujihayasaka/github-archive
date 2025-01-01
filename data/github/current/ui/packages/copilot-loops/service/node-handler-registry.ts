import type {Node, NodeType, NodeValue} from '../types/app'
import type {NodeHandler, NodeExecutionContext} from '../types/node-handler-interface'
import {
  PromptNodeHandler,
  GitHubGraphQLNodeHandler,
  CodeNodeHandler,
  VisualizeNodeHandler,
  TextNodeHandler,
  LoopNodeHandler,
} from './node-handlers'

/**
 * Registry that manages all node handlers and provides unified access to them
 */
export class NodeHandlerRegistry {
  private readonly handlers = new Map<NodeType, NodeHandler>()

  constructor() {
    // Register all default handlers
    this.registerHandler(new PromptNodeHandler())
    this.registerHandler(new GitHubGraphQLNodeHandler())
    this.registerHandler(new CodeNodeHandler())
    this.registerHandler(new VisualizeNodeHandler())
    this.registerHandler(new TextNodeHandler())
    this.registerHandler(new LoopNodeHandler())
  }

  /**
   * Register a new handler for a node type
   */
  registerHandler<T extends Node>(handler: NodeHandler<T>): void {
    this.handlers.set(handler.type, handler as NodeHandler)
  }

  /**
   * Execute a node using its registered handler
   */
  async executeNode<T extends Node>(node: T, context: NodeExecutionContext): Promise<NodeValue> {
    const handler = this.handlers.get(node.type) as NodeHandler<T> | undefined
    if (!handler) {
      throw new Error(`No handler registered for node type: ${node.type}`)
    }
    return handler.execute(node, context)
  }

  /**
   * Get metadata for a node type
   */
  getMetadata(nodeType: NodeType) {
    const handler = this.handlers.get(nodeType)
    return handler?.metadata
  }

  /**
   * Get all metadata as an array (for React components)
   */
  getAllMetadata() {
    return Array.from(this.handlers.values()).map(handler => handler.metadata)
  }

  /**
   * Get all registered node types
   */
  getAllNodeTypes(): NodeType[] {
    return Array.from(this.handlers.keys())
  }

  /**
   * Check if a node type is executable
   */
  isExecutable(nodeType: NodeType): boolean {
    const metadata = this.getMetadata(nodeType)
    return metadata?.isExecutable ?? false
  }

  /**
   * Check if a node type requires code evaluation (string values should be JSON-stringified)
   */
  requiresCodeEvaluation(nodeType: NodeType): boolean {
    const metadata = this.getMetadata(nodeType)
    return metadata?.requiresCodeEvaluation ?? false
  }
}

/**
 * Global registry instance
 */
export const nodeHandlerRegistry = new NodeHandlerRegistry()

import type {Node, CodeNode, PipelineNode, PromptNode, GitHubGraphQLNode, TextNode, VisualizeNode} from '../types/app'

export function isCodeNode(node: Node): node is CodeNode {
  return node.type === 'code'
}

export function isPromptNode(node: Node): node is PromptNode {
  return node.type === 'prompt'
}

export function isVisualizeNode(node: Node): node is VisualizeNode {
  return node.type === 'visualize'
}

export function isGitHubGraphQLNode(node: Node): node is GitHubGraphQLNode {
  return node.type === 'github-graphql'
}

export function isPipelineNode(node: Node): node is PipelineNode {
  return node.type === 'pipeline'
}

export function isTextNode(node: Node): node is TextNode {
  return node.type === 'text'
}

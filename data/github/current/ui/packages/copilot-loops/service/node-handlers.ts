import {
  CodeIcon,
  TypographyIcon,
  CopilotIcon,
  GitBranchIcon,
  GitPullRequestIcon,
  MarkGithubIcon,
} from '@primer/octicons-react'
import type {NodeValue, PromptNode, GitHubGraphQLNode, CodeNode, VisualizeNode, TextNode, LoopNode} from '../types/app'
import type {NodeHandler, NodeExecutionContext} from '../types/node-handler-interface'
import {getDefaultNodeContent} from '../types/node-handler-interface'
import {createNodePromptChat} from '../utils/utils'
import {isTextNode} from '../utils/node-assertions'
import {getInputNodeTypeField} from '../types/input-types'

/**
 * Handler for prompt nodes - uses AI chat completion
 */
export class PromptNodeHandler implements NodeHandler<PromptNode> {
  readonly type = 'prompt' as const
  readonly metadata = {
    contentFields: ['content'] as Array<keyof PromptNode>,
    icon: () => CopilotIcon,
    description: () => 'Use AI to process a node',
    label: () => 'Prompt',
    color: 'purple' as const,
    type: 'prompt' as const,
    outputLabel: 'Markdown',
    isExecutable: true,
  }

  async execute(node: PromptNode, context: NodeExecutionContext): Promise<NodeValue> {
    const messages = await createNodePromptChat(node)

    let result = ''
    for await (const chunk of context.chatClient.getChatCompletion(messages, node.model, context.signal)) {
      result += chunk
      context.onPartialResult?.(result)
    }

    return result
  }
}

/**
 * Handler for GitHub GraphQL nodes - fetches data from GitHub API
 */
export class GitHubGraphQLNodeHandler implements NodeHandler<GitHubGraphQLNode> {
  readonly type = 'github-graphql' as const
  readonly metadata = {
    type: 'github-graphql' as const,
    contentFields: ['content'] as Array<keyof GitHubGraphQLNode>,
    icon: () => MarkGithubIcon,
    description: () => 'Retrieve data from GitHub',
    label: () => 'GitHub GraphQL',
    color: 'gray' as const,
    featureFlag: 'copilot_pipes_github_graphql_nodes',
    outputLabel: 'JSON',
    isExecutable: true,
  }

  async execute(node: GitHubGraphQLNode, context: NodeExecutionContext): Promise<NodeValue> {
    const graphQLResult = await context.graphQLClient.getGraphQLResponse(node.content, context.signal)
    return graphQLResult?.data ?? null
  }
}

/**
 * Handler for code nodes - returns content as-is (execution handled elsewhere)
 */
export class CodeNodeHandler implements NodeHandler<CodeNode> {
  readonly type = 'code' as const
  readonly metadata = {
    type: 'code' as const,
    color: 'pink' as const,
    contentFields: ['content'] as Array<keyof CodeNode>,
    icon: () => CodeIcon,
    description: () => 'Use classic code to process a node',
    label: () => 'Code',
    featureFlag: 'copilot_pipes_react_nodes',
    outputLabel: 'Code output',
    isExecutable: true,
    requiresCodeEvaluation: true,
  }

  async execute(node: CodeNode, _context: NodeExecutionContext): Promise<NodeValue> {
    return getDefaultNodeContent(node)
  }
}

/**
 * Handler for visualize nodes - returns content as-is (rendering handled elsewhere)
 */
export class VisualizeNodeHandler implements NodeHandler<VisualizeNode> {
  readonly type = 'visualize' as const
  readonly metadata = {
    type: 'visualize' as const,
    contentFields: ['content'] as Array<keyof VisualizeNode>,
    icon: () => GitBranchIcon,
    description: () => 'Use HTML and CSS to view output',
    label: () => 'Visualize',
    color: 'olive' as const,
    featureFlag: 'copilot_pipes_react_nodes',
  }

  async execute(node: VisualizeNode, _context: NodeExecutionContext): Promise<NodeValue> {
    return getDefaultNodeContent(node)
  }
}

/**
 * Handler for text nodes - input nodes with various input types
 */
export class TextNodeHandler implements NodeHandler<TextNode> {
  readonly type = 'text' as const
  readonly metadata = {
    type: 'text' as const,
    contentFields: ['content'] as Array<keyof TextNode>,
    icon: (node?: TextNode) => (node && isTextNode(node) ? getInputNodeTypeField(node, 'icon') : TypographyIcon),
    description: (node?: TextNode) =>
      node && isTextNode(node) ? getInputNodeTypeField(node, 'description') : 'Input for nodes',
    label: (node?: TextNode) => (node && isTextNode(node) ? getInputNodeTypeField(node, 'name') : 'Input'),
    color: 'blue' as const,
  }

  async execute(node: TextNode, _context: NodeExecutionContext): Promise<NodeValue> {
    return getDefaultNodeContent(node)
  }
}

/**
 * Handler for loop nodes - pipeline nodes
 */
export class LoopNodeHandler implements NodeHandler<LoopNode> {
  readonly type = 'loop' as const
  readonly metadata = {
    type: 'loop' as const,
    contentFields: ['content'] as Array<keyof LoopNode>,
    icon: () => GitPullRequestIcon,
    description: () => 'Use an existing pipeline as a node',
    label: () => 'Pipeline',
    color: 'coral' as const,
    featureFlag: 'copilot_pipes_pipeline_nodes',
    outputLabel: 'Pipeline output',
    isExecutable: true,
  }

  async execute(node: LoopNode, _context: NodeExecutionContext): Promise<NodeValue> {
    // TODO: Implement pipeline execution logic
    // For now, return the content as placeholder
    return getDefaultNodeContent(node)
  }
}

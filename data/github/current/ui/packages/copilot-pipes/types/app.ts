export interface Pipeline {
  id: string
  title: string
  description?: string
  nodes: Node[]
}

export type NodeValue = string | number | boolean | string[] | null

type NodeBase = {
  id: string
  title: string
  description: string
  content: string
}

export type InputTypeRange = {
  type: 'range'
  min: number
  max: number
}

export type InputTypeText = {
  type: 'text'
}

export type InputTypeBoolean = {
  type: 'boolean'
}

export type InputTypeSelect = {
  type: 'select'
  options: string[]
}

export type InputTypeFile = {
  type: 'file'
  fileType: 'pdf' | 'image' | 'video' | 'audio' | 'document' | 'code' | 'other'
}

export type InputType = InputTypeRange | InputTypeText | InputTypeBoolean | InputTypeSelect | InputTypeFile

export type TextNode = NodeBase & {
  type: 'text'
  inputType: InputType
}

export type PromptNode = NodeBase & {
  type: 'prompt'
}

export type CodeNode = NodeBase & {
  type: 'code'
}

export type VisualizeNode = NodeBase & {
  type: 'visualize'
}

export type GitHubGraphQLNode = NodeBase & {
  type: 'github-graphql'
}

export type PipelineNode = NodeBase & {
  type: 'pipeline'
  pipelineId: string
  pipelineInputValues?: PipelineInputValue[]
}

export type Node = TextNode | PromptNode | CodeNode | VisualizeNode | GitHubGraphQLNode | PipelineNode

export type NodeType = Node['type']

export type PipelineInputValue = {
  nodeId: string
  inputId: string
  doMapInput?: boolean
}

interface Edge {
  from: string
  to: string
}

export type PipelineGraph = {
  nodes: Map<string, Node>
  edges: Edge[]
  layers: Node[][]
}

export type ChatMessage = {
  role: 'user' | 'assistant'
  content: string
}

export interface PipelineValidationError {
  error: string
  involvedNodes: string[]
}

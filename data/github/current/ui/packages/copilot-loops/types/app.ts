import type {IconColor} from '@github-ui/pacer/Icon'

export interface Pipeline {
  id: string
  title: string
  description?: string
  nodes: Node[]
  updatedAt: string
  color?: IconColor
}

export type NodeValue = string | number | boolean | string[] | object | null

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
  model?: string
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

export type LoopNode = NodeBase & {
  type: 'loop'
  loopId: string
  loopInputValues?: LoopInputValue[]
}

export type Node = TextNode | PromptNode | CodeNode | VisualizeNode | GitHubGraphQLNode | LoopNode

export type NodeType = Node['type']

export type LoopInputValue = {
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
  role: 'user' | 'system'
  content: string
}

export const pipelineErrorType = {
  MissingProperty: 'MissingProperty',
  CycleDetected: 'CycleDetected',
  NonexistentNode: 'NonexistentNode',
  DisconnectedNode: 'DisconnectedNode',
  InvalidBooleanValue: 'InvalidBooleanValue',
  InvalidRangeValue: 'InvalidRangeValue',
  InvalidSelectValue: 'InvalidSelectValue',
  InvalidFileType: 'InvalidFileType',
  EmptyInputValue: 'EmptyInputValue',
} as const

export type PipelineErrorType = keyof typeof pipelineErrorType

export interface PipelineValidationError {
  error: string
  errorType: PipelineErrorType
  involvedNodes: string[]
}

import type {NodeValue, Pipeline, PipelineValidationError} from '../types/app'

export interface ExecutionState {
  nodes: Record<string, NodeExecutionState>
  iteration: number
}

interface NodeExecutionState {
  value?: NodeValue
  error?: string
  cachedPrompt?: string
  running: boolean
  pending: boolean
  progress: number
}

export const defaultExecutionState: ExecutionState = {
  nodes: {},
  iteration: 0,
}

export const defaultNodeState: NodeExecutionState = {
  value: null,
  running: false,
  pending: false,
  progress: 0,
}

export interface PipelineState {
  pipelines: {[id: string]: Pipeline}
  validationErrors: PipelineValidationError[]
  selectedPipelineId: string | null
  isUpdating: boolean
  isLoading: boolean
}

export const defaultPipelineState: PipelineState = {
  pipelines: {},
  validationErrors: [],
  selectedPipelineId: null,
  isUpdating: false,
  isLoading: false,
}

export interface UIState {
  focusedNodeId: string | null
  hoveredNodeId: string | null
}

export const defaultUIState: UIState = {
  focusedNodeId: null,
  hoveredNodeId: null,
}

export interface PipesState {
  executionState: ExecutionState
  uiState: UIState
  pipelineState: PipelineState
}

export const defaultPipesState: PipesState = {
  executionState: defaultExecutionState,
  uiState: defaultUIState,
  pipelineState: defaultPipelineState,
}

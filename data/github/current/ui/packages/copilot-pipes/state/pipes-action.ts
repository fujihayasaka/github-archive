import type {Pipeline, Node, NodeValue} from '../types/app'
import type {ExecutionState} from './pipes-state'

export type PipesAction =
  | {type: 'INITIALIZE_PIPELINES'; pipelines: Pipeline[]}
  | {type: 'SELECT_PIPELINE'; pipelineId: string | null}
  | {type: 'ADD_PIPELINE'; pipeline: Pipeline}
  | {type: 'REMOVE_PIPELINE'; pipelineId: string}
  | {type: 'SET_IS_UPDATING'; updating: boolean}
  // Pipeline Actions
  | {type: 'ADD_NODE_TO_PIPELINE'; pipelineId: string; node: Node}
  | {type: 'UPDATE_NODE_CONTENT'; pipelineId: string; nodeId: string; content: string}
  | {type: 'UPDATE_PIPELINE'; pipelineId: string; updates: Partial<Pipeline>}
  | {type: 'UPDATE_PIPELINE_NODE'; pipelineId: string; nodeId: string; updates: Partial<Node>}
  | {type: 'UPDATE_NODE'; pipelineId: string; nodeId: string; updates: Partial<Node & {doRemove: true}>}
  | {type: 'REMOVE_NODE'; pipelineId: string; nodeId: string}
  // UI Actions
  | {type: 'FOCUS_NODE'; nodeId: string | null}
  | {type: 'HOVER_NODE'; nodeId: string | null}
  // Execution State
  | {type: 'RESTORE_EXECUTION_STATE'; executionState: ExecutionState}
  | {type: 'CLEAR_NODE_RESULTS'; pipelineId: string; nodeIds: string[]}
  | {type: 'UPDATE_NODE_VALUE'; pipelineId: string; nodeId: string; value: NodeValue; iteration: number}
  | {type: 'UPDATE_NODE_ERROR'; pipelineId: string; nodeId: string; error: string; iteration: number}
  | {type: 'SET_RUNNING'; nodeId: string; running: boolean; iteration: number}
  | {type: 'SET_PENDING'; nodeId: string; pending: boolean; iteration: number}
  | {type: 'UPDATE_PROGRESS'; nodeId: string; progress: number; iteration: number}
  | {type: 'CLEAR_PENDING_NODES'; iteration: number}
  | {type: 'CANCEL_EXECUTION'; iteration: number}
  | {type: 'INCREMENT_ITERATION'}

import type {NodeValue} from '../types/app'
import type {ExecutionState} from './pipes-state'

export type PipesAction =
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

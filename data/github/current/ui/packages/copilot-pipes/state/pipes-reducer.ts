import {executionReducer} from './execution-reducer'
import {pipelineStateReducer} from './pipeline-reducer'
import type {PipesAction} from './pipes-action'
import type {PipesState} from './pipes-state'
import {uiReducer} from './ui-reducer'

export function pipesReducer(state: PipesState, action: PipesAction): PipesState {
  return {
    ...state,
    executionState: executionReducer(state.executionState, action),
    uiState: uiReducer(state.uiState, action),
    pipelineState: pipelineStateReducer(state.pipelineState, action),
  }
}

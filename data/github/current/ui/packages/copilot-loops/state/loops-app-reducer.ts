import {executionReducer} from './execution-reducer'
import type {PipesAction} from './pipes-action'
import type {PipesState} from './pipes-state'
import {uiReducer} from './ui-reducer'

export function loopsAppReducer(state: PipesState, action: PipesAction): PipesState {
  return {
    ...state,
    executionState: executionReducer(state.executionState, action),
    uiState: uiReducer(state.uiState, action),
  }
}

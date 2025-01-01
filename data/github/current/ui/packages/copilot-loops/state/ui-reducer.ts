import type {PipesAction} from './pipes-action'
import type {UIState} from './pipes-state'

export function uiReducer(state: UIState, action: PipesAction): UIState {
  switch (action.type) {
    case 'FOCUS_NODE': {
      return {...state, focusedNodeId: action.nodeId}
    }
    case 'HOVER_NODE': {
      return {...state, hoveredNodeId: action.nodeId}
    }
    default:
      return state
  }
}

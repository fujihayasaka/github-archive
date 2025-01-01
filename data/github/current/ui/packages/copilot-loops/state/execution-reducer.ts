import type {PipesAction} from './pipes-action'
import {defaultNodeState, type ExecutionState} from './pipes-state'

export function executionReducer(state: ExecutionState, action: PipesAction): ExecutionState {
  switch (action.type) {
    case 'RESTORE_EXECUTION_STATE':
      return {
        ...action.executionState,
        nodes: Object.fromEntries(
          Object.entries(action.executionState.nodes).map(([id, n]) => [
            id,
            {...defaultNodeState, value: n.value, error: n.error},
          ]),
        ),
      }
    case 'CLEAR_NODE_RESULTS': {
      const nodes = {...state.nodes}
      for (const id of action.nodeIds) {
        delete nodes[id]
      }
      return {
        ...state,
        nodes,
      }
    }
    case 'SET_RUNNING': {
      if (action.iteration !== state.iteration) return state
      return {
        ...state,
        nodes: {
          ...state.nodes,
          [action.nodeId]: {
            ...(state.nodes[action.nodeId] ?? defaultNodeState),
            running: action.running,
          },
        },
      }
    }
    case 'SET_PENDING': {
      if (action.iteration !== state.iteration) return state
      return {
        ...state,
        nodes: {
          ...state.nodes,
          [action.nodeId]: {
            ...(state.nodes[action.nodeId] ?? defaultNodeState),
            pending: action.pending,
          },
        },
      }
    }
    case 'UPDATE_PROGRESS': {
      if (action.iteration !== state.iteration) return state
      return {
        ...state,
        nodes: {
          ...state.nodes,
          [action.nodeId]: {
            ...(state.nodes[action.nodeId] ?? defaultNodeState),
            progress: action.progress,
          },
        },
      }
    }
    case 'UPDATE_NODE_VALUE': {
      if (action.iteration !== state.iteration) return state
      return {
        ...state,
        nodes: {
          ...state.nodes,
          [action.nodeId]: {
            ...(state.nodes[action.nodeId] ?? defaultNodeState),
            value: action.value,
          },
        },
      }
    }
    case 'UPDATE_NODE_ERROR': {
      if (action.iteration !== state.iteration) return state
      return {
        ...state,
        nodes: {
          ...state.nodes,
          [action.nodeId]: {
            ...(state.nodes[action.nodeId] ?? defaultNodeState),
            error: action.error,
            value: null,
            running: false,
          },
        },
      }
    }
    case 'CLEAR_PENDING_NODES': {
      if (action.iteration !== state.iteration) return state
      return {
        ...state,
        nodes: Object.fromEntries(
          Object.entries(state.nodes).map(([nodeId, nodeState]) => [
            nodeId,
            {
              ...nodeState,
              pending: false,
            },
          ]),
        ),
      }
    }
    case 'CANCEL_EXECUTION': {
      if (action.iteration !== state.iteration) return state
      return {
        ...state,
        nodes: Object.fromEntries(
          Object.entries(state.nodes).map(([nodeId, nodeState]) => [
            nodeId,
            {
              ...nodeState,
              running: false,
              pending: false,
              progress: 0,
            },
          ]),
        ),
      }
    }
    case 'INCREMENT_ITERATION': {
      return {
        ...state,
        iteration: state.iteration + 1,
      }
    }
    default:
      return state
  }
}

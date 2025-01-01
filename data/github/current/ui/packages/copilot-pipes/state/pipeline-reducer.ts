import {validatePipeline} from '../service/validate-pipeline'
import type {Pipeline, Node} from '../types/app'
import {sanitizeNode, sanitizePipeline} from '../utils/pipes'
import type {PipesAction} from './pipes-action'
import type {PipelineState} from './pipes-state'

export function pipelineStateReducer(state: PipelineState, action: PipesAction): PipelineState {
  switch (action.type) {
    case 'INITIALIZE_PIPELINES': {
      const selected = action.pipelines.find(p => p.id === state.selectedPipelineId)
      const validationErrors = selected ? validatePipeline(selected) : []
      return {
        ...state,
        validationErrors,
        pipelines: action.pipelines.reduce((acc, p) => ({...acc, [p.id]: p}), {}),
        isLoading: false,
      }
    }
    case 'SELECT_PIPELINE': {
      if (action.pipelineId === null) return {...state, selectedPipelineId: null}

      const selected = state.pipelines[action.pipelineId]
      if (!selected) return state

      return {...state, selectedPipelineId: action.pipelineId, validationErrors: validatePipeline(selected)}
    }
    case 'SET_IS_UPDATING':
      return {...state, isUpdating: action.updating}
    case 'ADD_PIPELINE':
      return {
        ...state,
        pipelines: {...state.pipelines, [action.pipeline.id]: action.pipeline},
        selectedPipelineId: action.pipeline.id,
        validationErrors: validatePipeline(action.pipeline),
      }
    case 'REMOVE_PIPELINE': {
      const withoutDeleted = {...state.pipelines}
      delete withoutDeleted[action.pipelineId]

      const selectedPipelineId =
        state.selectedPipelineId === action.pipelineId ? state.pipelines[0]?.id ?? null : state.selectedPipelineId

      const selectedPipeline = selectedPipelineId ? state.pipelines[selectedPipelineId] : null

      const validationErrors = selectedPipeline ? validatePipeline(selectedPipeline) : []

      return {
        ...state,
        pipelines: withoutDeleted,
        validationErrors,
        selectedPipelineId,
      }
    }
    case 'UPDATE_PIPELINE':
    case 'ADD_NODE_TO_PIPELINE':
    case 'UPDATE_PIPELINE_NODE':
    case 'UPDATE_NODE':
    case 'UPDATE_NODE_CONTENT':
    case 'REMOVE_NODE': {
      const currentPipeline = state.pipelines[action.pipelineId]
      if (!currentPipeline) return state

      const updated = pipelineReducer(currentPipeline, action)
      const validationErrors = validatePipeline(updated)

      return {
        ...state,
        validationErrors,
        pipelines: {
          ...state.pipelines,
          [currentPipeline.id]: updated,
        },
      }
    }
    default:
      return state
  }
}

function pipelineReducer(pipeline: Pipeline, action: PipesAction): Pipeline {
  switch (action.type) {
    case 'ADD_NODE_TO_PIPELINE': {
      return {
        ...pipeline,
        nodes: [...(pipeline.nodes ?? []), action.node],
      }
    }
    case 'REMOVE_NODE': {
      return {
        ...pipeline,
        nodes: pipeline.nodes.filter(n => n.id !== action.nodeId),
      }
    }
    case 'UPDATE_NODE': {
      const nodeIndex = pipeline.nodes.findIndex(n => n.id === action.nodeId)
      if (nodeIndex === -1) {
        return {
          ...pipeline,
          nodes: [
            ...pipeline.nodes,
            {
              id: action.nodeId,
              type: 'text',
              title: '',
              description: '',
              content: '',
              ...action.updates,
            } as Node,
          ],
        }
      } else if (action.updates.doRemove) {
        return {
          ...pipeline,
          nodes: [...pipeline.nodes.slice(0, nodeIndex), ...pipeline.nodes.slice(nodeIndex + 1)],
        }
      } else {
        const node = pipeline.nodes[nodeIndex]
        return {
          ...pipeline,
          nodes: [
            ...pipeline.nodes.slice(0, nodeIndex),
            {...node, ...action.updates} as Node,
            ...pipeline.nodes.slice(nodeIndex + 1),
          ],
        }
      }
    }
    case 'UPDATE_PIPELINE_NODE': {
      const nodeIndex = pipeline.nodes.findIndex(n => n.id === action.nodeId)
      if (nodeIndex === -1) return pipeline
      const node = pipeline.nodes[nodeIndex]
      const sanitizedNode = sanitizeNode({...node, ...action.updates} as Node, [])
      if (!sanitizedNode) return pipeline
      return {
        ...pipeline,
        nodes: [...pipeline.nodes.slice(0, nodeIndex), sanitizedNode, ...pipeline.nodes.slice(nodeIndex + 1)],
      }
    }
    case 'UPDATE_NODE_CONTENT': {
      const nodeIndex = pipeline.nodes.findIndex(n => n.id === action.nodeId)
      if (nodeIndex === -1) return pipeline

      const node = pipeline.nodes[nodeIndex]
      return {
        ...pipeline,
        nodes: [
          ...pipeline.nodes.slice(0, nodeIndex),
          {...node, content: action.content} as Node,
          ...pipeline.nodes.slice(nodeIndex + 1),
        ],
      }
    }
    case 'UPDATE_PIPELINE': {
      return sanitizePipeline(
        {
          ...pipeline,
          ...action.updates,
        },
        [],
      )
    }
    default:
      return pipeline
  }
}

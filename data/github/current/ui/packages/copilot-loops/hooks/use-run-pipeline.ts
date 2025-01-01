import {useCallback} from 'react'
import {usePipesDispatch, useGetPipesState} from '../contexts/PipesStateProvider'
import {usePipesService} from '../contexts/PipesServiceProvider'
import {logError} from '../utils/console'
import {clearDownstreamNodes} from '../utils/pipes'
import {useCurrentLoop} from './use-current-loop'
import {useHasValidationErrors} from './use-validation-errors'

export function useRunPipeline() {
  const dispatch = usePipesDispatch()
  const service = usePipesService()
  const getState = useGetPipesState()
  const hasValidationErrors = useHasValidationErrors()
  const loop = useCurrentLoop()

  const runPipeline = async (nodeId?: string) => {
    if (hasValidationErrors) return

    try {
      dispatch({type: 'INCREMENT_ITERATION'})
      const currentIteration = getState().executionState.iteration + 1

      if (nodeId) {
        clearDownstreamNodes(loop, nodeId, dispatch)
      } else {
        dispatch({
          type: 'CLEAR_NODE_RESULTS',
          pipelineId: loop.id,
          nodeIds: loop.nodes.map(n => n.id),
        })
      }

      await service.runPipeline(loop, currentIteration, dispatch)
    } catch (error) {
      logError('Error running pipeline:', error)
    }
  }

  const stopPipeline = useCallback(() => {
    const iteration = getState().executionState.iteration

    service.stopPipeline(loop.id, iteration, dispatch)
  }, [dispatch, getState, loop.id, service])

  return {runPipeline, stopPipeline}
}

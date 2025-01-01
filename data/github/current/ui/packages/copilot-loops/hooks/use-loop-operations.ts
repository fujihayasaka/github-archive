import {
  addNodeToPipeline,
  removeNodeFromPipeline,
  updateNodeInPipeline,
  updateNodeContentInPipeline,
} from '../utils/update-loop'
import type {Node, Pipeline} from '../types/app'
import {useLoop} from './queries/use-loop'
import {usePipesDispatch} from '../contexts/PipesStateProvider'
import {useUpdateLoopMutation} from './mutations/use-update-loop-mutation'

/**
 * This hook provides operations for modifying the current loop.
 */
export function useLoopOperations() {
  const {data: loop} = useLoop()
  const {mutate: updateLoop, isPending} = useUpdateLoopMutation()
  const dispatch = usePipesDispatch()

  const handleUpdateLoop = (updatedLoop: Pipeline, onSuccess?: () => void) => {
    if (!updatedLoop) return

    updateLoop(
      {
        loopID: updatedLoop.id,
        updateFn: () => updatedLoop,
      },
      {onSuccess},
    )
  }

  return {
    addNode: (node: Node) => {
      if (!loop) return
      const updatedLoop = addNodeToPipeline(loop, node)
      const handleSuccess = () => dispatch({type: 'FOCUS_NODE', nodeId: node.id})

      handleUpdateLoop(updatedLoop, handleSuccess)
    },
    removeNode: (nodeId: string) => {
      if (!loop) return
      const updatedLoop = removeNodeFromPipeline(loop, nodeId)
      const handleSuccess = () => dispatch({type: 'FOCUS_NODE', nodeId: null})

      handleUpdateLoop(updatedLoop, handleSuccess)
    },
    updateNode: (nodeId: string, updates: Partial<Node>) => {
      if (!loop) return
      const updatedLoop = updateNodeInPipeline(loop, nodeId, updates)
      handleUpdateLoop(updatedLoop)
    },
    updateNodeContent: (nodeId: string, content: string) => {
      if (!loop) return
      const updatedLoop = updateNodeContentInPipeline(loop, nodeId, content)
      handleUpdateLoop(updatedLoop)
    },
    updateLoop: (updatedLoop: Pipeline) => {
      handleUpdateLoop(updatedLoop)
    },
    isPending,
  }
}

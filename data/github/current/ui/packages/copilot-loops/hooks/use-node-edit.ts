import {useDebounce} from '@github-ui/use-debounce'
import {useNode} from '../state/lenses'
import type {Node} from '../types/app'
import {getOutputNodes, sanitizeNode} from '../utils/pipes'
import {useRunPipeline} from './use-run-pipeline'
import {useLoopOperations} from './use-loop-operations'
import {useCurrentLoop} from './use-current-loop'
import {useHasValidationErrors} from './use-validation-errors'

export function useNodeEdit({nodeId}: {nodeId: string; pipelineId: string}) {
  const {runPipeline, stopPipeline} = useRunPipeline()
  const {updateNode} = useLoopOperations()
  const hasValidationErrors = useHasValidationErrors()

  const node = useNode(nodeId)
  const loop = useCurrentLoop()

  const isOutput = getOutputNodes(loop).some(n => n.id === nodeId)

  const runPipelineDebounced = useDebounce((nodeIdToRun: string) => runPipeline(nodeIdToRun), 1000)

  const runPipelineFromNode = async () => {
    if (hasValidationErrors) return
    if (!node) return

    runPipeline(node.id)
  }

  const onUpdate = (updates: Partial<Node>) => {
    if (!node) return

    const sanitizedNode = sanitizeNode({...node, ...updates} as Node, [])
    if (!sanitizedNode) return

    updateNode(node.id, sanitizedNode)

    runPipelineDebounced(node.id)
  }

  return {
    isOutput,
    node,
    runPipelineFromNode,
    onUpdate,
    onStop: stopPipeline,
  }
}

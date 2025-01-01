import {usePipesStateLens} from '../contexts/PipesStateProvider'
import {useLoopLens} from '../hooks/use-loop-lens'
import {useValidationErrors} from '../hooks/use-validation-errors'
import type {Pipeline, Node, NodeValue} from '../types/app'
import {getInputIds} from '../utils/pipes'
import type {PipesState} from './pipes-state'

/**
 * The edge component uses internal state lenses to determine the edge's status (`IDLE`, `PROCESSING`, `COMPLETED`, or `ERROR`).
 * The visual representation of the edge changes based on this status.
 */
export type Status = 'IDLE' | 'PROCESSING' | 'COMPLETED' | 'ERROR'

export function useNodeIDs() {
  const joined = useLoopLens(
    // Return a string so that we only re-render when the actual ids have changed
    loop => loop?.nodes?.map(n => n.id)?.join('|'),
  )
  return joined?.split('|') ?? []
}

export const nodeDefinition = (nodeID: string, pipeline: Pipeline | null | undefined) => {
  return pipeline?.nodes.find(n => n.id === nodeID)
}

export function useNodeContent(nodeId: string) {
  return useLoopLens(loop => nodeDefinition(nodeId, loop)?.content ?? '')
}

export function useNodeType(nodeId: string) {
  return useLoopLens(loop => nodeDefinition(nodeId, loop)?.type ?? 'text')
}

export function useNodeInputIds(nodeId: string): string[] {
  const joined = useLoopLens(loop => {
    // Return a string so that we only re-render when the actual inputs have changed
    const node = nodeDefinition(nodeId, loop)
    if (!node) return ''
    return [...getInputIds(node)].sort().join('|')
  })
  return joined === '' ? [] : joined.split('|')
}

const nodeState = (nodeID: string) => (s: PipesState) => s.executionState.nodes[nodeID]

export function useNode(nodeID: string): Node | undefined {
  return useLoopLens(loop => nodeDefinition(nodeID, loop))
}

export function useNodeValue(nodeID: string): NodeValue {
  return usePipesStateLens(s => nodeState(nodeID)(s)?.value ?? null)
}

export function useNodeError(nodeID: string): string | undefined {
  return usePipesStateLens(s => nodeState(nodeID)(s)?.error)
}

export function useNodeRunning(nodeID: string): boolean {
  return usePipesStateLens(s => nodeState(nodeID)(s)?.running ?? false)
}

export function useNodeProgress(nodeID: string): number {
  return usePipesStateLens(s => nodeState(nodeID)(s)?.progress ?? 0)
}

export function useLoopIsRunning(): boolean {
  return usePipesStateLens((s: PipesState) => {
    return Object.values(s.executionState.nodes).some(node => node.running)
  })
}
export function useNodeIndicatorStatus(nodeId: string): Status {
  const validationErrors = useValidationErrors()
  return usePipesStateLens(({executionState}) => {
    if (!nodeId) return 'IDLE'
    const isRunning = executionState.nodes[nodeId]?.running || false
    const isDone =
      executionState.nodes[nodeId]?.value &&
      !executionState.nodes[nodeId]?.running &&
      !validationErrors.some(e => e.involvedNodes.includes(nodeId))
    const isError = executionState.nodes[nodeId]?.error || validationErrors.some(e => e.involvedNodes.includes(nodeId))
    return isError ? 'ERROR' : isRunning ? 'PROCESSING' : isDone ? 'COMPLETED' : 'IDLE'
  })
}

export function useEdgeStatus(sourceNodeId: string, targetNodeId: string): Status {
  const validationErrors = useValidationErrors()
  return usePipesStateLens(({executionState}) => {
    if (!sourceNodeId || !targetNodeId) return 'IDLE'
    const isRunning = executionState.nodes[targetNodeId]?.running || false

    // Whether the source node has completed successfully:
    // 1. It has a value.
    // 2. It is no longer running.
    // 3. It has no associated validation errors.
    const isDone =
      executionState.nodes[sourceNodeId]?.value &&
      !executionState.nodes[sourceNodeId]?.running &&
      !validationErrors.some(e => e.involvedNodes.includes(sourceNodeId))

    // Whether the source node has encountered an error:
    // 1. Either during execution (runtime error),
    // 2. Or before execution (validation error).
    const isError =
      executionState.nodes[sourceNodeId]?.error || validationErrors.some(e => e.involvedNodes.includes(sourceNodeId))

    return isError ? 'ERROR' : isRunning ? 'PROCESSING' : isDone ? 'COMPLETED' : 'IDLE'
  })
}

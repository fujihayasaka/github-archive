import {usePipesStateLens} from '../contexts/PipesStateProvider'
import type {Pipeline, Node, NodeValue} from '../types/app'
import {getInputIds} from '../utils/pipes'
import type {PipesState} from './pipes-state'

export function currentPipeline(s: PipesState): Pipeline | undefined {
  let out: Pipeline | undefined = undefined

  if (s.pipelineState.selectedPipelineId) {
    out = s.pipelineState.pipelines[s.pipelineState.selectedPipelineId]
    if (out) return out
  }

  const [pipeline] = Object.values(s.pipelineState.pipelines)
  return pipeline
}

export function useNodeIDs() {
  const joined = usePipesStateLens(
    // Return a string so that we only re-render when the actual ids have changed
    s =>
      currentPipeline(s)
        ?.nodes?.map(n => n.id)
        ?.join('|'),
  )
  return joined?.split('|') ?? []
}

export const nodeDefinition = (nodeID: string) => (s: PipesState) => {
  const pipeline = currentPipeline(s)
  return pipeline?.nodes.find(n => n.id === nodeID)
}

export function useNodeContent(nodeId: string) {
  return usePipesStateLens(s => nodeDefinition(nodeId)(s)?.content ?? '')
}

export function useNodeType(nodeId: string) {
  return usePipesStateLens(s => nodeDefinition(nodeId)(s)?.type ?? 'text')
}

export function useNodeInputIds(nodeId: string): string[] {
  const joined = usePipesStateLens(s => {
    // Return a string so that we only re-render when the actual inputs have changed
    const node = nodeDefinition(nodeId)(s)
    if (!node) return ''
    return [...getInputIds(node)].sort().join('|')
  })
  return joined === '' ? [] : joined.split('|')
}

export function useHasValidationErrors(nodeId?: string): boolean {
  return usePipesStateLens(
    s => !!s.pipelineState.validationErrors.find(e => !nodeId || e.involvedNodes.includes(nodeId)),
  )
}

export function useValidationErrors(nodeId: string): string[] {
  const joined = usePipesStateLens(s =>
    // Return a string so that we only re-render when the actual inputs have changed
    s.pipelineState.validationErrors
      .filter(e => e.involvedNodes.includes(nodeId))
      .map(e => e.error)
      .join('|'),
  )
  return joined === '' ? [] : joined.split('|')
}

const nodeState = (nodeID: string) => (s: PipesState) => s.executionState.nodes[nodeID]

export function useCurrentPipeline(): Pipeline {
  const pipeline = usePipesStateLens(currentPipeline)
  if (!pipeline)
    throw new Error('useCurrentPipeline should only be used in a context where we are guaranteed to have a pipeline')
  return pipeline
}

export function useNode(nodeID: string): Node | undefined {
  return usePipesStateLens(nodeDefinition(nodeID))
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

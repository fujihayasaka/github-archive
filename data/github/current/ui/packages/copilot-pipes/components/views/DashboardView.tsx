import type {Node, TextNode} from '../../types/app'
import {getOutputNodes} from '../../utils/pipes'
import {NodeComponent} from '../nodes/NodeComponent'
import {usePipesStateLens} from '../../contexts/PipesStateProvider'
import {currentPipeline, useNodeProgress, useNodeRunning} from '../../state/lenses'

export function DashboardView() {
  const pipelineId = usePipesStateLens(s => s.pipelineState.selectedPipelineId)
  const isRunning = usePipesStateLens(s => Object.values(s.executionState.nodes).filter(n => n.running).length > 0)

  const totalProgress = usePipesStateLens(s => {
    const pipeline = currentPipeline(s)
    if (!pipeline) return 0
    const runningCount = Object.values(s.executionState.nodes).filter(n => n.running).length
    return Math.round((100 * runningCount) / pipeline.nodes.length)
  })

  const inputIds = usePipesStateLens(s => {
    const pipeline = currentPipeline(s)
    if (!pipeline) return []
    return pipeline.nodes.filter((node: Node) => (node as TextNode).inputType).map(n => n.id)
  })

  const firstOutputId = usePipesStateLens(s => {
    const pipeline = currentPipeline(s)
    if (!pipeline) return undefined
    return getOutputNodes(pipeline)[0]?.id
  })

  if (!pipelineId) return null

  return (
    <div className="relative w-full h-full flex mx-auto overflow-hidden min-w-0">
      {isRunning && (
        <div className="absolute top-0 left-0 right-0 h-1 bg-bgColor-inset">
          <div
            className="h-full bg-gradient-to-r from-bgColor-accent-emphasis to-bgColor-success-emphasis transition-all duration-300 ease-in-out"
            style={{width: `${totalProgress}%`, backgroundSize: '80vw'}}
          />
        </div>
      )}
      <div className="flex-none w-[20em] h-full p-6 overflow-auto flex flex-col gap-y-3">
        <h6 className="flex-none text-xs uppercase text-fg-muted tracking-widest">Inputs</h6>
        {inputIds.map(inputId => (
          <div className="flex-1 min-h-0" key={inputId}>
            <DashboardViewNode nodeId={inputId} pipelineId={pipelineId} />
          </div>
        ))}
      </div>
      <div className="flex-1 h-full min-w-0 p-6 pl-0 overflow-auto">
        {firstOutputId && <NodeComponent nodeId={firstOutputId} pipelineId={pipelineId} style="just-output" />}
      </div>
    </div>
  )
}

const DashboardViewNode = ({nodeId, pipelineId}: {nodeId: string; pipelineId: string; isOutput?: boolean}) => {
  const isRunning = useNodeRunning(nodeId)
  const progress = useNodeProgress(nodeId)

  return (
    <div className="relative h-full">
      {isRunning && (
        <div className="absolute top-0 left-0 right-0 h-1 bg-bgColor-inset rounded-full overflow-hidden">
          <div
            className="h-full bg-bgColor-accent-emphasis transition-all duration-300 ease-in-out animate-pulse"
            style={{width: `${progress}%`}}
          />
        </div>
      )}
      <NodeComponent key={nodeId} pipelineId={pipelineId} nodeId={nodeId} style="dashboard" />
    </div>
  )
}

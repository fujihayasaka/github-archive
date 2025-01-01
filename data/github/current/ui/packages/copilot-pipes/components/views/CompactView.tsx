import {useRef, useState} from 'react'
import {line, curveMonotoneY} from 'd3'
import {
  graphStratify,
  sugiyama,
  layeringSimplex,
  decrossTwoLayer,
  twolayerGreedy,
  twolayerAgg,
  tweakShape,
  shapeRect,
  type Graph,
} from 'd3-dag'

import styles from './CompactView.module.css'
import {NodeComponent} from '../nodes/NodeComponent'
import {getInputs} from '../../utils/pipes'
import {CompactStyleEdge} from '../nodes/compact/CompactStyleEdge'
import {usePipesStateLens} from '../../contexts/PipesStateProvider'
import {useCurrentPipeline, useNodeIDs} from '../../state/lenses'

export const getRawNodeIdFromInput = (input = '') => input.split('|')[0]

const gradientKeyframes = `
@keyframes flowAnimation {
  from {
    stroke-dashoffset: 100;
  }
  to {
    stroke-dashoffset: 0;
  }
}

@keyframes activeFlowAnimation {
  0% {
    stroke-dashoffset: 105%;
  }
  // add a bit delay
  60% {
    stroke-dashoffset: 5%;
  }
  100% {
    stroke-dashoffset: 5%;
  }
}
`
const gradientColor = '#1f6feb'
type NodeData = {id: string; parentIds: string[]}

export function CompactView() {
  const nodeIds = useNodeIDs()
  const pipelineId = usePipesStateLens(s => s.pipelineState.selectedPipelineId)
  const runningNodes = usePipesStateLens(s =>
    Object.fromEntries(Object.entries(s.executionState.nodes).map(([id, node]) => [id, node.running])),
  )
  const containerRef = useRef<HTMLDivElement>(null)

  const [selectedNodeId, setSelectedNodeId] = useState<string | null>(null)

  const handleNodeClick = (nodeId: string) => {
    setSelectedNodeId(nodeId === selectedNodeId ? null : nodeId)
  }

  const {layout, pipelineDimensions, edges} = usePipelineLayout()

  const selectedNodeOffset = getSelectedNodeOffset(
    pipelineDimensions,
    selectedNodeId ? layout[selectedNodeId] : undefined,
  )

  if (!pipelineId) return null

  return (
    <div className={styles.container} ref={containerRef}>
      <style>{gradientKeyframes}</style>
      <div className={styles.innerContainer}>
        {/* Nodes */}
        <div
          className={styles.nodesContainer}
          style={{
            height: pipelineDimensions.height,
            width: pipelineDimensions.width,
            transform: `translate(${selectedNodeOffset.x}px, ${selectedNodeOffset.y}px)`,
          }}
        >
          {nodeIds.map(nodeId => (
            <div
              key={nodeId}
              role="button"
              tabIndex={0}
              className={styles.nodeWrapper}
              style={{
                left: layout[nodeId]?.x ?? 0,
                top: layout[nodeId]?.y ?? 0,
              }}
              onClick={() => handleNodeClick(nodeId)}
              onKeyDown={e => {
                // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
                if (e.key === 'Enter' || e.key === ' ') {
                  handleNodeClick(nodeId)
                }
              }}
            >
              <NodeComponent
                key={nodeId}
                pipelineId={pipelineId}
                nodeId={nodeId}
                style="compact"
                isSelected={selectedNodeId === nodeId}
              />
            </div>
          ))}
        </div>

        {/* Edges */}
        {pipelineDimensions.width !== 0 && (
          <svg
            className={styles.edgeContainer}
            style={{
              height: pipelineDimensions.height,
              width: pipelineDimensions.width,
              transform: `translate(${selectedNodeOffset.x}px, ${selectedNodeOffset.y}px)`,
            }}
            role="presentation"
          >
            <defs>
              <linearGradient id="lineGradient" gradientUnits="userSpaceOnUse">
                <stop offset="0%" stopColor="currentColor" stopOpacity="0.4" />
                <stop offset="100%" stopColor="currentColor" stopOpacity="0.4" />
              </linearGradient>
              <linearGradient id="dotGradient" gradientUnits="userSpaceOnUse">
                <stop offset="0%" stopColor="currentColor" stopOpacity="0.8" />
                <stop offset="100%" stopColor="currentColor" stopOpacity="0.8" />
              </linearGradient>
              <linearGradient id="activeEdgeGradient" gradientUnits="userSpaceOnUse" x1="0%" y1="0%" x2="0%" y2="100%">
                <stop stopColor={gradientColor} stopOpacity="0.5" />
                <stop stopColor={gradientColor} />
                <stop offset="32.5%" stopColor={gradientColor} />
                <stop offset="100%" stopColor={gradientColor} stopOpacity="0.5" />
              </linearGradient>
            </defs>
            {edges.map(edge => {
              const processing = !!Object.entries(runningNodes).find(
                ([nodeId, isRunning]) => nodeId === edge.target && isRunning,
              )
              return (
                <CompactStyleEdge key={`${edge.source}-${edge.target}`} path={edge.path} isProcessing={processing} />
              )
            })}
          </svg>
        )}
      </div>
      {selectedNodeId && (
        <div
          className={styles.rightSidePanel}
          style={{
            maxWidth: selectedNodeId !== undefined ? '50%' : '0%',
            opacity: selectedNodeId !== undefined ? '1' : '0',
          }}
        >
          <NodeComponent
            key={selectedNodeId}
            pipelineId={pipelineId}
            nodeId={selectedNodeId}
            style="dashboard"
            isContentVisibleDefault={false}
          />
        </div>
      )}
    </div>
  )
}

interface CompactPipelineLayout {
  layout: Record<string, Point>
  edges: Edge[]
  pipelineDimensions: Dimensions
}

interface Dimensions {
  width: number
  height: number
}

interface Edge {
  points: Point[]
  path: string
  source: string
  target: string
}

interface Point {
  x: number
  y: number
}

function usePipelineLayout(): CompactPipelineLayout {
  const pipeline = useCurrentPipeline()

  const builder = graphStratify()
    .id((d: {id: string}) => d.id)
    .parentIds((d: NodeData) => d.parentIds)

  const dagData = pipeline.nodes.map(node => ({
    id: getRawNodeIdFromInput(node.id) || '',
    parentIds: [...getInputs(node)].map(input => getRawNodeIdFromInput(input) || '').filter(Boolean),
  }))

  const layout: Record<string, Point> = {}
  const edges: Edge[] = []

  try {
    const dag: Graph<NodeData, undefined> = builder(dagData)
    const nodeRadius: [number, number] = [30, 10]

    const D3layout = sugiyama()
      .nodeSize([200, 120])
      .layering(layeringSimplex())
      .decross(decrossTwoLayer().order(twolayerGreedy().base(twolayerAgg())))
      .gap(nodeRadius)
      .tweaks([tweakShape([nodeRadius[0], nodeRadius[1]], shapeRect)])

    const {width, height} = D3layout(dag as Graph<never, never>)
    const pipelineDimensions = {width, height}

    for (const node of dag.nodes()) {
      if (node.data.id) {
        layout[node.data.id] = {
          x: node.x,
          y: node.y,
        }
      }
    }

    for (const {points, source, target} of dag.links()) {
      const path = line().curve(curveMonotoneY)(points) || ''
      edges.push({
        path,
        points: points.map(([x, y]) => ({x, y})),
        source: source.data.id || '',
        target: target.data.id || '',
      })
    }

    return {layout, edges, pipelineDimensions}
  } catch {
    return getDefaultLayout(pipeline.nodes.map(n => n.id))
  }
}

const roughNodeDimensions = {width: 300, height: 50}

function getDefaultLayout(nodeIDs: string[]): CompactPipelineLayout {
  const layout: Record<string, Point> = {}
  const edges: Edge[] = []
  const pipelineDimensions = {width: roughNodeDimensions.width, height: nodeIDs.length * roughNodeDimensions.height}

  for (let i = 0; i < nodeIDs.length; ++i) {
    // eslint-disable-next-line @typescript-eslint/no-non-null-assertion
    const nodeId = nodeIDs[i]!
    layout[nodeId] = {
      x: roughNodeDimensions.width / 2,
      y: i * roughNodeDimensions.height,
    }
  }

  return {layout, edges, pipelineDimensions}
}

function getSelectedNodeOffset(pipelineDimensions: Dimensions, nodeLocation: Point | undefined): Point {
  if (!nodeLocation) return {x: 0, y: 0}

  const offsetX = pipelineDimensions.width / 2 - nodeLocation.x
  const offsetY = pipelineDimensions.height / 2 - nodeLocation.y
  return {x: offsetX, y: offsetY}
}

import {useRef, useState, useEffect, useCallback} from 'react'
import {select, zoom, zoomIdentity, interpolate, easeQuadInOut} from 'd3'
import {
  decrossTwoLayer,
  graphStratify,
  layeringSimplex,
  sugiyama,
  twolayerAgg,
  twolayerGreedy,
  type Graph,
} from 'd3-dag'
import {sendEvent} from '@github-ui/hydro-analytics'

import styles from './Canvas.module.css'
import {getInputIds, getPipelineGraph} from '../utils/pipes'
import {usePipesDispatch, usePipesStateLens} from '../contexts/PipesStateProvider'

import {CompactStyleEdge} from './nodes/compact/CompactStyleEdge'
import {CanvasHeader} from './CanvasHeader'
import {CompactNode} from './nodes/compact/CompactNode'
import {useCurrentLoop} from '../hooks/use-current-loop'
import {useNodeIDs} from '../state/lenses'

const gradientColor = '#1f6feb'
type NodeData = {id: string; parentIds: string[]}

export function Canvas() {
  const nodeIds = useNodeIDs()
  const loop = useCurrentLoop()
  const graph = getPipelineGraph(loop)
  const [nodeCanvas, setNodeCanvas] = useState<HTMLDivElement | null>(null)
  const [flying, setFlying] = useState(false)
  const isFirstLoad = useRef(true)
  const dispatch = usePipesDispatch()

  const selectedNodeId = usePipesStateLens(s => s.uiState.focusedNodeId)
  const handleNodeClick = (nodeId: string) => {
    const isDeselecting = nodeId === selectedNodeId
    dispatch({type: 'FOCUS_NODE', nodeId: isDeselecting ? null : nodeId})

    sendEvent('dotcom_chat.activate', {
      target: isDeselecting ? 'CANVAS_NODE_DESELECT' : 'CANVAS_NODE_SELECT',
      mode: 'loops',
    })
  }

  const {layout, pipelineDimensions, edges} = usePipelineLayout()

  // Store zoom behavior in a ref so we can use it later.
  const zoomBehaviorRef = useRef<d3.ZoomBehavior<HTMLDivElement, unknown> | null>(null)

  const clearSelectedNode = () => {
    if (selectedNodeId) {
      sendEvent('dotcom_chat.activate', {target: 'CANVAS_DESELECT', mode: 'loops'})
    }
    dispatch({type: 'FOCUS_NODE', nodeId: null})
  }

  const centerNodeCanvas = useCallback(
    ({duration = 500}: {duration?: number}) => {
      if (!nodeCanvas || !zoomBehaviorRef.current) return

      // Fit the diagram into view
      const containerRect = nodeCanvas.getBoundingClientRect()
      const containerWidth = containerRect.width
      const containerHeight = containerRect.height

      // we need to manually calculate:
      // 1. the width and height of the nodes-overlay by check the max x and y of the nodes, plus
      // 2. half size of the node (width and height),
      const diagramWidth = Math.max(...Object.values(layout).map(node => node.x)) + 100
      const diagramHeight = Math.max(...Object.values(layout).map(node => node.y)) + 25
      const translateX = containerWidth / 2 - diagramWidth / 2
      const translateY = containerHeight / 2 - diagramHeight / 2

      const fitTransform = zoomIdentity.translate(translateX, translateY).scale(1)
      select(nodeCanvas)
        .transition()
        .duration(duration)
        .ease(easeQuadInOut)
        .call(zoomBehaviorRef.current.transform, fitTransform)
    },
    // eslint-disable-next-line react-hooks/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [nodeCanvas],
  )

  // Callback ref: This function is called when the nodeCanvas mounts.
  const handleNodeCanvasRef = useCallback(
    (node: HTMLDivElement | null) => {
      if (node) {
        setNodeCanvas(node)
        const nodeCanvasSelection = select(node)

        const updateGrid = (zoomEvent: d3.D3ZoomEvent<HTMLDivElement, unknown>) => {
          select('#dot-pattern')
            .attr('x', zoomEvent.transform.x)
            .attr('y', zoomEvent.transform.y)
            .attr('width', 25 * zoomEvent.transform.k)
            .attr('height', 25 * zoomEvent.transform.k)
            .select('rect')
            .attr('x', (25 * zoomEvent.transform.k) / 2 - 2 / 2)
            .attr('y', (25 * zoomEvent.transform.k) / 2 - 2 / 2)
            .attr('opacity', Math.min(zoomEvent.transform.k, 1))
        }

        const PAN_THRESHOLD = 5
        let initialTransform: d3.ZoomTransform | null = null
        let hasMovedEnough = false

        const zoomBehavior = zoom<HTMLDivElement, unknown>()
          .scaleExtent([1, 1])
          .interpolate(interpolate)
          .on('start', event => {
            initialTransform = event.transform
            hasMovedEnough = false
          })
          .on('zoom', event => {
            if (!initialTransform) return
            const dx = event.transform.x - initialTransform.x
            const dy = event.transform.y - initialTransform.y
            const dist = Math.sqrt(dx * dx + dy * dy)
            if (!hasMovedEnough && dist < PAN_THRESHOLD) {
              return
            }

            hasMovedEnough = true

            // Now apply the transform
            select('#edges-group').attr('transform', event.transform)
            select('#nodes-overlay')
              .style('transform-origin', '0 0')
              .style(
                'transform',
                `translate(${event.transform.x}px, ${event.transform.y}px) scale(${event.transform.k})`,
              )
            updateGrid(event)
          })

        zoomBehaviorRef.current = zoomBehavior
        nodeCanvasSelection.call(zoomBehavior)
        centerNodeCanvas({
          duration: 0,
        })
      }
    },
    [centerNodeCanvas],
  )

  // When a node is selected, smoothly fly to it.
  useEffect(() => {
    if (flying) return
    if (!selectedNodeId) return
    if (!nodeCanvas || !zoomBehaviorRef.current) return

    const nodePos = layout[selectedNodeId]
    if (!nodePos) return

    setFlying(true)

    const containerRect = nodeCanvas.getBoundingClientRect()
    const containerWidth = containerRect.width
    const containerHeight = containerRect.height

    // Center the node in the container.
    const translateX = containerWidth / 2 - nodePos.x
    const translateY = containerHeight / 2 - nodePos.y
    const newTransform = zoomIdentity.translate(translateX, translateY).scale(1)

    if (isFirstLoad.current === true) {
      select(nodeCanvas).call(zoomBehaviorRef.current.transform, newTransform)
      isFirstLoad.current = false
    } else {
      select(nodeCanvas)
        .transition()
        .duration(500)
        .ease(easeQuadInOut)
        .call(zoomBehaviorRef.current.transform, newTransform)
    }
    setFlying(false)
    // eslint-disable-next-line react-hooks/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [selectedNodeId, flying, nodeCanvas])

  return (
    <>
      <CanvasHeader centerNodeCanvas={centerNodeCanvas} />
      <div className={styles.canvasContainer} ref={handleNodeCanvasRef}>
        {/* background functions as a light popover dismiss */}
        {/* eslint-disable-next-line jsx-a11y/no-static-element-interactions */}
        <div
          className={styles.canvasGraph}
          onClick={clearSelectedNode}
          onKeyDown={e => {
            // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
            if (e.key === 'Enter' || e.key === ' ') {
              e.preventDefault()
              clearSelectedNode()
            }
          }}
        >
          <svg aria-label="Diagram" className={styles.diagram}>
            <defs>
              {/* The pattern for grid background */}
              <pattern id="dot-pattern" patternUnits="userSpaceOnUse" x="0" y="0" width={25} height={25}>
                <rect
                  x={25 / 2 - 2 / 2}
                  y={25 / 2 - 2 / 2}
                  rx="50%"
                  ry="50%"
                  width={2}
                  height={2}
                  className={styles.gridPattern}
                />
              </pattern>

              {/* Gradients for edges */}
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

            {/* Grid Background */}
            <rect fill="url(#dot-pattern)" width="100%" height="100%" />

            {/* Edges Group */}
            {pipelineDimensions.width !== 0 && (
              <g id="edges-group">
                {edges.map(edge => {
                  return (
                    <CompactStyleEdge
                      key={`${edge.source}-${edge.target}`}
                      path={edge.path}
                      source={edge.source}
                      target={edge.target}
                    />
                  )
                })}
              </g>
            )}
          </svg>

          <div id="nodes-overlay" className={styles.nodesOverlay}>
            {nodeIds.map(nodeId => (
              <div
                key={nodeId}
                role="button"
                tabIndex={0}
                className={styles.nodeWrapper}
                style={{
                  left: (layout[nodeId]?.x ?? 0) - 100,
                  top: (layout[nodeId]?.y ?? 0) - 25,
                }}
                onClick={e => {
                  // prevent the click event from bubbling up to the parent div handler
                  e.stopPropagation()
                  handleNodeClick(nodeId)
                }}
                onKeyDown={e => {
                  // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
                  if (e.key === 'Enter' || e.key === ' ') {
                    e.stopPropagation()
                    handleNodeClick(nodeId)
                  }
                }}
              >
                <CompactNode
                  pipelineId={loop.id}
                  nodeId={nodeId}
                  hasPredecessors={graph.edges.some(e => e.to === nodeId)}
                  hasSuccessors={graph.edges.some(e => e.from === nodeId)}
                />
              </div>
            ))}
          </div>
        </div>
      </div>
    </>
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
  const loop = useCurrentLoop()

  const builder = graphStratify()
    .id((d: {id: string}) => d.id)
    .parentIds((d: NodeData) => d.parentIds)

  const nodeIds = new Set(loop.nodes.map(node => node.id))
  const dagData = loop.nodes.map(node => ({
    id: node.id,
    parentIds: Array.from(getInputIds(node)).map(nodeId => {
      if (!nodeIds.has(nodeId)) return ''

      return nodeId
    }),
  }))

  const layout: Record<string, Point> = {}
  const edges: Edge[] = []

  try {
    const dag: Graph<NodeData, undefined> = builder(dagData)
    const nodeRadius: [number, number] = [10, 10]

    const D3layout = sugiyama()
      .nodeSize([250, 120])
      .layering(layeringSimplex())
      .decross(decrossTwoLayer().order(twolayerGreedy().base(twolayerAgg())))
      .gap(nodeRadius)

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

    const generateRoundedVerticalPath = (points: Array<[number, number]>): string => {
      if (points.length < 2) return ''

      const [startX, startY] = points[0] || [0, 0]
      const lastPoint = points[points.length - 1]
      const [endX, endY] = lastPoint ? lastPoint : [0, 0]

      const deltaX = endX - startX
      const absDeltaX = Math.abs(deltaX)
      const isStraight = absDeltaX < 10

      if (isStraight) {
        return `M ${startX},${startY} L ${endX},${endY}`
      }

      const cornerRadius = 12
      const verticalSplit = (startY + endY) / 2

      const verticalDown = verticalSplit - cornerRadius
      const verticalUp = verticalSplit + cornerRadius

      const directionX = deltaX > 0 ? 1 : -1
      const horizontalLength = absDeltaX - cornerRadius * 2

      return `
        M ${startX},${startY}
        L ${startX},${verticalDown}
        A ${cornerRadius},${cornerRadius} 0 0 ${directionX > 0 ? 0 : 1} ${
          startX + directionX * cornerRadius
        },${verticalSplit}
        L ${startX + directionX * (cornerRadius + horizontalLength)},${verticalSplit}
        A ${cornerRadius},${cornerRadius} 0 0 ${directionX > 0 ? 1 : 0} ${endX},${verticalUp}
        L ${endX},${endY}
      `
        .trim()
        .replace(/\s+/g, ' ')
    }

    for (const {points, source, target} of dag.links()) {
      const path = generateRoundedVerticalPath(points)
      edges.push({
        path,
        points: points.map(([x, y]) => ({x, y})),
        source: source.data.id || '',
        target: target.data.id || '',
      })
    }

    return {layout, edges, pipelineDimensions}
  } catch {
    return getDefaultLayout(loop.nodes.map(n => n.id))
  }
}

const roughNodeDimensions = {width: 200, height: 100}

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

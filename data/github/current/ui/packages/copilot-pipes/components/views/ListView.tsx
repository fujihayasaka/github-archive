import {memo, useState, useMemo} from 'react'
import type {Node} from '../../types/app'
import {getInputs, getOutputNodes} from '../../utils/pipes'
import {ListStyle} from '../ListStyle'
import {NodeComponent} from '../nodes/NodeComponent'
import {useCurrentPipeline, useNodeRunning} from '../../state/lenses'

const getNodeDepths = (nodes: Node[]) => {
  const depths = new Map<string, number>()

  const calculateDepth = (nodeId: string, currentDepth: number, visited = new Set<string>()) => {
    if (visited.has(nodeId)) return
    visited.add(nodeId)

    const currentMaxDepth = depths.get(nodeId) || 0
    depths.set(nodeId, Math.max(currentMaxDepth, currentDepth))

    const node = nodes.find(n => n.id === nodeId)
    if (node && 'inputs' in node && node.inputs) {
      for (const input of getInputs(node)) {
        calculateDepth(input, currentDepth + 1, new Set(visited))
      }
    }
  }

  // Start from nodes that aren't inputs to any other node
  const outputNodes = nodes.filter(
    node =>
      !nodes.some(n => {
        const inputs = getInputs(n)
        return [...inputs].some(input => input === node.id)
      }),
  )

  for (const node of outputNodes) {
    calculateDepth(node.id, 0)
  }

  return depths
}

const buildNodeHierarchy = (nodes: Node[]) => {
  const nodeDepths = getNodeDepths(nodes)
  const nodeMap = new Map<string, string[]>()

  // Group nodes by their parents, but only if the parent is at a shallower depth
  for (const node of nodes) {
    if ('inputs' in node && node.inputs) {
      const nodeDepth = nodeDepths.get(node.id) || 0
      const inputNodes = [...getInputs(node)]
        .map(input => {
          const inputNode = nodes.find(n => n.id === input)
          const inputDepth = nodeDepths.get(input) || 0
          // Only include input if this is its deepest usage
          return inputNode && inputDepth === nodeDepth + 1 ? inputNode : undefined
        })
        .filter((n): n is Node => n !== undefined)
        .map(n => n.id)

      if (inputNodes.length > 0) {
        nodeMap.set(node.id, inputNodes)
      }
    }
  }

  return nodeMap
}

const getRootNodes = (nodes: Node[], nodeMap: Map<string, string[]>) => {
  // Get all nodes that are used as inputs
  const allInputNodes = Array.from(nodeMap.values()).flat()
  // Root nodes are those that either:
  // 1. Aren't inputs to any other node, or
  // 2. Are used as inputs but at a shallower depth than their deepest usage
  return nodes.filter(node => !allInputNodes.includes(node.id)).map(n => n.id)
}

const findPathToRoot = (nodeId: string, nodes: Node[]): Set<string> => {
  const path = new Set<string>()

  const traverse = (currentId: string, visited = new Set<string>()) => {
    if (visited.has(currentId)) return
    visited.add(currentId)
    path.add(currentId)

    // Find all nodes that have this node as an input
    for (const node of nodes) {
      const inputs = getInputs(node)
      if ('inputs' in node && [...inputs].some(input => input === currentId)) {
        traverse(node.id, visited)
      }
    }
  }

  traverse(nodeId)
  return path
}

interface NodeTreeItemProps {
  nodeId: string
  depth?: number
  nodeMap: Map<string, string[]>
  focusedNodeId: string | null
  highlightedNodes: Set<string>
  onNodeClick: (nodeId: string) => void
  pipelineId: string
}

const NodeTreeItem = memo(function NodeTreeItem({
  nodeId,
  depth = 0,
  nodeMap,
  focusedNodeId,
  highlightedNodes,
  onNodeClick,
  pipelineId,
}: NodeTreeItemProps) {
  const inputNodes = nodeMap.get(nodeId) || []
  const isRunning = useNodeRunning(nodeId)

  const isHighlighted = highlightedNodes.has(nodeId)

  return (
    <>
      <ListStyle
        key={nodeId}
        nodeId={nodeId}
        depth={depth}
        isLoading={isRunning}
        isSelected={focusedNodeId === nodeId}
        isHighlighted={isHighlighted}
        onClick={() => onNodeClick(nodeId)}
      />
      {inputNodes.map(inputNode => (
        <NodeTreeItem
          key={inputNode}
          nodeId={inputNode}
          depth={depth + 1}
          nodeMap={nodeMap}
          focusedNodeId={focusedNodeId}
          highlightedNodes={highlightedNodes}
          onNodeClick={onNodeClick}
          pipelineId={pipelineId}
        />
      ))}
    </>
  )
})

export function ListView() {
  const pipeline = useCurrentPipeline()
  const output = getOutputNodes(pipeline)
  const [focusedNodeId, setFocusedNodeId] = useState<string | null>(output[0]?.id || null)
  const highlightedNodes = useMemo(
    () => (focusedNodeId ? findPathToRoot(focusedNodeId, pipeline.nodes) : new Set<string>()),
    [focusedNodeId, pipeline.nodes],
  )

  const hierarchy = useMemo(() => {
    const nodeMap = buildNodeHierarchy(pipeline.nodes)
    const rootNodes = getRootNodes(pipeline.nodes, nodeMap)
    return {nodeMap, rootNodes}
  }, [pipeline.nodes])

  return (
    <div className="relative w-full h-full flex mx-auto overflow-hidden min-w-0">
      <div className="flex-none w-[20em] h-full p-6 overflow-auto">
        <h6 className="text-xs uppercase text-fg-muted tracking-widest mb-4">Nodes</h6>
        {hierarchy.rootNodes.map(nodeId => (
          <NodeTreeItem
            key={nodeId}
            nodeId={nodeId}
            nodeMap={hierarchy.nodeMap}
            focusedNodeId={focusedNodeId}
            highlightedNodes={highlightedNodes}
            onNodeClick={setFocusedNodeId}
            pipelineId={pipeline.id}
          />
        ))}
      </div>
      <div className="flex-1 h-full p-6 overflow-auto">
        {focusedNodeId && <NodeComponent pipelineId={pipeline.id} nodeId={focusedNodeId} style="dashboard" />}
      </div>
    </div>
  )
}

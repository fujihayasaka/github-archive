import type {Node, Pipeline, PipelineGraph, PipelineInputValue, TextNode} from '../types/app'
import {isPipelineNode, isTextNode} from './node-assertions'
import {logError, logWarning} from './console'
import type {Dispatch} from 'react'
import type {PipesAction} from '../state/pipes-action'

export type IsRunningCallback = (nodeId: string, isRunning: boolean) => void
export type ResultsCallback = (results: Map<string, string>) => void

export const getPipelineGraph = (pipeline: Pipeline): PipelineGraph => {
  const graph: PipelineGraph = {
    nodes: new Map<string, Node>(),
    edges: [],
    layers: [],
  }
  if (!pipeline.nodes) return graph

  // Add all nodes to the graph
  for (const node of pipeline.nodes) {
    if (!node?.id) continue
    const id = node.id.split('|')[0] ?? node.id
    graph.nodes.set(id, node)
  }

  // Create edges from inputs
  for (const node of pipeline.nodes) {
    for (const input of getInputs(node)) {
      const id = getInputId(input)
      if (!node?.id || !id) continue
      graph.edges.push({
        from: id,
        to: node.id,
      })
    }
  }

  const layers = getLayers(graph)
  graph.layers = layers

  return graph
}

export function getInputs(node: Node): Set<string> {
  const variableMatches = node.content.match(/{{([\w-]+)(?:\|([\w-]+))?}}/g) || []
  return new Set(variableMatches.map(match => match.replace(/[{}]/g, '')))
}

export function getInputIds(node: Node): Set<string> {
  return new Set([...getInputs(node)].map(getInputId))
}

function getInputId(input: string) {
  // eslint-disable-next-line @typescript-eslint/no-non-null-assertion
  return input.split('|')[0]!
}

export function clearDownstreamNodes(pipeline: Pipeline, nodeId: string, dispatch: Dispatch<PipesAction>) {
  const graph = getPipelineGraph(pipeline)
  const downstream = getDownstreamNodes(graph, nodeId)
  dispatch({type: 'CLEAR_NODE_RESULTS', pipelineId: pipeline.id, nodeIds: [...downstream]})
}

function getDownstreamNodes(graph: PipelineGraph, nodeId: string): Set<string> {
  const downstream = new Set(graph.edges.filter(e => e.from === nodeId).map(e => e.to))
  for (const n of downstream) {
    for (const node of getDownstreamNodes(graph, n)) {
      downstream.add(node)
    }
  }
  downstream.add(nodeId)
  return downstream
}

function getLayers(graph: PipelineGraph): Node[][] {
  const nodeLayers: Record<string, number> = {}
  const maxRecursionDepth = 100
  const nodeStack = new Set<string>()

  const computeNodeLayer = (nodeId: string, depth = 0): number => {
    try {
      if (nodeStack.has(nodeId)) {
        throw new Error(`Potential cycle detected at node ${nodeId}`)
      }
      nodeStack.add(nodeId)

      // Guard against infinite recursion
      if (depth > maxRecursionDepth) {
        logWarning(`Maximum recursion depth reached for node ${nodeId}`)
        return 0
      }

      // Return cached result if available
      if (nodeLayers[nodeId] !== undefined) {
        return nodeLayers[nodeId]
      }

      const node = graph.nodes.get(nodeId)
      if (!node) {
        nodeLayers[nodeId] = 0
        return 0
      }

      const nodeInputs = getInputs(node)
      if (!nodeInputs || nodeInputs.size === 0) {
        const outputs = graph.edges.filter(e => e.from === nodeId).map(e => e.to)
        if (outputs.length === 0) {
          nodeLayers[nodeId] = -1
        } else {
          nodeLayers[nodeId] = 1
        }
      } else {
        // Compute the layer as one more than the max layer among inputs
        const inputLayers = [...nodeInputs].map(input => {
          const inputId = input.split('|')[0] ?? input
          return computeNodeLayer(inputId, depth + 1)
        })
        nodeLayers[nodeId] = Math.max(...inputLayers) + 1
      }

      return nodeLayers[nodeId]
    } finally {
      nodeStack.delete(nodeId) // Always clean up the stack
    }
  }

  // Compute layers for all nodes
  for (const [nodeId] of graph.nodes) {
    if (!nodeLayers[nodeId]) {
      try {
        computeNodeLayer(nodeId)
      } catch (e) {
        logError(`Error computing layer for node ${nodeId}:`, e)
        nodeLayers[nodeId] = 0
      }
    }
  }

  // Reassign MAX to the last layer
  const maxLayer = Math.max(...Object.values(nodeLayers)) + 1
  for (const nodeId of Object.keys(nodeLayers)) {
    if (nodeLayers[nodeId] === -1) {
      nodeLayers[nodeId] = maxLayer
    }
  }

  // Build the layers array
  const layers: Node[][] = []
  for (const [nodeId, layer] of Object.entries(nodeLayers)) {
    const node = graph.nodes.get(nodeId)
    if (node) {
      if (!layers[layer]) {
        layers[layer] = []
      }
      layers[layer].push(node)
    }
  }

  return layers.filter(Boolean)
}

type RemovableNode = Node & {doRemove?: boolean}

export const sanitizeNode = (node: RemovableNode, pipelines: Pipeline[]): Node | null => {
  if (!node || typeof node !== 'object' || node?.doRemove) {
    return null
  }

  if (!node.title && !node.description && !node.content) {
    return null
  }

  const sanitizedNode = {
    ...node,
    title: node.title || '',
    description: node.description || '',
    type: (node.type || 'prompt').trim(),
    inputType: (node as TextNode).inputType || undefined,
    content: node.content || '',
    id: (node.id || '').trim(),
    doRemove: node.doRemove ?? false,
  } as RemovableNode

  if (typeof sanitizedNode.content !== 'string') {
    sanitizedNode.content = ''
  }
  if (isPipelineNode(sanitizedNode)) {
    const selectedPipe = pipelines.find(pipe => pipe.id === sanitizedNode.pipelineId)
    if (selectedPipe) {
      const inputValueNodeIdMap =
        sanitizedNode.pipelineInputValues?.reduce(
          (result: {[key: string]: PipelineInputValue}, input: PipelineInputValue) => {
            result[input.inputId] = input
            return result
          },
          {},
        ) || {}

      sanitizedNode.pipelineInputValues = selectedPipe.nodes
        ?.filter(n => isTextNode(n))
        .map(textNode => {
          const input = inputValueNodeIdMap[textNode.id]
          if (!input) throw new Error(`Input not found for node ${textNode.id}`)

          return {
            inputId: textNode.id,
            nodeId: input.nodeId,
            doMapInput: !!input.doMapInput,
          }
        })
    }
  }

  return sanitizedNode
}

export const sanitizePipeline = (pipeline: Pipeline, pipelines: Pipeline[]): Pipeline => {
  const sanitizedPipeline = {
    ...pipeline,
    nodes: (pipeline.nodes || [])
      .map((node: Node) => sanitizeNode(node, pipelines))
      .filter((node): node is Node => node !== null),
  }
  return sanitizedPipeline
}

export function getOutputNodes(pipeline: Pipeline): Node[] {
  const graph = getPipelineGraph(pipeline)
  return pipeline.nodes.filter(n => isOutputNode(n, graph))
}

/**
 * A node is an output node if it has predecessors but no successors
 */
function isOutputNode(node: Node, graph: PipelineGraph): boolean {
  return !graph.edges.some(e => e.from === node.id) && graph.edges.some(e => e.to === node.id)
}

import type {Pipeline, PipelineGraph, Node, TextNode, PipelineValidationError} from '../types/app'
import {getPipelineGraph} from '../utils/pipes'

export function validatePipeline(pipeline: Pipeline): PipelineValidationError[] {
  const errors: PipelineValidationError[] = validatePipelineProperties(pipeline)

  const graph = getPipelineGraph(pipeline)

  for (const edge of graph.edges) {
    const fromNode = pipeline.nodes.find(n => n.id === edge.from)
    const toNode = pipeline.nodes.find(n => n.id === edge.to)
    if (!fromNode || !toNode) {
      errors.push({
        error: `Node ${edge.to} references a nonexistent node {{${edge.from}}}`,
        involvedNodes: [edge.to],
      })
    }
  }

  const cycle = findCycle(graph)
  if (cycle && cycle.length > 0) {
    // Add the first element to the end to make the cycle in the error message clearer
    // eslint-disable-next-line @typescript-eslint/no-non-null-assertion
    const cycleList = [...cycle, cycle[0]!]
    errors.push({error: `Pipeline contains a cycle: ${cycleList.join(' → ')}`, involvedNodes: cycle})
  }

  const disconnected = findDisconnectedNodes(graph)
  if (disconnected.length > 0) {
    errors.push({
      error: `Pipeline contains unreachable nodes: ${disconnected.join(', ')}`,
      involvedNodes: disconnected,
    })
  }
  return errors
}

function findCycle(graph: PipelineGraph): string[] | null {
  const visited = new Set<string>()
  const stack = new Set<string>()
  const path: string[] = []

  // Helper function to perform DFS
  const dfs = (nodeId: string): string[] | null => {
    if (stack.has(nodeId)) {
      // Found a cycle, extract the cycle path
      const cycleStartIndex = path.indexOf(nodeId)
      return path.slice(cycleStartIndex)
    }
    if (visited.has(nodeId)) {
      return null
    }

    // Mark the current node as visited and add it to the recursion stack and path
    visited.add(nodeId)
    stack.add(nodeId)
    path.push(nodeId)

    // Recur for all the vertices adjacent to this vertex
    for (const edge of graph.edges) {
      if (edge.from === nodeId) {
        const cyclePath = dfs(edge.to)
        if (cyclePath) {
          return cyclePath
        }
      }
    }

    // Remove the current node from the recursion stack and path
    stack.delete(nodeId)
    path.pop()
    return null
  }

  // Call the helper function to detect cycle in different DFS trees
  for (const node of graph.nodes.values()) {
    if (!visited.has(node.id)) {
      const cyclePath = dfs(node.id)
      if (cyclePath) {
        return cyclePath
      }
    }
  }

  return null
}

function findDisconnectedNodes(graph: PipelineGraph): string[] {
  const nodes = [...graph.nodes.values()]
  if (nodes.length === 0) {
    return []
  }

  const visited = new Set<string>()

  // Helper function to perform DFS
  const dfs = (nodeId: string) => {
    visited.add(nodeId)
    for (const edge of graph.edges) {
      if (edge.from === nodeId && !visited.has(edge.to)) {
        dfs(edge.to)
      }
      if (edge.to === nodeId && !visited.has(edge.from)) {
        dfs(edge.from)
      }
    }
  }

  // Start DFS from the first node
  // eslint-disable-next-line @typescript-eslint/no-non-null-assertion
  dfs(nodes[0]!.id)

  // Collect all nodes that are not visited
  const disconnectedNodes = nodes.filter(node => !visited.has(node.id)).map(node => node.id)

  return disconnectedNodes
}

function validatePipelineProperties(pipeline: Pipeline): PipelineValidationError[] {
  let errors: PipelineValidationError[] = []
  if (typeof pipeline.title !== 'string') {
    errors.push({error: `Pipeline is missing a title`, involvedNodes: []})
  }
  if (!Array.isArray(pipeline.nodes) || pipeline.nodes.length === 0) {
    errors.push({error: `Pipeline has no nodes`, involvedNodes: []})
  }
  for (const node of pipeline.nodes) {
    errors = errors.concat(validateNodeProperties(node))
  }
  return errors
}

function validateNodeProperties(node: Node): PipelineValidationError[] {
  let errors: PipelineValidationError[] = []
  if (typeof node.title !== 'string' || node.title.length === 0) {
    errors.push({error: `Node is missing a title`, involvedNodes: [node.id]})
  }

  switch (node.type) {
    case 'text':
      errors = errors.concat(validateTextNodeProperties(node))
  }
  return errors
}

function validateTextNodeProperties(node: TextNode): PipelineValidationError[] {
  const errors: PipelineValidationError[] = []
  const input = node.inputType
  if (typeof input !== 'object' || !input) {
    errors.push({error: `inputType is required for text nodes`, involvedNodes: [node.id]})
  }
  switch (input.type) {
    case 'boolean':
      if (!['true', 'false'].includes(node.content)) {
        errors.push({error: `A boolean input must have a value of either "true" or "false"`, involvedNodes: [node.id]})
      }
      break
    case 'range':
      if (typeof input.min !== 'number') {
        errors.push({error: `A range input must have a min`, involvedNodes: [node.id]})
      }
      if (typeof input.max !== 'number') {
        errors.push({error: `A range input must have a max`, involvedNodes: [node.id]})
      }
      break
    case 'select':
      if (!Array.isArray(input.options) || input.options.length === 0) {
        errors.push({error: `A select input must have options`, involvedNodes: [node.id]})
      } else if (!input.options.includes(node.content)) {
        errors.push({error: `A select node must have content equal to one of its options`, involvedNodes: [node.id]})
      }
      break
    case 'file':
      if (!['pdf', 'video', 'image', 'audio', 'document', 'code', 'other'].includes(input.fileType)) {
        errors.push({error: `Invalid file type ${input.fileType}`, involvedNodes: [node.id]})
      }
      break
    case 'text':
      break
  }
  return errors
}

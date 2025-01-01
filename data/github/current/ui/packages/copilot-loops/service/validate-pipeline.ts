import type {Pipeline, PipelineGraph, Node, TextNode, PipelineValidationError} from '../types/app'
import {pipelineErrorType} from '../types/app'
import {inputTypeInfo} from '../types/input-types'
import {getPipelineGraph} from '../utils/pipes'
import {nodeHandlerRegistry} from './node-handler-registry'

/**
 * Type guard that validates if an unknown object conforms to the Pipeline type structure
 * @param obj - The object to validate
 * @returns A type predicate indicating if the object is a Pipeline
 */
export function validatePipelineObject(obj: unknown): obj is Pipeline {
  if (!obj || typeof obj !== 'object') {
    return false
  }

  const pipeline = obj as Partial<Pipeline>

  // Check if the object has the required Pipeline properties
  if (
    !('title' in pipeline) ||
    typeof pipeline.title !== 'string' ||
    !('nodes' in pipeline) ||
    !Array.isArray(pipeline.nodes)
  ) {
    return false
  }

  const validNodeTypes = nodeHandlerRegistry.getAllNodeTypes()
  const validInputTypes = Object.keys(inputTypeInfo)

  // Check that each node has required properties
  for (const node of pipeline.nodes || []) {
    if (!node || typeof node !== 'object') {
      return false
    }

    if (!('id' in node) || typeof node.id !== 'string') {
      return false
    }

    if (!('type' in node) || typeof node.type !== 'string' || !validNodeTypes.includes(node.type)) {
      return false
    }

    if (!('title' in node) || typeof node.title !== 'string') {
      return false
    }

    if (!('content' in node) || typeof node.content !== 'string') {
      return false
    }

    if (node.type === 'text') {
      if (!('inputType' in node) || typeof node.inputType !== 'object' || node.inputType === null) {
        return false
      }

      const inputType = node.inputType as {type?: string}

      if (!('type' in inputType) || typeof inputType.type !== 'string') {
        return false
      }

      if (!validInputTypes.includes(inputType.type)) {
        return false
      }

      switch (inputType.type) {
        case 'range': {
          const rangeInput = inputType as {min?: number; max?: number}
          if (typeof rangeInput.min !== 'number' || typeof rangeInput.max !== 'number') {
            return false
          }
          break
        }

        case 'select': {
          const selectInput = inputType as {options?: string[]}
          if (!Array.isArray(selectInput.options) || selectInput.options.length === 0) {
            return false
          }
          break
        }

        case 'file': {
          const fileInput = inputType as {fileType?: string}
          if (typeof fileInput.fileType !== 'string') {
            return false
          }
          break
        }
      }
    }
  }

  return true
}

export function validatePipeline(pipeline: Pipeline): PipelineValidationError[] {
  const errors: PipelineValidationError[] = validatePipelineProperties(pipeline)

  const graph = getPipelineGraph(pipeline)

  for (const edge of graph.edges) {
    const fromNode = pipeline.nodes.find(n => n.id === edge.from)
    const toNode = pipeline.nodes.find(n => n.id === edge.to)
    if (!fromNode || !toNode) {
      errors.push({
        error: `Node ${edge.to} references a nonexistent node {{${edge.from}}}`,
        errorType: pipelineErrorType.NonexistentNode,
        involvedNodes: [edge.to],
      })
    }
  }

  const cycle = findCycle(graph)
  if (cycle && cycle.length > 0) {
    // Add the first element to the end to make the cycle in the error message clearer
    // eslint-disable-next-line @typescript-eslint/no-non-null-assertion
    const cycleList = [...cycle, cycle[0]!]
    errors.push({
      error: `Pipeline contains a cycle: ${cycleList.join(' → ')}`,
      errorType: pipelineErrorType.CycleDetected,
      involvedNodes: cycle,
    })
  }

  const disconnected = findDisconnectedNodes(graph)
  if (disconnected.length > 0) {
    errors.push({
      error: `Pipeline contains unreachable nodes: ${disconnected.join(', ')}`,
      errorType: pipelineErrorType.DisconnectedNode,
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

  const components: Array<Set<string>> = []
  const visited = new Set<string>()

  // Helper function to perform DFS and collect connected components
  const dfs = (nodeId: string, component: Set<string>) => {
    visited.add(nodeId)
    component.add(nodeId)

    for (const edge of graph.edges) {
      if (edge.from === nodeId && !visited.has(edge.to)) {
        dfs(edge.to, component)
      }
      if (edge.to === nodeId && !visited.has(edge.from)) {
        dfs(edge.from, component)
      }
    }
  }

  // Find all connected components
  for (const node of nodes) {
    if (!visited.has(node.id)) {
      const component = new Set<string>()
      dfs(node.id, component)
      components.push(component)
    }
  }

  // If there's only one component, there are no disconnected nodes
  if (components.length <= 1) {
    return []
  }

  // Find the largest component - we consider this the "main" graph
  const mainComponent = components.reduce(
    (largest, current) => (current.size > largest.size ? current : largest),
    new Set<string>(),
  )

  // All nodes not in the main component are considered disconnected
  const disconnectedNodes: string[] = []
  for (const node of nodes) {
    if (!mainComponent.has(node.id)) {
      disconnectedNodes.push(node.id)
    }
  }

  return disconnectedNodes
}

function validatePipelineProperties(pipeline: Pipeline): PipelineValidationError[] {
  let errors: PipelineValidationError[] = []
  if (typeof pipeline.title !== 'string') {
    errors.push({
      error: `Pipeline is missing a title`,
      errorType: pipelineErrorType.MissingProperty,
      involvedNodes: [],
    })
  }
  if (!Array.isArray(pipeline.nodes) || pipeline.nodes.length === 0) {
    errors.push({
      error: `Pipeline has no nodes`,
      errorType: pipelineErrorType.MissingProperty,
      involvedNodes: [],
    })
  }
  for (const node of pipeline.nodes) {
    errors = errors.concat(validateNodeProperties(node))
  }
  return errors
}

function validateNodeProperties(node: Node): PipelineValidationError[] {
  let errors: PipelineValidationError[] = []
  if (typeof node.title !== 'string' || node.title.length === 0) {
    errors.push({
      error: `Node is missing a title`,
      errorType: pipelineErrorType.MissingProperty,
      involvedNodes: [node.id],
    })
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
    errors.push({
      error: `inputType is required for text nodes`,
      errorType: pipelineErrorType.MissingProperty,
      involvedNodes: [node.id],
    })
    return errors
  }

  switch (input.type) {
    case 'boolean':
      if (!['true', 'false'].includes(node.content)) {
        errors.push({
          error: `A boolean input must have a value of either "true" or "false"`,
          errorType: pipelineErrorType.InvalidBooleanValue,
          involvedNodes: [node.id],
        })
      }
      break
    case 'range':
      if (typeof input.min !== 'number') {
        errors.push({
          error: `A range input must have a min`,
          errorType: pipelineErrorType.InvalidRangeValue,
          involvedNodes: [node.id],
        })
      }
      if (typeof input.max !== 'number') {
        errors.push({
          error: `A range input must have a max`,
          errorType: pipelineErrorType.InvalidRangeValue,
          involvedNodes: [node.id],
        })
      }
      break
    case 'select':
      if (!Array.isArray(input.options) || input.options.length === 0) {
        errors.push({
          error: `A select input must have options`,
          errorType: pipelineErrorType.InvalidSelectValue,
          involvedNodes: [node.id],
        })
      } else if (!input.options.includes(node.content)) {
        errors.push({
          error: `A select node must have content equal to one of its options`,
          errorType: pipelineErrorType.InvalidSelectValue,
          involvedNodes: [node.id],
        })
      }
      break
    case 'file':
      if (!['pdf', 'video', 'image', 'audio', 'document', 'code', 'other'].includes(input.fileType)) {
        errors.push({
          error: `Invalid file type ${input.fileType}`,
          errorType: pipelineErrorType.InvalidFileType,
          involvedNodes: [node.id],
        })
      }
      break
    case 'text':
      if (!node.content) {
        errors.push({
          error: `Input needs a value`,
          errorType: pipelineErrorType.EmptyInputValue,
          involvedNodes: [node.id],
        })
      }
      break
  }
  return errors
}

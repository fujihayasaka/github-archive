import type {Pipeline, Node} from '../types/app'

/**
 * Add a node to the pipeline
 */
export function addNodeToPipeline(pipeline: Pipeline, node: Node): Pipeline {
  if (!pipeline) return pipeline

  return {
    ...pipeline,
    nodes: [...(pipeline.nodes || []), node],
    updatedAt: new Date().toISOString(),
  }
}

/**
 * Remove a node from the pipeline
 */
export function removeNodeFromPipeline(pipeline: Pipeline, nodeId: string): Pipeline {
  if (!pipeline) return pipeline

  return {
    ...pipeline,
    nodes: pipeline.nodes.filter(n => n.id !== nodeId),
    updatedAt: new Date().toISOString(),
  }
}

/**
 * Update a node in the pipeline
 */
export function updateNodeInPipeline(pipeline: Pipeline, nodeId: string, updates: Partial<Node>): Pipeline {
  if (!pipeline) return pipeline

  const nodeIndex = pipeline.nodes.findIndex(n => n.id === nodeId)
  if (nodeIndex === -1) {
    // If the node doesn't exist, create a new one with the updates
    return addNodeToPipeline(pipeline, {
      id: nodeId,
      type: 'text',
      title: '',
      description: '',
      content: '',
      ...updates,
    } as Node)
  } else {
    const node = pipeline.nodes[nodeIndex]
    return {
      ...pipeline,
      nodes: [
        ...pipeline.nodes.slice(0, nodeIndex),
        {...node, ...updates} as Node,
        ...pipeline.nodes.slice(nodeIndex + 1),
      ],
      updatedAt: new Date().toISOString(),
    }
  }
}

/**
 * Update node content in a pipeline
 */
export function updateNodeContentInPipeline(pipeline: Pipeline, nodeId: string, content: string): Pipeline {
  if (!pipeline) return pipeline
  return updateNodeInPipeline(pipeline, nodeId, {content})
}

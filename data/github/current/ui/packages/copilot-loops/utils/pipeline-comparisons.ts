import type {Pipeline} from '../types/app'
import isEqual from 'lodash-es/isEqual'

/**
 * Compares two pipelines to determine if they are equal by comparing only essential fields.
 * Only compares title, description, nodes, and color fields.
 */
export function arePipelinesEqual(pipelineA?: Pipeline | null, pipelineB?: Pipeline | null): boolean {
  if (!pipelineA && !pipelineB) return true
  if (!pipelineA || !pipelineB) return false

  const compareFieldsA = {
    title: pipelineA.title,
    description: pipelineA.description,
    nodes: pipelineA.nodes,
    color: pipelineA.color,
  }

  const compareFieldsB = {
    title: pipelineB.title,
    description: pipelineB.description,
    nodes: pipelineB.nodes,
    color: pipelineB.color,
  }

  return isEqual(compareFieldsA, compareFieldsB)
}

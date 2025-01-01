import {validatePipeline} from '../service/validate-pipeline'
import {pipelineErrorType, type Pipeline, type PipelineErrorType, type PipelineValidationError} from '../types/app'
import {getPipelineGraph} from './pipes'

export const unfixableErrors = new Set<PipelineErrorType>([pipelineErrorType.EmptyInputValue])

/**
 * When a loop has certain errors, we don't want to run autofix since it has a low chance of success.
 */
export function onlyUnfixableErrors(errors: PipelineValidationError[]): boolean {
  return errors.length > 0 && errors.every(err => unfixableErrors.has(err.errorType))
}

/**
 * Find the first node in the pipeline with validation errors
 */
export function firstNodeWithValidationErrors(loop: Pipeline): string | undefined {
  const validationErrors = validatePipeline(loop)
  const errorNodes = new Set<string>(
    validationErrors.reduce(
      (prev: string[], current: PipelineValidationError) => prev.concat(current.involvedNodes),
      [],
    ),
  )

  // Work through the graph layers so that the error we look at is as early in the pipeline as possible
  const graph = getPipelineGraph(loop)
  for (const layer of graph.layers) {
    for (const node of layer) {
      if (errorNodes.has(node.id)) return node.id
    }
  }

  return undefined
}

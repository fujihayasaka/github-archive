import {useMemo} from 'react'
import {validatePipeline} from '../service/validate-pipeline'
import type {PipelineValidationError} from '../types/app'
import {useLoop} from './queries/use-loop'

export function useValidationErrors(): PipelineValidationError[] {
  const {data: loop} = useLoop()
  return useMemo(() => {
    if (!loop) return []

    return validatePipeline(loop)
  }, [loop])
}

export function useNodeValidationErrors(nodeId: string): string[] {
  const validationErrors = useValidationErrors()
  return useMemo(
    () =>
      validationErrors
        .filter(e => {
          return e.involvedNodes.includes(nodeId)
        })
        .map(e => e.error),
    [nodeId, validationErrors],
  )
}

export function useHasValidationErrors(nodeId?: string): boolean {
  const validationErrors = useValidationErrors()
  return validationErrors.some(e => !nodeId || e.involvedNodes.includes(nodeId))
}

import {arePipelinesEqual} from '../utils/pipeline-comparisons'
import {useLoop} from './queries/use-loop'

/**
 * This hook determines the current state of a pipeline draft:
 * - Is it a new pipeline (has no saved version)?
 * - Does it have unsaved changes (draft different from saved)?
 */
export function useLoopDraftStatus() {
  const {data: savedLoop} = useLoop('latest')
  const {data: draftLoop} = useLoop('draft')

  const hasSavedLoop = !!savedLoop
  const hasDraftLoop = !!draftLoop

  const hasPipeline = hasSavedLoop || hasDraftLoop
  const isNew = !hasSavedLoop && hasDraftLoop

  // Calculate hasChanges by comparing the two pipelines
  const hasChanges = hasDraftLoop && hasSavedLoop && !arePipelinesEqual(draftLoop, savedLoop)

  return {
    hasChanges,
    hasPipeline,
    isNew,
  }
}

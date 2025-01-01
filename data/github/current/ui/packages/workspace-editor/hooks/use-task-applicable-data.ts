import type {ParsedDiff} from 'diff'
import {useMemo} from 'react'

import {useFilesContext} from '../contexts/FilesContext'
import {problemWithTaskSuggestions} from '../utilities/suggestion-helpers'
import type {BlobPayload, FocusedGenerativeTaskData} from '../utilities/workspace-editor-types'
import {useLocalSuggestionState} from './use-local-suggestion-state'

export function useTaskApplicableData(
  task: FocusedGenerativeTaskData,
  blobData: BlobPayload | undefined,
  parsedDiff: ParsedDiff | undefined,
) {
  const {getAppliedSuggestions} = useLocalSuggestionState()
  const appliedSuggestions = getAppliedSuggestions()
  const {getFileStatuses, getCurrentFileContent} = useFilesContext()

  return useMemo(() => {
    if (!parsedDiff?.hunks || !blobData) {
      return {
        isAppliable: false,
        applyTooltip: '',
      }
    }

    const hunks = parsedDiff?.hunks.map(hunk => ({filePath: task.path, diff: {...hunk}}))

    const taskWithSuggestions = {...task, suggestions: hunks}
    const problem = problemWithTaskSuggestions(appliedSuggestions, getFileStatuses(), taskWithSuggestions, [
      [blobData, getCurrentFileContent(task.path, blobData.blobContents).content],
    ])
    return {isAppliable: !problem, applyTooltip: problem || ''}
  }, [appliedSuggestions, blobData, getCurrentFileContent, getFileStatuses, parsedDiff?.hunks, task])
}

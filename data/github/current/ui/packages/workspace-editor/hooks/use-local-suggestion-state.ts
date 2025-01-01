import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {clearLocalStorage, useLocalStorage} from '@github-ui/use-safe-storage/local-storage'
import {useCallback} from 'react'

import type {
  FocusedTaskData,
  FocusedTaskSuggestion,
  WorkspaceEditorRoutePayload,
} from '../utilities/workspace-editor-types'

// Format we use to store v2 applied suggestion in local storage
interface AppliedSuggestion {
  fully_applied?: boolean
  files: string[]
}

// These key building functions are exported only to support testing
export function buildSuggestionsStorageKey(org: string, repoName: string, entityId: string) {
  return `hadron-editor-suggestions/${org}/${repoName}/${entityId}`
}

export function buildSuggestionsStorageKeyV2(org: string, repoName: string, entityId: string) {
  return `hadron-editor-suggestions-v2/${org}/${repoName}/${entityId}`
}

export function buildDismissedSuggestionsStorageKey(org: string, repoName: string, entityId: string) {
  return `hadron-editor-suggestions-dismissed/${org}/${repoName}/${entityId}`
}

/**
 * This hook manages our local-storage backed suggestion state.
 *
 * This includes what suggestions (and individual diffs) it thinks
 * we have applied, and also what we've dismissed interactively.
 */
export function useLocalSuggestionState() {
  const {repo, pullRequestNumber} = useRoutePayload<WorkspaceEditorRoutePayload>()
  const {name, ownerLogin} = repo

  const [appliedSuggestions, setAppliedSuggestions] = useLocalStorage<number[]>(
    buildSuggestionsStorageKey(ownerLogin, name, pullRequestNumber),
    [],
  )

  const [appliedSuggestionsV2, setAppliedSuggestionsV2] = useLocalStorage<Record<string, AppliedSuggestion>>(
    buildSuggestionsStorageKeyV2(ownerLogin, name, pullRequestNumber),
    {},
  )

  const [dismissedSuggestions, setDismissedSuggestions] = useLocalStorage<number[]>(
    buildDismissedSuggestionsStorageKey(ownerLogin, name, pullRequestNumber),
    [],
  )

  /**
   * This being a callback is what gets us refreshing when a suggestion is applied
   * If this changes significantly or goes away, make sure that non-focused files
   * when applied are updating all UI state properly!
   */
  const getAppliedSuggestions = useCallback(() => {
    // For compatibility we gather ids from both the v1 and v2 data sources
    // This makes sure that if someone has stored data in v1 when we flip the
    // flag everything continues to work the same.
    //
    // We don't do anything in the read path in the reverse direction. Instead
    // for now we always write v1 data when we write v2, so disabling the FF
    // always lands users in a good state.
    const allIds = Object.entries(appliedSuggestionsV2)
      .map(([id]) => Number(id))
      .concat(appliedSuggestions)
    const ids = new Set<number>(allIds)
    return Array.from(ids)
  }, [appliedSuggestions, appliedSuggestionsV2])

  const updateAppliedSuggestions = useCallback(
    (task: FocusedTaskData, suggestions: FocusedTaskSuggestion[]) => {
      // Always update our V1 data
      let newAppliedSuggestions: number[] = appliedSuggestions
      if (!appliedSuggestions.includes) {
        // Work around malformed applied suggestions
        newAppliedSuggestions = [task.sourceId]
      } else if (!appliedSuggestions.includes(task.sourceId)) {
        newAppliedSuggestions = [...appliedSuggestions, task.sourceId]
      }
      setAppliedSuggestions(newAppliedSuggestions)

      // Create or update our current entry with files touched
      const appliedForTask = appliedSuggestionsV2[task.sourceId.toString()] || {
        files: [],
      }
      appliedForTask.files = [...new Set([...appliedForTask.files, ...suggestions.map(s => s.filePath)])]

      // New list to save
      const updated: Record<string, AppliedSuggestion> = {
        ...appliedSuggestionsV2,
        [task.sourceId.toString()]: appliedForTask,
      }

      // Stub in any v1 entries we found that aren't in v2 data yet
      for (const id of newAppliedSuggestions) {
        if (!updated[id.toString()]) {
          updated[id.toString()] = {fully_applied: true, files: []}
        }
      }
      setAppliedSuggestionsV2(updated)
    },
    [appliedSuggestions, appliedSuggestionsV2, setAppliedSuggestions, setAppliedSuggestionsV2],
  )

  const isSingleSuggestionApplied = useCallback(
    (task: FocusedTaskData, suggestion: FocusedTaskSuggestion): boolean => {
      const applied = appliedSuggestionsV2[task.sourceId.toString()]
      if (!applied) {
        // If we didn't have it in v2, peek in v1
        // If we applied on v1 treat as the whole suggestion applied (can't do better)
        return appliedSuggestions.includes && appliedSuggestions.includes(task.sourceId)
      }

      return applied.fully_applied || applied.files.includes(suggestion.filePath)
    },
    [appliedSuggestions, appliedSuggestionsV2],
  )

  const dismissSuggestion = useCallback(
    (task: FocusedTaskData) => {
      setDismissedSuggestions([...new Set([...dismissedSuggestions, task.sourceId])])
    },
    [dismissedSuggestions, setDismissedSuggestions],
  )

  const getDismissedSuggestions = useCallback(() => {
    return dismissedSuggestions
  }, [dismissedSuggestions])

  const reopenSuggestion = useCallback(
    (task: FocusedTaskData) => {
      setDismissedSuggestions(dismissedSuggestions.filter(suggestionId => suggestionId !== task.sourceId))
    },
    [dismissedSuggestions, setDismissedSuggestions],
  )

  const resetSuggestionState = useCallback(() => {
    const suggestionKey = buildSuggestionsStorageKey(ownerLogin, name, pullRequestNumber)
    const suggestionKeyV2 = buildSuggestionsStorageKeyV2(ownerLogin, name, pullRequestNumber)
    const dismissedKey = buildDismissedSuggestionsStorageKey(ownerLogin, name, pullRequestNumber)
    clearLocalStorage([dismissedKey, suggestionKey, suggestionKeyV2])
  }, [name, ownerLogin, pullRequestNumber])

  const resetSuggestionsForFile = useCallback(
    (filePath: string) => {
      // V1 storage doesn't have file tracking, so we can only update v2
      const newAppliedSuggestions = [...appliedSuggestions]
      const newAppliedSuggestionsV2 = Object.fromEntries(
        Object.entries(appliedSuggestionsV2).filter(([id, suggestion]) => {
          if (suggestion.files.includes(filePath)) {
            const v1index = newAppliedSuggestions.indexOf(Number(id))
            if (v1index !== -1) {
              newAppliedSuggestions.splice(v1index, 1)
            }
            return false
          }
          return true
        }),
      )
      setAppliedSuggestions(newAppliedSuggestions)
      setAppliedSuggestionsV2(newAppliedSuggestionsV2)
    },
    [appliedSuggestions, appliedSuggestionsV2, setAppliedSuggestions, setAppliedSuggestionsV2],
  )

  return {
    dismissSuggestion,
    getAppliedSuggestions,
    getDismissedSuggestions,
    isSingleSuggestionApplied,
    reopenSuggestion,
    resetSuggestionState,
    resetSuggestionsForFile,
    updateAppliedSuggestions,
  }
}

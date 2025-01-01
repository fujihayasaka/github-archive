import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {createContext, type PropsWithChildren, useCallback, useContext, useMemo, useState} from 'react'
import {useNavigate} from 'react-router-dom'

import {useFocusedTask} from '../hooks/use-focused-task'
import {useSuggestion} from '../hooks/use-suggestion'
import {focusedTaskQueryParam, removeQueryParam, setQueryParam} from '../utilities/query-params'
import {fileUrl} from '../utilities/urls'
import type {FocusedTaskData, WorkspaceEditorRoutePayload} from '../utilities/workspace-editor-types'

interface SuggestionContextData {
  clearFocusedTaskId: () => void
  focusedTask: FocusedTaskData | undefined
  focusedTaskId: number | null
  isError: boolean
  isLoading: boolean
  updateFocusedTaskId: (taskId: number) => void
}

/**
 * Context that manages loading and managing the current focused Suggestion
 */
const SuggestionContext = createContext<SuggestionContextData | undefined>(undefined)

export function SuggestionContextProvider({children}: PropsWithChildren) {
  const {path, repo, pullRequestNumber} = useRoutePayload<WorkspaceEditorRoutePayload>()
  const focusOnSuggestionPathEnabled = useFeatureFlag('workspace_editor_focus_on_suggestion_path')
  const navigate = useNavigate()
  const {initialTaskId} = useFocusedTask()
  const [focusedTaskId, setFocusedTaskId] = useState<number | null>(initialTaskId)

  const updateFocusedTaskId = useCallback((taskId: number) => {
    setQueryParam(focusedTaskQueryParam, taskId.toString())
    setFocusedTaskId(taskId)
  }, [])

  const {suggestion, isLoading, isError} = useSuggestion(focusedTaskId)
  const [prevSuggestionSourceId, setPrevSuggestionSourceId] = useState(suggestion?.sourceId)

  if (prevSuggestionSourceId !== suggestion?.sourceId) {
    if (focusOnSuggestionPathEnabled && suggestion && path !== suggestion.path) {
      const suggestionFileUrl = fileUrl({
        owner: repo.ownerLogin,
        repo: repo.name,
        path: suggestion.path,
        pullNumber: pullRequestNumber,
        location: window.location,
      })
      setTimeout(() => navigate(suggestionFileUrl))
    }

    setPrevSuggestionSourceId(suggestion?.sourceId)
  }

  const clearFocusedTaskId = useCallback(() => {
    removeQueryParam(focusedTaskQueryParam)
    setFocusedTaskId(null)
  }, [])

  const value = useMemo(
    () => ({
      clearFocusedTaskId,
      // Don't return this suggestion if the task is not the focused task.
      // This might happen when loading a new task.
      focusedTask: focusedTaskId === suggestion?.sourceId ? suggestion : undefined,
      focusedTaskId,
      isError,
      isLoading,
      updateFocusedTaskId,
    }),
    [clearFocusedTaskId, suggestion, focusedTaskId, isError, isLoading, updateFocusedTaskId],
  )

  return <SuggestionContext.Provider value={value}>{children}</SuggestionContext.Provider>
}

export function useSuggestionContext() {
  const context = useContext(SuggestionContext)
  if (!context) {
    throw new Error('useSuggestionContext must be used within an SuggestionContextProvider')
  }
  return context
}

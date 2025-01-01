import {Spinner} from '@primer/react'
import {useEffect, useState} from 'react'

import {useSuggestionContext} from '../contexts/SuggestionContext'
import {useSuggestions} from '../hooks/use-suggestions'
import {focusedTaskQueryParam, setQueryParam} from '../utilities/query-params'
import {isGenerativeTask} from '../utilities/task-helpers'
import {type DisplayTaskData, type FocusedTaskData, TaskTypes} from '../utilities/workspace-editor-types'
import {GenerateFix} from './generate-fix-panel/GenerateFix'
import {RightSidePanelContent} from './RightSidePanelComponents'
import {Suggestion} from './Suggestion'
import {Suggestions} from './Suggestions'

interface SelectedTaskProps {
  currentTask: FocusedTaskData
  suggestionsForPagination: DisplayTaskData[]
}

function SelectedTask({currentTask, suggestionsForPagination}: SelectedTaskProps) {
  if (!currentTask) return null

  switch (currentTask.type) {
    case TaskTypes.Autofix:
    case TaskTypes.Suggestion:
      return <Suggestion currentTask={currentTask} suggestionsForPagination={suggestionsForPagination} />
    case TaskTypes.Generative:
      if (!isGenerativeTask(currentTask)) throw new Error('Unexpected task type.')
      return <GenerateFix focusedGenerativeTask={currentTask} suggestionsForPagination={suggestionsForPagination} />
    default:
      return null
  }
}

const SuggestionPanel = () => {
  const [suggestionsForPagination, setSuggestionsForPagination] = useState<DisplayTaskData[]>([])

  const {
    focusedTaskId,
    focusedTask: currentTask,
    isError: isTaskError,
    isLoading: isTaskLoading,
    updateFocusedTaskId,
  } = useSuggestionContext()

  const {isError, suggestionMap} = useSuggestions()

  useEffect(() => {
    if (currentTask) setQueryParam(focusedTaskQueryParam, currentTask.sourceId.toString())
    // Only run on initial render, context will handle updates.
    // eslint-disable-next-line react-compiler/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  if (isError || isTaskError) {
    return (
      <RightSidePanelContent>
        <div>Something went wrong. Please try again.</div>
      </RightSidePanelContent>
    )
  } else if ((focusedTaskId && isTaskLoading) || (!focusedTaskId && !suggestionMap)) {
    return (
      <RightSidePanelContent>
        <div className="mt-4 d-flex flex-justify-center">
          <Spinner />
        </div>
      </RightSidePanelContent>
    )
  } else if (currentTask) {
    return <SelectedTask currentTask={currentTask} suggestionsForPagination={suggestionsForPagination} />
  } else if (suggestionMap) {
    return (
      <Suggestions
        suggestions={suggestionMap}
        onTaskSelected={updateFocusedTaskId}
        setSuggestionsForPagination={setSuggestionsForPagination}
      />
    )
  }
}

export default SuggestionPanel

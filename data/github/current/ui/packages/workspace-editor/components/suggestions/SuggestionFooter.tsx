import {CheckIcon} from '@primer/octicons-react'
import {Button, Link} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'

import {useFocus} from '../../contexts/FocusContext'
import {useSuggestionContext} from '../../contexts/SuggestionContext'
import {useLocalSuggestionState} from '../../hooks/use-local-suggestion-state'
import {useSuggestionNavigation} from '../../hooks/use-suggestion-navigation'
import {useAnalytics} from '../../telemetry/use-analytics'
import {anyActionableSuggestions} from '../../utilities/suggestion-helpers'
import type {DisplayTaskData, FocusedTaskData} from '../../utilities/workspace-editor-types'
import {SuggestionPaginator} from '../SuggestionPaginator'
import {RightSidePanelFooter} from './../RightSidePanelComponents'
import styles from './SuggestionFooter.module.css'

const ActionButtons = ({
  currentTask,
  onDismiss,
  applyButton,
  showSuggestionApplied,
}: {
  currentTask: FocusedTaskData
  onDismiss: () => void
  applyButton: JSX.Element | null
  showSuggestionApplied: boolean
}) => {
  const {reopenSuggestion, getDismissedSuggestions} = useLocalSuggestionState()
  const sendEvent = useAnalytics()

  const dismissedSuggestions = getDismissedSuggestions()
  const sourceIdNum = currentTask.sourceId
  if (dismissedSuggestions.includes(sourceIdNum)) {
    const onReopenSuggestion = () => {
      reopenSuggestion(currentTask)
      sendEvent('suggestion.reopened')
    }
    return (
      <span className={styles.suggestionStatus}>
        <span className={styles.colorMuted}>Suggestion dismissed.</span>
        <Link onClick={onReopenSuggestion}>Undo</Link>
      </span>
    )
  } else if (showSuggestionApplied) {
    return (
      <span className={styles.suggestionStatus}>
        <Octicon icon={CheckIcon} sx={{color: 'success.fg'}} />
        <span className={styles.colorMuted}>Suggestion applied</span>
      </span>
    )
  } else if (currentTask.outdated) {
    return (
      <span className={styles.suggestionStatus}>
        <span className={styles.colorMuted}>Suggestion outdated</span>
      </span>
    )
  } else {
    return (
      <>
        <Button sx={{marginRight: 2}} onClick={onDismiss}>
          Dismiss
        </Button>
        {applyButton}
      </>
    )
  }
}

export const SuggestionFooter = ({
  applyButton,
  showSuggestionApplied,
  suggestionsForPagination,
}: {
  applyButton: JSX.Element | null
  showSuggestionApplied: boolean
  suggestionsForPagination: DisplayTaskData[]
}) => {
  const {dismissSuggestion, getAppliedSuggestions, getDismissedSuggestions} = useLocalSuggestionState()
  const {clearFocusedTaskId, focusedTask: currentTask, updateFocusedTaskId} = useSuggestionContext()
  const navigateToSuggestionPath = useSuggestionNavigation()
  const sendEvent = useAnalytics()
  const {focusTarget} = useFocus()
  if (!currentTask) return null

  const currentPaginatorIndex = suggestionsForPagination.findIndex(
    suggestion => suggestion.sourceId === currentTask.sourceId,
  )
  const onPaginatorClick = (indexNumberModifier: number) => {
    const nextTask = findNewOpenTask(indexNumberModifier)
    if (nextTask?.sourceId) {
      updateFocusedTaskId(nextTask.sourceId)
      navigateToSuggestionPath(nextTask)
    } else {
      clearFocusedTaskId()
    }
    focusTarget('suggestionPanelHeader')
  }

  const findNewOpenTask = (indexNumberModifier: number, dismissedSuggestions?: number[]) => {
    const appliedSuggestions = getAppliedSuggestions()
    dismissedSuggestions = dismissedSuggestions || getDismissedSuggestions()
    if (!anyActionableSuggestions(suggestionsForPagination, appliedSuggestions, dismissedSuggestions)) {
      return null
    }

    let newIndex = currentPaginatorIndex + indexNumberModifier
    if (newIndex < 0) {
      newIndex = suggestionsForPagination.length - 1
    } else if (newIndex >= suggestionsForPagination.length) {
      newIndex = 0
    }
    return suggestionsForPagination[newIndex]
  }

  const onDismissSuggestion = () => {
    dismissSuggestion(currentTask)
    sendEvent('suggestion.dismissed')
    const dismissedSuggestions = [...getDismissedSuggestions(), currentTask.sourceId]

    const nextTask = findNewOpenTask(1, dismissedSuggestions)
    if (nextTask && nextTask.sourceId !== currentTask.sourceId) {
      updateFocusedTaskId(nextTask.sourceId)
      navigateToSuggestionPath(nextTask)
    } else {
      clearFocusedTaskId()
    }
    focusTarget('suggestionPanelHeader')
  }

  const paginatorComponent = (
    <SuggestionPaginator
      currentIndex={currentPaginatorIndex}
      pageCount={suggestionsForPagination.length}
      onClick={onPaginatorClick}
    />
  )

  return (
    <RightSidePanelFooter>
      {paginatorComponent}
      <div className={styles.actionButtonsWrapper}>
        <ActionButtons
          currentTask={currentTask}
          onDismiss={onDismissSuggestion}
          applyButton={applyButton}
          showSuggestionApplied={showSuggestionApplied}
        />
      </div>
    </RightSidePanelFooter>
  )
}

import {ActionList} from '@primer/react'

import {useFocus} from '../../contexts/FocusContext'
import {useSuggestionNavigation} from '../../hooks/use-suggestion-navigation'
import type {DisplayTaskData} from '../../utilities/workspace-editor-types'
import {SuggesterAvatar} from '../SuggesterAvatar'
import {SuggestionTitle} from '../SuggestionTitle'

/**
 * Render a single ActionList.Item for a suggestion.
 */
export function SuggestionsListItem({
  suggestion,
  onTaskSelected,
}: {
  suggestion: DisplayTaskData
  onTaskSelected: (taskSourceId: number) => void
}) {
  const {focusTarget} = useFocus()
  const navigateToSuggestionPath = useSuggestionNavigation()

  const onSelect = () => {
    onTaskSelected(suggestion.sourceId)
    navigateToSuggestionPath(suggestion)
    focusTarget('suggestionPanelHeader')
  }

  return (
    <ActionList.Item className="m-0" key={suggestion.sourceId} onSelect={onSelect}>
      <ActionList.LeadingVisual>
        <SuggesterAvatar suggester={suggestion.author} />
      </ActionList.LeadingVisual>
      <SuggestionTitle task={suggestion} />
    </ActionList.Item>
  )
}

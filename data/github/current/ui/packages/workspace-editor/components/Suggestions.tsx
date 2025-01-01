import {useLocalSuggestionState} from '../hooks/use-local-suggestion-state'
import {groupedSuggestions} from '../utilities/suggestion-helpers'
import type {SuggestionCommentData} from '../utilities/workspace-editor-types'
import {RightSidePanelContent} from './RightSidePanelComponents'
import {ExpandableSuggestions} from './suggestions/ExpandableSuggestions'
import {OpenSuggestions} from './suggestions/OpenSuggestions'

export const Suggestions = ({
  onTaskSelected,
  suggestions,
  setSuggestionsForPagination,
}: {
  onTaskSelected: (taskSourceId: number) => void
  suggestions: SuggestionCommentData
  setSuggestionsForPagination: (suggestion: number[]) => void
}) => {
  const {getAppliedSuggestions, getDismissedSuggestions} = useLocalSuggestionState()
  const appliedSuggestions = getAppliedSuggestions()
  const dismissedSuggestions = getDismissedSuggestions()

  const {
    outdatedSuggestionsMap,
    dismissedSuggestionsMap,
    appliedSuggestionsMap,
    openSuggestionsMap,
    openSuggestionIds,
  } = groupedSuggestions(suggestions, appliedSuggestions, dismissedSuggestions)

  const handleTaskSelectedOpen = (taskSourceId: number) => {
    onTaskSelected(taskSourceId)
    setSuggestionsForPagination(openSuggestionIds)
  }

  const handleTaskSelectedClosed = (taskSourceId: number) => {
    onTaskSelected(taskSourceId)
    setSuggestionsForPagination([])
  }

  return (
    <RightSidePanelContent padding={2}>
      <OpenSuggestions onTaskSelected={handleTaskSelectedOpen} openSuggestions={openSuggestionsMap} />
      <ExpandableSuggestions
        filteredSuggestionsMap={appliedSuggestionsMap}
        description={`${appliedSuggestionsMap.length} applied`}
        onTaskSelected={handleTaskSelectedClosed}
      />
      <ExpandableSuggestions
        filteredSuggestionsMap={dismissedSuggestionsMap}
        description={`${dismissedSuggestionsMap.length} dismissed`}
        onTaskSelected={handleTaskSelectedClosed}
      />
      <ExpandableSuggestions
        filteredSuggestionsMap={outdatedSuggestionsMap}
        description={`${outdatedSuggestionsMap.length} outdated`}
        onTaskSelected={handleTaskSelectedClosed}
      />
    </RightSidePanelContent>
  )
}

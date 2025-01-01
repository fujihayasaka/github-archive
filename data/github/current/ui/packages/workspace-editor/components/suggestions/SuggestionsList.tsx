import {ActionList} from '@primer/react'

import type {DisplayTaskData} from '../../utilities/workspace-editor-types'
import listStyles from './SuggestionsList.module.css'
import {SuggestionsListItem} from './SuggestionsListItem'

/**
 * Render a basic ActionList of suggestion items.
 */
export function SuggestionsList({
  id,
  suggestionsMap,
  onTaskSelected,
}: {
  id?: string
  suggestionsMap: Array<[string, DisplayTaskData]>
  onTaskSelected: (taskSourceId: number) => void
}) {
  const suggestions = suggestionsMap.map(([_, task]) => task)

  return (
    <ActionList className={listStyles.actionList} id={id}>
      {suggestions.map(suggestion => (
        <SuggestionsListItem key={suggestion.sourceId} suggestion={suggestion} onTaskSelected={onTaskSelected} />
      ))}
    </ActionList>
  )
}

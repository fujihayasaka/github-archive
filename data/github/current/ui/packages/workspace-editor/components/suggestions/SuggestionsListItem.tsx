import {ActionList} from '@primer/react'

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
  return (
    <ActionList.Item className="m-0" key={suggestion.sourceId} onSelect={() => onTaskSelected(suggestion.sourceId)}>
      <ActionList.LeadingVisual>
        <SuggesterAvatar suggester={suggestion.author} />
      </ActionList.LeadingVisual>
      <SuggestionTitle task={suggestion} />
    </ActionList.Item>
  )
}

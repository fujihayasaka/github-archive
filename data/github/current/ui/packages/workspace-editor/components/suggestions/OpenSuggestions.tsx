import {ActionList} from '@primer/react'

import {groupDescription} from '../../utilities/suggestion-helpers'
import type {SuggestionCommentData, TaskTypes} from '../../utilities/workspace-editor-types'
import EmptySuggestionState from '../EmptySuggestionState'
import styles from './OpenSuggestions.module.css'
import {SuggestionsListItem} from './SuggestionsListItem'

export function OpenSuggestions({
  onTaskSelected,
  openSuggestions,
}: {
  onTaskSelected: (sourceId: number) => void
  openSuggestions: Array<[string, SuggestionCommentData]>
}) {
  if (!openSuggestions.length) {
    return <EmptySuggestionState />
  }

  return (
    <ActionList className={styles.actionList}>
      {openSuggestions.map(([type, suggestionGroup]) => {
        const suggestionList = Object.entries(suggestionGroup)
        return (
          // we have to use a css selector to grab the div wrapping the group heading and remove its left padding
          <ActionList.Group key={`open-${type}`} className={styles.ActionList_Group}>
            <ActionList.GroupHeading as="h3" className={styles.groupHeading}>
              {groupDescription(type as TaskTypes, suggestionList.length)}
            </ActionList.GroupHeading>
            {suggestionList.map(([_, suggestion]) => (
              <SuggestionsListItem key={suggestion.sourceId} suggestion={suggestion} onTaskSelected={onTaskSelected} />
            ))}
          </ActionList.Group>
        )
      })}
    </ActionList>
  )
}

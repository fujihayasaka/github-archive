import {LoadingSkeleton} from '@github-ui/skeleton/LoadingSkeleton'
import {testIdProps} from '@github-ui/test-id-props'
import {ActionList} from '@primer/react'
import {clsx} from 'clsx'
import {type ReactNode, useMemo} from 'react'

import {useFilter, useInput, useSuggestions} from '../context'
import {getFilterValue, getUniqueReactKey} from '../utils'
import {SuggestionItem} from './SuggestionItem'
import styles from './SuggestionsList.module.css'

export const SuggestionsList = ({id}: {id: string}) => {
  const {id: filterContextId} = useFilter()
  id = id ?? filterContextId

  const {suggestionsListRef, activeSuggestion, isFetchingSuggestions, position, suggestionGroups, suggestionsVisible} =
    useSuggestions()
  const {suspendFocus} = useInput()

  const skeletonRow = (key: string, animationStyle: 'wave' | 'pulse' = 'wave') => {
    return (
      <div key={key} className={styles.Box_0}>
        <LoadingSkeleton variant="elliptical" width="20px" height="20px" animationStyle={animationStyle} />
        <LoadingSkeleton variant="rounded" width="random" height="16px" animationStyle={animationStyle} />
      </div>
    )
  }

  const blankSlateSkeletons = useMemo(
    () => (
      <div>
        {Array(8)
          .fill(1)
          .map((_, i) => skeletonRow(`loading-skeleton-${i}`))}
      </div>
    ),
    [],
  )

  // When prefetching, we will only show a single loading skeleton
  const partialResultSkeletons = useMemo(() => skeletonRow(`prefetched-loading-skeleton`, 'pulse'), [])

  const showSuggestionsOverlay =
    (suggestionsVisible && suggestionGroups.some(s => s.suggestions.length > 0)) || isFetchingSuggestions

  const generatedSuggestions = useMemo(() => {
    let rowIndex = -1
    const renderedSuggestions: ReactNode[] = []
    suggestionGroups.map((suggestionGroup, groupIndex) => {
      if (suggestionGroup.suggestions.length > 0) {
        // This is a group
        renderedSuggestions.push(
          <ActionList.Group key={getUniqueReactKey('group', suggestionGroup.id)}>
            {suggestionGroup.title && (
              <ActionList.GroupHeading {...testIdProps('suggestions-heading')} aria-hidden="true">
                {suggestionGroup.title}
              </ActionList.GroupHeading>
            )}
            {suggestionGroup.suggestions.map(suggestion => {
              rowIndex++
              return (
                <SuggestionItem
                  {...suggestion}
                  suggestionId={rowIndex}
                  key={getUniqueReactKey(
                    'suggestion',
                    suggestion.id,
                    `${getFilterValue(suggestion.value)}-${suggestion.displayName}-${suggestion.description}`,
                  )}
                  active={rowIndex === activeSuggestion}
                />
              )
            })}
          </ActionList.Group>,
        )

        if (
          groupIndex++ < suggestionGroups.length - 1 &&
          (suggestionGroups[groupIndex++]?.suggestions ?? []).length > 0
        )
          renderedSuggestions.push(<ActionList.Divider key={getUniqueReactKey('divider', suggestionGroup.id)} />)
      }
    })

    return renderedSuggestions
  }, [activeSuggestion, suggestionGroups])

  return (
    <div className={styles.Box_1} {...testIdProps('backdrop-anchor')}>
      {
        <div
          id={`${id}-suggestions`}
          ref={suggestionsListRef}
          className={clsx(styles.Box_3, showSuggestionsOverlay && styles.showOverlay)}
          style={{
            left: `${position ? position.left : 0}px`,
          }}
        >
          <ActionList
            {...testIdProps('filter-results')}
            aria-label={isFetchingSuggestions ? 'Loading Suggestions' : 'Suggestions'}
            role="listbox"
            id={`${id}-results`}
            className={styles.ActionList_0}
            onMouseDown={e => suspendFocus(e.currentTarget)}
          >
            {showSuggestionsOverlay && suggestionGroups.some(s => s.suggestions.length > 0) && generatedSuggestions}
            {/* Only show one skeleton row when there is at least one suggestionGroup with suggestions in it */}
            {showSuggestionsOverlay && isFetchingSuggestions && (
              <div>
                {suggestionGroups.some(s => s.suggestions.length > 0) ? partialResultSkeletons : blankSlateSkeletons}
              </div>
            )}
          </ActionList>
        </div>
      }
    </div>
  )
}

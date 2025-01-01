import {GitHubAvatar} from '@github-ui/github-avatar'
import {UnsafeHTMLText} from '@github-ui/safe-html/UnsafeHTML'
import {ActionList} from '@primer/react'
import {clsx} from 'clsx'
import {useCallback} from 'react'

import {useInput, useSuggestions} from '../context'
import type {ARIAFilterSuggestion} from '../types'
import {getFilterValue} from '../utils'
import styles from './SuggestionItem.module.css'

type SuggestionItemProps = {
  /** The index of the suggestion item, used for identifying which is active */
  suggestionId: number
  /** Whether or not the item should be displayed as active */
  active?: boolean
} & ARIAFilterSuggestion

export const SuggestionItem = (suggestion: SuggestionItemProps) => {
  const {suggestionId, active, icon: Icon, iconColor, value, avatar, displayName, ariaLabel} = suggestion
  const {suggestionSelected, activeSuggestionRef} = useSuggestions()
  const {inputRef} = useInput()

  const onSuggestionSelectHandler = useCallback(() => {
    suggestionSelected(suggestion)
    inputRef.current?.focus()
  }, [inputRef, suggestion, suggestionSelected])

  const setActiveSuggestionRef = useCallback(
    (node: HTMLLIElement) => {
      if (active && node) {
        // eslint-disable-next-line react-hooks/react-compiler
        activeSuggestionRef.current = node
        node.scrollIntoView({block: 'nearest'})
      } else {
        activeSuggestionRef.current = null
      }
    },
    [active, activeSuggestionRef],
  )

  return (
    <ActionList.Item
      id={`suggestion-${suggestionId}`}
      onSelect={onSuggestionSelectHandler}
      active={active}
      role="option"
      aria-label={ariaLabel}
      aria-selected={active}
      tabIndex={-1}
      aria-labelledby={undefined}
      ref={setActiveSuggestionRef}
      className={styles.item}
    >
      {(Icon || iconColor || avatar) && (
        <ActionList.LeadingVisual>
          <div className={styles.Box_0}>
            {Icon ? (
              <Icon fill={iconColor ?? 'currentcolor'} />
            ) : iconColor ? (
              <div style={{backgroundColor: iconColor}} className={styles.Box_1} />
            ) : null}
            {avatar && (
              <GitHubAvatar
                src={avatar.url}
                alt={getFilterValue(value) ?? 'User Avatar'}
                square={false}
                className={styles.GitHubAvatar_0}
              />
            )}
          </div>
        </ActionList.LeadingVisual>
      )}
      {/* We set the inner HTML dangerously here because we can receive HTML back from the server for Labels */}
      <UnsafeHTMLText
        html={displayName ?? getFilterValue(value) ?? ''}
        className={clsx(styles.SafeHTMLText_0, suggestion.description ? styles.boldText : styles.normalText)}
      />
      {suggestion.description && suggestion.inlineDescription !== undefined && (
        <ActionList.Description
          variant={suggestion.inlineDescription ? 'inline' : 'block'}
          className={styles.ActionList_Description}
          truncate={!!suggestion.inlineDescription}
        >
          {suggestion.description}
        </ActionList.Description>
      )}
    </ActionList.Item>
  )
}

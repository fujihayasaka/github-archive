import {GitHubAvatar} from '@github-ui/github-avatar'
import {SafeHTMLText} from '@github-ui/safe-html'
import {ActionList} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
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
  const {suggestionId, active, icon, iconColor, value, avatar, displayName, ariaLabel} = suggestion
  const {suggestionSelected, activeSuggestionRef} = useSuggestions()
  const {inputRef} = useInput()

  const onSuggestionSelectHandler = useCallback(() => {
    suggestionSelected(suggestion)
    inputRef.current?.focus()
  }, [inputRef, suggestion, suggestionSelected])

  const setActiveSuggestionRef = useCallback(
    (node: HTMLLIElement) => {
      if (active && node) {
        // eslint-disable-next-line react-compiler/react-compiler
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
      {(icon || iconColor || avatar) && (
        <ActionList.LeadingVisual>
          <div className={styles.Box_0}>
            {icon ? (
              <Octicon icon={icon} fill={iconColor ?? 'currentcolor'} />
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
      <SafeHTMLText
        unverifiedHTML={displayName ?? getFilterValue(value) ?? ''}
        className={clsx(styles.SafeHTMLText_0, suggestion.description ? styles.boldText : styles.normalText)}
      />
      {suggestion.description && suggestion.inlineDescription !== undefined && (
        <ActionList.Description
          variant={suggestion.inlineDescription ? 'inline' : 'block'}
          className={styles.ActionList_Description}
        >
          {suggestion.description}
        </ActionList.Description>
      )}
    </ActionList.Item>
  )
}

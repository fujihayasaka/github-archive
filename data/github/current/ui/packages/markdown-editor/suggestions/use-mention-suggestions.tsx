// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {BONUS_POINT, DIRECT_MATCH, fuzzyScore, NO_MATCH} from '@github-ui/fuzzy-score/fuzzy-score'
import {GitHubAvatar} from '@github-ui/github-avatar'
import type {Suggestion, Trigger} from '@github-ui/inline-autocomplete/types'
import {ActionList} from '@primer/react'
import {useMemo} from 'react'

import type {UseSuggestionsHook} from '.'
import {suggestionsCalculator} from '.'
import styles from './use-mention-suggestions.module.css'

/** Could be a user, team, or organization - anything that can be mentioned. */
export type Mentionable = {
  description: string
  /** The ID of the team or the login of the user. Do not include the `@` symbol. */
  identifier: string
  avatarUrl?: string
  participant?: boolean
}

const trigger: Trigger = {
  triggerChar: '@',
}

const mentionableToSuggestion = (mentionable: Mentionable): Suggestion => ({
  value: mentionable.identifier,
  render: props => (
    <ActionList.Item {...props}>
      {mentionable.avatarUrl && (
        <ActionList.LeadingVisual>
          <GitHubAvatar size={16} src={mentionable.avatarUrl} />
        </ActionList.LeadingVisual>
      )}
      <span className={styles.identifierText}>{mentionable.identifier}</span>{' '}
      <ActionList.Description truncate>{mentionable.description}</ActionList.Description>
    </ActionList.Item>
  ),
})

const scoreSuggestion = (query: string, mentionable: Mentionable): number => {
  const fzyScore = Math.max(fuzzyScore(query, mentionable.identifier), fuzzyScore(query, mentionable.description))

  if (fzyScore === NO_MATCH) {
    return fzyScore
  } else if (fzyScore > 0 && mentionable.participant) {
    return DIRECT_MATCH
  } else {
    // Bonus points to prioritize participants
    return mentionable.participant ? fzyScore + BONUS_POINT : fzyScore
  }
}

const tieBreaker = (mentionableOne: Mentionable, mentionableTwo: Mentionable): number => {
  // Alphabetical order, we only need to look at the identifier given these are unique.
  if (mentionableOne.participant && !mentionableTwo.participant) {
    return -1
  } else if (mentionableTwo.participant && !mentionableOne.participant) {
    return 1
  }

  return mentionableOne.identifier.localeCompare(mentionableTwo.identifier)
}

export const useMentionSuggestions: UseSuggestionsHook<Mentionable> = mentionables => {
  const calculateSuggestions = useMemo(
    () => suggestionsCalculator(mentionables, scoreSuggestion, tieBreaker, mentionableToSuggestion),
    [mentionables],
  )
  return {
    calculateSuggestions,
    trigger,
  }
}

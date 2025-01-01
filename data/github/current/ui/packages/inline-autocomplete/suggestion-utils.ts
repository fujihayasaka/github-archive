import type {NullSuggestion, Suggestion} from './types'

export const isNullSuggestion = (suggestion: Suggestion): suggestion is NullSuggestion =>
  typeof suggestion === 'object' && suggestion.value === null

export const getSuggestionValue = (suggestion: Suggestion): string | null =>
  typeof suggestion === 'string' ? suggestion : suggestion.value

export const getSuggestionKey = (suggestion: Suggestion): string => {
  if (typeof suggestion === 'string') return suggestion
  if (suggestion.value === null) return suggestion.key
  return suggestion.key ?? suggestion.value
}

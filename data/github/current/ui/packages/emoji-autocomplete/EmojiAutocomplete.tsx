import type {InlineAutocompleteProps} from '@github-ui/inline-autocomplete'
import {InlineAutocomplete} from '@github-ui/inline-autocomplete'
import {useEmojiSuggestions} from '@github-ui/markdown-editor/suggestions/use-emoji-suggestions'
import {useState} from 'react'
import {emojiList} from './emojis'
import type {ShowSuggestionsEvent, Suggestions} from '@github-ui/inline-autocomplete/types'

export interface EmojiAutocompleteProps
  extends Omit<InlineAutocompleteProps, 'triggers' | 'suggestions' | 'onShowSuggestions' | 'onHideSuggestions'> {
  tone?: number
}

const emptyArray: [] = []

export function EmojiAutocomplete({tone, ...props}: EmojiAutocompleteProps) {
  const {calculateSuggestions, trigger} = useEmojiSuggestions(emojiList, {tone})

  const [suggestions, setSuggestions] = useState<Suggestions | null>(null)

  const onShowSuggestions = async ({query}: ShowSuggestionsEvent) => {
    setSuggestions('loading')
    try {
      const filteredSuggestions = await calculateSuggestions(query)
      setSuggestions(filteredSuggestions)
    } catch {
      setSuggestions(emptyArray)
    }
  }

  return (
    <InlineAutocomplete
      triggers={[trigger]}
      suggestions={suggestions}
      onShowSuggestions={onShowSuggestions}
      onHideSuggestions={() => setSuggestions(null)}
      {...props}
    />
  )
}

// eslint-disable-next-line no-restricted-imports
import {EmojiAutocomplete as GitHubEmojiAutocomplete, type EmojiAutocompleteProps} from '@github-ui/emoji-autocomplete'

import {getInitialState} from '../../helpers/initial-state'

/**
 * Wrapper around `@github-ui/emoji-autocomplete` that auto-applies tone configured in Memex.
 */
export function EmojiAutocomplete(props: Omit<EmojiAutocompleteProps, 'tone'>) {
  return <GitHubEmojiAutocomplete {...props} tone={getInitialState().themePreferences.preferred_emoji_skin_tone} />
}

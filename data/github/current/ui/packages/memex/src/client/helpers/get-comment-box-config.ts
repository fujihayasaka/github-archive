import type {CommentBoxConfig} from '@github-ui/comment-box/CommentBox'

import {getInitialState} from './initial-state'

export function getCommentBoxConfig(): CommentBoxConfig {
  const {loggedInUser, themePreferences} = getInitialState()
  return {
    pasteUrlsAsPlainText: loggedInUser?.paste_url_link_as_plain_text ?? false,
    useMonospaceFont: themePreferences?.markdown_fixed_width_font ?? false,
    emojiSkinTonePreference: themePreferences?.preferred_emoji_skin_tone,
  }
}

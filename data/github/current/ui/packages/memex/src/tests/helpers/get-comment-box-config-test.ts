import {getCommentBoxConfig} from '../../client/helpers/get-comment-box-config'
import {getInitialState} from '../../client/helpers/initial-state'
import {asMockFunction} from '../mocks/stub-utilities'

jest.mock('../../client/helpers/initial-state')

describe('getCommentBoxConfig', () => {
  it('returns the correct properties from initial state', () => {
    asMockFunction(getInitialState).mockReturnValue({
      loggedInUser: {paste_url_link_as_plain_text: true},
      themePreferences: {markdown_fixed_width_font: true, preferred_emoji_skin_tone: 1},
    } as any)

    expect(getCommentBoxConfig()).toEqual({
      pasteUrlsAsPlainText: true,
      useMonospaceFont: true,
      emojiSkinTonePreference: 1,
    })
  })

  it('handles undefined values', () => {
    asMockFunction(getInitialState).mockReturnValue({} as any)

    expect(getCommentBoxConfig()).toEqual({
      pasteUrlsAsPlainText: false,
      useMonospaceFont: false,
      emojiSkinTonePreference: undefined,
    })
  })
})

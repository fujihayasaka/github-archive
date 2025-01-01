import {emojiCharMap} from '@github-ui/emoji-autocomplete/emojis'
import escapeRegExp from 'lodash-es/escapeRegExp'

const shortCodes = Object.keys(emojiCharMap).map(key => `:${escapeRegExp(key)}:`)
const shortCodesRegex = new RegExp(shortCodes.join('|'), 'g')

export const replaceShortCodesWithEmojis = (str: string) => {
  if (!shortCodesRegex.test(str)) return str

  return str.replace(shortCodesRegex, shortCode => {
    const trimmedShortCode = shortCode.substring(1, shortCode.length - 1)
    return emojiCharMap[trimmedShortCode] ?? shortCode
  })
}

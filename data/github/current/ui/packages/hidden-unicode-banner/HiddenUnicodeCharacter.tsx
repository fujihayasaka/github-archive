import type {SafeHTMLString} from '@github-ui/safe-html'
import type React from 'react'
import {
  hasHiddenUnicodeCharacters,
  hiddenUnicodeReplacementMap,
  splitAroundHiddenUnicodeCharacters,
  type HiddenUnicodeReplacement,
} from './utils'

export function HiddenUnicodeCharacter({char}: {char: HiddenUnicodeReplacement}) {
  return <span className="hidden-unicode-replacement padded">{char}</span>
}

function hiddenUnicodeCharacterHtmlString(hiddenUnicodeReplacementString: HiddenUnicodeReplacement): SafeHTMLString {
  // We purposely don't want to escape the HTML because we know that the string will be from the replacementMap
  // eslint-disable-next-line github/unescaped-html-literal
  return `<span class="hidden-unicode-replacement">${hiddenUnicodeReplacementString}</span>` as SafeHTMLString
  // Casting to SafeHTMLString is safe because we know this exact html,
  // and we know that `hiddenUnicodeReplacementString` can only have a few specific values
}

export function showHiddenUnicodeCharacters(text: SafeHTMLString): React.ReactNode[] | null {
  if (!hasHiddenUnicodeCharacters(text)) {
    return null
  }

  // Split the text into an array of strings and hidden Unicode control characters.
  const splitText = splitAroundHiddenUnicodeCharacters(text)

  return splitText.map((segment, index) => {
    const replacement: HiddenUnicodeReplacement | undefined = hiddenUnicodeReplacementMap.get(segment)
    // eslint-disable-next-line @eslint-react/no-array-index-key
    return replacement ? <HiddenUnicodeCharacter key={index} char={replacement} /> : segment
  })
}

export function showHiddenUnicodeCharactersHTML(text: SafeHTMLString): SafeHTMLString | null {
  if (!hasHiddenUnicodeCharacters(text)) {
    return null
  }

  // Split the text into an array of strings and hidden Unicode control characters.
  const splitText = splitAroundHiddenUnicodeCharacters(text)

  const replacedSegments = splitText.map(segment => {
    const replacement: HiddenUnicodeReplacement | undefined = hiddenUnicodeReplacementMap.get(segment)
    if (!replacement) return segment
    return hiddenUnicodeCharacterHtmlString(replacement)
  })

  // Casting to SafeHTMLString is safe because we all we have done is take
  // verified html and replaced dangerous unicode characters with safe strings.
  return replacedSegments.join('') as SafeHTMLString
}

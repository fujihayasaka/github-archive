import type {SpacingOptions} from '@github-ui/code-mirror'
import {getLanguageInfo} from '@github-ui/copilot-chat/utils/language-info'

import type {File} from '../components/ContentPreview/content-preview-types'

const DEFAULT_TAB_SIZE = 8
const DEFAULT_SOFT_TAB_SIZE = 2
const MIN_TAB_SIZE = 1
const MAX_TAB_SIZE = 12

// ported from https://github.com/github/github/blob/master/app/helpers/editor_config_helper.rb
export function guessCodeMirrorSettings({language, value}: File): SpacingOptions {
  const indentStyle = guessIndentStyle(value)
  const indentSize = guessIndentSize(value, indentStyle)
  const lineWrapping = wrapMode(language)

  return {
    indentUnit: indentSize,
    indentWithTabs: indentStyle === 'tab',
    lineWrapping,
  }
}

function guessIndentStyle(value: string) {
  return /^\t/m.test(value) ? 'tab' : 'space'
}

function castTabWidth(n: number | undefined) {
  return n !== undefined && n >= MIN_TAB_SIZE && n <= MAX_TAB_SIZE ? n : DEFAULT_SOFT_TAB_SIZE
}

function guessIndentSize(value: string, indentMode: 'tab' | 'space') {
  if (indentMode === 'space') {
    const match = value.match(/^( +)[^*]/im)
    return castTabWidth(match?.[1]?.length)
  } else {
    return DEFAULT_TAB_SIZE
  }
}

function wrapMode(language: string) {
  const info = getLanguageInfo(language)
  return info?.wrap ?? false
}

import type {CopilotMarkdownExtension} from '@github-ui/copilot-markdown/extension'
import {allowAttributesHook, attributesSelector} from '@github-ui/copilot-markdown/utils'
import type {MarkedExtension} from 'marked'

import {FileBlock, fileBlockAttributes, isCompleteAttribute, languageAttribute, nameAttribute} from './FileBlock'
import styles from './FileBlock.module.css'

/** Matches code block languages in the form `language name=filename`. The presence of the `name` indicates a file. */
const fileLangRegex = /^(?<lang>[^\s]+) name=(?<name>[^\s]+)/

/** A completed code block is one that has a closing delimeter. Incomplete blocks are still streaming. */
const completeCodeBlockRegex = /\n(?:`{3,}|~{3,})\s*$/

const markedFileView: MarkedExtension = {
  extensions: [
    {
      name: 'code',
      renderer(token) {
        if (token.type !== 'code') return false

        // eslint-disable-next-line @typescript-eslint/no-unsafe-argument
        const match = fileLangRegex.exec(token.lang)
        if (!match?.groups) return false

        const {lang, name} = match.groups
        const isComplete = completeCodeBlockRegex.test(token.raw)

        const container = document.createElement('div')
        container.classList.add(styles.blockContainer)
        container.setAttribute(languageAttribute, lang ?? '')
        container.setAttribute(nameAttribute, name ?? '')
        container.setAttribute(isCompleteAttribute, isComplete ? 'true' : '')
        container.textContent = token.text

        return container.outerHTML
      },
    },
  ],
}

/**
 * Renders small blocks that can be clicked to open files for previewing. Must be configured before
 * `codeBlocksExtension` because it also operates on code blocks and should take priority.
 */
export default function fileViewExtension(): CopilotMarkdownExtension {
  return {
    marked: [markedFileView],
    sanitizer: {
      attributeHook: allowAttributesHook(fileBlockAttributes),
      allowedClassNames: [styles.blockContainer],
    },
    react: {
      selector: attributesSelector(fileBlockAttributes),
      Component: FileBlock,
    },
  }
}

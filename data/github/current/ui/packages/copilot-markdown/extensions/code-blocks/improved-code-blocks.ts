import type {CopilotMarkdownExtension} from '../../extension'
import {allowAttributesHook, attributesSelector} from '../../utils'
import {CodeBlock, codeBlockAttributes, languageAttribute} from './CodeBlock'
import styles from './CodeBlock.module.css'

export function improvedCodeBlocksExtension(): CopilotMarkdownExtension {
  return {
    marked: [
      {
        extensions: [
          {
            name: 'code',
            renderer(token) {
              if (token.type !== 'code') return false

              const lang = token.lang.split(' ')[0] ?? ''

              const element = document.createElement('div')
              element.setAttribute(languageAttribute, lang)
              element.textContent = token.text
              element.classList.add(styles.blockContainer)

              return element.outerHTML
            },
          },
        ],
      },
    ],
    sanitizer: {
      attributeHook: allowAttributesHook(codeBlockAttributes),
      allowedClassNames: [styles.blockContainer],
    },
    react: {
      selector: attributesSelector(codeBlockAttributes),
      Component: CodeBlock,
    },
  }
}

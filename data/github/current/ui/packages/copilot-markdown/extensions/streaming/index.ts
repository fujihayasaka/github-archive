import {copilotFeatureFlags} from '@github-ui/copilot-chat/utils/copilot-feature-flags'
import type {CopilotMarkdownExtension} from '../../extension'
import styles from './streaming-cursor.module.css'

import {findAndReplace} from 'hast-util-find-and-replace'
import {h} from 'hastscript'
import {visitParents} from 'unist-util-visit-parents'
import {visit} from 'unist-util-visit'
import type {Text} from 'hast'

declare module 'mdast' {
  interface Node {
    isStreaming?: boolean
  }
}

interface StreamingExtensionOptions {
  isStreaming: boolean
}

/** Indicates the termination of streaming markdown. Extensions can use this to determine if a node is currently streaming. */
export const streamingIndicatorChar = '▋'
const streamingIndicatorRegex = new RegExp(streamingIndicatorChar, 'g')

const emptyOrWhitespaceRegex = /^\s*$/

/** RegExes must match a 3-char sliding window and be start-anchored. */
const autoClosableDelimiters: Array<[openRegex: RegExp, closeRegex: RegExp, closeDelimiterStr: string]> = [
  [/^\s`/, /^[^\s]`/, '`'],
  [/^\s_/, /^[^\s]_/, '_'],
  [/^\s\*\*/, /^[^\s]\*\*/, '**'],
  [/^\s~~/, /^[^\s]~~/, '~~'],
  [/^\s\*/, /^[^\s]\*/, '*'],
  [/^\s\[/, /^[^\s]\]/, '](#)'],
  [/^\]\(/, /^[^\s]\)/, ')'],
]

/**
 * Attempt to identify common unclosed formatting tags and replace them with nodes. Only looks at the
 * currently-streaming text node, so will only apply basic inline formatting without nested tags. This isn't perfect,
 * but it doesn't have to be because any issues will resolve themselves as the content keeps streaming. This just
 * improves the appearance of streaming markdown by minimizing reformatting (which causes flickering).
 */
export function applyUnclosedFormatting(text: string) {
  // Using a set assumes we won't see any self-nested tags like `**hello **world`
  const delimiterQueue = new Set<string>()

  // By using a sliding window of three characters over text, we only have to iterate one time
  // Adding a leading whitespace to the first window gracefully handles the special case of anything that starts at the beginning
  for (let i = -1, window = ` ${text.slice(0, 2)}`; i <= text.length - 3; i++, window = text.slice(i, i + 3)) {
    // This is a lot of regex tests but the window string is very small and the regexes are very fast. We can still
    // avoid extra regex tests by checking the set
    for (const [openRegex, closeRegex, closeDelimiter] of autoClosableDelimiters)
      if (!delimiterQueue.has(closeDelimiter) && openRegex.test(window)) {
        delimiterQueue.add(closeDelimiter)
        break
      } else if (delimiterQueue.has(closeDelimiter) && closeRegex.test(window)) {
        delimiterQueue.delete(closeDelimiter)
        break
      }
  }

  // Reverse order - the first open tag encountered should be the last to be closed
  for (const delimiter of Array.from(delimiterQueue).reverse()) text += delimiter

  return text
}

/**
 * Applies styles and properties for streaming Markdown content.
 */
export default function streamingExtension({isStreaming}: StreamingExtensionOptions): CopilotMarkdownExtension {
  if (!isStreaming) return {}

  if (copilotFeatureFlags.bufferStreamingContent)
    return {
      // Inserting the caret before rendering ensures that we keep it inside the current tag (ie, at the end of a header)
      preprocessMarkdown: md => `${applyUnclosedFormatting(md)} ${streamingIndicatorChar}`,
      transformMarkdown: tree =>
        visitParents(tree, (node, ancestors) => {
          // Replace the streaming character with isStreaming property on the nodes (all the way up the tree)
          if ('value' in node && node.value?.includes(streamingIndicatorChar)) {
            node.value = node.value.replace(streamingIndicatorChar, '')
            node.isStreaming = true
            for (const ancestor of ancestors) ancestor.isStreaming = true
          }
        }),
      transformHtml: tree =>
        visit(tree, 'text', (textNode, nodeIndex, parent) => {
          // Split words apart into individual spans for fade effect
          if (parent === undefined || nodeIndex === undefined || emptyOrWhitespaceRegex.test(textNode.value)) return

          const wordNodes = textNode.value.split(' ').map((w, i, {length}) => {
            const content = i < length - 1 ? `${w} ` : w
            if (emptyOrWhitespaceRegex.test(content)) return {type: 'text', value: content} as Text
            else return h('span', content)
          })
          parent.children.splice(nodeIndex, 1, ...wordNodes)

          // Tell the walker to skip all the nodes we just added
          return nodeIndex + wordNodes.length
        }),
    }

  return {
    preprocessMarkdown: md => `${md} ${streamingIndicatorChar}`,
    transformHtml: tree =>
      findAndReplace(tree, [
        streamingIndicatorRegex,
        () => h('span', {class: styles.streamingCursor}, streamingIndicatorChar),
      ]),
  }
}

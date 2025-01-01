import hljs from 'highlight.js'
import type {MarkedExtension, Tokens} from 'marked'
import {markedHighlight} from 'marked-highlight'

import type {CopilotMarkdownExtension, SanitizeAttributeHook} from '../../extension'
import {improvedCodeBlocksExtension} from './improved-code-blocks'

interface CodeBlocksExtensionOptions {
  improvedCodeBlocks: boolean
}

export default function codeBlocksExtension({
  improvedCodeBlocks,
}: CodeBlocksExtensionOptions): CopilotMarkdownExtension {
  // New code blocks extension uses React
  if (improvedCodeBlocks) return improvedCodeBlocksExtension()

  const nonce = crypto.randomUUID()

  let codeCopyButtonRendering = false
  /** Modifies code blocks so that they can have a copy button. */
  const markedCopyableCodeBlocks: MarkedExtension = {
    extensions: [
      {
        name: 'code',
        renderer(token) {
          if (token.type !== 'code' || codeCopyButtonRendering) return false

          const codeToken = token as Tokens.Code

          codeCopyButtonRendering = true
          // this will render the code block so we set codeCopyButtonRendering so that we return false
          // to trigger the default rendering and not an infinite loop
          const html = this.parser.parse([codeToken])
          codeCopyButtonRendering = false
          const container = document.createElement('span')
          container.innerHTML = html

          const copyContent = token.raw.replace(/^[`~]{3,}.*?\n/, '').replace(/\n[`~]{3,}\n?$/, '')

          // setting this data attribute is what triggers the behavior to add the clipboard button
          container.setAttribute('data-snippet-clipboard-copy-content', `${nonce}:${copyContent}`)
          container.classList.add('snippet-clipboard-content')

          return container.outerHTML
        },
      },
    ],
  }

  const allowClipboardCopyAttributes: SanitizeAttributeHook = (node, data) => {
    const clipboardAttr = ['data-snippet-clipboard-copy-content', 'data-clipboard-copy-content']
    if (!clipboardAttr.includes(data.attrName)) return
    // ensuring that the value starts with our nonce so we know it came from our code
    if (!data.attrValue.startsWith(`${nonce}:`)) {
      data.keepAttr = false
      return
    }
    // remove the nonce
    data.attrValue = data.attrValue.slice(nonce.length + 1)
    // forceKeepAttr doesn't set the attribute's value to the new data.attrValue so we do it instead
    node.setAttribute(data.attrName, data.attrValue)
    data.forceKeepAttr = true
  }

  return {
    marked: [
      markedHighlight({
        langPrefix: 'hljs language-',
        highlight(code) {
          return hljs.highlightAuto(code).value
        },
      }),
      markedCopyableCodeBlocks,
    ],
    sanitizer: {
      attributeHook: allowClipboardCopyAttributes,
      allowedClassNames: ['file', 'snippet-clipboard-content', 'hljs', /^(hljs|language-|\b(blob|diff|file)-)/],
    },
  }
}

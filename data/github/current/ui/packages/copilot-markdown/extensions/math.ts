import {defaultDisplayDelimiters, defaultInlineDelimiters, markedMath} from '@github-ui/marked-math'

import type {CopilotMarkdownExtension, SanitizeAttributeHook} from '../extension'

const allowMathRendererAttributes: SanitizeAttributeHook = (node, data) => {
  if (node.nodeName === 'MATH-RENDERER' && data.attrName.match(/^(data-.*|style|class)$/)) data.forceKeepAttr = true
}

export default function mathExtension(): CopilotMarkdownExtension {
  return {
    marked: [
      markedMath({
        // ChatGPT uses escaped brackets with inside whitespace as math delimeters
        displayDelimiters: [...defaultDisplayDelimiters, {open: /\\\[\s/, close: /\s\\\]/}],
        inlineDelimiters: [...defaultInlineDelimiters, {open: /\\\( /, close: / \\\)/}],
      }),
    ],
    sanitizer: {
      allowedTagNames: ['math-renderer'],
      attributeHook: allowMathRendererAttributes,
    },
  }
}

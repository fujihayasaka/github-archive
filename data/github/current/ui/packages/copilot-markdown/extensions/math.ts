import {
  defaultDisplayDelimiters,
  defaultInlineDelimiters,
  type MarkdownMathOptions,
} from '@github-ui/markdown-math/options'
import {remarkMath} from '@github-ui/markdown-math/remark'

import type {CopilotMarkdownExtension, ReactComponentsExtension} from '../extension'
import {createElement} from 'react'

const remarkOptions: MarkdownMathOptions = {
  // Remark operates on the parsed text which does not include escaping backslashes
  displayDelimiters: [...defaultDisplayDelimiters, {open: /\[\s/, close: /\s\]/}],
  inlineDelimiters: [...defaultInlineDelimiters, {open: /\( /, close: / \)/}],
}

const reactComponents: ReactComponentsExtension = {
  // React doesn't support `className` on custom elements (and rehype-react doesn't know this), so we have to
  // rename it to `class`.
  ['math-renderer' as 'div']: ({node, children, className, ...props}) =>
    createElement('math-renderer', {...props, class: className}, children),
}

export default function mathExtension(): CopilotMarkdownExtension {
  return {
    transformMarkdown: remarkMath(remarkOptions),
    reactComponents,
  }
}

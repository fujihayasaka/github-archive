// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {streamingIndicatorChar} from '@github-ui/copilot-markdown'
import type {CopilotMarkdownExtension, ReactComponentsExtension} from '@github-ui/copilot-markdown/extension'
import {dataAttrToPropName, parseJsonAttribute} from '@github-ui/copilot-markdown/utils'
import {visit} from 'unist-util-visit'

import {FileBlock, type FileBlockProps} from './FileBlock'

const fileblockAttribute = 'data-fileblock-props'
const fileblockProperty = dataAttrToPropName(fileblockAttribute)

/** Matches code block meta in the form `name=filename`. The presence of the `name` indicates a file. */
const nameRegex = /^name=(?<name>[^\s]+)/
/**
 * Matches the file name in the first line of a code block.
 * We have this because sometimes the model does it this way, even though it shouldn't.
 */
const fileNameCodeRegex = /^name=(?<name>[^\s]+)\n?/

/** Number of lines of code to show in the block. */
const previewLines = 5

function getName(meta: string | undefined, code: string): {name?: string; code: string} {
  const nameMatch = meta && nameRegex.exec(meta)
  if (nameMatch) return {name: nameMatch.groups?.name, code}

  const codeMatch = fileNameCodeRegex.exec(code)
  if (codeMatch)
    // if the file name is on the first line of the code block, we have to remove it
    return {name: codeMatch.groups?.name, code: code.replace(fileNameCodeRegex, '')}

  return {code}
}

const reactComponents: ReactComponentsExtension = {
  code: (props, fallthrough) => {
    const fileblockProps = parseJsonAttribute<FileBlockProps>(props, fileblockAttribute)
    if (!fileblockProps) return fallthrough

    return <FileBlock {...fileblockProps}>{props.children}</FileBlock>
  },
}

/**
 * Renders small blocks that can be clicked to open files for previewing. Must be configured before
 * `codeBlocksExtension` because it also operates on code blocks and should take priority.
 */
export default function fileViewExtension(fileBlocksInMessage: string[]): CopilotMarkdownExtension {
  return {
    transformMarkdown: tree =>
      visit(tree, 'code', node => {
        const language = node.lang ?? ''
        const {name, code} = getName(node.meta ?? undefined, node.value)
        if (!name) return

        if (!fileBlocksInMessage.includes(name)) {
          fileBlocksInMessage.push(name)
        }

        const previewCode = code.split('\n').slice(0, previewLines).join('\n')

        const lineNumber = node.position?.start.line ?? 0

        node.value = previewCode
        node.data = {
          ...node.data,
          hName: 'code',
          hProperties: {
            [fileblockProperty]: JSON.stringify({
              language,
              name,
              code,
              line: lineNumber,
              isStreaming: node.isStreaming || code.includes(streamingIndicatorChar),
              isClipped: previewCode.length < code.length,
              index: fileBlocksInMessage.indexOf(name),
            } satisfies FileBlockProps),
          },
        }
      }),
    transformHtml: tree =>
      // Code nodes render as two nested elements (pre > code) by default, so we transform the html to remove the outer element
      visit(tree, 'element', (node, i, parent) => {
        const child = node.children?.[0]
        if (
          parent &&
          i !== undefined &&
          node.tagName === 'pre' &&
          node.children?.length === 1 &&
          child?.type === 'element' &&
          child.tagName === 'code' &&
          fileblockProperty in child.properties
        )
          parent.children.splice(i, 1, child)
      }),
    reactComponents,
  }
}

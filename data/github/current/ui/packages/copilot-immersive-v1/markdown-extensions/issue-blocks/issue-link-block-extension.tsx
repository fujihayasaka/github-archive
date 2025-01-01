// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import type {CopilotMarkdownExtension, ReactComponentsExtension} from '@github-ui/copilot-markdown/extension'
import {dataAttrToPropName, parseJsonAttribute} from '@github-ui/copilot-markdown/utils'
import {toString} from 'mdast-util-to-string'
import {visit} from 'unist-util-visit'

import {IssueLinkBlock, type IssueLinkBlockProps} from './IssueLinkBlock'

const issueLinkAttribute = 'data-issuelink-props'
const issueLinkProperty = dataAttrToPropName(issueLinkAttribute)

const issueLinkRegex = /\/(?<owner>[^/]+)\/(?<repo>[^/]+)\/issues\/(?<number>\d+)/

const reactComponents: ReactComponentsExtension = {
  span: (props, fallthrough) => {
    const issueLinkBlockProps = parseJsonAttribute<IssueLinkBlockProps>(props, issueLinkAttribute)
    if (!issueLinkBlockProps) return fallthrough

    return <IssueLinkBlock {...issueLinkBlockProps} />
  },
}

/**
 * Intercepts issue links and replaces them with a link that opens the issue browser
 */
export default function issueLinkExtension(): CopilotMarkdownExtension {
  return {
    transformMarkdown: tree =>
      visit(tree, 'link', node => {
        // Only select links to the current origin
        try {
          const linkOrigin = new URL(node.url, window.location.origin).origin
          if (linkOrigin !== window.location.origin) return
        } catch {
          // unparseable URL
          return
        }

        const match = issueLinkRegex.exec(node.url)
        if (!match?.groups) return
        const {owner = '', repo = '', number = ''} = match.groups

        node.data = {
          hName: 'span',
          hProperties: {
            [issueLinkProperty]: JSON.stringify({
              owner,
              repo,
              issueNumber: number,
              href: node.url,
              children: toString(node),
            } satisfies IssueLinkBlockProps),
          },
        }
      }),
    reactComponents,
  }
}

import {visit} from 'unist-util-visit'
import type {CopilotMarkdownExtension, RehypeHtmlTransformer} from '../extension'

const hastOpenLinksInNewTab: RehypeHtmlTransformer = tree =>
  visit(tree, node => {
    if (node.type !== 'element') return

    if (node.tagName === 'a' || 'target' in node.properties) {
      node.properties.target = '_blank'
      node.properties.rel = 'noopener noreferrer'
    }

    if (!('target' in node.properties) && ('xlink:href' in node.properties || 'href' in node.properties)) {
      node.properties['xlink:show'] = 'new'
    }
  })

interface LinksExtensionOptions {
  openLinksInCurrentTab?: boolean
}

export default function linksExtension({openLinksInCurrentTab}: LinksExtensionOptions): CopilotMarkdownExtension {
  return {
    transformHtml: openLinksInCurrentTab ? undefined : hastOpenLinksInNewTab,
  }
}

import styles from './links.module.css'
import type {CopilotChatReference, WebSearchReference} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import type {AfterSanitizeAttributeHook, CopilotMarkdownExtension, SanitizeAttributeHook} from '../extension'

const hovercardUrlAttribute = 'data-hovercard-url'

const allowHovercardAttributes: SanitizeAttributeHook = (node, data) => {
  switch (data.attrName) {
    case hovercardUrlAttribute:
      data.forceKeepAttr = true
      break
    // Allow href attributes on hovercard elements
    case 'href':
      data.forceKeepAttr = node.hasAttribute(hovercardUrlAttribute)
      break
  }
}

/**
 * If `to` is an absolute URL, convert it to a relative URL if it's on the same origin. Otherwise returns it unmodified.
 *
 * e.g. if you're on "https://github.com/foo/bar" and you pass in "https://github.com/biz/baz", it will return /biz/baz.
 */
function unabsoluteUrl(to: string) {
  if (to.match(/^https?:\/\//)) {
    let url: URL
    try {
      url = new URL(to, window.location.href)
    } catch {
      // if it's not a valid URL, don't worry about it
      return to
    }
    if (url.origin === window.location.origin) {
      return url.pathname + url.search + url.hash
    }
  }
  return to
}

/** Set all elements owning target to target=_blank if in immersive */
const openLinksInNewTab: AfterSanitizeAttributeHook = node => {
  if ('target' in node || node instanceof HTMLAnchorElement) {
    node.setAttribute('target', '_blank')
    // prevent https://www.owasp.org/index.php/Reverse_Tabnabbing
    node.setAttribute('rel', 'noopener noreferrer')
  }

  // set non-HTML/MathML links to xlink:show=new
  if (
    !node.hasAttribute('target') &&
    // eslint-disable-next-line github/get-attribute
    (node.hasAttribute('xlink:href') || node.hasAttribute('href'))
  ) {
    // eslint-disable-next-line github/get-attribute
    node.setAttribute('xlink:show', 'new')
  }
}

interface LinksExtensionOptions {
  openLinksInCurrentTab?: boolean
  references?: CopilotChatReference[]
}

export default function linksExtension({
  openLinksInCurrentTab,
  references,
}: LinksExtensionOptions): CopilotMarkdownExtension {
  const enrichLinksWithIcons: AfterSanitizeAttributeHook = node => {
    // add classes to prettify links to certain resources
    if (node instanceof HTMLAnchorElement) {
      const originalHref = node.getAttribute('href')
      if (originalHref) {
        let href = unabsoluteUrl(originalHref)
        if (href.startsWith('/')) {
          href = href.slice(1)
          const parts = href.split('/')
          // file (/primer/react/blob/main/packages/react/src/Box/Box.tsx)
          if (parts.length > 3 && parts[2] === 'blob') {
            // snippet (/primer/react/blob/main/packages/react/src/Box/Box.tsx#L17-L24)
            if (parts[parts.length - 1]?.match(/#L\d+(-L\d+)?$/)) {
              node.classList.add(styles.snippet, styles.iconLink)
            } else {
              node.classList.add(styles.file, styles.iconLink)
            }
          }
          // commit (/primer/react/commit/a3355a5483e37bebe077c7aa000ae8e4ed0f77b9)
          if (parts.length === 4 && parts[2] === 'commit' && parts[3]?.match(/^[0-9a-f]{40}$/i)) {
            node.classList.add(styles.commit, styles.iconLink)
          }
        }
        // bing result
        const bingRefs = references?.filter(ref => ref.type === 'web-search') as WebSearchReference[] | null
        if (bingRefs?.some(ref => ref.results.some(result => result.url === originalHref))) {
          node.classList.add(styles.bing, styles.colorIconLink)
        }
      }
    }
  }

  return {
    sanitizer: {
      attributeHook: allowHovercardAttributes,
      afterAttributesHook: (...args) => {
        if (!openLinksInCurrentTab) openLinksInNewTab(...args)
        enrichLinksWithIcons(...args)
      },
      allowedClassNames: Object.values(styles),
    },
  }
}

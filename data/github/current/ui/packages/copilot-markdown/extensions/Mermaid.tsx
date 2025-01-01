import {useMemo} from 'react'
import {visit} from 'unist-util-visit'
import {dataAttrToPropName, parseJsonAttribute} from '../utils'
import type {CopilotMarkdownExtension, ReactComponentsExtension} from '../extension'
import {Spinner} from '@primer/react'
import styles from './Mermaid.module.css'
import {clsx} from 'clsx'

// Define the property names for our Mermaid diagram
const mermaidAttribute = 'data-mermaid-props'
const mermaidProperty = dataAttrToPropName(mermaidAttribute)

interface MermaidProps {
  code: string
  identity: string
  viewscreenHost: string
}

interface MermaidExtensionOptions {
  viewscreenHost: string
}

export function MermaidRenderer({code, identity, viewscreenHost}: MermaidProps) {
  // Create the viewscreen URL using the provided host or the default
  const host = viewscreenHost
  const viewscreenPath = '/markdown/mermaid'
  const viewscreenUrl = `${host}${viewscreenPath}`

  // Base64 encode the Mermaid code for the viewscreen service
  const encodedData = useMemo(() => btoa(encodeURIComponent(code)), [code])

  return (
    <section
      className={clsx('js-render-needs-enrichment', 'render-needs-enrichment', styles.diagramContainer)}
      data-identity={identity}
      data-host={host}
      data-src={`${viewscreenUrl}?data=${encodedData}`}
      data-type="mermaid"
      aria-label="Mermaid diagram rendered output container"
    >
      <div className="js-render-enrichment-target" data-json={JSON.stringify({data: code})} data-plain={code}>
        <div className={styles.hiddenSourceCode}>
          <pre lang="mermaid">{code}</pre>
        </div>
      </div>
      <span className={clsx('js-render-enrichment-loader', styles.loaderContainer)} role="presentation">
        <Spinner />
      </span>
    </section>
  )
}

const reactComponents: ReactComponentsExtension = {
  code: (props, fallthrough) => {
    const isMermaid = props.className?.includes('language-mermaid')

    if (!isMermaid) return fallthrough

    const mermaidProps = parseJsonAttribute<MermaidProps>(props, mermaidAttribute)
    if (!mermaidProps) return fallthrough

    return (
      <MermaidRenderer
        code={mermaidProps.code}
        identity={mermaidProps.identity}
        viewscreenHost={mermaidProps.viewscreenHost}
      />
    )
  },
}

export default function mermaidExtension(options: MermaidExtensionOptions): CopilotMarkdownExtension {
  return {
    transformMarkdown: tree =>
      visit(tree, 'code', node => {
        if (node.lang !== 'mermaid') return

        node.data = {
          ...node.data,
          hName: 'code',
          hProperties: {
            className: ['language-mermaid'],
            [mermaidProperty]: JSON.stringify({
              code: node.value,
              identity: `mermaid-${Math.random().toString(36).slice(2, 11)}`,
              viewscreenHost: options.viewscreenHost,
            } satisfies MermaidProps),
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
          mermaidProperty in child.properties
        )
          parent.children.splice(i, 1, child)
      }),
    reactComponents,
  }
}

import {MarkdownViewer} from '@github-ui/markdown-viewer'
import {forwardRef, useMemo, useRef, useState} from 'react'

import {transformContentToHTML} from './render-markdown'
import type {CopilotMarkdownExtension} from './extension'
import atMentionsExtension from './extensions/at-mentions'
import codeBlocksExtension from './extensions/code-blocks'
import mathExtension from './extensions/math'
import linksExtension from './extensions/links'
import type {
  CopilotAnnotations,
  CopilotChatAgent,
  CopilotChatReference,
} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {useIsomorphicLayoutEffect, useRefObjectAsForwardedRef} from '@primer/react'
import {Block, type BlockProps} from './Block'
import {clsx} from 'clsx'
import styles from './MarkdownRenderer.module.css'
import vulnerabilitiesExtension from './extensions/vulnerabilities'
import publicCodeReferencesExtension from './extensions/public-code-references'

export interface MarkdownRendererProps {
  /** Markdown to render. */
  markdown: string
  /** Callback when a link is clicked. `preventDefault` to stop navigation. */
  onLinkClick?: (event: MouseEvent) => void
  /** By default, links will open in a new tab. Set to `false` to open links in the current tab instead. */
  openLinksInCurrentTab?: boolean
  /** Class(es) to apply to the container element. */
  className?: string
  /** Configuration for the public code references and vulnerabilities extensions. */
  references?: CopilotChatReference[]
  /** Configuration for the annotations extension. */
  annotations?: CopilotAnnotations
  /** Configuration for the at-mentions extension. */
  agents?: CopilotChatAgent[]
  /** Callback to fetch agents for the at-mentions extension. */
  fetchAgents?: () => Promise<CopilotChatAgent[]>
  /** Set to `true` to render code blocks as rich React blocks. */
  improvedCodeBlocks?: boolean
  /** Extensions to apply to the markdown **/
  extensions?: CopilotMarkdownExtension[]
}

const emptyArray = [] as const

export const MarkdownRenderer = forwardRef<HTMLDivElement, MarkdownRendererProps>(function MarkdownRenderer(
  {
    markdown,
    onLinkClick,
    agents,
    fetchAgents,
    improvedCodeBlocks = false,
    openLinksInCurrentTab,
    references,
    annotations,
    className,
    extensions: additionalExtensions,
  },
  forwardedRef,
) {
  const extensions = useMemo(() => {
    const result: CopilotMarkdownExtension[] = [
      atMentionsExtension({agents, fetchAgents}),
      // More specific extensions must go last! So math (which uses `math` code blocks) and files (which use
      // `lang name=filename` code blocks) must follow the codeBlocksExtension
      codeBlocksExtension({improvedCodeBlocks}),
      mathExtension(),
      linksExtension({openLinksInCurrentTab, references}),
    ]

    if (annotations?.CodeVulnerability)
      result.push(vulnerabilitiesExtension({vulnerabilities: annotations.CodeVulnerability}))

    if (annotations?.PublicCodeReference)
      result.push(publicCodeReferencesExtension({references: annotations.PublicCodeReference}))

    if (additionalExtensions) result.push(...additionalExtensions)

    return result
  }, [
    additionalExtensions,
    agents,
    annotations?.CodeVulnerability,
    annotations?.PublicCodeReference,
    fetchAgents,
    improvedCodeBlocks,
    openLinksInCurrentTab,
    references,
  ])

  const html = useMemo(() => transformContentToHTML(markdown, extensions), [markdown, extensions])

  const ref = useRef<HTMLDivElement>(null)
  useRefObjectAsForwardedRef(forwardedRef, ref)

  // Memoize the MarkdownViewer so that when we trigger the second render by updating the blocks array, the
  // viewer doesn't disrupt our efforts by re-rendering its in DOM
  const markdownViewer = useMemo(
    () => (
      <MarkdownViewer
        onLinkClick={onLinkClick}
        verifiedHTML={html}
        ref={ref}
        className={clsx(styles.container, className)}
      />
    ),
    [className, html, onLinkClick],
  )

  // We can't render blocks on the first render because they depend on (and modify) the rendered HTML, so we store
  // blocks in state and update the array in an effect to trigger a second render
  const [blocks, setBlocks] = useState<readonly BlockProps[]>(emptyArray)
  useIsomorphicLayoutEffect(() => {
    if (!ref.current) {
      setBlocks(emptyArray)
      return
    }

    const result: BlockProps[] = []

    for (const {react} of extensions)
      if (react)
        for (const target of ref.current.querySelectorAll<HTMLDivElement>(react.selector))
          result.push({
            target,
            Component: react.Component,
          })

    setBlocks(result)

    // We want to reinject the blocks every time MarkdownViewer re-renders and clears the blocks
  }, [markdownViewer])

  return (
    <>
      {markdownViewer}

      {blocks.map((props, index) => (
        // It's safe to use indexes as keys here since the order is consistent across renders
        // eslint-disable-next-line @eslint-react/no-array-index-key
        <Block {...props} key={index} />
      ))}
    </>
  )
})

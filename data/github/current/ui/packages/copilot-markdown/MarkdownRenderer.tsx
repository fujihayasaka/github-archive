import {forwardRef, useMemo, useEffect, useState} from 'react'

import codeBlocksExtension from './extensions/code-blocks'
import mathExtension from './extensions/math'
import linksExtension from './extensions/links'
import {clsx} from 'clsx'
import styles from './MarkdownRenderer.module.css'
import {ExtensionContext} from './extensions/ExtensionContext'

import ReactMarkdown from 'react-markdown'
import remarkGfm from 'remark-gfm'
import rehypeHighlight from 'rehype-highlight'
import {all} from 'lowlight'

import {useCombinedComponents} from './combine-components'
import type {CopilotMarkdownExtension} from './extension'

import {copilotFeatureFlags} from '@github-ui/copilot-chat/utils/copilot-feature-flags'
import type {PluggableList} from 'unified'
import streamingExtension from './extensions/streaming'

// eslint-disable-next-line no-barrel-files/no-barrel-files
export {streamingIndicatorChar} from './extensions/streaming'

/**
 * Apply this class to elements to suppress the fade-in animation. This should only be done as a workaround if there
 * is a conflicting animation already applied (ie, to `Spinner` components).
 */
export const disableStreamingFadeIn = styles.noFade

export interface MarkdownRendererProps {
  /** Markdown to render. */
  markdown: string
  /** Callback when a link is clicked. `preventDefault` to stop navigation. */
  onLinkClick?: (event: MouseEvent) => void
  /** By default, links will open in a new tab. Set to `false` to open links in the current tab instead. */
  openLinksInCurrentTab?: boolean
  /** Class(es) to apply to the container element. */
  className?: string
  /** Extensions to apply to the markdown **/
  extensions?: readonly CopilotMarkdownExtension[]
  /** Show the streaming cursor and buffer incoming content. */
  isStreaming?: boolean
  /** Chat mode, for telemetry. */
  chatMode?: 'assistive' | 'immersive'
}

type InnerMarkdownRendererProps = Pick<
  MarkdownRendererProps,
  'markdown' | 'extensions' | 'onLinkClick' | 'className' | 'isStreaming'
>

const emptyArray = [] as const

const STREAMING_FADE_DURATION_MS = 750

const ReactMarkdownRenderer = forwardRef<HTMLDivElement, InnerMarkdownRendererProps>(function ReactMarkdownRenderer(
  {className, markdown, extensions = emptyArray, isStreaming},
  ref,
) {
  const isEmpty = markdown.length === 0
  const isPending = isStreaming && isEmpty

  const remarkPlugins: PluggableList = [
    remarkGfm,
    ...extensions.map(e => (e.transformMarkdown ? () => e.transformMarkdown : undefined)).filter(e => !!e),
  ]
  const rehypePlugins: PluggableList = [
    [rehypeHighlight, {languages: all}],
    ...extensions.map(e => (e.transformHtml ? () => e.transformHtml : undefined)).filter(e => !!e),
  ]

  const components = useCombinedComponents(extensions)

  let preprocessedMarkdown = markdown
  for (const extension of extensions)
    preprocessedMarkdown = extension.preprocessMarkdown?.(preprocessedMarkdown) ?? preprocessedMarkdown

  // Keep the fade-in animation class activated until the fade completes
  const [fadingInContent, setFadingInContent] = useState(isStreaming)
  useEffect(() => {
    if (!isStreaming) {
      const timeout = setTimeout(() => {
        setFadingInContent(false)
      }, STREAMING_FADE_DURATION_MS)
      return () => clearTimeout(timeout)
    } else {
      setFadingInContent(true)
    }
  }, [isStreaming])

  return (
    <div
      ref={ref}
      className={clsx(
        'markdown-body',
        styles.container,
        className,
        fadingInContent && copilotFeatureFlags.bufferStreamingContent && styles.fadeInContent,
      )}
      style={
        {
          '--MarkdownRenderer_streaming-fade-duration': `${STREAMING_FADE_DURATION_MS}ms`,
        } as React.CSSProperties
      }
      data-copilot-markdown
    >
      {copilotFeatureFlags.bufferStreamingContent && isPending && (
        <>
          <span className="sr-only">Waiting for reply…</span>
          <span className={clsx(styles.pendingCursor, styles.noFade)} role="presentation">
            ▋
          </span>
          {/* Ensures container doesn't collapse to zero-height when empty */}
          &nbsp;
        </>
      )}
      <ReactMarkdown remarkPlugins={remarkPlugins} rehypePlugins={rehypePlugins} components={components}>
        {preprocessedMarkdown}
      </ReactMarkdown>
    </div>
  )
})

export const MarkdownRenderer = forwardRef<HTMLDivElement, MarkdownRendererProps>(function MarkdownRenderer(
  {isStreaming = false, chatMode, extensions: additionalExtensions, openLinksInCurrentTab, ...props},
  ref,
) {
  const extensions = useMemo(() => {
    const result: CopilotMarkdownExtension[] = [
      // More specific extensions must go last! So math (which uses `math` code blocks) and files (which use
      // `lang name=filename` code blocks) must follow the codeBlocksExtension
      codeBlocksExtension(),
      mathExtension(),
      linksExtension({openLinksInCurrentTab}),
    ]

    result.push(streamingExtension({isStreaming}))

    if (additionalExtensions) result.push(...additionalExtensions)

    return result
  }, [additionalExtensions, openLinksInCurrentTab, isStreaming])

  return (
    <ExtensionContext.Provider value={useMemo(() => ({isStreaming, chatMode}), [isStreaming, chatMode])}>
      <ReactMarkdownRenderer ref={ref} extensions={extensions} isStreaming={isStreaming} {...props} />
    </ExtensionContext.Provider>
  )
})

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

import type {PluggableList} from 'unified'

import {useCombinedComponents} from './combine-components'
import type {CopilotMarkdownExtension} from './extension'

import streamingExtension from './extensions/streaming'
import type {CopilotAnnotations} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {useClientValue} from '@github-ui/use-client-value'

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
  /** Optional invisible header value for screen readers */
  accessibleHeader?: string
  /** Annotations to show in the code blocks. */
  copilotAnnotations?: CopilotAnnotations
  /** Whether or not code lines should be wrapped in CodeBlocks */
  wrapCodeLines?: boolean
  /** Callback when the wrapCodeLines setting is changed */
  onWrapCodeLinesChange?: (wrap: boolean) => void
}

const emptyArray = [] as const

export const STREAMING_FADE_DURATION_MS = 750

export const MarkdownRenderer = forwardRef<HTMLDivElement, MarkdownRendererProps>(function ReactMarkdownRenderer(
  {
    className,
    markdown,
    chatMode,
    openLinksInCurrentTab,
    extensions: additionalExtensions = emptyArray,
    isStreaming,
    accessibleHeader,
    copilotAnnotations,
    wrapCodeLines,
    onWrapCodeLinesChange,
  },
  ref,
) {
  // Keep the fade-in animation class activated until the fade completes
  const [fadingInContent, setFadingInContent] = useState(isStreaming ?? false)
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

  const extensions = useMemo(
    () => [
      // More specific extensions must go last! So math (which uses `math` code blocks) and files (which use
      // `lang name=filename` code blocks) must follow the codeBlocksExtension
      codeBlocksExtension(),
      mathExtension(),
      linksExtension({openLinksInCurrentTab}),
      streamingExtension({isStreaming: fadingInContent}),
      ...additionalExtensions,
    ],
    [additionalExtensions, openLinksInCurrentTab, fadingInContent],
  )

  const remarkPlugins: PluggableList = [
    remarkGfm,
    ...extensions.map(e => (e.transformMarkdown ? () => e.transformMarkdown : undefined)).filter(e => !!e),
  ]

  const [rehypePlugins] = useClientValue<PluggableList>(
    () => [
      [rehypeHighlight, {languages: all}],
      ...extensions.map(e => (e.transformHtml ? () => e.transformHtml : undefined)).filter(e => !!e),
    ],
    [],
    [],
  )

  const components = useCombinedComponents(extensions)

  const preprocessedMarkdown = extensions.reduce((md, ext) => ext.preprocessMarkdown?.(md) ?? md, markdown)

  return (
    <ExtensionContext.Provider
      value={useMemo(
        () => ({isStreaming, chatMode, copilotAnnotations, wrapCodeLines, onWrapCodeLinesChange}),
        [isStreaming, chatMode, copilotAnnotations, wrapCodeLines, onWrapCodeLinesChange],
      )}
    >
      {accessibleHeader && <h3 className="sr-only">{accessibleHeader}</h3>}
      <div
        ref={ref}
        className={clsx('markdown-body', styles.container, className, fadingInContent && styles.fadeInContent)}
        style={{
          '--MarkdownRenderer_streaming-fade-duration': `${STREAMING_FADE_DURATION_MS}ms`,
        }}
        data-copilot-markdown
      >
        <ReactMarkdown remarkPlugins={remarkPlugins} rehypePlugins={rehypePlugins} components={components}>
          {preprocessedMarkdown}
        </ReactMarkdown>
      </div>
    </ExtensionContext.Provider>
  )
})

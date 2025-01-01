import type React from 'react'
import ReactMarkdown from 'react-markdown'
import remarkGfm from 'remark-gfm'
import {useHunks} from '../utils/HunkContext'
import {Diff} from './Diff'
import {useEffect, useRef} from 'react'
import {useHeadings, type Heading} from '../utils/HeadingContext'
import styles from './MarkdownWalkthrough.module.css'
interface MarkdownWalkthroughProps {
  markdownContent: string
}

interface CodeComponentProps extends React.HTMLProps<HTMLElement> {
  inline?: boolean
  node?: {
    children?: Array<{
      position?: unknown
    }>
  }
}

const MarkdownWalkthrough: React.FC<MarkdownWalkthroughProps> = ({markdownContent}) => {
  const {clearHeadings, setHeadings} = useHeadings()
  const {getHunkById} = useHunks()
  const containerRef = useRef<HTMLDivElement>(null)
  const isFirstRender = useRef(true)
  const processedContent = markdownContent.replace(/\\n/g, '\n\n')

  // Extract headings from the DOM after render
  useEffect(() => {
    if (!containerRef.current) return

    // Clear headings on first render
    if (isFirstRender.current) {
      clearHeadings()
      isFirstRender.current = false
    }

    // Find all h2 and h3 elements in the container
    const headingElements = containerRef.current.querySelectorAll('h2, h3')
    const headings: Heading[] = []
    let currentH2: Heading | null = null

    for (const el of headingElements) {
      const text = el.textContent || ''
      const id = el.id || slugify(text)
      const level = el.tagName.toLowerCase() === 'h2' ? 2 : 3
      const heading: Heading = {id, text, level}

      if (level === 2) {
        currentH2 = heading
      } else if (level === 3 && currentH2) {
        heading.parentId = currentH2.id
      }

      headings.push(heading)
    }

    setHeadings(headings)

    // Cleanup on unmount
    return () => {
      clearHeadings()
    }
  }, [clearHeadings, setHeadings, processedContent])

  return (
    <div ref={containerRef} className={styles.markdownWalkthrough}>
      <ReactMarkdown
        remarkPlugins={[remarkGfm]}
        skipHtml
        components={{
          h2: ({children}) => {
            const headingText = getHeadingTextFromChildren(children)
            const id = slugify(headingText)
            return (
              <h2 id={id} className={id === 'overview' ? 'overview-heading' : undefined}>
                {children}
              </h2>
            )
          },
          h3: ({children}) => {
            const headingText = getHeadingTextFromChildren(children)
            const id = slugify(headingText)
            return <h3 id={id}>{children}</h3>
          },
          code(props: CodeComponentProps) {
            const {children} = props
            // const language = match ? match[1] : ''
            const content = String(children).replace(/\n$/, '')

            const hunkRefs = parseHunkReferences(content)
            const inline = typeof props?.node?.children?.[0]?.position !== 'undefined'
            if (inline) {
              if (hunkRefs.length === 1) {
                const hunk = hunkRefs[0] ? getHunkById(hunkRefs[0].hunkId) : null
                return hunk ? <Diff fileName={hunk.filePath} lines={hunk.lines} /> : <code {...props}>{children}</code>
              }
              // For all other inline code, render as normal
              return <code {...props}>{content}</code>
            } else {
              if (hunkRefs.length > 0) {
                // Render all hunks in sequence
                return (
                  <div>
                    {hunkRefs.map(ref => {
                      const hunk = getHunkById(ref.hunkId)
                      return hunk ? (
                        <Diff key={ref.hunkId} fileName={hunk.filePath} lines={hunk.lines} />
                      ) : (
                        <code key={`invalid-${ref.hunkId}`}>{ref.fullMatch}</code>
                      )
                    })}
                  </div>
                )
              }
              return <code {...props}>{content}</code>
            }
          },
        }}
      >
        {processedContent}
      </ReactMarkdown>
    </div>
  )
}

function parseHunkReferences(content: string): Array<{hunkId: string; fullMatch: string}> {
  const regex = /\[HUNK:(.*)\]/g
  const matches: Array<{hunkId: string; fullMatch: string}> = []
  let match

  while ((match = regex.exec(content)) !== null) {
    if (!match[1]) {
      continue
    }
    matches.push({
      hunkId: match[1].trim(),
      fullMatch: match[0],
    })
  }

  return matches
}

function slugify(text: string): string {
  return text
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/(^-|-$)/g, '')
}

// Convert React children to a string for slugify
function getHeadingTextFromChildren(children: React.ReactNode): string {
  return Array.isArray(children) ? children.join('') : String(children || '')
}

export default MarkdownWalkthrough

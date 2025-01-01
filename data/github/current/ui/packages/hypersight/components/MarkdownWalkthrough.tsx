import type React from 'react'
import ReactMarkdown from 'react-markdown'
import remarkGfm from 'remark-gfm'
import {useHunks} from '../utils/HunkContext'
import {DiffFile} from './DiffFile'
import {useEffect, useRef} from 'react'
import {useHeadings, type Heading} from '../utils/HeadingContext'
import type {DiffHunk} from '../utils/types'
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
  className?: string // Add className prop for language info
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
            const {children, className} = props
            const content = String(children).replace(/\n$/, '')
            const filePath = className ? extractFilePath(className) : null
            const hunkRefs = parseHunkReferences(content)
            const inline = typeof props?.node?.children?.[0]?.position !== 'undefined'
            const shouldRenderHunks = !inline && hunkRefs.length > 0

            if (!shouldRenderHunks) {
              return <code {...props}>{content}</code>
            }

            const hunks: DiffHunk[] = hunkRefs
              .map(ref => getHunkById(ref.hunkId))
              .filter((hunk): hunk is DiffHunk => hunk !== undefined && hunk !== null)

            if (filePath) return <DiffFile fileName={filePath} hunks={hunks} />

            // if file path isn't parsed correctly, we can fallback to mapping over the hunks and grouping by their
            // file path property
            const groupedHunks = groupHunksByFilePath(hunks)
            return (
              <>
                {Object.entries(groupedHunks).map(([path, {hunksInPath}]) => (
                  <DiffFile key={filePath} fileName={path} hunks={hunksInPath} />
                ))}
              </>
            )
          },
        }}
      >
        {processedContent}
      </ReactMarkdown>
    </div>
  )
}

function groupHunksByFilePath(hunks: DiffHunk[]): Record<string, {hunksInPath: DiffHunk[]}> {
  const hunkGroups: Record<string, {hunksInPath: DiffHunk[]}> = {}
  for (const hunk of hunks) {
    if (!hunkGroups[hunk.filePath]) {
      hunkGroups[hunk.filePath] = {hunksInPath: []}
    }
    hunkGroups[hunk.filePath]?.hunksInPath.push(hunk)
  }
  return hunkGroups
}

// Extract file path from the code block language info (className)
function extractFilePath(className: string): string | undefined {
  // className format is "language-diff:path/to/file.ts"
  const match = className.match(/language-diff:(.+)/)
  return match ? match[1] : undefined
}

type HunkMatch = {hunkId: number; fullMatch: string}
function parseHunkReferences(content: string): HunkMatch[] {
  // Match both old format [HUNK:id] and new format [HUNK:id] with multiple per code block
  const regex = /\[HUNK:([^\]]+)\]/g
  const matches: HunkMatch[] = []
  let match

  while ((match = regex.exec(content)) !== null) {
    if (!match[1]) {
      continue
    }
    matches.push({
      hunkId: parseInt(match[1].trim(), 10),
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

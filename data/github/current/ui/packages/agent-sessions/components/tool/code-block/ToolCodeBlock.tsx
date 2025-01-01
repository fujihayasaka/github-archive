import styles from './ToolCodeBlock.module.css'
import {type PropsWithChildren, useId, useState, useRef, useEffect} from 'react'
import {FoldDownIcon, FoldUpIcon} from '@primer/octicons-react'
import {Button, Stack} from '@primer/react'
import {Banner} from '@primer/react/experimental'
import {useLayoutEffect} from '@github-ui/use-layout-effect'
import {useSessionContext} from '../../../contexts/SessionContext'
import {useCurrentRepository} from '@github-ui/current-repository'
import {generateWorkflowRunLink} from '../../../utils/generate-actions-link'
import {clsx} from 'clsx'

const TRUNCATION_THRESHOLD = 10000
const HEIGHT_THRESHOLD = 150 // px

export interface ToolCodeBlockProps {
  language?: string
  characterCount?: number
  bashLoading?: boolean
  code: string
  startOffset: number
  endOffset: number
}

export function ToolCodeBlock({characterCount, bashLoading, children}: PropsWithChildren<ToolCodeBlockProps>) {
  const codeBlockLabelId = useId()
  const [isExpanded, setIsExpanded] = useState(false)
  const [isCollapsible, setIsCollapsible] = useState(false)
  const codeRef = useRef<HTMLElement>(null)
  const {session} = useSessionContext()
  const [loaderChar, setLoaderChar] = useState('|')
  const repo = useCurrentRepository()

  // Measure actual rendered height
  useLayoutEffect(() => {
    if (codeRef.current) {
      const height = codeRef.current.offsetHeight
      setIsCollapsible(height > HEIGHT_THRESHOLD)
    }
  }, [children])

  useEffect(() => {
    let intervalId: NodeJS.Timeout | undefined
    if (bashLoading) {
      const loaderChars = ['|', '/', '-', '\\']
      let currentCharIndex = 0
      intervalId = setInterval(() => {
        currentCharIndex = (currentCharIndex + 1) % loaderChars.length
        setLoaderChar(loaderChars[currentCharIndex] || '|')
      }, 250)
    } else {
      setLoaderChar('|') // Reset loader char when not loading
    }
    return () => clearInterval(intervalId)
  }, [bashLoading])

  const shouldTruncate = (characterCount ?? 0) > TRUNCATION_THRESHOLD

  return (
    <figure
      className={clsx('position-relative', styles.container, isCollapsible && !isExpanded && styles.isCollapsible)}
      aria-labelledby={codeBlockLabelId}
    >
      <div className={styles.codeContainer}>
        {/* eslint-disable-next-line jsx-a11y/no-noninteractive-tabindex */}
        <pre className={`${styles.code} ${isCollapsible && !isExpanded ? styles.collapsed : ''}`} tabIndex={0}>
          <code ref={codeRef} className={styles.codeWrap}>
            {children}
            {bashLoading && <span>{loaderChar}</span>}
          </code>
        </pre>

        {(isCollapsible || shouldTruncate) && (
          <Stack className="px-3 pb-2">
            {shouldTruncate && isExpanded && session && (
              <Banner
                aria-label="Output truncated"
                title="Output truncated"
                hideTitle
                description="Only the first 10,000 characters are shown."
                variant="warning"
                primaryAction={
                  <Banner.PrimaryAction
                    as="a"
                    href={generateWorkflowRunLink(repo.ownerLogin, repo.name, session.workflow_run_id)}
                    className={styles.fullLogsLink}
                  >
                    View full output
                  </Banner.PrimaryAction>
                }
              />
            )}

            {isCollapsible && (
              <Button
                leadingVisual={isExpanded ? FoldUpIcon : FoldDownIcon}
                onClick={() => setIsExpanded(!isExpanded)}
                aria-label={isExpanded ? 'Collapse code block' : 'Expand code block'}
                variant="invisible"
                className={clsx('fgColor-muted', !isExpanded && styles.collapsedToolButton)}
              >
                {isExpanded ? 'Show less' : 'Show more'}
              </Button>
            )}
          </Stack>
        )}
      </div>
    </figure>
  )
}

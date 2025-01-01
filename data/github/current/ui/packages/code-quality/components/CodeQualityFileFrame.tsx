import {IconButton} from '@primer/react'
import {useState} from 'react'
import styles from './CodeQualityFileFrame.module.css'
import {ChevronDownIcon, ChevronRightIcon} from '@primer/octicons-react'
import type {SafeHTMLString} from '@github-ui/safe-html'
import {clsx} from 'clsx'
import {CodeQualitySnippet} from './CodeQualitySnippet'

export interface CodeQualityFileFrameProps {
  filePath: string
  // Start line number of code snippet
  snippetStartLine: number
  // Start line number of finding
  startLine: number
  endLine: number
  startColumn: number
  endColumn: number
  codeSnippetLines: SafeHTMLString[]
}

export function CodeQualityFileFrame({
  filePath,
  snippetStartLine,
  startLine,
  endLine,
  startColumn,
  endColumn,
  codeSnippetLines,
}: React.PropsWithChildren<CodeQualityFileFrameProps>) {
  const [isOpen, setIsOpen] = useState(true)

  return (
    <div>
      <Header isOpen={isOpen} toggleOpen={() => setIsOpen(v => !v)}>
        <div className="text-mono f6">
          {filePath}:{startLine}
        </div>
      </Header>

      {isOpen && (
        <div className={styles.body}>
          {codeSnippetLines.length === 0 ? (
            <div className="flex-column flex-items-center text-center pt-4 pb-2 px-2">
              <h2 className="f4">Preview unavailable</h2>
              <p className="color-fg-muted">The file content could not be displayed.</p>
            </div>
          ) : (
            <CodeQualitySnippet
              snippetStartLine={snippetStartLine}
              startLine={startLine}
              endLine={endLine}
              startColumn={startColumn}
              endColumn={endColumn}
              codeLines={codeSnippetLines}
            />
          )}
        </div>
      )}
    </div>
  )
}

function Header(props: React.PropsWithChildren<{isOpen: boolean; toggleOpen(): void}>) {
  const {isOpen, toggleOpen, children} = props

  return (
    <div className={clsx(styles.header, !isOpen && styles.headerClosed)}>
      <IconButton
        icon={isOpen ? ChevronDownIcon : ChevronRightIcon}
        onClick={toggleOpen}
        variant="invisible"
        size="small"
        aria-label={`${isOpen ? 'Close' : 'Open'} code snippet`}
      />
      {children}
    </div>
  )
}

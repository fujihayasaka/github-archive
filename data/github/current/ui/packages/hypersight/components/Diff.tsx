import {getLineNumberWidth} from '@github-ui/diffs/diff-line-helpers'
import {UnifiedDiffLines} from '@github-ui/diffs/DiffParts'
import type {DiffLine} from '@github-ui/diffs/types'
import {ChevronDownIcon, ChevronRightIcon} from '@primer/octicons-react'
import {IconButton} from '@primer/react'
import {clsx} from 'clsx'
import {memo, useMemo, useState} from 'react'
import styles from './Diff.module.css'
import walkthroughStyles from './MarkdownWalkthrough.module.css'
/**
 * Component that shows a basic diff displayed via an HTML table.
 */
export const Diff = memo(function Diff({
  fileName,
  headerActions,
  headerPrefix,
  lines,
  initiallyCollapsed,
}: {
  fileName: string
  headerActions?: JSX.Element
  headerPrefix?: JSX.Element
  lines: DiffLine[]
  initiallyCollapsed?: boolean
}) {
  const lineWidth = getLineNumberWidth(lines)
  const [isCollapsed, setIsCollapsed] = useState(!!initiallyCollapsed)

  // Only trim first character if it's a space, plus, or minus
  const diffLines = useMemo(() => {
    return lines.map(line => {
      if (line.text !== ' ' && line.text.length > 0) {
        return {
          ...line,
          html: line.html.substring(1),
          text: line.text.substring(1),
        }
      }
      return line
    })
  }, [lines])

  return (
    // .diff-table classname provides targeting in markdown walkthrough styles
    <div className={clsx(styles.diff, isCollapsed && styles.diffCollapsed, walkthroughStyles.diffTable)}>
      <div
        className={clsx(
          styles.diffHeader,
          isCollapsed && styles.diffHeaderCollapsed,
          'd-flex flex-row flex-items-center gap-2 px-2 py-2',
        )}
      >
        {headerPrefix}
        <IconButton
          className="flex-shrink-0"
          aria-label={isCollapsed ? `expand diff: ${fileName}` : `collapse diff: ${fileName}`}
          icon={isCollapsed ? ChevronRightIcon : ChevronDownIcon}
          onClick={() => setIsCollapsed(!isCollapsed)}
          size="small"
          variant="invisible"
        />
        <code className={clsx(styles.fileName, 'f6')}>{fileName}</code>
        <div className="d-flex flex-row flex-items-center gap-2 ml-auto">{headerActions}</div>
      </div>
      {!isCollapsed && (
        // eslint-disable-next-line @github-ui/github-monorepo/no-sx
        <UnifiedDiffLines lineWidth={lineWidth} lines={diffLines} tabSize={2} sx={{borderLeft: 0, borderRight: 0}} />
      )}
    </div>
  )
})

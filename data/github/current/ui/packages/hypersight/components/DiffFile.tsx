import {getLineNumberWidth} from '@github-ui/diffs/diff-line-helpers'
import {UnifiedDiffLines} from '@github-ui/diffs/DiffParts'
import type {DiffHunk} from '../utils/types'
import {ChevronDownIcon, ChevronRightIcon} from '@primer/octicons-react'
import {IconButton} from '@primer/react'
import {clsx} from 'clsx'
import {memo, useMemo, useState} from 'react'
import styles from './DiffFile.module.css'
import walkthroughStyles from './MarkdownWalkthrough.module.css'

export const DiffFile = memo(function DiffFile({
  fileName,
  hunks,
  headerActions,
  headerPrefix,
  initiallyCollapsed,
}: {
  fileName: string
  hunks: DiffHunk[]
  headerActions?: JSX.Element
  headerPrefix?: JSX.Element
  initiallyCollapsed?: boolean
}) {
  const [isCollapsed, setIsCollapsed] = useState(!!initiallyCollapsed)

  const content = useMemo(() => {
    if (isCollapsed) return null
    return hunks.map(hunk => <HunkLines key={hunk.hunkId} hunk={hunk} />)
  }, [hunks, isCollapsed])

  return (
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
      {content}
    </div>
  )
})

function HunkLines({hunk}: {hunk: DiffHunk}) {
  const {lines} = hunk
  const lineWidth = getLineNumberWidth(lines)
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
  // eslint-disable-next-line @github-ui/github-monorepo/no-sx
  return <UnifiedDiffLines lineWidth={lineWidth} lines={diffLines} tabSize={2} sx={{borderLeft: 0, borderRight: 0}} />
}

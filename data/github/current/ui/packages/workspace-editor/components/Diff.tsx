import {getLineNumberWidth} from '@github-ui/diffs/diff-line-helpers'
import {UnifiedDiffLines} from '@github-ui/diffs/DiffParts'
import type {DiffLine} from '@github-ui/diffs/types'
import {ChevronDownIcon, ChevronRightIcon} from '@primer/octicons-react'
import {IconButton, Label} from '@primer/react'
import {clsx} from 'clsx'
import {memo, useState} from 'react'

import {rtlProofPath} from '../utilities/file-path-helpers'
import styles from './Diff.module.css'

/**
 * Component that shows a basic diff displayed via an HTML table.
 */
export const Diff = memo(function Diff({
  fileName,
  headerActions,
  headerPrefix,
  lines,
  outdated,
  initiallyCollapsed,
}: {
  fileName: string
  headerActions?: JSX.Element
  headerPrefix?: JSX.Element
  lines: DiffLine[]
  outdated: boolean
  initiallyCollapsed?: boolean
}) {
  const lineWidth = getLineNumberWidth(lines)
  const [isCollapsed, setIsCollapsed] = useState(!!initiallyCollapsed)

  return (
    <div className={clsx(styles.diff, isCollapsed && styles.diffCollapsed)}>
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
          variant="invisible"
        />
        <code className={clsx(styles.fileName, 'f6')}>{rtlProofPath(fileName)}</code>
        {outdated && <Label variant="attention">Outdated</Label>}
        <div className="d-flex flex-row flex-items-center gap-2 ml-auto">{headerActions}</div>
      </div>
      {!isCollapsed && (
        <UnifiedDiffLines lineWidth={lineWidth} lines={lines} tabSize={2} className={styles.UnifiedDiffLines} />
      )}
    </div>
  )
})

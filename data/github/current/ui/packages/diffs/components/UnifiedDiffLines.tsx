import {SafeHTMLDiv, type SafeHTMLString} from '@github-ui/safe-html'
import {Box, type SxProp} from '@primer/react'
import {clsx} from 'clsx'
import {getBackgroundColor} from '../diff-line-helpers'
import type {DiffLine, SimpleDiffLine} from '../types'
import {HunkKebabIcon} from './HunkKebabIcon'
import {UnifiedDiffTable} from './UnifiedDiffTable'
import styles from './UnifiedDiffLines.module.css'

/**
 * Presentational component for a non-interactive line number cell
 */
function LineNumberCell({line, children}: {line: SimpleDiffLine; children: React.ReactNode}) {
  return (
    <td
      className={styles.diffLineNumber}
      style={{backgroundColor: getBackgroundColor(line.type, true), textAlign: 'center'}}
    >
      <code>{children}</code>
    </td>
  )
}

/**
 * Presentational component for a non-interactive hunk cell
 * Note that it spans the entire table row
 */
function HunkCell({line}: {line: SimpleDiffLine}) {
  return (
    <td colSpan={4} className={styles.diffHunkCell} valign="top">
      <div className="d-flex flex-row">
        <HunkKebabIcon />
        <code className={styles.diffHunkText}>
          {/* Explicitly mark html as safe because it is server-sanitized */}
          <SafeHTMLDiv className={clsx(styles.diffTextInner, 'color-fg-muted')} html={line.html as SafeHTMLString} />
        </code>
      </div>
    </td>
  )
}

/**
 * Renders a non-interactive row of a unified diff line
 * Specifically for use in outdated threads, which return a slightly different set of difflines
 * This component was derived from the interactive version (CodeDiffLine) in DiffLineTableRow.tsx
 */
function UnifiedDiffRow({line}: {line: DiffLine; tabSize: number}) {
  const isHunkRow = line.type === 'HUNK'
  const showLeftNumber = line.type !== 'ADDITION'
  const showRightNumber = line.type !== 'DELETION'

  const lineMarker = line.type === 'ADDITION' ? '+' : line.type === 'DELETION' ? '-' : undefined
  const showLineMarker = !!lineMarker

  return (
    <tr>
      {isHunkRow && <HunkCell line={line} />}
      {!isHunkRow && (
        <>
          <LineNumberCell line={line}>{showLeftNumber && line.left}</LineNumberCell>
          <LineNumberCell line={line}>{showRightNumber && line.right}</LineNumberCell>
          <td className={styles.diffTextCell} style={{backgroundColor: getBackgroundColor(line.type, false)}}>
            <code
              className={clsx(
                line.type === 'ADDITION' && styles.syntaxHighlightedAdditionLine,
                line.type === 'DELETION' && styles.syntaxHighlightedDeletionLine,
              )}
            >
              {showLineMarker && <span className={styles.diffTextMarker}>{lineMarker}</span>}
              {/* Explicitly mark html as safe because it is server-sanitized */}
              <SafeHTMLDiv
                className={styles.diffTextInner}
                html={line.html as SafeHTMLString}
                style={{
                  backgroundColor: getBackgroundColor(line.type, false),
                }}
              />
            </code>
          </td>
        </>
      )}
    </tr>
  )
}

export function UnifiedDiffLines({
  sx,
  lines,
  lineWidth,
  tabSize,
}: {
  lines: DiffLine[]
  lineWidth: string
  tabSize: number
} & SxProp) {
  const diffRows = lines.map((diffline, index) => {
    const line = diffline
    // eslint-disable-next-line @eslint-react/no-array-index-key
    return <UnifiedDiffRow key={index} line={line} tabSize={tabSize} />
  })

  return (
    <Box
      as="table"
      className="tab-size"
      data-tab-size={tabSize}
      sx={{
        borderTop: 0,
        borderBottom: 0,
        borderLeft: 1,
        borderRight: 1,
        borderStyle: 'solid',
        borderColor: 'border.muted',
        ...sx,
      }}
    >
      <UnifiedDiffTable lineWidth={lineWidth}>{diffRows}</UnifiedDiffTable>
    </Box>
  )
}

import {getLineNumberWidth} from '@github-ui/diffs/diff-line-helpers'
import {threadLineLocation, UnifiedDiffLines} from '@github-ui/diffs/DiffParts'
import {type BetterSystemStyleObject, Box, type SxProp, Text} from '@primer/react'

import type {Thread} from '../types'

/**
 * Renders a static representation of a unified diff
 * Specifically for use in outdated threads, which return a slightly different set of difflines
 */
export function StaticUnifiedDiffPreview({
  sx,
  tabSize,
  thread,
  hideHeaderDetails,
  diffTableSx,
}: {tabSize: number; thread: Thread; hideHeaderDetails?: boolean; diffTableSx?: BetterSystemStyleObject} & SxProp) {
  if (!thread.subject?.diffLines || thread.subject?.diffLines.length < 1) {
    return null
  }

  const lineWidth = getLineNumberWidth(thread.subject.diffLines)

  return (
    <Box
      sx={{
        m: 3,
        border: 0,
        borderBottomWidth: 6,
        borderStyle: 'solid',
        borderColor: 'border.muted',
        borderBottomLeftRadius: 2,
        borderBottomRightRadius: 2,
        ...sx,
      }}
    >
      {!hideHeaderDetails && (
        <Box
          sx={{
            borderWidth: 1,
            borderStyle: 'solid',
            borderTopLeftRadius: 2,
            borderTopRightRadius: 2,
            borderColor: 'border.muted',
            color: 'fg.muted',
            px: 2,
            py: 1,
          }}
        >
          <Text sx={{fontSize: 0, color: 'fg.muted'}}>
            Line{' '}
            {threadLineLocation({
              originalStartLine: thread.subject.originalStartLine,
              originalEndLine: thread.subject.originalEndLine,
              startDiffSide: thread.subject.startDiffSide,
              endDiffSide: thread.subject.endDiffSide,
            })}
            , commit <code>{thread.subject.pullRequestCommit?.commit.abbreviatedOid}</code>
          </Text>
        </Box>
      )}
      <UnifiedDiffLines lineWidth={lineWidth} lines={thread.subject.diffLines} tabSize={tabSize} sx={diffTableSx} />
    </Box>
  )
}

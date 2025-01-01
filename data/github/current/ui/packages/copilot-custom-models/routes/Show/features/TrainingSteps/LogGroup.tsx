import {useMemo, type SyntheticEvent} from 'react'
import type {Log as ILog, LogGroup} from '../../../../types'
import {Log} from './Log'
import {Box, Label, Text} from '@primer/react'
import {colors} from './colors'

interface Props {
  logGroup: LogGroup
}

export function LogGroup({logGroup}: Props) {
  const {logs, name, ui_group_logs: isGrouped} = logGroup
  const sortedLogs = useMemo(() => logs.sort(sortFn), [logs])

  if (!isGrouped) return <>{renderLogs(sortedLogs)}</>

  const summary = name || 'View details'
  const isEmpty = !sortedLogs.length

  return (
    <details onToggle={onToggle}>
      <Box
        as="summary"
        sx={{
          color: colors.fg.default,
          fontFamily: 'var(--fontStack-monospace)',
          fontSize: '12px',
          lineHeight: '20px',
          width: '100%',
        }}
      >
        {summary}{' '}
        {isEmpty && <Label sx={{color: colors.fg.default, fontFamily: 'var(--fontStack-sansSerif)'}}>pending</Label>}
      </Box>
      <div>{isEmpty ? <EmptyState /> : renderLogs(sortedLogs, isGrouped)}</div>
    </details>
  )
}

function onToggle(e: SyntheticEvent<HTMLDetailsElement>) {
  e.stopPropagation()
}

function renderLogs(logs: LogGroup['logs'], isGrouped = false) {
  return logs.map(log => <Log key={`${log.logged_at}-${log.message}`} isGrouped={isGrouped} log={log} />)
}

function EmptyState() {
  return (
    <Text
      sx={{
        color: colors.fg.default,
        fontFamily: 'var(--fontStack-monospace)',
        fontSize: '12px',
        lineHeight: '20px',
        pl: '16px',
        width: '100%',
        wordBreak: 'break-word',
      }}
    >
      Logs will appear when this repository processing stage starts.
    </Text>
  )
}

function sortFn(a: ILog, b: ILog): -1 | 0 | 1 {
  return a.logged_at < b.logged_at ? -1 : a.logged_at > b.logged_at ? 1 : 0
}

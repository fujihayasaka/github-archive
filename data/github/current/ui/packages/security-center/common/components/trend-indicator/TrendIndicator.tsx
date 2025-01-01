import {ArrowDownIcon, ArrowUpIcon, PulseIcon} from '@primer/octicons-react'
import {Box, Spinner} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import {clsx} from 'clsx'

import styles from './TrendIndicator.module.css'

type Props = {
  loading: boolean
  error: boolean
  value?: number
  flipColor?: boolean
  sx?: object
  maxValue?: number
  metric?: string
}

export function TrendIndicator({
  loading,
  error,
  value,
  flipColor = false,
  sx,
  maxValue = 999,
  metric = '%',
}: Props): JSX.Element {
  if (error) {
    return <></>
  }

  if (loading || value === undefined) {
    return (
      <Spinner
        data-testid="trend-indicator-spinner"
        size="small"
        sx={{
          ...sx,
        }}
        className={styles.Spinner}
      />
    )
  }

  let color = 'fg.muted'
  let icon = PulseIcon
  if (value > 0) {
    color = flipColor ? 'success.fg' : 'closed.fg'
    icon = ArrowUpIcon
  } else if (value < 0) {
    color = flipColor ? 'closed.fg' : 'success.fg'
    icon = ArrowDownIcon
  }

  return (
    <Box
      className={clsx('text-small', styles.Box)}
      sx={{
        ...sx,
        color,
      }}
    >
      <Octicon icon={icon} />{' '}
      <span data-testid="trend-indicator-value">
        {value > maxValue ? `${maxValue}${metric}+` : `${value}${metric}`}
      </span>
    </Box>
  )
}

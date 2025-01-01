import type {SxProp} from '@primer/react'
import {Box, Text} from '@primer/react'
import {Stack} from '@primer/react/experimental'

export interface CounterProps extends SxProp {
  count: number
  total?: number
  metric?: {singular: string; plural: string} | string
  variant?: 'default' | 'wide'
}

function Counter({variant = 'default', ...props}: CounterProps) {
  const countStyle = {
    fontSize: '24px',
    fontWeight: 400,
    lineHeight: '24px',
    mb: 1,
  }

  const mutedStyle = {
    fontSize: '16px',
    fontWeight: 400,
    color: 'fg.muted',
  }

  function pluralizeCountLabel() {
    if (props.metric === undefined) {
      return null
    }

    const style = props.total ? mutedStyle : countStyle
    let metric = ''

    if (typeof props.metric === 'string') {
      metric = props.metric
    } else {
      metric = props.count === 1 ? props.metric.singular : props.metric.plural
    }

    return <Text sx={{...style, ml: 1}}> {metric.toLowerCase()}</Text>
  }

  function renderCount() {
    const numberFormatter = Intl.NumberFormat('en-US', {
      notation: 'standard',
    })
    const count = numberFormatter.format(props.count)

    return (
      <Stack
        direction="horizontal"
        justify="space-between"
        gap="condensed"
        className={variant === 'wide' ? 'width-full' : undefined}
      >
        <Text sx={countStyle}>{count}</Text>
        {props.total !== undefined && <Text sx={mutedStyle}>of {numberFormatter.format(props.total)}</Text>}
      </Stack>
    )
  }

  const boxStyle = {
    display: 'flex',
    ...props.sx,
  }

  return (
    <Box sx={boxStyle}>
      {renderCount()}
      {pluralizeCountLabel()}
    </Box>
  )
}

Counter.displayName = 'DataCard.Counter'

export default Counter

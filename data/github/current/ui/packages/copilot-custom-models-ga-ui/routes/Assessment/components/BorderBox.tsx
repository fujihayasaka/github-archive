import {Box} from '@primer/react'
import type {BoxProps} from '@primer/react'
import {theme} from '../../../theme'

export function BorderBox({sx, ...props}: BoxProps) {
  return (
    <Box
      sx={{
        border: theme.border,
        borderRadius: '8px',
        p: '16px',
        ...sx,
      }}
      {...props}
    />
  )
}

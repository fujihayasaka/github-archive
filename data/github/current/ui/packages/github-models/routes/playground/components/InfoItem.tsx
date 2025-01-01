import type {PropsWithChildren} from 'react'
import {Box, type BoxProps} from '@primer/react'

interface InfoItemProps extends PropsWithChildren<BoxProps> {
  isInline: boolean
  label?: string
}

export function InfoItem({isInline = false, children, label, ...rest}: InfoItemProps) {
  return (
    <Box
      sx={{
        display: 'flex',
        flexDirection: 'column',
        fontSize: 1,
        flex: 1,
        ...(isInline && {
          flexBasis: '140px',
          mr: [2, 2, 0],
        }),
      }}
    >
      {label && <Box sx={{color: 'fg.default', fontSize: 1, fontWeight: 'semibold', mb: 0}}>{label}</Box>}
      <Box sx={{color: 'fg.muted'}} {...rest}>
        {children}
      </Box>
    </Box>
  )
}

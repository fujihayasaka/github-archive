import type {ReactNode} from 'react'
import {Box, type BetterSystemStyleObject} from '@primer/react'

type RoundedBoxProps = {
  sx?: BetterSystemStyleObject
  children: ReactNode
}
export function RoundedBox({sx, children}: RoundedBoxProps) {
  return (
    <Box
      className="Box"
      sx={{
        ...sx,
        '> :first-child': {
          borderBottomColor: 'border.default',
          borderBottomWidth: 1,
          borderBottomStyle: 'solid',
          borderTopLeftRadius: 2,
          borderTopRightRadius: 2,
        },
        '> :only-child': {
          borderBottomWidth: 0,
        },
      }}
    >
      {children}
    </Box>
  )
}

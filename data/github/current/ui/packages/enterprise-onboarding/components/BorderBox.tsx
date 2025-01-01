import {Box, type BetterSystemStyleObject} from '@primer/react'

interface BorderBoxProps {
  children: React.ReactNode
  sx?: BetterSystemStyleObject
}

export function BorderBox({children, sx, ...rest}: BorderBoxProps) {
  return (
    <Box
      sx={{
        display: 'flex',
        border: 1,
        borderStyle: 'solid',
        borderColor: 'border.muted',
        borderRadius: 2,
        ...sx,
      }}
      {...rest}
    >
      {children}
    </Box>
  )
}

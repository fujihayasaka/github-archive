import {LightBulbIcon} from '@primer/octicons-react'
import {Box, Text} from '@primer/react'
import type {PropsWithChildren} from 'react'
import {theme} from '../../../theme'

type Props = PropsWithChildren

export function InsetBanner({children}: Props) {
  return (
    <Box
      sx={{
        alignItems: 'flex-start',
        backgroundColor: theme.color.bgInset,
        borderTop: theme.border,
        display: 'flex',
        p: '8px',
      }}
    >
      <Box
        sx={{
          alignItems: 'center',
          color: theme.color.fgAccent,
          display: 'flex',
          height: '32px',
          justifyContent: 'center',
          width: '32px',
        }}
      >
        <LightBulbIcon size={16} />
      </Box>

      <Text sx={{color: theme.color.fgDefault, py: '6px', ...theme.typography.body.medium}}>{children}</Text>
    </Box>
  )
}

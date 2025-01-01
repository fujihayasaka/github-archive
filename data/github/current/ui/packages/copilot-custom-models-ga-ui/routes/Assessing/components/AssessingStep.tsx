import {Box, Text} from '@primer/react'
import type {Icon as IIcon} from '@primer/octicons-react'
import {theme} from '../../../theme'

interface Props {
  Icon: IIcon
  text: string
}

export function AssessingStep({Icon, text}: Props) {
  return (
    <Box
      sx={{
        alignItems: 'center',
        backgroundColor: 'var(--bgColor-muted)',
        borderRadius: '6px',
        display: 'flex',
        gap: '24px',
        height: '64px',
        p: '16px',
        width: '430px',
      }}
    >
      <Box
        sx={{
          alignItems: 'center',
          border: '2px solid var(--borderColor-success-muted)',
          borderRadius: '50%',
          color: theme.color.fgMuted,
          display: 'flex',
          height: '32px',
          justifyContent: 'center',
          svg: {color: `${theme.color.fgMuted} !important`},
          width: '32px',
        }}
      >
        <Icon size={16} />
      </Box>
      <Text sx={{color: theme.color.fgDefault, ...theme.typography.body.mediumBold}}>{text}</Text>
    </Box>
  )
}

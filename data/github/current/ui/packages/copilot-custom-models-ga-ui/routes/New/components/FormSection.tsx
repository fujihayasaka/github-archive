import type {Icon} from '@primer/octicons-react'
import {Box, Heading, Text} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import type {PropsWithChildren} from 'react'
import {theme} from '../../../theme'

interface Props extends PropsWithChildren {
  icon: Icon
  subtitle?: string
  title: string
}

export function FormSection({children, icon, subtitle, title}: Props) {
  return (
    <Box sx={{display: 'flex', gap: '8px', width: '100%'}}>
      <Box
        sx={{
          alignItems: 'center',
          display: 'flex',
          flexDirection: 'column',
          gap: '2px',
          justifyContent: 'center',
        }}
      >
        <Box
          sx={{
            alignItems: 'center',
            backgroundColor: 'var(--bgColor-muted)',
            borderRadius: '9999px',
            display: 'flex',
            height: '32px',
            justifyContent: 'center',
            width: '32px',
          }}
        >
          <Octicon color={theme.color.fgMuted} icon={icon} aria-hidden="true" sx={{height: '16px', width: '16px'}} />
        </Box>
        <Box
          sx={{backgroundColor: 'blue', border: '1.5px solid var(--borderColor-default)', flexGrow: 1, width: '1px'}}
        />
      </Box>

      <Box
        sx={{
          color: theme.color.fgDefault,
          display: 'flex',
          flexDirection: 'column',
          gap: '16px',
          justifyContent: 'center',
          pb: '6px',
          width: '100%',
        }}
      >
        <Box sx={{display: 'flex', flexDirection: 'column', gap: '2px', width: '100%'}}>
          <Heading as="h4" sx={{my: '6px', ...theme.typography.body.mediumBold}}>
            {title}
          </Heading>
          <Text sx={{color: theme.color.fgMuted, ...theme.typography.body.small}}>{subtitle}</Text>
        </Box>

        {children}
      </Box>
    </Box>
  )
}

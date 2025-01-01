import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {Box, Text} from '@primer/react'
import type {RoutePayload} from './types'
import {Links} from '../../components/Links'
import {AssessingSteps} from './components/AssessingSteps'
import {theme} from '../../theme'

export function Assessing() {
  const routePayload = useRoutePayload<RoutePayload>()

  return (
    <Box
      sx={{
        alignItems: 'center',
        display: 'flex',
        flexDirection: 'column',
        gap: '24px',
        justifyContent: 'center',
        mt: '64px',
        p: '32px',
        width: '100%',
      }}
    >
      <Box sx={{backgroundColor: 'rgba(246, 248, 250, 0.5)', height: '215px', width: '466px'}} />
      <Box
        sx={{
          alignItems: 'center',
          display: 'flex',
          flexDirection: 'column',
          gap: '4px',
          justifyContent: 'center',
          textAlign: 'center',
          width: '630px',
        }}
      >
        <Text sx={{color: theme.color.fgDefault, ...theme.typography.title.medium}}>
          We&apos;re assessing your training data
        </Text>
        <Text sx={{color: theme.color.fgMuted, ...theme.typography.body.large}}>
          This could take a few minutes, we&apos;ll show you the assessment report and give you a chance to evaluate and
          refine the selected data.
        </Text>
      </Box>
      <AssessingSteps />
      <Links {...routePayload} />
    </Box>
  )
}

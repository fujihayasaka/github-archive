import {Box, Button, Heading, Text} from '@primer/react'
import {Links} from '../../components/Links'
import type {RoutePayload} from './types'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {MarketingBanner} from './components/MarketingBanner'
import {HowItWorksItem} from './components/HowItWorksItem'
import {Divider} from './components/Divider'
import {theme} from '../../theme'

export function Index() {
  const routePayload = useRoutePayload<RoutePayload>()

  return (
    <Box
      sx={{
        alignItems: 'center',
        display: 'flex',
        flexDirection: 'column',
        gap: '40px',
        justifyContent: 'center',
        maxWidth: '823px',
        mt: '64px',
      }}
    >
      <Box sx={{alignItems: 'center', display: 'flex', flexDirection: 'column', gap: '12px', justifyContent: 'center'}}>
        <Box
          sx={{
            alignItems: 'center',
            display: 'flex',
            flexDirection: 'column',
            justifyContent: 'center',
            gap: '8px',
            textAlign: 'center',
          }}
        >
          <Heading as="h1">Fine-tune a model that works for your team</Heading>
          <Text sx={{color: theme.color.fgDefault, ...theme.typography.body.large}}>
            Make Copilot smarter with code suggestions tailored to your organization&apos;s unique coding practices.
            Fine-tuning improves accuracy, increases acceptance rates, and unlocks Copilot&apos;s full potential in your
            favorite IDEs.
          </Text>
        </Box>

        <Button as="a" href={routePayload.newPath} variant="primary">
          Fine-tune your first model
        </Button>
      </Box>

      <Box sx={{alignItems: 'center', display: 'flex', gap: '24px', justifyContent: 'center'}}>
        <MarketingBanner />
        <MarketingBanner />
      </Box>

      <Box sx={{display: 'flex', flexDirection: 'column', gap: '24px', justifyContent: 'center', width: '100%'}}>
        <Heading as="h2" sx={{...theme.typography.title.medium}}>
          How it works
        </Heading>
        <Box sx={{display: 'flex', flexDirection: 'column', gap: '12px', justifyContent: 'center', width: '100%'}}>
          <HowItWorksItem />
          <Divider />
          <HowItWorksItem />
          <Divider />
          <HowItWorksItem />
        </Box>
      </Box>

      <Links {...routePayload} />
    </Box>
  )
}

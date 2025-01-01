// eslint-disable-next-line no-restricted-imports
import {Box, ThemeProvider} from '@primer/react'
import {TrainingHeader} from './components/TrainingHeader'
import {TrainingSteps} from './features/TrainingSteps'
import {PipelineCard} from '../../features/PipelineCard'
import {PipelineBanner} from '../../features/PipelineBanner'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import type {RoutePayload} from './types'
import {PipelineDetailsProvider} from '../../features/PipelineDetails'
import {RouteProviders} from '../../context/RouteProviders'

export function Show() {
  return (
    <RouteProviders>
      <Component />
    </RouteProviders>
  )
}

function Component() {
  const {adminEmail, hasAnyDeployed, isStale, organization, pipelineDetails, rateLimitResetAt, withinRateLimit} =
    useRoutePayload<RoutePayload>()

  return (
    <Box sx={{display: 'flex', flexDirection: 'column', gap: '16px'}}>
      <PipelineDetailsProvider
        adminEmail={adminEmail}
        hasAnyDeployed={hasAnyDeployed}
        isStale={isStale}
        isViewingDetails
        org={organization.slug}
        pipelineForBanner={pipelineDetails}
        pipelineForCard={pipelineDetails}
        rateLimitResetAt={rateLimitResetAt}
        withinRateLimit={withinRateLimit}
      >
        <TrainingHeader />
        <PipelineBanner />
        <PipelineCard />
        <ThemeProvider colorMode="dark">
          <TrainingSteps />
        </ThemeProvider>
      </PipelineDetailsProvider>
    </Box>
  )
}

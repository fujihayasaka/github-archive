import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {Box, Flash, Heading, Text} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import {QueryClientProvider} from '@tanstack/react-query'
import {getQueryClient} from '@github-ui/security-campaigns-shared/utils/query-client'
import type {SecurityCampaign} from '@github-ui/security-campaigns-shared/SecurityCampaign'
import {RepoProgressMetric} from '../components/RepoProgressMetric'
import {RepoAlertsList} from '../components/RepoAlertsList'
import {CampaignManagerText} from '../components/CampaignManagerText'
import type {Repository} from '@github-ui/security-campaigns-shared/types/repository'
import {RelayEnvironmentProvider} from 'react-relay'
import {relayEnvironmentWithMissingFieldHandlerForNode} from '@github-ui/relay-environment'
import {BetaLabel} from '@github-ui/lifecycle-labels/beta'
import {RepoStatusMetric} from '../components/RepoStatusMetric'
import {RepoAutofixMetric} from '../components/RepoAutofixMetric'
import {InfoIcon} from '@primer/octicons-react'
import {BetaFeedback} from '../components/BetaFeedback'
import {isFeatureEnabled} from '@github-ui/feature-flags'
import {useState} from 'react'

export interface RepositorySecurityCampaignShowPayload {
  campaign: SecurityCampaign
  alertsPath: string
  repository: Repository
  orgCampaignPath: string | null
  createBranchPath: string | null
  closeAlertsPath: string | null
  showHubberWarning: boolean
}
const relayEnvironment = relayEnvironmentWithMissingFieldHandlerForNode()

export function RepositorySecurityCampaignShow() {
  const payload = useRoutePayload<RepositorySecurityCampaignShowPayload>()
  const lifecycleLabelNameEnabled = isFeatureEnabled('lifecycle_label_name_updates')

  const [queryClient] = useState(() => getQueryClient())
  return (
    <RelayEnvironmentProvider environment={relayEnvironment}>
      <QueryClientProvider client={queryClient}>
        {payload.showHubberWarning && (
          <Flash>
            <Octicon icon={InfoIcon} sx={{mr: 1}} />
            As a Hubber, you are able to view this page, but it would not be visible otherwise. Turn off site admin /
            employee mode (in the footer) to disable this feature.
          </Flash>
        )}
        <Box sx={{display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 2}}>
          <Box sx={{display: 'flex', flexDirection: 'row', alignItems: 'baseline'}}>
            <Heading data-hpc as="h2">
              {payload.campaign.name}
            </Heading>
            <CampaignManagerText manager={payload.campaign.manager} sx={{ml: 2}} />
          </Box>
          {lifecycleLabelNameEnabled ? (
            <BetaLabel feedbackUrl="https://gh.io/security-campaigns-feedback" />
          ) : (
            <BetaFeedback />
          )}
        </Box>
        <Text as="p" sx={{color: 'fg.muted'}}>
          {payload.campaign.description}
        </Text>
        <Box sx={{display: 'flex', gap: 2}}>
          <RepoProgressMetric
            orgCampaignPath={payload.orgCampaignPath}
            alertsPath={payload.alertsPath}
            endsAt={new Date(payload.campaign.endsAt)}
            createdAt={new Date(payload.campaign.createdAt)}
          />
          <RepoStatusMetric endsAt={new Date(payload.campaign.endsAt)} alertsPath={payload.alertsPath} />
          <RepoAutofixMetric alertsPath={payload.alertsPath} />
        </Box>
        <Box sx={{mt: 2}}>
          <RepoAlertsList
            alertsPath={payload.alertsPath}
            repository={payload.repository}
            createBranchPath={payload.createBranchPath ?? undefined}
            closeAlertsPath={payload.closeAlertsPath ?? undefined}
          />
        </Box>
      </QueryClientProvider>
    </RelayEnvironmentProvider>
  )
}

import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {Box, Flash, Heading, Text} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import type {SecurityCampaign} from '@github-ui/security-campaigns-shared/SecurityCampaign'
import {RepoProgressMetric} from '../components/RepoProgressMetric'
import {RepoAlertsList} from '../components/RepoAlertsList'
import {CampaignManagersText} from '../components/CampaignManagersText'
import type {Repository} from '@github-ui/security-campaigns-shared/types/repository'
import {RelayEnvironmentProvider} from 'react-relay'
import {relayEnvironmentWithMissingFieldHandlerForNode} from '@github-ui/relay-environment'
import {BetaLabel} from '@github-ui/lifecycle-labels/beta'
import {RepoStatusMetric} from '../components/RepoStatusMetric'
import {RepoAutofixSupportedMetric} from '../components/RepoAutofixSupportedMetric'
import {InfoIcon} from '@primer/octicons-react'
import {securityCampaignOrgCampaignPath, securityCampaignRepoAlertsPath} from '@github-ui/paths'
import {CampaignContactLink} from '../components/CampaignContactLink'
import type {Issue} from '../types/issue'
import {IssueLink} from '../components/IssueLink'
import {CampaignFeedbackLink} from '../components/CampaignFeedbackLink'

export interface RepositorySecurityCampaignShowPayload {
  campaign: SecurityCampaign
  repository: Repository
  showOrgCampaignLink: boolean
  canCreateBranch: boolean
  canCloseAlerts: boolean
  showHubberWarning: boolean
  issue: Issue | null
  delegatedAlertDismissalEnabled: boolean
  campaignsGAEnabled: boolean
}
const relayEnvironment = relayEnvironmentWithMissingFieldHandlerForNode()

export function RepositorySecurityCampaignShow() {
  const payload = useRoutePayload<RepositorySecurityCampaignShowPayload>()

  const alertsPath = securityCampaignRepoAlertsPath({
    owner: payload.repository.ownerLogin,
    repo: payload.repository.name,
    securityCampaignNumber: payload.campaign.number,
  })

  return (
    <RelayEnvironmentProvider environment={relayEnvironment}>
      {payload.showHubberWarning && (
        <Flash>
          <Octicon icon={InfoIcon} sx={{mr: 1}} />
          As a Hubber, you are able to view this page, but it would not be visible otherwise. Turn off site admin /
          employee mode (in the footer) to disable this feature.
        </Flash>
      )}
      <Box
        sx={{display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between', gap: 2}}
        className="border-bottom pb-2 mb-2"
      >
        <Box sx={{display: 'flex', flexDirection: 'column', gap: 2}}>
          <Heading data-hpc as="h2" className="f2 text-normal">
            {payload.campaign.name}
          </Heading>
          <div>
            <CampaignManagersText managers={payload.campaign.managers} teamManagers={payload.campaign.teamManagers} />
            <CampaignContactLink contactLink={payload.campaign.contactLink} />
            {payload.issue !== null && (
              <>
                and tracked on the issue
                <IssueLink issue={payload.issue} />
              </>
            )}
          </div>
        </Box>
        <Box sx={{display: 'flex', alignItems: 'center', gap: 2}}>
          {payload.campaignsGAEnabled ? (
            <CampaignFeedbackLink />
          ) : (
            <BetaLabel feedbackUrl="https://gh.io/security-campaigns-feedback" />
          )}
        </Box>
      </Box>
      <Text as="p" sx={{color: 'fg.muted'}}>
        {payload.campaign.description}
      </Text>
      <Box sx={{display: 'flex', flexWrap: 'wrap', gap: 2}}>
        <RepoProgressMetric
          orgCampaignPath={
            payload.showOrgCampaignLink
              ? securityCampaignOrgCampaignPath({
                  org: payload.repository.ownerLogin,
                  securityCampaignNumber: payload.campaign.number,
                })
              : null
          }
          alertsPath={alertsPath}
          endsAt={new Date(payload.campaign.endsAt)}
          createdAt={new Date(payload.campaign.createdAt)}
        />
        <RepoStatusMetric endsAt={new Date(payload.campaign.endsAt)} alertsPath={alertsPath} />
        <RepoAutofixSupportedMetric alertsPath={alertsPath} />
      </Box>
      <Box sx={{mt: 2}}>
        <RepoAlertsList
          alertsPath={alertsPath}
          repository={payload.repository}
          securityCampaignNumber={payload.campaign.number}
          canCreateBranch={payload.canCreateBranch}
          canCloseAlerts={payload.canCloseAlerts}
          delegatedAlertDismissalEnabled={payload.delegatedAlertDismissalEnabled ?? false}
        />
      </Box>
    </RelayEnvironmentProvider>
  )
}

import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {Flash, Heading, Stack, Text} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import {RepoProgressMetric} from '../components/RepoProgressMetric'
import {RepoAlertsList} from '../components/RepoAlertsList'
import {CampaignManagersText} from '../components/CampaignManagersText'
import {RelayEnvironmentProvider} from 'react-relay'
import {relayEnvironmentWithMissingFieldHandlerForNode} from '@github-ui/relay-environment'
import {RepoStatusMetric} from '../components/RepoStatusMetric'
import {RepoAutofixSupportedMetric} from '../components/RepoAutofixSupportedMetric'
import {InfoIcon} from '@primer/octicons-react'
import {securityCampaignOrgCampaignPath, securityCampaignRepoAlertsPath} from '@github-ui/paths'
import {CampaignContactLink} from '../components/CampaignContactLink'
import type {Issue} from '../types/issue'
import {IssueLink} from '../components/IssueLink'
import {CampaignFeedbackLink} from '../components/CampaignFeedbackLink'
import type {SecurityCampaign} from '../types/security-campaign'
import type {Repository} from '../types/repository'

export interface RepositorySecurityCampaignShowPayload {
  campaign: SecurityCampaign
  repository: Repository
  showOrgCampaignLink: boolean
  canCreateBranch: boolean
  canCloseAlerts: boolean
  showHubberWarning: boolean
  issue: Issue | null
  delegatedAlertDismissalEnabled: boolean
  assignToCopilotEnabled: boolean
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
      <Stack
        direction="horizontal"
        align="start"
        justify="space-between"
        gap="condensed"
        className="border-bottom pb-2 mb-2"
      >
        <Stack>
          <Heading data-hpc as="h2" className="f2 text-normal">
            {payload.campaign.name}
          </Heading>
          <div>
            <CampaignManagersText managers={payload.campaign.managers} teamManagers={payload.campaign.teamManagers} />
            <CampaignContactLink
              contactLink={payload.campaign.contactLink}
              teamCount={payload.campaign.teamManagers.length}
              userCount={payload.campaign.managers.length}
            />
            {payload.issue !== null && (
              <>
                {payload.campaign.contactLink === null && <span>&nbsp;</span>}
                <span>and tracked on the issue</span>
                <IssueLink issue={payload.issue} />
              </>
            )}
          </div>
        </Stack>
        <Stack direction="horizontal" align="center" gap="condensed">
          <CampaignFeedbackLink />
        </Stack>
      </Stack>
      <Text as="p" sx={{color: 'fg.muted'}}>
        {payload.campaign.description}
      </Text>
      <Stack direction="horizontal" wrap="wrap" gap="condensed">
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
      </Stack>
      <Stack className="mt-2">
        <RepoAlertsList
          alertsPath={alertsPath}
          repository={payload.repository}
          securityCampaignNumber={payload.campaign.number}
          canCreateBranch={payload.canCreateBranch}
          canCloseAlerts={payload.canCloseAlerts}
          delegatedAlertDismissalEnabled={payload.delegatedAlertDismissalEnabled ?? false}
        />
      </Stack>
    </RelayEnvironmentProvider>
  )
}

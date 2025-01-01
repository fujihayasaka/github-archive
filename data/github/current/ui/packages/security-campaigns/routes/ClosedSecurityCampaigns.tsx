import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {Box, Heading, Link, Text} from '@primer/react'
import {ClosedSecurityCampaignsList} from '../components/ClosedSecurityCampaignsList'
import {BetaLabel} from '@github-ui/lifecycle-labels/beta'
import {CampaignFeedbackLink} from '../components/CampaignFeedbackLink'

export interface ClosedSecurityCampaignsPayload {
  // The login of the organization
  organizationLogin: string

  // The total number of closed campaigns in this org
  closedCampaignsCounts: number

  // API path to fetch the list of closed campaigns
  closedCampaignsPath: string

  // The URL to the docs around closing campaigns
  closingOrDeletingCampaignsDocsUrl: string

  campaignsGAEnabled: boolean

  // The total number of open campaigns in this org
  openCampaignsCounts: number

  // The maximum number of open campaigns allowed in this org
  maxOpenCampaigns: number
}

export const ClosedSecurityCampaigns = () => {
  const payload = useRoutePayload<ClosedSecurityCampaignsPayload>()
  const docsUrl = payload.closingOrDeletingCampaignsDocsUrl

  return (
    <>
      <Box sx={{display: 'flex', alignItems: 'center', justifyContent: 'space-between'}}>
        <Heading data-hpc as="h2">
          Closed campaigns
        </Heading>
        {payload.campaignsGAEnabled ? (
          <CampaignFeedbackLink />
        ) : (
          <BetaLabel feedbackUrl="https://gh.io/security-campaigns-feedback" />
        )}
      </Box>
      <Text as="p" sx={{color: 'fg.muted'}}>
        Campaigns that have been closed, but can be re-opened.{' '}
        {docsUrl && (
          <Link inline href={docsUrl}>
            Learn more about closed campaigns.
          </Link>
        )}
      </Text>

      <hr />

      <ClosedSecurityCampaignsList {...payload} />
    </>
  )
}

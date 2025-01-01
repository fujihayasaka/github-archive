import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {Box, Heading, Link, Text} from '@primer/react'
import {ClosedSecurityCampaignsList} from '../components/ClosedSecurityCampaignsList'
import {QueryClientProvider} from '@tanstack/react-query'
import {getQueryClient} from '@github-ui/security-campaigns-shared/utils/query-client'
import {BetaLabel} from '@github-ui/lifecycle-labels/beta'
import {BetaFeedback} from '../components/BetaFeedback'
import {isFeatureEnabled} from '@github-ui/feature-flags'
import {useState} from 'react'

export interface ClosedSecurityCampaignsPayload {
  // The total number of closed campaigns in this org
  closedCampaignsCounts: number

  // API path to fetch the list of closed campaigns
  closedCampaignsPath: string

  // The URL to the docs around closing campaigns
  closingOrDeletingCampaignsDocsUrl: string
}

export const ClosedSecurityCampaigns = () => {
  const payload = useRoutePayload<ClosedSecurityCampaignsPayload>()
  const lifecycleLabelNameEnabled = isFeatureEnabled('lifecycle_label_name_updates')
  const docsUrl = payload.closingOrDeletingCampaignsDocsUrl

  const [queryClient] = useState(() => getQueryClient())
  return (
    <QueryClientProvider client={queryClient}>
      <Box sx={{display: 'flex', alignItems: 'center', justifyContent: 'space-between'}}>
        <Heading data-hpc as="h2">
          Closed campaigns
        </Heading>
        {lifecycleLabelNameEnabled ? (
          <BetaLabel feedbackUrl="https://gh.io/security-campaigns-feedback" />
        ) : (
          <BetaFeedback />
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
    </QueryClientProvider>
  )
}

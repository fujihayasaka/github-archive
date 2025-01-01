import {QueryClientProvider} from '@tanstack/react-query'
import {getQueryClient} from '@github-ui/security-campaigns-shared/utils/query-client'
import {OrgSecurityCampaign} from '../components/OrgSecurityCampaign'
import {useState} from 'react'

export function OrgSecurityCampaignShow() {
  const [queryClient] = useState(() => getQueryClient())
  return (
    <QueryClientProvider client={queryClient}>
      <OrgSecurityCampaign />
    </QueryClientProvider>
  )
}

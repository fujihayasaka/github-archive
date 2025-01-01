import {QueryClientProvider} from '@tanstack/react-query'
import {getQueryClient} from '@github-ui/security-campaigns-shared/utils/query-client'
import {
  SecurityCampaignCreateButton,
  type SecurityCampaignCreateButtonProps,
} from './components/SecurityCampaignCreateButton'
import {useState} from 'react'

export function SecurityCampaignCreation(props: SecurityCampaignCreateButtonProps) {
  const [queryClient] = useState(() => getQueryClient())
  return (
    <QueryClientProvider client={queryClient}>
      <SecurityCampaignCreateButton {...props} />
    </QueryClientProvider>
  )
}

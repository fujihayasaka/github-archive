import {NavigationContextProvider} from '@github-ui/licensing-common/contexts/NavigationContext'
import {Summary, type SummaryProps} from './Summary'

export interface OverviewProps {
  enterpriseContactUrl: string
  copilot: SummaryProps
  isStafftools: boolean
  slug: string
  isTeams: boolean
}

export function Overview({copilot, ...props}: OverviewProps) {
  return (
    <NavigationContextProvider {...props}>
      <div className="mb-4" data-testid="licensing-copilot-overview">
        <Summary {...copilot} />
      </div>
    </NavigationContextProvider>
  )
}

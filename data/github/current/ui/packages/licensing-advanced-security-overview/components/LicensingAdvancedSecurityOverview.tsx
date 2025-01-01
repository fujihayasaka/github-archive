import {NavigationContextProvider} from '@github-ui/licensing-common/contexts/NavigationContext'
import {
  LicensingAdvancedSecuritySummary,
  type LicensingAdvancedSecuritySummaryProps,
} from './LicensingAdvancedSecuritySummary'

export interface LicensingAdvancedSecurityOverviewProps {
  enterpriseContactUrl: string
  ghas: LicensingAdvancedSecuritySummaryProps
  isStafftools: boolean
  slug: string
}

export function LicensingAdvancedSecurityOverview({ghas, ...props}: LicensingAdvancedSecurityOverviewProps) {
  return (
    <NavigationContextProvider {...props}>
      <div className="mb-4" data-testid="licensing-advanced-security-overview">
        <LicensingAdvancedSecuritySummary {...ghas} />
      </div>
    </NavigationContextProvider>
  )
}

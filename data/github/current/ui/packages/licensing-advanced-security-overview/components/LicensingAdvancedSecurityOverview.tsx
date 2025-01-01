import {NavigationContextProvider} from '@github-ui/licensing-common/contexts/NavigationContext'
import {
  LicensingAdvancedSecuritySummary,
  type LicensingAdvancedSecuritySummaryProps,
} from './LicensingAdvancedSecuritySummary'
import type {TradeScreeningResult} from '../types/trade-screening'

export interface LicensingAdvancedSecurityOverviewProps {
  enterpriseContactUrl: string
  ghas: LicensingAdvancedSecuritySummaryProps
  tradeScreeningResult: TradeScreeningResult
  isStafftools: boolean
  slug: string
  isTeams: boolean
}

export function LicensingAdvancedSecurityOverview({ghas, ...props}: LicensingAdvancedSecurityOverviewProps) {
  return (
    <NavigationContextProvider {...props}>
      <div className="mb-4" data-testid="licensing-advanced-security-overview">
        <LicensingAdvancedSecuritySummary {...ghas} tradeScreeningResult={props.tradeScreeningResult} />
      </div>
    </NavigationContextProvider>
  )
}

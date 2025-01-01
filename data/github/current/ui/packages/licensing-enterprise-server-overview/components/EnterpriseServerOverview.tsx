import {EnterpriseServerSummary, type EnterpriseServerSummaryProps} from './EnterpriseServerSummary'

export interface EnterpriseServerOverviewProps {
  ghesUsage: EnterpriseServerSummaryProps
}

export function EnterpriseServerOverview({ghesUsage}: EnterpriseServerOverviewProps) {
  return (
    <div className="mb-4" data-testid="licensing-enterprise-server-overview">
      <EnterpriseServerSummary {...ghesUsage} />
    </div>
  )
}

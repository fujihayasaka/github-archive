import {Link} from '@primer/react'
import {useRepoAlertsQuery} from '../hooks/use-repo-alerts-query'
import {defaultQuery} from '../hooks/use-alerts-params'
import {ProgressMetric} from './ProgressMetric'

export interface RepoProgressMetricProps {
  alertsPath: string
  endsAt: Date
  createdAt: Date
  orgCampaignPath: string | null
}

export function RepoProgressMetric({alertsPath, orgCampaignPath, endsAt, createdAt}: RepoProgressMetricProps) {
  // Always make this request separately since we don't want to apply any filters here
  const query = useRepoAlertsQuery(alertsPath, {query: defaultQuery, cursor: null})

  const orgLink =
    orgCampaignPath !== null ? <Link href={orgCampaignPath}>View organization-level campaign</Link> : undefined

  return (
    <ProgressMetric
      openCount={query.data?.openCount}
      closedCount={query.data?.closedCount}
      openWithLinksCount={query.data?.openWithLinksCount}
      isSuccess={query.isSuccess}
      endsAt={endsAt}
      createdAt={createdAt}
      action={orgLink}
    />
  )
}

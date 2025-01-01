import type {FilterProvider} from '@github-ui/filter'
import {addUrlToHistoryStack} from '@github-ui/history'
import {SingleSignOnBanner} from '@github-ui/single-sign-on-banner'
import {useSso} from '@github-ui/use-sso'
import {Stack} from '@primer/react/experimental'
import {useEffect, useMemo, useState} from 'react'

import PageLayout from '../common/components/page-layout'
import {useDirtyStateTracking} from '../common/hooks/use-dirty-state-tracking'
import AlertsFixedCard from './components/alerts-fixed-card/AlertsRemediatedCard'
import {AlertsTimechartCard, DEFAULT_QUERY} from './components/alerts-timechart-card/AlertsTimechartCard'
import RepositoriesTable from './components/repositories-table/RepositoriesTable'

export interface SecurityCenterDependabotMetricsProps {
  initialQuery?: string
  feedbackLink: {
    text: string
    url: string
  }
  showIncompleteDataWarning: boolean
  incompleteDataWarningDocHref: string
  exportErrorMessage?: string
  filterProviders: FilterProvider[]
  showChartFeatures?: boolean
  allowedDependabotQualifiers: string[]
}

export function SecurityCenterDependabotMetrics({
  initialQuery,
  feedbackLink,
  showIncompleteDataWarning,
  incompleteDataWarningDocHref,
  filterProviders,
  showChartFeatures,
  allowedDependabotQualifiers,
}: SecurityCenterDependabotMetricsProps): JSX.Element {
  // prepare SSO org names for banner
  const {ssoOrgs} = useSso()
  const ssoOrgNames = ssoOrgs.map(o => o['login']).filter(n => n !== undefined)

  // track selected filter state
  const [query, setQuery] = useState<string>(initialQuery ?? DEFAULT_QUERY)
  const [queryIsDirty, resetQueryIsDirty] = useDirtyStateTracking(query, DEFAULT_QUERY, !!initialQuery)

  // keep browser URL in sync with selected trend grouping
  useEffect(() => {
    const url = new URL(window.location.href, window.location.origin)
    const nextParams = url.searchParams

    if (queryIsDirty) {
      nextParams.set('query', query)
    } else {
      nextParams.delete('query')
    }

    addUrlToHistoryStack(`${url.pathname}${url.search}`)
  }, [query, queryIsDirty])

  const cardProps = useMemo(() => {
    return {
      query,
      allowedDependabotQualifiers,
    }
  }, [query, allowedDependabotQualifiers])

  return (
    <PageLayout>
      <PageLayout.Banners>
        {ssoOrgNames.length > 0 && <SingleSignOnBanner protectedOrgs={ssoOrgNames} data-testid="sso-banner" />}
      </PageLayout.Banners>

      <PageLayout.Header
        title="Dependabot"
        description="A report of vulnerabilities by Dependabot"
        feedbackLink={feedbackLink}
      />

      <PageLayout.FilterBar
        filter={<PageLayout.Filter providers={filterProviders} query={query} onSubmit={setQuery} />}
        revert={
          <PageLayout.FilterRevert
            show={queryIsDirty}
            onRevert={() => {
              setQuery(DEFAULT_QUERY)
              resetQueryIsDirty()
            }}
          />
        }
      />

      <PageLayout.LimitedRepoWarning show={showIncompleteDataWarning} href={incompleteDataWarningDocHref} />

      {/* showChartFeatures controls hiding specific tiles and is feature flag dependabot_alerts_vad_show_charts */}
      <PageLayout.Content>
        <Stack direction={'vertical'}>
          <AlertsTimechartCard {...cardProps} />

          <Stack direction={'horizontal'} wrap={'wrap'}>
            {showChartFeatures && <AlertsFixedCard {...cardProps} />}
          </Stack>

          <Stack direction={'horizontal'}>
            <Stack.Item grow>{<RepositoriesTable {...cardProps} />}</Stack.Item>
          </Stack>
        </Stack>
      </PageLayout.Content>
    </PageLayout>
  )
}

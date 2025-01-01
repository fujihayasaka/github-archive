import DataCard from '@github-ui/data-card'
import {AlertIcon, KeyIcon, RepoIcon, ShieldCheckIcon} from '@primer/octicons-react'
import {Heading, Stack} from '@primer/react'
import {Blankslate} from '@primer/react/experimental'
import {useMemo} from 'react'

import {usePaths} from '../../common/contexts/Paths'
import {useQuery} from '../../common/hooks/use-config-query'
import {tryFetchJson} from '../../common/utils/fetch-json'
import type {PushProtectionMetricsResponse} from '../types/push-protection-metrics'
import {AggregateMetricsList} from './AggregateMetricsList'
import styles from './PushProtectionMetrics.module.css'
import {SeeAllMetricsButton} from './SeeAllMetrics'

export interface PushProtectionMetricsProps {
  startDate: string
  endDate: string
  query: string
  noData?: boolean
}

interface NoDataResponse {
  noData: string
}

type FetchResponse = NoDataResponse | {payload: PushProtectionMetricsResponse}

function isNoDataResponse(response: FetchResponse): response is NoDataResponse {
  return response.hasOwnProperty('noData')
}

const meanResponseTimeLabel = (meanResponseTime: number): string => (meanResponseTime < 60 * 60 ? 'minutes' : 'hours')
function meanResponseTimeNumber(meanResponseTime: number): number {
  if (meanResponseTime === 0) return 0
  let formatted = meanResponseTime / 60
  if (formatted > 60) {
    formatted = formatted / 60
  }
  return Math.round(formatted * 10) / 10
}

export function PushProtectionMetrics({
  startDate,
  endDate,
  query = '',
  noData,
}: PushProtectionMetricsProps): JSX.Element {
  const paths = usePaths()
  const path = paths.secretsPushProtectionMetricsPath({startDate, endDate, query})

  const {
    data: metrics,
    isLoading,
    isError,
  } = useQuery({
    queryKey: [path, noData],
    queryFn: async () => {
      if (noData) return null

      const res = await tryFetchJson<FetchResponse>(path)
      if (!res) throw new Error('Failed to fetch push protection metrics')

      if (isNoDataResponse(res)) return null
      if (!res.payload) throw new Error('Failed to fetch push protection metrics')
      return res.payload
    },
  })
  const openStatus = metrics?.bypassesByRequestStatusCounts.find(({name}) => name === 'Open')
  const approvedStatus = metrics?.bypassesByRequestStatusCounts.find(({name}) => name === 'Approved')
  const rejectedStatus = metrics?.bypassesByRequestStatusCounts.find(({name}) => name === 'Rejected')
  const cancelledStatus = metrics?.bypassesByRequestStatusCounts.find(({name}) => name === 'Cancelled')
  const bypassedPercentage = useMemo(() => {
    if (!metrics || metrics.totalBlocksCount === 0) {
      return 0
    }
    return (metrics.bypassedAlertsCount / metrics.totalBlocksCount) * 100
  }, [metrics])
  const isNoData = !metrics

  if (isError) {
    return requestErrorBlankslate()
  }

  return (
    <>
      <div data-hpc className={styles.Box}>
        <Heading as="h3" className={styles.Heading}>
          Push protection
        </Heading>
        <Stack direction="horizontal" wrap="wrap" className="mt-2">
          <DataCard
            data-testid="bypassed-secrets-count"
            cardTitle="Bypassed secrets"
            loading={isLoading}
            noData={isNoData}
          >
            <DataCard.Counter
              count={isNoData || !metrics ? 0 : metrics.bypassedAlertsCount}
              total={isNoData || !metrics ? 0 : metrics.totalBlocksCount}
            />
            <DataCard.ProgressBar
              data={[{progress: bypassedPercentage, color: 'attention.emphasis'}]}
              aria-label="Secrets successfully blocked"
            />
            <DataCard.Description>
              {`${isNoData || !metrics ? 0 : metrics.successfulBlocksCount} secrets blocked successfully`}
            </DataCard.Description>
          </DataCard>
          <DataCard
            data-testid="bypass-requests-by-status"
            cardTitle="Bypass requests"
            loading={isLoading}
            noData={isNoData}
          >
            <DataCard.Counter count={isNoData || !metrics ? 0 : metrics.bypassRequestsCount} metric={'requests'} />
            <DataCard.ProgressBar
              data={[
                {progress: openStatus?.percent || 0},
                {progress: approvedStatus?.percent || 0},
                {progress: rejectedStatus?.percent || 0},
                {progress: cancelledStatus?.percent || 0},
              ]}
              aria-label="Bypass requests by status"
            />
            {(openStatus || approvedStatus || rejectedStatus || cancelledStatus) && (
              <div className={styles.Box_2}>
                {openStatus && (
                  <span key={openStatus.name} className={styles.Text}>
                    <span className={styles.Text_1}>{openStatus.count}</span> {openStatus.name}
                  </span>
                )}
                {approvedStatus && (
                  <span key={approvedStatus.name} className={styles.Text}>
                    <span className={styles.Text_1}>{approvedStatus.count}</span> {approvedStatus.name}
                  </span>
                )}
                {rejectedStatus && (
                  <span key={rejectedStatus.name} className={styles.Text_2}>
                    <span className={styles.Text_1}>{rejectedStatus.count}</span> {rejectedStatus.name}
                  </span>
                )}
                {cancelledStatus && (
                  <span key={cancelledStatus.name} className={styles.Text}>
                    <span className={styles.Text_1}>{cancelledStatus.count}</span> {cancelledStatus.name}
                  </span>
                )}
              </div>
            )}
          </DataCard>
          <DataCard
            data-testid="mean-time-to-response"
            cardTitle="Mean time to response"
            loading={isLoading}
            noData={isNoData}
          >
            <div className={styles.Box_3}>
              <DataCard.Counter
                count={meanResponseTimeNumber(metrics?.meanResponseTime || 0)}
                metric={meanResponseTimeLabel(metrics?.meanResponseTime || 0)}
              />
            </div>
            <DataCard.Description>Average time to respond to bypass requests</DataCard.Description>
          </DataCard>
        </Stack>
      </div>
      <div className={styles.Box}>
        <Heading as="h3" className={styles.Heading}>
          Blocks
        </Heading>
        <span className={styles.Text_3}>
          All secrets pushed, including secrets bypassed and secrets fixed on block. Only secrets bypassed create
          alerts.
        </span>
        <Stack direction="horizontal" wrap="wrap" className="mt-3">
          <AggregateMetricsList
            data-testid="blocks-by-token-type"
            title="Most blocked secret types"
            loading={isLoading}
            aggregateCounts={isNoData || !metrics ? [] : metrics.blocksByTokenTypeCounts}
            icon={KeyIcon}
            seeAllButton={
              <li className="mt-2">
                <SeeAllMetricsButton
                  label="See all blocked secret types"
                  header="Most blocked secret types"
                  href={paths.secretsPushProtectionBlocksByTokenTypeMetricsPath({startDate, endDate, query})}
                />
              </li>
            }
          />
          <AggregateMetricsList
            data-testid="blocks-by-repo"
            title="Repositories with most pushes blocked"
            loading={isLoading}
            aggregateCounts={isNoData || !metrics ? [] : metrics.blocksByRepositoryCounts}
            icon={RepoIcon}
            seeAllButton={
              <li className="mt-2">
                <SeeAllMetricsButton
                  label="See all repositories with pushes blocked"
                  header="Repositories with most pushes blocked"
                  href={paths.secretsPushProtectionBlocksByRepositoryMetricsPath({startDate, endDate, query})}
                />
              </li>
            }
          />
        </Stack>
      </div>
      <div className={styles.Box}>
        <Heading as="h3" className={styles.Heading}>
          Bypasses
        </Heading>
        <span className={styles.Text_3}>
          Secrets pushed and bypassed. A user allowed this secret to be pushed and the secret was exposed in a
          repository.
        </span>
        <Stack direction="horizontal" wrap="wrap" className="mt-3">
          <AggregateMetricsList
            data-testid="bypasses-by-token-type"
            title="Most bypassed secret types"
            loading={isLoading}
            aggregateCounts={isNoData || !metrics ? [] : metrics.bypassesByTokenTypeCounts}
            icon={KeyIcon}
            seeAllButton={
              <li className="mt-2">
                <SeeAllMetricsButton
                  label="See all bypassed secret types"
                  header="Most bypassed secret types"
                  href={paths.secretsPushProtectionBypassesByTokenTypeMetricsPath({startDate, endDate, query})}
                  baseIndexLink={paths.secretScanningAlertCentricViewPath({query: 'bypassed:true'})}
                />
              </li>
            }
            baseIndexLink={paths.secretScanningAlertCentricViewPath({query: 'bypassed:true'})}
          />
          <AggregateMetricsList
            data-testid="bypasses-by-repo"
            title="Repositories with most secrets bypassed"
            loading={isLoading}
            aggregateCounts={isNoData || !metrics ? [] : metrics.bypassesByRepositoryCounts}
            icon={RepoIcon}
            seeAllButton={
              <li className="mt-2">
                <SeeAllMetricsButton
                  label="See all repositories with secrets bypassed"
                  header="Repositories with most secrets bypassed"
                  href={paths.secretsPushProtectionBypassesByRepositoryMetricsPath({startDate, endDate, query})}
                  baseIndexLink={paths.secretScanningAlertCentricViewPath({query: 'bypassed:true'})}
                />
              </li>
            }
            baseIndexLink={paths.secretScanningAlertCentricViewPath({query: 'bypassed:true'})}
          />
        </Stack>
        <div className={styles.Box_5}>
          <AggregateMetricsList
            data-testid="bypasses-by-reason"
            title="Bypass reason distribution"
            loading={isLoading}
            aggregateCounts={isNoData || !metrics ? [] : metrics.bypassesByReasonCounts}
            icon={ShieldCheckIcon}
          />
        </div>
      </div>
    </>
  )
}

function requestErrorBlankslate(): JSX.Element {
  return (
    <DataCard data-testid="push-protection-metrics-request-error-blankslate" className={styles.DataCard}>
      <Blankslate>
        <Blankslate.Visual>
          <AlertIcon size="medium" />
        </Blankslate.Visual>
        <Blankslate.Heading>Secret scanning data could not be loaded right now</Blankslate.Heading>
      </Blankslate>
    </DataCard>
  )
}

import {Suspense, lazy, useCallback, useEffect, useMemo, useState} from 'react'
import {ActionList, ActionMenu, Spinner} from '@primer/react'
import {Banner} from '@primer/react/experimental'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {useSearchParams} from '@github-ui/use-navigate'
import {RangePicker} from '../components/RangePicker'
import {Skeleton} from '../components/Skeleton'
import {fetchJsonPoll} from '../helpers/fetch-json-poll'
import type {Contributor, Metric, RawContributor} from '../repos-contributors-chart-types'
import {mergeWeeksFromContributors} from '../helpers/merge-weeks-from-contributors'
import {useRangeSelection} from '../contexts/RangeSelectionContext'

import styles from './Index.module.css'
import {transformWeeks} from '../helpers/transform-weeks'
import {computeMetricsFromWeeks} from '../helpers/compute-metrics-from-weeks'
import {getWeekRangeIndices} from '../helpers/get-week-range-indices'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'
import {useCalculatedMax} from '../contexts/CalculatedMaxContext'

const ReposContributorsChart = lazy(async () => import('../components/ReposContributorsChart'))

export type IndexProps = {
  graphDataPath: string
  isUsingContributionInsights: boolean
  defaultBranch: string
}

const METRICS: {[key in Metric]: string} = {
  commits: 'Commits',
  additions: 'Additions',
  deletions: 'Deletions',
}

export const Index = () => {
  const routePayload = useRoutePayload<IndexProps>()
  const columnCharts = useFeatureFlag('repos_column_charts')
  const [{graphDataPath, isUsingContributionInsights, defaultBranch}] = useState<IndexProps>(() => routePayload)

  const [searchParams, setSearchParams] = useSearchParams()
  const [isLoaded, setIsLoaded] = useState(false)
  const [errorMessage, setErrorMessage] = useState<string | undefined>()
  const [contributors, setContributors] = useState<RawContributor[]>([])
  const [selectedMetric, setSelectedMetric] = useState<Metric>(() => {
    const metric = searchParams.get('selectedMetric') || 'commits'
    if (Object.keys(METRICS).includes(metric)) {
      return metric as Metric
    }
    return 'commits'
  })
  const rangeSelection = useRangeSelection()
  const {reset} = useCalculatedMax()
  const {summaryWeeks, summaryMetrics, from, to} = useMemo(() => {
    const weeks = mergeWeeksFromContributors(contributors)
    const range = getWeekRangeIndices({weeks, rangeSelection})
    const slicedWeeks = columnCharts ? weeks : weeks.slice(range.from, range.to + 1)
    const metrics = computeMetricsFromWeeks(slicedWeeks)
    return {
      summaryWeeks: slicedWeeks,
      summaryMetrics: metrics,
      from: range.from,
      to: range.to,
    }
  }, [columnCharts, contributors, rangeSelection])

  const mappedContributors = useMemo<Contributor[]>(
    () =>
      contributors
        .map(({author, weeks: _weeks}) => {
          const transformedWeeks = transformWeeks(_weeks)
          const slicedWeeks = transformedWeeks.slice(from, to + 1)
          const {totals, metrics} = computeMetricsFromWeeks(slicedWeeks)
          if (totals.commits === 0) {
            return null
          }
          return {
            author,
            weeks: slicedWeeks,
            totals,
            metrics,
          }
        })
        .filter(contributor => !!contributor)
        .sort((a, b) => (a.totals[selectedMetric] - b.totals[selectedMetric] < 0 ? 1 : -1)),
    [contributors, selectedMetric, from, to],
  )

  const minDate = columnCharts ? summaryWeeks[0]?.week : (contributors[0]?.weeks[0]?.w ?? 0) * 1000

  useEffect(() => {
    async function getContributors() {
      try {
        const response = await fetchJsonPoll(graphDataPath)
        if (response.ok) {
          const results: RawContributor[] = await response.json()
          if (results.length === 0) {
            setErrorMessage("We don't have enough data to generate this graph")
          } else {
            setContributors(results)
          }
        } else {
          const {unusable} = await response.json()
          if (unusable) {
            setErrorMessage('We need at least one non-empty commit with an email to generate this graph')
          } else {
            setErrorMessage('There was an error generating this graph')
          }
        }
      } catch {
        setErrorMessage('There was an error generating this graph')
      }
      setIsLoaded(true)
    }
    getContributors()
  }, [graphDataPath])

  const onSelectedMetricChange = useCallback(
    (metric: Metric) => {
      reset()
      setSelectedMetric(metric)
      searchParams.set('selectedMetric', metric)
      setSearchParams(searchParams.toString())
    },
    [searchParams, reset, setSearchParams, setSelectedMetric],
  )

  if (errorMessage) {
    return (
      <Banner variant="critical" className="mb-3" title="Graph could not be rendered" hideTitle>
        <Banner.Description>{errorMessage}</Banner.Description>
      </Banner>
    )
  }

  return (
    <div className="d-flex flex-column gap-3">
      <div className="d-flex flex-wrap flex-justify-between">
        <div className={styles.titleContainer}>
          <h1 className="h2">Contributors</h1>
          <p className="color-fg-muted">
            {!isUsingContributionInsights ? (
              <>Contributions per week to {defaultBranch}, excluding merge commits</>
            ) : (
              <>
                Contributions per week to {defaultBranch}, line counts have been omitted because commit count exceeds
                10,000.
              </>
            )}
          </p>
        </div>
        <div className="d-flex gap-2">
          <RangePicker minDate={minDate} />
          {!isUsingContributionInsights ? (
            <ActionMenu>
              <ActionMenu.Button>
                <span className="color-fg-muted">Contributions:</span> {METRICS[selectedMetric]}
              </ActionMenu.Button>
              <ActionMenu.Overlay width="auto">
                <ActionList selectionVariant="single">
                  {Object.keys(METRICS).map(metric => (
                    <ActionList.Item
                      key={metric}
                      selected={selectedMetric === metric}
                      onSelect={() => {
                        onSelectedMetricChange(metric as Metric)
                      }}
                    >
                      {METRICS[metric as Metric]}
                    </ActionList.Item>
                  ))}
                </ActionList>
              </ActionMenu.Overlay>
            </ActionMenu>
          ) : null}
        </div>
      </div>
      <div key={selectedMetric} className="d-flex flex-column gap-3">
        {isLoaded ? (
          <Suspense fallback={<Skeleton />}>
            <ReposContributorsChart
              selectedMetric={selectedMetric}
              weeks={summaryWeeks}
              onlyCommits={isUsingContributionInsights}
              {...summaryMetrics}
            />
          </Suspense>
        ) : (
          <>
            <Skeleton />
            <div className="text-center p-3">
              <Spinner />
              <div className="graph-loading msg">
                <p>Crunching the latest data, just for you. Hang tight…</p>
              </div>
            </div>
          </>
        )}
        <ul className={styles.chartList}>
          {mappedContributors.map((contributor, index) => (
            <li key={contributor.author.id} className={styles.chartListItem}>
              <Suspense>
                <ReposContributorsChart
                  {...contributor}
                  place={index + 1}
                  selectedMetric={selectedMetric}
                  onlyCommits={isUsingContributionInsights}
                />
              </Suspense>
            </li>
          ))}
          {mappedContributors.length % 2 !== 0 && <li className={styles.chartListItem} />}
        </ul>
      </div>
    </div>
  )
}

import {type ComponentProps, useCallback, useEffect, useRef, useState, useMemo} from 'react'
import {Label, Link} from '@primer/react'
import {debounce} from '@github/mini-throttle'
import {useParams} from 'react-router-dom'
import {ChartCard, type ChartCardProps} from '@github-ui/chart-card'
import {GitHubAvatar} from '@github-ui/github-avatar'
import type {SeriesOptionsType} from 'highcharts'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'
import type {Author, Metric, SummarizedCommitMetrics, Totals, Week} from '../repos-contributors-chart-types'
import {useRangeSelection} from '../contexts/RangeSelectionContext'
import {useCalculatedMax} from '../contexts/CalculatedMaxContext'
import styles from './ReposContributorsChart.module.css'

type HighchartsReactRefObject = NonNullable<ChartCardProps['chartRef']> extends React.RefObject<infer T> ? T : never
type ChartProps = ComponentProps<typeof ChartCard.Chart>
type AxisSetExteremesEventObject = Parameters<
  NonNullable<NonNullable<NonNullable<ChartProps['xAxisOptions']>['events']>['setExtremes']>
>[0]

const chartHeights: {[size: string]: string} = {
  medium: '256px',
  small: '128px',
}

const SELECTION_TRIGGERS = ['mousewheel', 'pan', 'navigator']

export interface ReposContributorsChartProps {
  author?: Author
  weeks: Week[]
  totals: Totals
  metrics: SummarizedCommitMetrics
  selectedMetric: Metric
  onlyCommits?: boolean
  place?: number
}

const DATE_FORMAT_OPTIONS: Intl.DateTimeFormatOptions = {
  month: 'short',
  day: 'numeric',
  year: 'numeric',
}
const intersectionObserverOptions = {
  root: null,
  rootMargin: '20px',
  threshold: 0,
}

export default function ReposContributorsChart({
  author,
  weeks,
  totals,
  metrics,
  selectedMetric,
  onlyCommits = false,
  place,
}: ReposContributorsChartProps) {
  const columnCharts = useFeatureFlag('repos_column_charts')
  const rangeSelection = useRangeSelection()
  const {addValue, max} = useCalculatedMax()

  const metricDisplayName = `${selectedMetric.slice(0, 1).toUpperCase()}${selectedMetric.slice(1)}`
  const firstDate = columnCharts && rangeSelection.from ? new Date(rangeSelection.from) : weeks[0]?.date
  const lastDate = columnCharts && rangeSelection.to ? new Date(rangeSelection.to) : weeks.at(-1)?.date

  const isAcrossMultipleYears = firstDate?.getFullYear() !== lastDate?.getFullYear()

  const screenReaderTitleSuffix = `'s ${metricDisplayName}`
  const firstDateDisplay = firstDate?.toLocaleDateString(undefined, DATE_FORMAT_OPTIONS)
  const lastDateDisplay = lastDate?.toLocaleDateString(undefined, DATE_FORMAT_OPTIONS)

  const size = author ? 'small' : 'medium'

  const containerRef = useRef(null)
  const [isVisible, setIsVisible] = useState(!author)

  const chartRef = useRef<HighchartsReactRefObject>(null)

  const onObserverUpdate: IntersectionObserverCallback = useCallback(
    entries => {
      const [entry] = entries
      setIsVisible(!!entry?.isIntersecting)
      if (entry?.isIntersecting) {
        const chart = chartRef.current?.chart
        if (!chart || !author) return
        chart.yAxis[0]?.setExtremes(0, max, true, false, {
          trigger: 'sync',
        })
      }
    },
    [author, chartRef, max, setIsVisible],
  )

  useEffect(() => {
    const observer = new IntersectionObserver(onObserverUpdate, intersectionObserverOptions)
    const containerRefCurrent = containerRef.current
    if (containerRefCurrent) {
      if (isVisible) {
        observer.unobserve(containerRefCurrent)
      } else {
        observer.observe(containerRefCurrent)
      }
    }

    return () => {
      if (containerRefCurrent) observer.unobserve(containerRefCurrent)
    }
  }, [containerRef, isVisible, onObserverUpdate])

  // When dates change, update the chart's navigator (the range selector)
  useEffect(() => {
    const chart = chartRef.current?.chart
    if (!columnCharts || !chart) return
    const {dataMin, dataMax} = chart.xAxis[0]?.getExtremes() ?? {}
    chart.xAxis[0]?.setExtremes(rangeSelection.from ?? dataMin, rangeSelection.to ?? dataMax, true)
  }, [author, columnCharts, chartRef, metrics, selectedMetric, rangeSelection])

  useEffect(() => {
    if (chartRef.current && author) {
      const chart = chartRef.current?.chart
      chart.yAxis[0]?.setExtremes(0, max, true, false, {
        trigger: 'sync',
      })
    }
  }, [author, chartRef, max])

  const type = columnCharts ? 'column' : 'areaspline'

  const options = useMemo<ChartProps>(
    () => ({
      showRangeSelector: columnCharts && !author,
      dataGrouping: columnCharts && !!author,
      type,
      series: [
        {
          type,
          name: metricDisplayName,
          data: metrics[selectedMetric],
        },
      ],
      xAxisTitle: '',
      yAxisTitle: 'Contributions',
      plotOptions: {
        series: {
          marker: {
            enabled: false,
          },
        },
        column: columnCharts
          ? {
              pointPadding: 0,
              borderWidth: 1,
              borderColor: 'var(--bgColor-default)',
              groupPadding: 0,
              borderRadius: 2,
              states: {
                hover: {
                  color: `color-mix(in srgb, var(--data-blue-color-emphasis) 80%, transparent)`,
                },
              },
            }
          : undefined,
      },
      xAxisOptions: {
        min: rangeSelection.from,
        max: rangeSelection.to,
        minRange: 7 * 24 * 60 * 60 * 1000,
        type: 'datetime',
        labels: {
          format: columnCharts ? undefined : `{value:%b %e${columnCharts || isAcrossMultipleYears ? ', %Y' : ''}}`,
        },
        events: {
          afterSetExtremes: debounce(({trigger, min, max: _max}: AxisSetExteremesEventObject) => {
            if (columnCharts && SELECTION_TRIGGERS.includes(trigger)) {
              rangeSelection.setDate({from: min, to: _max})
            }
          }, 100),
        },
      },
      yAxisOptions: {
        ...(author
          ? {
              min: 0,
              max,
            }
          : {}),
        endOnTick: false,
        maxPadding: 0.2,
        tickPixelInterval: author ? 25 : 29,
        labels: {
          align: 'left',
          x: 5,
          y: 3,
        },
      },
      tooltipOptions: {
        xDateFormat: 'Week of %e %b, %Y',
        split: false,
      },
      overrideOptionsNotRecommended: {
        chart: {
          panning: {
            enabled: !author,
          },
          zooming: {
            mouseWheel: {
              enabled: false,
            },
            resetButton: {
              theme: {
                style: {
                  display: 'none',
                },
              },
            },
          },
          events: {
            load() {
              if (author) {
                // @ts-expect-error -- We know either yData or processedYData exist at runtime
                const yData = this.series?.[0].processedYData || this.series?.[0].yData
                addValue(Math.max(...yData))
              }
            },
            redraw() {
              if (author) {
                // @ts-expect-error -- We know processedYData exists at runtime
                const yData = this.series?.[0].processedYData || this.series?.[0].yData
                addValue(Math.max(...yData))
              }
            },
          },
          // compensates for the space taken up by the navigator handles and scrollbar
          // 10 is the default horizontal padding in highcharts
          spacing: author ? undefined : [0, 10, 0, 10],
        },
        exporting: {
          csv: {
            columnHeaderFormatter: (item: SeriesOptionsType) => (item.isXAxis ? 'Week of' : item.name),
          },
        },
        rangeSelector: {
          enabled: false,
        },
        scrollbar: {
          enabled: !author,
        },
        navigator: {
          enabled: !author,
        },
      },
    }),
    // Workaround to stop re-renders from stealing focus on the chart navigator,
    // see https://github.com/github/github/pull/341018#issuecomment-2407609939
    // eslint-disable-next-line react-hooks/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
    !columnCharts || author ? [metrics, rangeSelection, max] : [],
  )

  return (
    <div ref={containerRef} style={{minHeight: chartHeights[size]}}>
      {isVisible ? (
        <ChartCard size={size} chartRef={chartRef}>
          <ChartCard.Title as="h2">
            {author ? (
              <span className="d-flex flex-items-center flex-justify-start">
                <Link href={author.path}>{author.login}</Link>
                <span className="sr-only">{screenReaderTitleSuffix}</span>
              </span>
            ) : (
              <span>{metricDisplayName} over time</span>
            )}
          </ChartCard.Title>
          <ChartCard.Description>
            {author ? (
              <AuthorDescription author={author} totals={totals} onlyCommits={onlyCommits} />
            ) : (
              <span>
                Weekly from {firstDateDisplay} to {lastDateDisplay}
              </span>
            )}
          </ChartCard.Description>
          {author ? (
            <ChartCard.LeadingVisual>
              <Link href={author.path} data-hovercard-url={author.hovercard_url}>
                <GitHubAvatar src={author.avatar} size={40} />
                <span className="sr-only">{author.login}</span>
              </Link>
            </ChartCard.LeadingVisual>
          ) : null}
          {place ? (
            <ChartCard.TrailingVisual>
              <Label>#{place}</Label>
            </ChartCard.TrailingVisual>
          ) : null}
          <ChartCard.Chart {...options} />
        </ChartCard>
      ) : null}
    </div>
  )
}

type AuthorDescriptionProps = {
  author: Author
  onlyCommits?: boolean
  totals: {
    additions: number
    deletions: number
    commits: number
  }
}
function AuthorDescription({
  author,
  onlyCommits = false,
  totals: {additions, deletions, commits},
}: AuthorDescriptionProps) {
  const {owner, repo} = useParams()
  const [prettyCommits, prettyAdditions, prettyDeletions] = [commits, additions, deletions].map(value =>
    value.toLocaleString(),
  )
  return (
    <div className={styles.authorDescriptionWrapper}>
      <Link href={`/${owner}/${repo}/commits?author=${encodeURIComponent(author.login)}`} muted>
        {prettyCommits} commit{commits > 1 ? 's' : ''}
      </Link>
      {!onlyCommits ? (
        <span className={styles.additionsDeletionsWrapper}>
          <span className="color-fg-success">{prettyAdditions} ++</span>
          <span className="color-fg-danger">{prettyDeletions} --</span>
        </span>
      ) : null}
    </div>
  )
}

import {Box, Heading} from '@primer/react'
import capitalize from 'lodash-es/capitalize'

import {ChartCard} from '@github-ui/chart-card'

import {ErrorComponent, LoadingComponent, NoDataComponent} from '..'

import {RequestState, UsageGrouping, UsagePeriod} from '../../enums'
import {boxStyle} from '../../utils/style'
import {getPeriodText} from '../../utils'

import type {Filters, UsageChartData} from '../../types/usage'
import type {ReactNode} from 'react'

const containerStyle = {
  ...boxStyle,
  width: '100%',
  height: '100%',
  p: 0,
  mb: 3,
}

const chartHeaderContainerStyle = {
  display: 'flex',
  alignItems: 'center',
  justifyContent: 'space-between',
  pl: 3,
  pr: 3,
  pt: 3,
}

const innerContainerStyle = {
  height: '432px',
  border: 0,
}

const chartSubtitleStyle = (showTitle: boolean) => {
  if (showTitle) {
    return {
      color: 'fg.muted',
      fontSize: '14px',
      fontWeight: 'normal',
    }
  } else {
    return {
      color: 'fg.muted',
      fontSize: '16px',
      fontWeight: 'bold',
    }
  }
}

function getChartTitle(filters: Filters) {
  let title = 'Metered usage'
  let groupByType = ''

  switch (filters.group?.type) {
    case UsageGrouping.ORG: {
      groupByType = 'Organization'
      break
    }
    case UsageGrouping.REPO: {
      groupByType = 'Repository'
      break
    }
    case UsageGrouping.SKU: {
      groupByType = 'SKU'
      break
    }
    case UsageGrouping.PRODUCT: {
      groupByType = 'Product'
      break
    }
    case UsageGrouping.COSTCENTER: {
      groupByType = 'Cost Center'
      break
    }
  }

  // Only attempt to add filter data to the title text if it exists and has a filter value
  if (filters.searchQuery && filters.searchQuery.includes(':')) {
    let queryPartsTitleText = ''
    // Split by spaces, unless those spaces are in quotation marks, which is common for cost center names
    const queryParts = filters.searchQuery.match(/(?:[^\s"]+|"[^"]*")+/g) || []

    for (const queryPart of queryParts) {
      const [groupByField, groupByValue] = queryPart.split(':')

      if (!groupByField || !groupByValue) continue

      if (['repo', 'org'].includes(groupByField)) {
        queryPartsTitleText += `${groupByValue} `
      } else if (['product', 'sku'].includes(groupByField)) {
        queryPartsTitleText += `${capitalize(groupByValue)} `
      } else if (['cost_center'].includes(groupByField)) {
        // Cost center names with spaces will be in quotation marks, remove those if present at beginning and end
        if (groupByValue.startsWith('"') && groupByValue.endsWith('"')) {
          queryPartsTitleText += `${groupByValue.split('').slice(1, -1).join('')} `
        } else {
          queryPartsTitleText += `${groupByValue} `
        }
      }
    }

    if (queryPartsTitleText) title = `${queryPartsTitleText} usage`
  }

  if (groupByType) title += ` grouped by ${groupByType}`

  return title
}

function getChartPeriod(filters: Filters) {
  switch (filters.period?.type) {
    case UsagePeriod.THIS_YEAR:
    case UsagePeriod.LAST_YEAR: {
      return 30 * 24 * 3600 * 1000 // month
    }
    case UsagePeriod.THIS_MONTH:
    case UsagePeriod.LAST_MONTH: {
      return 24 * 3600 * 1000 // day
    }
    case UsagePeriod.TODAY: {
      return 3600 * 1000 // hour
    }
    default: {
      return 24 * 3600 * 1000 // day
    }
  }
}

function getTooltipLabel(filters: Filters) {
  switch (filters.period?.type) {
    case UsagePeriod.THIS_YEAR:
    case UsagePeriod.LAST_YEAR: {
      return 'in %b %Y' // month
    }
    case UsagePeriod.THIS_MONTH:
    case UsagePeriod.LAST_MONTH: {
      return 'on %b %e, %Y' // day
    }
    case UsagePeriod.TODAY: {
      return 'at %l%p' // hour
    }
    default: {
      return '%b %e, %Y' // day
    }
  }
}

function getXAxisLabel(filters: Filters) {
  switch (filters.period?.type) {
    case UsagePeriod.THIS_YEAR:
    case UsagePeriod.LAST_YEAR: {
      return '{value:%b}' // month
    }
    case UsagePeriod.THIS_MONTH:
    case UsagePeriod.LAST_MONTH: {
      return '{value:%b %e}' // month day
    }
    case UsagePeriod.TODAY: {
      return '{value:%l%p}' // hour AM/PM
    }
    default: {
      return '{value:%b %e}' // month day
    }
  }
}

interface UsageChartProps {
  filters: Filters
  requestState: RequestState
  usage: UsageChartData[]
  // Used to add children alongside the usage actions component.
  children?: ReactNode
  // Whether or not to show the chart title. The subtitle is always shown. Defaults to true
  showTitle?: boolean
}

const isLoadingStates = new Set<RequestState>([RequestState.INIT, RequestState.LOADING])

export function UsageChart({filters, requestState, usage, children, showTitle = true}: UsageChartProps) {
  const usageLength = usage.length
  const chartLoaded = requestState === RequestState.IDLE && usageLength > 0
  const usageChartStartDate = usage[0]?.data[0]?.x

  return (
    <div data-hpc>
      <Box sx={{pb: 2, display: ['block', 'none'], maxWidth: '100%'}}>{children}</Box>
      <Box sx={chartLoaded ? {} : containerStyle}>
        {!chartLoaded && (
          <Box sx={chartHeaderContainerStyle}>
            <div>
              {showTitle && (
                <Heading as="h3" sx={{fontSize: 2}} id="usage-chart-title" data-testid="usage-chart-title">
                  {getChartTitle(filters)}
                </Heading>
              )}
              <Heading
                as={showTitle ? 'h4' : 'h3'}
                sx={chartSubtitleStyle(showTitle)}
                id="usage-chart-subtitle"
                data-testid="usage-chart-subtitle"
                className={showTitle ? '' : 'h4'}
              >
                {getPeriodText(filters.period)}
              </Heading>
            </div>
            <Box sx={{pr: 2, display: ['none', 'block']}}>{children}</Box>
          </Box>
        )}

        <Box sx={{mb: 3}}>
          {isLoadingStates.has(requestState) && (
            <LoadingComponent sx={innerContainerStyle} testid="usage-loading-spinner" />
          )}
          {requestState === RequestState.ERROR && (
            <ErrorComponent sx={innerContainerStyle} testid="usage-loading-error" text="Something went wrong" />
          )}
          {requestState === RequestState.IDLE && (
            <>
              {usageLength === 0 && (
                <NoDataComponent sx={innerContainerStyle} testid="no-usage-data" text="No usage found" />
              )}
              {usageLength > 0 && (
                <ChartCard size="xl" border>
                  <ChartCard.Title sx={showTitle ? {} : chartSubtitleStyle(showTitle)}>
                    {showTitle ? getChartTitle(filters) : getPeriodText(filters.period)}
                  </ChartCard.Title>
                  {showTitle && <ChartCard.Description>{getPeriodText(filters.period)}</ChartCard.Description>}
                  <ChartCard.TrailingVisual>
                    <Box sx={{pr: 2, display: ['none', 'block']}}>{children}</Box>
                  </ChartCard.TrailingVisual>
                  <ChartCard.Chart
                    series={usage.map(dataset => ({...dataset, type: 'areaspline'}))}
                    xAxisTitle={'Time'}
                    yAxisTitle={'Billing'}
                    xAxisOptions={{
                      type: 'datetime',
                      labels: {
                        format: getXAxisLabel(filters),
                      },
                      title: {
                        text: null,
                      },
                      gridLineDashStyle: 'Solid',
                    }}
                    yAxisOptions={{
                      labels: {
                        format: '${value:,.0f}',
                      },
                      gridLineDashStyle: 'Solid',
                      title: {
                        text: null,
                      },
                    }}
                    plotOptions={{
                      series: {
                        pointStart: usageChartStartDate,
                        pointInterval: getChartPeriod(filters),
                        marker: {
                          enabled: false,
                        },
                      },
                    }}
                    type={'areaspline'}
                    overrideOptionsNotRecommended={{
                      legend: {
                        enabled: true,
                        margin: 16,
                        align: 'left',
                        layout: 'horizontal',
                        verticalAlign: 'top',
                        floating: false,
                        maxHeight: 64,
                      },
                      tooltip: {
                        dateTimeLabelFormats: {
                          millisecond: getTooltipLabel(filters),
                        },
                        // eslint-disable-next-line github/unescaped-html-literal
                        headerFormat: '<table><tr><th colspan="2">{series.name} {point.key}</th></tr>',
                        pointFormat:
                          // eslint-disable-next-line github/unescaped-html-literal
                          '<tr><td style="padding-top:var(--base-size-4)"><span style="color:{point.color}">●</span> Gross:</td><td style="text-align: right; padding-top:var(--base-size-4);"><strong>{point.custom.grossAmount:,.2f}</strong></td></tr><tr><td style="padding-top:var(--base-size-4); padding-left:16px"> Billed:</td><td style="text-align: right; padding-top:var(--base-size-4);"><strong>{point.custom.totalAmount:,.2f}</strong></td></tr><tr><td style="padding-top:var(--base-size-4); padding-left:16px"> Discount:</td><td style="text-align: right; padding-top:var(--base-size-4);"><strong>{point.custom.discountAmount:,.2f}</strong></td></tr><table>',
                      },
                      accessibility: {keyboardNavigation: {order: ['legend', 'series']}},
                    }}
                  />
                </ChartCard>
              )}
            </>
          )}
        </Box>
      </Box>
    </div>
  )
}

export default UsageChart

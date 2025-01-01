import {GearIcon} from '@primer/octicons-react'
import {Button, IconButton} from '@primer/react'
import {useMemo, useState} from 'react'

import ChartCard from '../../../common/components/chart-card'
import {HpcTag} from '../../../common/components/HpcTag'
import {usePaths} from '../../../common/contexts/Paths'
import {FunnelOrderingDialog} from './FunnelOrderingDialog'
import {useAlertTrendsQuery} from './use-alert-trends-query'

// Fixed category that will always stay at the top
const FIXED_CATEGORY = 'Matching Alerts'
// Reorderable categories default order
const DEFAULT_CUSTOM_CATEGORIES = ['has:patch', 'severity:critical,high', 'epss_percentage:>=0.01']
// Number of times each category is repeated in the chart
const REPEAT_CATEGORY_COUNT = 5

// Matches the DEFAULT_QUERY in ::SecurityCenter::Metrics::DependabotController
export const DEFAULT_QUERY: string = 'archived:false'

const filtersByCategory = new Map<string, string>([
  ['has:patch', 'has:patch'],
  ['severity:critical,high', 'severity:critical,high'],
  ['epss_percentage:>=0.01', 'epss_percentage:>=0.01'],
])

// Build the funnelOrder string from customCategories.
interface AlertsTimechartCardProps {
  query?: string
  allowedDependabotQualifiers: string[]
}

export function AlertsTimechartCard({
  query = DEFAULT_QUERY,
  allowedDependabotQualifiers,
}: AlertsTimechartCardProps): JSX.Element {
  const [customCategories, setCustomCategories] = useState<string[]>(DEFAULT_CUSTOM_CATEGORIES)
  const funnelOrder = customCategories.join(' ')
  const dataQuery = useAlertTrendsQuery({
    query,
    funnelOrder,
  })
  const [queryIsDirty, setQueryIsDirty] = useState(false)
  // State to control the ordering dialog open/close
  const [isOrderingOpen, setOrderingOpen] = useState(false)
  // Merge the fixed Matching Alerts with the custom (reorderable) categories
  const categories = useMemo(() => [FIXED_CATEGORY, ...customCategories], [customCategories])
  const repeatedCategories = useMemo(
    () => categories.flatMap(category => Array(REPEAT_CATEGORY_COUNT).fill(category)),
    [categories],
  )
  const paths = usePaths()

  // remove any token whose "qualifier:" isn’t in the list
  function sanitizeDependabotQuery(q: string): string {
    return q
      .split(/,\s+|\s+/)
      .filter(tok => {
        const [qual] = tok.split(':', 1)
        return qual !== undefined && allowedDependabotQualifiers.includes(qual)
      })
      .join(' ')
  }

  // Define formatLabelWithUrl here so it has access to customCategories
  function formatLabelWithUrl(labelText: string, count: number, isFirst: boolean): string {
    const index = customCategories.indexOf(labelText)
    const selectedCategories = customCategories.slice(0, index + 1)
    const selectedFilters = selectedCategories.map(cat => filtersByCategory.get(cat)).filter(Boolean) as string[]
    const sanitizeBaseQuery = sanitizeDependabotQuery(query)
    const searchQuery = [sanitizeBaseQuery, ...selectedFilters].filter(Boolean).join(' ')
    const url = paths.dependabotAlertsListPath({query: searchQuery.trim()})
    // Create outer div
    const wrapper = document.createElement('div')
    // Create <a> with count
    const anchor = document.createElement('a')
    anchor.href = url
    // Ensure clicking an x-axis alert count in the funnel chart navigates
    // to the Dependabot alerts page in the current tab
    anchor.target = '_self'
    anchor.className = 'color-fg-accent'
    anchor.setAttribute('aria-label', String(count))

    const countElement = document.createElement('strong')
    countElement.textContent = count.toLocaleString()
    anchor.appendChild(countElement)
    wrapper.appendChild(anchor)
    wrapper.appendChild(document.createElement('br'))

    // Add label text with previous labels in separate divs
    const labelsWrapper = document.createElement('div')
    labelsWrapper.style.display = 'flex'
    labelsWrapper.style.flexWrap = 'wrap'
    labelsWrapper.style.gap = '2px'
    labelsWrapper.style.marginTop = '5px'
    labelsWrapper.style.lineHeight = '1' // remove extra vertical spacing

    const currentIndex = customCategories.indexOf(labelText)
    const cumulativeLabels = isFirst ? [labelText] : [labelText, ...customCategories.slice(0, currentIndex).reverse()]

    for (const cumulativeLabel of cumulativeLabels) {
      const labelsDiv = document.createElement('div')
      labelsDiv.style.maxWidth = '100%'

      if (cumulativeLabel === FIXED_CATEGORY) {
        labelsDiv.textContent = cumulativeLabel
      } else {
        const markdownWrapper = document.createElement('div')
        markdownWrapper.className = 'markdown-body'
        markdownWrapper.style.lineHeight = '1'

        const label = document.createElement('code')
        label.textContent = cumulativeLabel
        label.style.fontSize = '11px'
        label.style.whiteSpace = 'nowrap'
        label.style.overflow = 'hidden'
        label.style.textOverflow = 'ellipsis'
        label.style.display = 'inline-block'
        label.style.maxWidth = '100%'
        label.style.lineHeight = '1'
        label.style.margin = '0'

        markdownWrapper.appendChild(label)
        labelsDiv.appendChild(markdownWrapper)
      }

      labelsWrapper.appendChild(labelsDiv)
    }

    wrapper.appendChild(labelsWrapper)

    return wrapper.outerHTML
  }

  const chartBlankslate = useMemo(() => {
    if (dataQuery.isPending) return {isLoading: true}
    if (dataQuery.isError) {
      return {
        isLoading: false,
        message: 'Alert trends could not be loaded right now.',
        isError: true,
        ariaLabel: 'Empty chart. Alert trends could not be loaded right now.',
      }
    }

    const total = dataQuery.data.points?.reduce((sum, point) => sum + point.y, 0) || 0

    if (total === 0) {
      return {
        isLoading: false,
        message: 'Try modifying your filters to see the security impact on your organization.',
        isError: false,
        ariaLabel: 'Empty chart. There are no alerts in this period.',
      }
    }

    return undefined
  }, [dataQuery])

  const categoryTotals = useMemo(() => {
    if (!dataQuery.isSuccess) return {}

    const totals: Record<string, number> = {}

    for (const category of categories) {
      const point = dataQuery.data.points?.find(p => p.x === category)
      totals[category] = point?.y || 0
    }

    return totals
  }, [dataQuery, categories])

  const chartSeries = useMemo(() => {
    if (!dataQuery.isSuccess) return []

    // Each category is duplicated 5 times to create a flattened visualization in the funnel chart.
    // Without this duplication, the chart would show a steep funnel shape. By repeating each
    // category multiple times, we spread the data points horizontally. The extra points are hidden
    // by setting the tickInterval to the same value as REPEAT_CATEGORY_COUNT.
    const categoriesMappedToPoints = categories.reduce<Highcharts.PointOptionsObject[]>((result, categoryLabel) => {
      const point = dataQuery.data.points?.find(p => p.x === categoryLabel)
      result.push({
        name: categoryLabel,
        y: point?.y ?? 0,
      })
      for (let i = 1; i < REPEAT_CATEGORY_COUNT; i++) {
        result.push({
          y: point?.y ?? 0,
          marker: {states: {hover: {enabled: false}}},
        })
      }
      return result
    }, [])

    return [
      {
        name: dataQuery.data.label,
        data: categoriesMappedToPoints,
        type: 'areaspline',
        color: 'var(--data-blue-color-emphasis)',
        borderColor: 'var(--data-blue-color-muted)',
        dashStyle: 'Solid',
        fillOpacity: 0.2,
        borderWidth: 1,
        marker: {
          enabled: false,
          symbol: 'circle',
          states: {
            hover: {enabled: true, lineWidth: 1, radius: 5},
          },
        },
      },
    ]
  }, [dataQuery, categories])

  const resetOrders = (): void => {
    // Reset to default query and custom reorderable categories.
    setQueryIsDirty(false)
    setCustomCategories(DEFAULT_CUSTOM_CATEGORIES)
  }

  return (
    <>
      <ChartCard
        blankslate={chartBlankslate}
        height={384}
        size="large"
        title="Alert prioritization"
        type="areaspline"
        series={chartSeries}
        categories={repeatedCategories}
        categoryTotals={categoryTotals}
        xAxisTitle=""
        yAxisTitle=""
        yAxisMin={0}
        xAxisLabelFormatter={formatLabelWithUrl}
        showTooltipTotalCount
        showNamedPointTooltipsOnly
        tickInterval={REPEAT_CATEGORY_COUNT}
        pointRange={1}
        pointStart={0}
        pointPlacement="on"
      >
        <ChartCard.Actions>
          <div style={{display: 'flex', gap: '8px', alignItems: 'center'}}>
            <IconButton
              onClick={() => setOrderingOpen(true)}
              aria-label="Configure funnel categories"
              icon={GearIcon}
              variant="invisible"
              className="color-fg-muted"
            />
            {queryIsDirty && (
              <Button size="small" variant="invisible" onClick={resetOrders}>
                Reset to default
              </Button>
            )}
          </div>
        </ChartCard.Actions>
      </ChartCard>
      <HpcTag loading={dataQuery.isPending} />
      {isOrderingOpen && (
        <FunnelOrderingDialog
          // Pass only the reorderable categories to the dialog
          initialOrder={customCategories}
          onSubmit={newOrder => {
            const isSame = JSON.stringify(newOrder) === JSON.stringify(DEFAULT_CUSTOM_CATEGORIES)
            setQueryIsDirty(!isSame)
            setCustomCategories(newOrder)
          }}
          closeDialog={() => setOrderingOpen(false)}
        />
      )}
    </>
  )
}

import {Accordion} from '@github-ui/accordion'
import type {CopilotHistoricalMetrics, CopilotMetricsDataType} from '@github-ui/copilot-metrics-insights'
import CopilotMetricsInsights from '@github-ui/copilot-metrics-insights/CopilotMetricsInsights'
import {useState} from 'react'

export interface StafftoolsCopilotMetricsDashboardsProps {
  dashboards: Array<{
    title: string
    historicalMetrics: CopilotHistoricalMetrics
    metricsDataType: CopilotMetricsDataType
  }>
}

export function StafftoolsCopilotMetricsDashboards({dashboards}: StafftoolsCopilotMetricsDashboardsProps) {
  const [expandedItems, setExpandedItems] = useState<string[]>([])
  return (
    <div>
      <Accordion expandedItems={expandedItems} onChange={setExpandedItems}>
        {dashboards.map(dashboard => (
          <Accordion.Item value={dashboard.title} key={dashboard.title}>
            <Accordion.Trigger>
              <h3>{dashboard.title}</h3>
            </Accordion.Trigger>
            <Accordion.Content>
              <CopilotMetricsInsights
                historicalMetrics={dashboard.historicalMetrics}
                metricsDataType={dashboard.metricsDataType}
              />
            </Accordion.Content>
          </Accordion.Item>
        ))}
      </Accordion>
    </div>
  )
}

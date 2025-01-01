import type {Meta, StoryObj} from '@storybook/react'
import CopilotMetricsInsights, {type CopilotMetricsInsightsProps} from './CopilotMetricsInsights'
import {
  getAverageContributionRoutePayload,
  getAveragePullRequestLeadTimeRoutePayload,
  getCompletionsAcceptanceRateRoutePayload,
  getCopilotMetricsInsightsRoutePayload,
  getGeneratedCodeAcceptanceRateRoutePayload,
} from '../test-utils/mock-data'

const meta = {
  title: 'CopilotMetricsInsights',
  component: CopilotMetricsInsights,
} satisfies Meta<typeof CopilotMetricsInsights>

export default meta

type Story = StoryObj<typeof CopilotMetricsInsights>

const adoptionMockData = getCopilotMetricsInsightsRoutePayload()
export const Adoption: Story = {
  args: {
    historicalMetrics: adoptionMockData.historicalMetrics,
    metricsDataType: adoptionMockData.metricsDataType,
  },
  render: (props: CopilotMetricsInsightsProps) => <CopilotMetricsInsights {...props} />,
}

const completionsAcceptanceMockData = getCompletionsAcceptanceRateRoutePayload()
export const CompletionsAcceptance: Story = {
  args: {
    historicalMetrics: completionsAcceptanceMockData.historicalMetrics,
    metricsDataType: completionsAcceptanceMockData.metricsDataType,
  },
  render: (props: CopilotMetricsInsightsProps) => <CopilotMetricsInsights {...props} />,
}

const generatedCodeAcceptanceMockData = getGeneratedCodeAcceptanceRateRoutePayload()
export const GeneratedCodeAcceptance: Story = {
  args: {
    historicalMetrics: generatedCodeAcceptanceMockData.historicalMetrics,
    metricsDataType: generatedCodeAcceptanceMockData.metricsDataType,
  },
  render: (props: CopilotMetricsInsightsProps) => <CopilotMetricsInsights {...props} />,
}

const averageContributionMockData = getAverageContributionRoutePayload()
export const AverageContribution: Story = {
  args: {
    historicalMetrics: averageContributionMockData.historicalMetrics,
    metricsDataType: averageContributionMockData.metricsDataType,
  },
  render: (props: CopilotMetricsInsightsProps) => <CopilotMetricsInsights {...props} />,
}
const averagePullRequestLeadTimeMockData = getAveragePullRequestLeadTimeRoutePayload()
export const AveragePullRequestLeadTime: Story = {
  args: {
    historicalMetrics: averagePullRequestLeadTimeMockData.historicalMetrics,
    metricsDataType: averagePullRequestLeadTimeMockData.metricsDataType,
  },
  render: (props: CopilotMetricsInsightsProps) => <CopilotMetricsInsights {...props} />,
}

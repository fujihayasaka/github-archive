import {App} from './App'
import {CopilotMetricsInsightsViewer} from './routes/CopilotMetricsInsightsViewer'
import {CopilotMetricsInsightsCatalog} from './routes/CopilotMetricsInsightsCatalog'
import {registerNavigatorApp} from '@github-ui/react-core/register-app'
import {jsonRoute} from '@github-ui/react-core/json-route'

registerNavigatorApp('copilot-metrics-insights', () => ({
  App,
  routes: [
    jsonRoute({path: '/orgs/:org/insights/metrics', Component: CopilotMetricsInsightsCatalog}),
    jsonRoute({path: '/orgs/:org/insights/metrics/copilot-user-onboarding', Component: CopilotMetricsInsightsViewer}),
    jsonRoute({
      path: '/orgs/:org/insights/metrics/copilot-code-completions-acceptance-rate',
      Component: CopilotMetricsInsightsViewer,
    }),
    jsonRoute({
      path: '/orgs/:org/insights/metrics/copilot-generated-code-acceptance-rate',
      Component: CopilotMetricsInsightsViewer,
    }),
    jsonRoute({
      path: '/orgs/:org/insights/metrics/average-commits-per-developer',
      Component: CopilotMetricsInsightsViewer,
    }),
    jsonRoute({
      path: '/orgs/:org/insights/metrics/average-pull-requests-merged-per-developer',
      Component: CopilotMetricsInsightsViewer,
    }),
    jsonRoute({
      path: '/orgs/:org/insights/metrics/pull-request-lead-time',
      Component: CopilotMetricsInsightsViewer,
    }),
  ],
}))

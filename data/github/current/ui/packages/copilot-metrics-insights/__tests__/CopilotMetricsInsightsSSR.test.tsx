/** @jest-environment node */
import {serverRenderReact} from '@github-ui/ssr-test-utils/server-render'
import {
  getCompletionsAcceptanceRateRoutePayload,
  getCopilotMetricsInsightsRoutePayload,
  getGeneratedCodeAcceptanceRateRoutePayload,
} from '../test-utils/mock-data'

// Register with react-core before attempting to render
import '../ssr-entry'

test('Renders CopilotMetricsInsights with SSR', async () => {
  const routePayload = getCopilotMetricsInsightsRoutePayload()
  const view = await serverRenderReact({
    name: 'copilot-metrics-insights',
    path: 'orgs/:org/insights/metrics/copilot-user-onboarding',
    data: {payload: routePayload},
  })

  expect(view).toMatch('copilot-metrics-chart-loading')
})

test('Renders CompletionsAcceptanceRate with SSR', async () => {
  const routePayload = getCompletionsAcceptanceRateRoutePayload()
  const view = await serverRenderReact({
    name: 'copilot-metrics-insights',
    path: 'orgs/:org/insights/metrics/copilot-code-completions-acceptance-rate',
    data: {payload: routePayload},
  })

  expect(view).toMatch('copilot-metrics-chart-loading')
})

test('Renders GeneratedCodeAccceptanceRate with SSR', async () => {
  const routePayload = getGeneratedCodeAcceptanceRateRoutePayload()
  const view = await serverRenderReact({
    name: 'copilot-metrics-insights',
    path: 'orgs/:org/insights/metrics/copilot-generated-code-acceptance-rate',
    data: {payload: routePayload},
  })

  expect(view).toMatch('copilot-metrics-chart-loading')
})

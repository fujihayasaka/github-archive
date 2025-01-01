/** @jest-environment node */
import {serverRenderReact} from '@github-ui/ssr-test-utils/server-render'
import {getCopilotMetricsInsightsRoutePayload} from '../test-utils/mock-data'

// Register with react-core before attempting to render
import '../ssr-entry'

test('Renders CopilotMetricsInsights with SSR', async () => {
  const routePayload = getCopilotMetricsInsightsRoutePayload()
  const view = await serverRenderReact({
    name: 'copilot-metrics-insights',
    path: 'orgs/:org/insights/metrics/copilot-user-engagement',
    data: {payload: routePayload},
  })

  expect(view).toMatch('copilot-metrics-chart-loading')
})

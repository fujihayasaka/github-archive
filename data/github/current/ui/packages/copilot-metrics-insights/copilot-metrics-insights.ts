import {App} from './App'
import {CopilotMetricsInsights} from './routes/CopilotMetricsInsights'
import {registerNavigatorApp} from '@github-ui/react-core/register-app'
import {jsonRoute} from '@github-ui/react-core/json-route'

registerNavigatorApp('copilot-metrics-insights', () => ({
  App,
  routes: [jsonRoute({path: '/orgs/:org/insights/metrics/copilot-user-engagement', Component: CopilotMetricsInsights})],
}))

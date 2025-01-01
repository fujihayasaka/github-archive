import {it, expect} from '@github-ui/tests'
import {serverRenderReact} from '@github-ui/ssr-test-utils/server-render'
import {getStafftoolsCopilotMetricsDashboardsProps} from './utils/mock-data'

// Register with react-core before attempting to render
import '../ssr-entry'

it('Renders stafftools-copilot-metrics-dashboards partial with SSR', async () => {
  const props = getStafftoolsCopilotMetricsDashboardsProps()
  const view = await serverRenderReact({
    name: 'stafftools-copilot-metrics-dashboards',
    data: {props},
  })

  expect(view).toMatch('Dashboard Title')
})

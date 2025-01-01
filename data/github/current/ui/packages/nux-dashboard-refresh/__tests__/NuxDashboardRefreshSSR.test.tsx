/** @jest-environment node */
import {serverRenderReact} from '@github-ui/ssr-test-utils/server-render'
import {getNuxDashboardRefreshPropsForSSRTest} from '../test-utils/mock-data'

// Register with react-core before attempting to render
import '../ssr-entry'

test('Renders nux-dashboard-refresh partial with SSR', async () => {
  const props = getNuxDashboardRefreshPropsForSSRTest()
  const view = await serverRenderReact({
    name: 'nux-dashboard-refresh',
    data: {props},
  })

  expect(view).toMatch(/GitHub for beginners on YouTube/)
  expect(view).toMatch(/Getting started/)
  expect(view).toMatch(/Start with GitHub Docs/)
  expect(view).toMatch(/Recommendations/)

  expect(view).toMatch(/Download Visual Studio with Copilot/)

  // The desktop banner should be hidden based on the test data
  expect(view).not.toMatch(/Download GitHub for Desktop/)

  // The first step should be checked and the rest unchecked based on the test data
  expect(view).toMatch(/stepper-step-0-checked/)
  expect(view).toMatch(/stepper-step-1-unchecked/)
  expect(view).toMatch(/stepper-step-2-unchecked/)
})

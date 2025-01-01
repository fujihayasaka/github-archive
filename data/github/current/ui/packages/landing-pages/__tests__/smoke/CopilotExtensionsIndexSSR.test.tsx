/** @jest-environment node */
import {serverRenderReact} from '@github-ui/ssr-test-utils/server-render'

// Register with react-core before attempting to render
import '../../ssr-entry'

test('Renders CopilotExtensionsIndex with SSR', async () => {
  const view = await serverRenderReact({
    name: 'landing-pages',
    path: '/features/copilot/extensions',
    data: {payload: {}},
  })

  // verify Hero
  expect(view).toMatch('Copilot Extensions')
})

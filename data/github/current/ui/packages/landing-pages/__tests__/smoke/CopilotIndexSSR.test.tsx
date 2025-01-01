/** @jest-environment node */
import {serverRenderReact} from '@github-ui/ssr-test-utils/server-render'

// Register with react-core before attempting to render
import '../../ssr-entry'

import featuresCopilotPagePayload from '../fixtures/routes/FeaturesCopilotPage/indexPagePayload'

test('Renders CopilotIndex with SSR', async () => {
  const view = await serverRenderReact({
    name: 'landing-pages',
    path: '/features/copilot',
    data: {
      payload: featuresCopilotPagePayload,
    },
  })

  // verify Hero
  expect(view).toMatch('GitHub Copilot')
})

/** @jest-environment node */
import {serverRenderReact} from '@github-ui/ssr-test-utils/server-render'

// Register with react-core before attempting to render
import '../../ssr-entry'

import PlansIndexPayload from '../fixtures/routes/security/plans-index-payload'

test('Renders SecurityPlansIndex with SSR', async () => {
  const view = await serverRenderReact({
    name: 'landing-pages',
    path: '/security/plans',
    data: {
      payload: PlansIndexPayload,
    },
  })

  // verify Hero
  expect(view).toMatch('Security')
})

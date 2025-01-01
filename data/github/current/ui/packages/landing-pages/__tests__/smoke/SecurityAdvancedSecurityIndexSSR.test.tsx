/** @jest-environment node */
import {serverRenderReact} from '@github-ui/ssr-test-utils/server-render'

// Register with react-core before attempting to render
import '../../ssr-entry'

import AdvancedSecurityIndexPayload from '../fixtures/routes/security/advanced-security-index-payload'

test('Renders SecurityAdvancedSecurityIndex with SSR', async () => {
  const view = await serverRenderReact({
    name: 'landing-pages',
    path: '/security/advanced-security',
    data: {
      payload: AdvancedSecurityIndexPayload,
    },
  })

  // verify Hero
  expect(view).toMatch('Advanced Security')
})

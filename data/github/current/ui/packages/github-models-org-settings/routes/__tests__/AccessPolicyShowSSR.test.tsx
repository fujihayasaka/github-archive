/** @jest-environment node */
// Register with react-core before attempting to render
import '../../ssr-entry'

import {serverRenderReact} from '@github-ui/ssr-test-utils/server-render'
import {organizationSettingsModelsAccessPolicyPath} from '@github-ui/paths'

import {mockAccessPolicyShowPayload} from '../../test-utils/mocks'

describe('AccessPolicyShow with server-side rendering', () => {
  it('renders', async () => {
    const routePayload = mockAccessPolicyShowPayload()
    const view = await serverRenderReact({
      name: 'github-models-org-settings',
      path: organizationSettingsModelsAccessPolicyPath({org: ':org'}),
      data: {payload: routePayload},
    })

    expect(view).toMatch('Models in your organization')
  })
})

import '../../ssr-entry'

import {describe, it, expect} from '@github-ui/tests'
import {serverRenderReact} from '@github-ui/ssr-test-utils/server-render'
import {accessPolicyShow} from '../access-policy-show-route'

import {mockAccessPolicyShowPayload} from '../../test-utils/mocks'

describe('AccessPolicyShow with server-side rendering', () => {
  it('renders', async () => {
    const routePayload = mockAccessPolicyShowPayload()
    const view = await serverRenderReact({
      name: 'github-models-org-settings',
      path: accessPolicyShow.generatePath({org: 'my-org'}),
      data: {
        payload: {
          [accessPolicyShow.id]: routePayload,
        },
      },
      data_router_enabled: true,
    })

    expect(view).toMatch('Models in your organization')
  })
})

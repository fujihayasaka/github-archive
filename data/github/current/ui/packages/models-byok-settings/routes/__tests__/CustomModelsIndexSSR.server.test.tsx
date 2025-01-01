// Register with react-core before attempting to render
import '../../ssr-entry'

import {serverRenderReact} from '@github-ui/ssr-test-utils/server-render'
import {describe, expect, it} from '@github-ui/tests'

import {mockCustomModelsIndexPayload} from '../../test-utils/mocks'
import {customModelsIndexRoute} from '../CustomModelsIndex/custom-models-index-route'

describe('CustomModelsIndex with server-side rendering', () => {
  it('renders', async () => {
    const routePayload = mockCustomModelsIndexPayload()
    const view = await serverRenderReact({
      name: 'models-byok-settings',
      path: customModelsIndexRoute.generatePath({org: 'my-org'}),
      data: {
        appPayload: {
          enabled_features: {github_models_byok: true},
        },
        payload: {
          [customModelsIndexRoute.id]: routePayload,
        },
      },
      data_router_enabled: true,
    })

    expect(view).toMatch('Custom models')
  })
})

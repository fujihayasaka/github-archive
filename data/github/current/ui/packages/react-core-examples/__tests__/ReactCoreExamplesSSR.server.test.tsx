// Register with react-core before attempting to render
import '../ssr-entry'

import {serverRenderReact} from '@github-ui/ssr-test-utils/server-render'
import {expect, it} from '@github-ui/tests'

import {getReactCoreExamplesRoutePayload} from './utils/mock-data'

it('Renders reactCoreExamplesIndexRoute with SSR', async () => {
  const routePayload = getReactCoreExamplesRoutePayload()
  const view = await serverRenderReact({
    name: 'react-core-examples',
    path: '/_react_core_examples',
    data: routePayload,
    data_router_enabled: true,
  })

  // verify ssr was able to render some content from the payload
  expect(view).toContain('Welcome')
  expect(view).toContain('testuser')
})

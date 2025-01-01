// Register with react-core before attempting to render
import '../ssr-entry'

import {serverRenderReact} from '@github-ui/ssr-test-utils/server-render'
import {expect, it} from '@github-ui/tests'

import {getReactSandboxRoutePayload} from './utils/mock-data'

it('Renders ReactSandbox with SSR', async () => {
  const routePayload = getReactSandboxRoutePayload()

  const view = await serverRenderReact({
    name: 'react-sandbox',
    path: '/_react_sandbox',
    data: {payload: routePayload},
  })

  // verify ssr was able to render some content from the payload
  expect(view).toMatch(routePayload.greeting)
})

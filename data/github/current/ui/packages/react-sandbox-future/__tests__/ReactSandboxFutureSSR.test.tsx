/** @jest-environment node */
import {serverRenderReact} from '@github-ui/ssr-test-utils/server-render'
import {getReactSandboxFutureIdRoutePayload, getReactSandboxFutureIndexRoutePayload} from '../test-utils/mock-data'

// Register with react-core before attempting to render
import '../ssr-entry'

describe('react-sandbox-future SSR', () => {
  test('Renders reactSandboxFutureIndexRoute with SSR', async () => {
    const routePayload = getReactSandboxFutureIndexRoutePayload()
    const view = await serverRenderReact({
      name: 'react-sandbox-future',
      path: '/_react_sandbox_future',
      data: routePayload,
      data_router_enabled: true,
    })

    // verify ssr was able to render some content from the payload
    expect(view).toContain('Data router sandbox')
    expect(view).toContain('reactSandboxFutureLayoutRoute-mainQuery-data')
    expect(view).toContain('reactSandboxFutureIndexRoute-mainQuery-data')
    expect(view).toContain('SERVER DATA – layoutRoute')
    expect(view).toContain('SERVER DATA – indexRoute')
    expect(view).not.toContain('reactSandboxFutureIdRoute-payload-data')
  })

  test('Renders reactSandboxFutureIdRoute with SSR', async () => {
    const routePayload = getReactSandboxFutureIdRoutePayload('1')

    const view = await serverRenderReact({
      name: 'react-sandbox-future',
      path: '/_react_sandbox_future/1',
      data: {...routePayload},
      data_router_enabled: true,
    })

    // verify ssr was able to render some content from the payload
    expect(view).toContain('Data router sandbox')
    expect(view).toContain('reactSandboxFutureLayoutRoute-mainQuery-data')
    expect(view).toContain('reactSandboxFutureIdRoute-mainQuery-data')
    expect(view).toContain('SERVER DATA – layoutRoute')
    expect(view).toContain('SERVER DATA – idRoute')
    expect(view).not.toContain('reactSandboxFutureIndexRoute-mainQuery-data')
  })
})

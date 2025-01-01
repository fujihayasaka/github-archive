/** @jest-environment node */
import {expect, it} from '@github-ui/tests'
import {serverRenderReact} from '@github-ui/ssr-test-utils/server-render'
import {getPatternConfigsPageRoutePayload} from '../test-utils/mock-data'
import {patternConfigsPageRoute} from '../routes/pattern-configs-page-route'

// Register with react-core before attempting to render
import '../ssr-entry'

it('renders PatternConfigsPage with SSR', async () => {
  const routePayload = getPatternConfigsPageRoutePayload()
  const view = await serverRenderReact({
    name: 'push-protection-pattern-configurations',
    path: patternConfigsPageRoute.path,
    data: {
      payload: {
        patternConfigsPageRoute: routePayload,
      },
    },
    data_router_enabled: true,
  })

  // verify ssr was able to render some content from the payload
  expect(view).toMatch('foo')
})

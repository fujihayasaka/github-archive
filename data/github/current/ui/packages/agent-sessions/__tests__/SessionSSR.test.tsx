/** @jest-environment node */
import {serverRenderReact} from '@github-ui/ssr-test-utils/server-render'
import {getSessionRoutePayload} from '../test-utils/mock-data'

// Register with react-core before attempting to render
import '../ssr-entry'

// Add mock for lowlight
jest.mock('@github-ui/copilot-markdown', () => ({
  MarkdownRenderer: ({markdown}: {markdown: string}) => markdown,
}))

test('Renders Session page with SSR', async () => {
  const routePayload = getSessionRoutePayload()
  const view = await serverRenderReact({
    name: 'agent-sessions',
    path: '/:owner/:repo/pull/:id/agent-sessions/:session_id',
    data: {
      payload: {
        sessionRoute: routePayload,
      },
    },
    data_router_enabled: true,
  })

  // verify ssr was able to render some content from the payload
  expect(view).toMatch('Session 1')
  // verify ssr was able to render the static part of the left nav
  expect(view).toMatch('Back to pull request')
  expect(view).toMatch('Sessions')
})

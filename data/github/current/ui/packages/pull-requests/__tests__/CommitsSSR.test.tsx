/** @jest-environment node */
import {serverRenderReact} from '@github-ui/ssr-test-utils/server-render'
import {getCommitsPageData, getCommitsRoutePayload} from '../test-utils/commits/commits-mock-data'

// Register with react-core before attempting to render
import '../ssr-entry'
import {getAppPayload} from '../test-utils/app-mock-data'
import {getHeaderPageData} from '../test-utils/header-mock-data'

describe('Commits SSR', () => {
  test('Renders Commits with SSR', async () => {
    const payload = getCommitsRoutePayload()
    const appPayload = getAppPayload()

    const view = await serverRenderReact({
      name: 'pull-requests',
      path: '/:owner/:repo/pull/:pr_number/commits',
      data: {payload, appPayload},
    })

    // verify ssr was able to render some content from the payload
    expect(view).toMatch(payload.pullRequest.title)
  })

  test('Renders Commits with SSR with `data_router_enabled: true`', async () => {
    const appPayload = getAppPayload()

    const layoutMainQuery = getHeaderPageData()
    const commitsMainQuery = getCommitsPageData()

    const view = await serverRenderReact({
      name: 'pull-requests',
      path: '/:owner/:repo/pull/:pr_number/commits',
      data: {
        payload: {
          pullRequestsLayoutRoute: layoutMainQuery,
          pullRequestsCommitsRoute: commitsMainQuery,
        },
        appPayload,
      },
      data_router_enabled: true,
    })

    // verify ssr was able to render some content from the payload
    expect(view).toMatch(layoutMainQuery.pullRequest.title)
  })
})

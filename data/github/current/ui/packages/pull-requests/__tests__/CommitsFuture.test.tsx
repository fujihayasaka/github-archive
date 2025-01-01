import {act, screen, waitFor, within} from '@testing-library/react'
import {render} from '@github-ui/react-core/future/test-utils/render'
import {generateCommitGroups} from '@github-ui/commits/test-helpers'
import {getCommitsRoutePayload, getCommitsPageData} from '../test-utils/commits-mock-data'
import {pullRequestsApp} from '../pull-requests'
import {setupServer} from 'msw/node'
import {http, HttpResponse} from 'msw'
import {dispatchAliveTestMessage} from '@github-ui/use-alive/test-utils'
import {PageData} from '@github-ui/pull-request-page-data-tooling/page-data'
import {PR_ALIVE_EVENT_NAMES} from '../hooks/use-refetch-on-alive-update'
import {getAppPayload} from '../test-utils/app-mock-data'
import type {CommitsRoutePayload} from '../routes/Commits'
import type {NavigationCounterPageData} from '../page-data/payloads/tab-counts'
import {getDiffstatPageData} from '../test-utils/header-mock-data'

jest.setTimeout(20_000)

const server = setupServer()

function seedServer({
  mainQuery,
  labelCounts = {conversationCount: 1, checksCount: 1, filesChangedCount: 1},
}: {
  mainQuery: CommitsRoutePayload
  labelCounts?: NavigationCounterPageData
}) {
  server.use(
    http.get('/:owner/:repo/pull/:pr_number/commits', () => {
      return HttpResponse.json({
        payload: {
          pullRequestsCommitsRoute: {
            mainQuery,
          },
        },
      })
    }),
    http.get('/:owner/:repo/pull/:pr_number/page_data/tab_counts', () => {
      return HttpResponse.json(labelCounts)
    }),
    http.get('/:owner/:repo/pull/:pr_number/deferred_commits_data', () => {}),
    http.post('/TEST_ANALYTICS_URL', () => {
      return HttpResponse.text('success')
    }),
    http.get('/:owner/:repo/pull/1/:pr_number/header', () => {}),
    http.get('/:owner/:repo/pull/1/:pr_number/diffstat', () => HttpResponse.json(getDiffstatPageData())),
  )
}

describe('pull-requests-future', () => {
  beforeAll(() => {
    server.listen()
  })
  beforeEach(() => {
    server.resetHandlers()
  })
  afterAll(() => {
    server.close()
  })

  const featureStates = [undefined, {react_data_router_pull_requests_layout: true}]

  test.each(featureStates)('Renders the commits', async enabledFeatures => {
    const mainQuery = {
      ...getCommitsRoutePayload(),
      /* Generate 1 commit group with a single commit to avoid duplicates in mock data */
      commitGroups: generateCommitGroups(1, 1),
    }
    const appPayload = getAppPayload(enabledFeatures)
    const commitGroups = mainQuery.commitGroups
    expect(commitGroups.length).toBeGreaterThanOrEqual(1)
    const firstCommit = commitGroups[0]!.commits[0]!

    seedServer({mainQuery})

    render(pullRequestsApp, '/monalisa/smile/pull/1/commits', {
      appPayload,
      embeddedData: {appPayload, payload: {}},
    })

    expect(await screen.findByRole('heading', {level: 1})).toHaveTextContent(mainQuery.pullRequest.title)
    expect(await screen.findByRole('heading', {name: firstCommit.shortMessage})).toBeVisible()

    const commitsList = screen.getByTestId('commits-list')
    expect(commitsList).toHaveAttribute('data-hpc')
    expect(within(commitsList).getByText(firstCommit.oid.substring(0, 7))).toBeInTheDocument()
  })

  test.each(featureStates)('Renders the blank state when request times out', async enabledFeatures => {
    const mainQuery = {
      ...getCommitsRoutePayload(),
      commitGroups: [],
      timeOutMessage: 'nope',
    }
    const appPayload = getAppPayload(enabledFeatures)
    const commitGroups = mainQuery.commitGroups
    expect(commitGroups.length).toBe(0)

    seedServer({mainQuery})

    render(pullRequestsApp, '/monalisa/smile/pull/1/commits', {
      appPayload,
      embeddedData: {appPayload, payload: {}},
    })

    expect(await screen.findByRole('heading', {level: 1})).toHaveTextContent(mainQuery.pullRequest.title)
    expect(await screen.findByText('Commit history cannot be loaded')).toBeInTheDocument()
  })

  test.each(featureStates)('Renders the blank state when there are no commits', async enabledFeatures => {
    const mainQuery = {
      ...getCommitsRoutePayload(),
      commitGroups: [],
    }
    const appPayload = getAppPayload(enabledFeatures)
    const commitGroups = mainQuery.commitGroups
    expect(commitGroups.length).toBe(0)

    seedServer({mainQuery})

    render(pullRequestsApp, '/monalisa/smile/pull/1/commits', {
      appPayload,
      embeddedData: {appPayload, payload: {}},
    })

    expect(await screen.findByRole('heading', {level: 1})).toHaveTextContent(mainQuery.pullRequest.title)
    expect(await screen.findByText('No commits history')).toBeInTheDocument()
  })

  test.each(featureStates)('Renders additional commits when we get an alive update', async enabledFeatures => {
    const mainQuery = {
      ...getCommitsRoutePayload(),
      /* Generate 1 commit group with a single commit to start */
      commitGroups: generateCommitGroups(1, 1),
    }
    const appPayload = getAppPayload(enabledFeatures)
    const commitGroups = mainQuery.commitGroups
    expect(commitGroups.length).toEqual(1)
    const firstCommit = commitGroups[0]!.commits[0]!

    seedServer({mainQuery})
    render(pullRequestsApp, '/monalisa/smile/pull/1/commits', {
      appPayload,
      embeddedData: {appPayload, payload: {}},
    })

    expect(await screen.findByRole('heading', {name: firstCommit.shortMessage})).toBeVisible()
    expect(await screen.findByText(firstCommit.oid.substring(0, 7))).toBeInTheDocument()

    const commitsPageData = getCommitsPageData()
    const newPayload = {
      ...commitsPageData,
      commitGroups: generateCommitGroups(1, 2),
    }
    server.use(
      http.get('/:owner/:repo/pull/:pr_number/page_data/commits', () => {
        return HttpResponse.json(newPayload)
      }),
    )

    act(() => {
      dispatchAliveTestMessage('pr-alive-channel', {})
    })

    expect(await screen.findByText(newPayload.commitGroups[0]!.commits[0]!.oid.substring(0, 7))).toBeInTheDocument()
    expect(await screen.findByText(newPayload.commitGroups[0]!.commits[1]!.oid.substring(0, 7))).toBeInTheDocument()
  })

  test.each(featureStates)('Fetches commit page data when git is updated', async enabledFeatures => {
    const mainQuery = {
      ...getCommitsRoutePayload(),
      /* Generate 1 commit group with a single commit to start */
      commitGroups: generateCommitGroups(1, 1),
    }
    const appPayload = getAppPayload(enabledFeatures)

    seedServer({mainQuery})

    render(pullRequestsApp, '/monalisa/smile/pull/1/commits', {
      appPayload,
      embeddedData: {appPayload, payload: {}},
    })

    expect(await screen.findByRole('heading', {level: 1})).toHaveTextContent(mainQuery.pullRequest.title)

    const commitsPageDataRoute = new URL(
      `${mainQuery.urls.conversation}/page_data/${PageData.commits}`,
      window.location.origin,
    )
    const spy = jest.fn()
    server.use(
      http.get('/:owner/:repo/pull/:pr_number/page_data/commits', ({request}) => {
        spy(request.url)
        return HttpResponse.json(getCommitsPageData())
      }),
    )

    act(() => {
      dispatchAliveTestMessage('pr-alive-channel', {event_updates: {git_updated: true}})
    })

    await waitFor(() => expect(spy).toHaveBeenCalledWith(commitsPageDataRoute.href))
  })

  const events = PR_ALIVE_EVENT_NAMES.filter(event => event !== 'title_updated' && event !== 'git_updated')
  const matrix: Array<[(typeof events)[0], (typeof featureStates)[0]]> = []
  for (const event of events) {
    for (const featureState of featureStates) {
      matrix.push([event, featureState])
    }
  }

  test.each(matrix)('Does not fetches commit page data when %s is updated', async (event, enabledFeatures) => {
    const mainQuery = {
      ...getCommitsRoutePayload(),
      /* Generate 1 commit group with a single commit to start */
      commitGroups: generateCommitGroups(1, 1),
    }
    const appPayload = getAppPayload(enabledFeatures)

    seedServer({mainQuery})
    render(pullRequestsApp, '/monalisa/smile/pull/1/commits', {
      appPayload,
      embeddedData: {appPayload, payload: {}},
    })

    expect(await screen.findByRole('heading', {level: 1})).toHaveTextContent(mainQuery.pullRequest.title)

    const spy = jest.fn()
    server.use(
      http.get('/:owner/:repo/pull/:pr_number/page_data/commits', () => {
        spy()
        return HttpResponse.json(getCommitsPageData())
      }),
    )

    act(() => {
      dispatchAliveTestMessage('pr-alive-channel', {event_updates: {[event]: true}})
    })

    expect(spy).not.toHaveBeenCalled()
  })

  test.each(featureStates)('Shows alert when we detect commit truncation', async enabledFeatures => {
    const mainQuery = {
      ...getCommitsRoutePayload(),
      truncated: true,
    }
    const appPayload = getAppPayload(enabledFeatures)

    seedServer({mainQuery})

    render(pullRequestsApp, '/monalisa/smile/pull/1/commits', {
      appPayload,
      embeddedData: {appPayload, payload: {}},
    })

    expect(await screen.findByRole('heading', {level: 1})).toHaveTextContent(mainQuery.pullRequest.title)

    expect(
      await screen.findByText("This pull request is big! We're only showing the most recent 250 commits"),
    ).toBeInTheDocument()
  })

  test.each(featureStates)("navigating outside of the app doesn't flash the error boundary", async enabledFeatures => {
    const warnSpy = jest.spyOn(console, 'warn').mockImplementation()
    const mainQuery = {
      ...getCommitsRoutePayload(),
      /* Generate 1 commit group with a single commit to avoid duplicates in mock data */
      commitGroups: generateCommitGroups(1, 1),
    }
    const appPayload = getAppPayload(enabledFeatures)
    const commitGroups = mainQuery.commitGroups
    expect(commitGroups.length).toBeGreaterThanOrEqual(1)

    seedServer({mainQuery})

    const {router} = await render(pullRequestsApp, ['/_some_route_outside_the_app', '/monalisa/smile/pull/1/commits'], {
      appPayload,
      embeddedData: {appPayload, payload: {}},
    })

    expect(await screen.findByRole('heading', {level: 1})).toHaveTextContent(mainQuery.pullRequest.title)

    await act(() => router.navigate(-1))
    expect(screen.queryByText(/Unable to load page./)).not.toBeInTheDocument()
    expect(warnSpy).toHaveBeenNthCalledWith(1, 'No routes matched location "/_some_route_outside_the_app" ')
  })
})

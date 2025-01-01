import {act, screen, waitFor, within} from '@testing-library/react'
import {render} from '@github-ui/react-core/future/test-utils/render'
import {generateCommitGroups} from '@github-ui/commits/test-helpers'
import {getCommitsPageData} from '../test-utils/commits/commits-mock-data'
import {pullRequestsApp} from '../pull-requests'
import {setupServer} from 'msw/node'
import {http, HttpResponse} from 'msw'
import {getAppPayload} from '../test-utils/app-mock-data'
import type {CommitsRoutePayload, LayoutRoutePayload} from '../routes/route-payload-types'
import type {NavigationCounterPageData} from '../page-data/payloads/tab-counts'
import {getDiffstatPageData, getHeaderPageData} from '../test-utils/header-mock-data'
import {dispatchAliveTestMessage} from '@github-ui/use-alive/test-utils'
import {PageData} from '@github-ui/pull-request-page-data-tooling/page-data'
import {PR_ALIVE_EVENT_NAMES} from '../hooks/use-refetch-on-alive-update'

jest.setTimeout(20_000)

const server = setupServer()

function seedServer({
  commitsMainQuery,
  layoutMainQuery,
  labelCounts = {conversationCount: 1, checksCount: 1, filesChangedCount: 1},
}: {
  commitsMainQuery?: CommitsRoutePayload
  layoutMainQuery?: LayoutRoutePayload
  labelCounts?: NavigationCounterPageData
}) {
  server.use(
    http.get('/:owner/:repo/pull/:pr_number/commits', () => {
      const payload = {
        pullRequestsCommitsRoute: commitsMainQuery,
      }

      const meta = {title: 'PR Commits page'}
      return HttpResponse.json({
        payload,
        meta,
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
    http.get('/:owner/:repo/pull/:pr_number', () => {
      return HttpResponse.json({
        payload: {
          pullRequestsLayoutRoute: layoutMainQuery,
        },
        meta: {},
      })
    }),
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

  test('Renders the commits', async () => {
    const layoutMainQuery = getHeaderPageData()
    const commitsMainQuery = {
      ...getCommitsPageData(),
      /* Generate 1 commit group with a single commit to avoid duplicates in mock data */
      commitGroups: generateCommitGroups(1, 1),
    }
    const appPayload = getAppPayload()
    const commitGroups = commitsMainQuery.commitGroups
    expect(commitGroups.length).toBeGreaterThanOrEqual(1)
    const firstCommit = commitGroups[0]!.commits[0]!

    seedServer({commitsMainQuery, layoutMainQuery})

    render(pullRequestsApp, '/monalisa/smile/pull/1/commits', {
      appPayload,
      embeddedData: {appPayload, payload: {}},
    })

    expect(await screen.findByRole('heading', {level: 1})).toHaveTextContent(layoutMainQuery.pullRequest.title)
    expect(await screen.findByRole('heading', {name: firstCommit.shortMessage})).toBeVisible()

    const commitsList = screen.getByTestId('commits-list')
    expect(commitsList).toHaveAttribute('data-hpc')
    expect(within(commitsList).getByText(firstCommit.oid.substring(0, 7))).toBeInTheDocument()
  })

  test('Renders the commits from embedded data', async () => {
    const layoutMainQuery = getHeaderPageData()
    const commitsMainQuery = {
      ...getCommitsPageData(),
      /* Generate 1 commit group with a single commit to avoid duplicates in mock data */
      commitGroups: generateCommitGroups(1, 1),
    }
    const appPayload = getAppPayload()
    const commitGroups = commitsMainQuery.commitGroups
    expect(commitGroups.length).toBeGreaterThanOrEqual(1)
    const firstCommit = commitGroups[0]!.commits[0]!

    const payload = {
      pullRequestsLayoutRoute: layoutMainQuery,
      pullRequestsCommitsRoute: commitsMainQuery,
    }

    // We don't expect to call the server for the layout or commits routes,
    // but there is still deferred data that needs to be mocked out.
    seedServer({})

    render(pullRequestsApp, '/monalisa/smile/pull/1/commits', {
      appPayload,
      embeddedData: {
        appPayload,
        payload,
        meta: {
          title: 'PR Commits page',
        },
      },
    })

    expect(await screen.findByRole('heading', {level: 1})).toHaveTextContent(layoutMainQuery.pullRequest.title)
    expect(await screen.findByRole('heading', {name: firstCommit.shortMessage})).toBeVisible()

    const commitsList = screen.getByTestId('commits-list')
    expect(commitsList).toHaveAttribute('data-hpc')
    expect(within(commitsList).getByText(firstCommit.oid.substring(0, 7))).toBeInTheDocument()
  })

  test('Renders the blank state when request times out', async () => {
    const layoutMainQuery = getHeaderPageData()
    const commitsMainQuery = {
      ...getCommitsPageData(),
      commitGroups: [],
      timeOutMessage: 'nope',
    }
    const appPayload = getAppPayload()
    const commitGroups = commitsMainQuery.commitGroups
    expect(commitGroups.length).toBe(0)

    seedServer({commitsMainQuery, layoutMainQuery})

    render(pullRequestsApp, '/monalisa/smile/pull/1/commits', {
      appPayload,
      embeddedData: {appPayload, payload: {}},
    })

    expect(await screen.findByRole('heading', {level: 1})).toHaveTextContent(layoutMainQuery.pullRequest.title)
    expect(await screen.findByText('Commit history cannot be loaded')).toBeInTheDocument()
  })

  test('Renders the blank state when there are no commits', async () => {
    const layoutMainQuery = getHeaderPageData()
    const commitsMainQuery = {
      ...getCommitsPageData(),
      commitGroups: [],
    }
    const appPayload = getAppPayload()
    const commitGroups = commitsMainQuery.commitGroups
    expect(commitGroups.length).toBe(0)

    seedServer({commitsMainQuery, layoutMainQuery})

    render(pullRequestsApp, '/monalisa/smile/pull/1/commits', {
      appPayload,
      embeddedData: {appPayload, payload: {}},
    })

    expect(await screen.findByRole('heading', {level: 1})).toHaveTextContent(layoutMainQuery.pullRequest.title)
    expect(await screen.findByText('No commits history')).toBeInTheDocument()
  })

  test('Renders additional commits when we get an alive update', async () => {
    const layoutMainQuery = getHeaderPageData()
    const commitsMainQuery = {
      ...getCommitsPageData(),
      /* Generate 1 commit group with a single commit to start */
      commitGroups: generateCommitGroups(1, 1),
    }
    const appPayload = getAppPayload()
    const commitGroups = commitsMainQuery.commitGroups
    expect(commitGroups.length).toEqual(1)
    const firstCommit = commitGroups[0]!.commits[0]!

    seedServer({commitsMainQuery, layoutMainQuery})
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

  test('Fetches commit page data when git is updated', async () => {
    const layoutMainQuery = getHeaderPageData()
    const commitsMainQuery = {
      ...getCommitsPageData(),
      /* Generate 1 commit group with a single commit to start */
      commitGroups: generateCommitGroups(1, 1),
    }
    const appPayload = getAppPayload()

    seedServer({commitsMainQuery, layoutMainQuery})

    render(pullRequestsApp, '/monalisa/smile/pull/1/commits', {
      appPayload,
      embeddedData: {appPayload, payload: {}},
    })

    expect(await screen.findByRole('heading', {level: 1})).toHaveTextContent(layoutMainQuery.pullRequest.title)

    const commitsPageDataRoute = new URL(
      `${layoutMainQuery.urls.conversation}/page_data/${PageData.commits}`,
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

  test.each(events)('Does not fetches commit page data when %s is updated', async event => {
    const layoutMainQuery = getHeaderPageData()
    const commitsMainQuery = {
      ...getCommitsPageData(),
      /* Generate 1 commit group with a single commit to start */
      commitGroups: generateCommitGroups(1, 1),
    }
    const appPayload = getAppPayload()

    seedServer({commitsMainQuery, layoutMainQuery})
    render(pullRequestsApp, '/monalisa/smile/pull/1/commits', {
      appPayload,
      embeddedData: {appPayload, payload: {}},
    })

    expect(await screen.findByRole('heading', {level: 1})).toHaveTextContent(layoutMainQuery.pullRequest.title)

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

  test('Shows alert when we detect commit truncation', async () => {
    const layoutMainQuery = getHeaderPageData()
    const commitsMainQuery = {
      ...getCommitsPageData(),
      truncated: true,
    }
    const appPayload = getAppPayload()

    seedServer({commitsMainQuery, layoutMainQuery})

    render(pullRequestsApp, '/monalisa/smile/pull/1/commits', {
      appPayload,
      embeddedData: {appPayload, payload: {}},
    })

    expect(await screen.findByRole('heading', {level: 1})).toHaveTextContent(layoutMainQuery.pullRequest.title)

    expect(
      await screen.findByText("This pull request is big! We're only showing the most recent 250 commits"),
    ).toBeInTheDocument()
  })

  test("navigating outside of the app doesn't flash the error boundary", async () => {
    const warnSpy = jest.spyOn(console, 'warn').mockImplementation()
    const layoutMainQuery = getHeaderPageData()
    const commitsMainQuery = {
      ...getCommitsPageData(),
      /* Generate 1 commit group with a single commit to avoid duplicates in mock data */
      commitGroups: generateCommitGroups(1, 1),
    }
    const appPayload = getAppPayload()
    const commitGroups = commitsMainQuery.commitGroups
    expect(commitGroups.length).toBeGreaterThanOrEqual(1)

    seedServer({commitsMainQuery, layoutMainQuery})

    const {router} = await render(pullRequestsApp, ['/_some_route_outside_the_app', '/monalisa/smile/pull/1/commits'], {
      appPayload,
      embeddedData: {appPayload, payload: {}},
    })

    expect(await screen.findByRole('heading', {level: 1})).toHaveTextContent(layoutMainQuery.pullRequest.title)

    await act(() => router.navigate(-1))
    expect(screen.queryByText(/Unable to load page./)).not.toBeInTheDocument()
    expect(warnSpy).toHaveBeenNthCalledWith(1, 'No routes matched location "/_some_route_outside_the_app" ')
  })
})

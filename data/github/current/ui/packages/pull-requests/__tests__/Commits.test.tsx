import {act, screen, within} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {generateCommitGroups} from '@github-ui/commits/test-helpers'
import {Commits} from '../routes/Commits'
import {getCommitsRoutePayload, getCommitsPageData} from '../test-utils/commits/commits-mock-data'
import {AppLayout} from '../AppLayout'
import {AliveTestProvider, dispatchAliveTestMessage} from '@github-ui/use-alive/test-utils'
// eslint-disable-next-line no-restricted-imports
import {expectMockFetchCalledTimes, mockFetch} from '@github-ui/mock-fetch'
import {PageData} from '@github-ui/pull-request-page-data-tooling/page-data'
import {PR_ALIVE_EVENT_NAMES} from '../hooks/use-refetch-on-alive-update'
import {getAppPayload} from '../test-utils/app-mock-data'
import {getDiffstatPageData} from '../test-utils/header-mock-data'

jest.mock('../page-data/loaders/use-diffstat-data', () => {
  return {
    useDiffstatData: () => ({data: getDiffstatPageData()}),
  }
})

function TestComponent() {
  return (
    <AliveTestProvider>
      <AppLayout>
        <Commits aliveChannelThrottleTimeout={0} />
      </AppLayout>
    </AliveTestProvider>
  )
}

jest.setTimeout(20_000)

const navigateFn = jest.fn()
jest.mock('@github-ui/use-navigate', () => {
  return {
    useNavigate: () => navigateFn,
  }
})

test('Renders the commits', async () => {
  const routePayload = {
    ...getCommitsRoutePayload(),
    /* Generate 1 commit group with a single commit to avoid duplicates in mock data */
    commitGroups: generateCommitGroups(1, 1),
  }
  const appPayload = getAppPayload()
  const commitGroups = routePayload.commitGroups
  expect(commitGroups.length).toBeGreaterThanOrEqual(1)
  const firstCommit = commitGroups[0]!.commits[0]!

  // eslint-disable-next-line testing-library/no-unnecessary-act
  await act(() => {
    render(<TestComponent />, {routePayload, appPayload})
  })

  expect(screen.getByRole('heading', {level: 1})).toHaveTextContent(routePayload.pullRequest.title)
  expect(screen.getByRole('heading', {name: firstCommit.shortMessage})).toBeVisible()
  expect(screen.queryByText('Preview')).not.toBeInTheDocument()
  expect(screen.queryByText('Switch back')).not.toBeInTheDocument()
  expect(screen.queryByText('Give feedback')).not.toBeInTheDocument()

  const commitsList = screen.getByTestId('commits-list')
  expect(commitsList).toHaveAttribute('data-hpc')
  expect(within(commitsList).getByText(firstCommit.oid.substring(0, 7))).toBeInTheDocument()
})

test('Renders the blank state when request times out', async () => {
  const routePayload = {
    ...getCommitsRoutePayload(),
    commitGroups: [],
    timeOutMessage: 'nope',
  }
  const appPayload = getAppPayload()
  const commitGroups = routePayload.commitGroups
  expect(commitGroups.length).toBe(0)

  // eslint-disable-next-line testing-library/no-unnecessary-act
  await act(() => {
    render(<TestComponent />, {routePayload, appPayload})
  })

  expect(screen.getByRole('heading', {level: 1})).toHaveTextContent(routePayload.pullRequest.title)
  expect(screen.getByText('Commit history cannot be loaded')).toBeInTheDocument()
})

test('Renders the blank state when there are no commits', async () => {
  const routePayload = {
    ...getCommitsRoutePayload(),
    commitGroups: [],
  }
  const appPayload = getAppPayload()
  const commitGroups = routePayload.commitGroups
  expect(commitGroups.length).toBe(0)

  render(<TestComponent />, {routePayload, appPayload})

  expect(screen.getByRole('heading', {level: 1})).toHaveTextContent(routePayload.pullRequest.title)
  expect(screen.getByText('No commits history')).toBeInTheDocument()
})

test('Renders additional commits when we get an alive update', async () => {
  const routePayload = {
    ...getCommitsRoutePayload(),
    /* Generate 1 commit group with a single commit to start */
    commitGroups: generateCommitGroups(1, 1),
  }
  const commitsPageDataRoute = `${routePayload.urls.conversation}/page_data/${PageData.commits}`
  const appPayload = getAppPayload()
  const commitGroups = routePayload.commitGroups
  expect(commitGroups.length).toEqual(1)
  const firstCommit = commitGroups[0]!.commits[0]!

  render(<TestComponent />, {routePayload, appPayload})

  expect(screen.getByRole('heading', {name: firstCommit.shortMessage})).toBeVisible()
  expect(screen.getByText(firstCommit.oid.substring(0, 7))).toBeInTheDocument()

  const commitsPageData = getCommitsPageData()
  const newPayload = {
    ...commitsPageData,
    commitGroups: generateCommitGroups(1, 2),
  }
  mockFetch.mockRoute(commitsPageDataRoute, newPayload)

  await act(() => {
    dispatchAliveTestMessage('pr-alive-channel', {})
  })

  expect(await screen.findByText(newPayload.commitGroups[0]!.commits[0]!.oid.substring(0, 7))).toBeInTheDocument()
  expect(await screen.findByText(newPayload.commitGroups[0]!.commits[1]!.oid.substring(0, 7))).toBeInTheDocument()
})

test('Fetches commit page data when git is updated', async () => {
  const routePayload = getCommitsRoutePayload()
  const appPayload = getAppPayload()

  render(<TestComponent />, {routePayload, appPayload})

  const commitsPageDataRoute = `${routePayload.urls.conversation}/page_data/${PageData.commits}`
  mockFetch.mockRoute(commitsPageDataRoute, getCommitsPageData())

  dispatchAliveTestMessage('pr-alive-channel', {event_updates: {git_updated: true}})

  // Data is refetched using setTimeout, so we need to wait for that to happen
  await act(() => new Promise(r => setTimeout(r, 0)))

  expectMockFetchCalledTimes(commitsPageDataRoute, 1)
})

test.each(PR_ALIVE_EVENT_NAMES.filter(event => event !== 'title_updated' && event !== 'git_updated'))(
  'Does not fetches commit page data when %s is updated',
  async event => {
    const routePayload = getCommitsRoutePayload()
    const appPayload = getAppPayload()

    render(<TestComponent />, {routePayload, appPayload})

    const commitsPageDataRoute = `${routePayload.urls.conversation}/page_data/${PageData.commits}`
    mockFetch.mockRoute(commitsPageDataRoute, getCommitsPageData())

    await act(() => {
      dispatchAliveTestMessage('pr-alive-channel', {event_updates: {[event]: true}})
    })

    expectMockFetchCalledTimes(commitsPageDataRoute, 0)
  },
)

test('Shows alert when we detect commit truncation', async () => {
  const routePayload = {
    ...getCommitsRoutePayload(),
    truncated: true,
  }
  const appPayload = getAppPayload()

  // eslint-disable-next-line testing-library/no-unnecessary-act
  await act(() => {
    render(<TestComponent />, {routePayload, appPayload})
  })

  expect(
    screen.getByText("This pull request is big! We're only showing the most recent 250 commits"),
  ).toBeInTheDocument()
})

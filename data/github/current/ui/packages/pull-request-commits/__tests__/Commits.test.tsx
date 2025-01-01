import {act, screen, within} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {generateCommitGroups} from '@github-ui/commits/test-helpers'
import {Commits} from '../routes/Commits'
import {getCommitsRoutePayload, getAppPayload, getHeaderPageData, getCommitsPageData} from '../test-utils/mock-data'
import {App} from '../App'
import {AliveTestProvider, dispatchAliveTestMessage} from '@github-ui/use-alive/test-utils'
import {expectMockFetchCalledTimes, mockFetch} from '@github-ui/mock-fetch'
import {PageData} from '@github-ui/pull-request-page-data-tooling/page-data'
import queryClient from '@github-ui/pull-request-page-data-tooling/query-client'
import {PR_ALIVE_EVENT_NAMES} from '../hooks/use-refetch-on-alive-update'

function TestComponent() {
  return (
    <App>
      <AliveTestProvider>
        <Commits />
      </AliveTestProvider>
    </App>
  )
}

afterEach(() => {
  // Reset the Tanstack Query Client Cache between tests to ensure that we don't use stale data.
  queryClient.clear()
})

jest.setTimeout(20_000)

const navigateFn = jest.fn()
jest.mock('@github-ui/use-navigate', () => {
  return {
    useNavigate: () => navigateFn,
  }
})
test('Renders the Heading', async () => {
  const routePayload = getCommitsRoutePayload()
  const appPayload = getAppPayload()

  // eslint-disable-next-line testing-library/no-unnecessary-act
  await act(() => {
    render(<TestComponent />, {routePayload, appPayload})
  })

  expect(screen.getByRole('heading', {level: 1})).toHaveTextContent(routePayload.pullRequest.title)
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

  const headerPageDataRoute = `${routePayload.urls.conversation}/page_data/${PageData.header}`
  mockFetch.mockRoute(headerPageDataRoute, getHeaderPageData())

  await act(() => {
    dispatchAliveTestMessage('commits-alive-channel', {})
  })

  expect(await screen.findByText(newPayload.commitGroups[0]!.commits[0]!.oid.substring(0, 7))).toBeInTheDocument()
  expect(await screen.findByText(newPayload.commitGroups[0]!.commits[1]!.oid.substring(0, 7))).toBeInTheDocument()
})

// Flakey test!
// https://github.com/github/github/issues/340799 for more
test.skip('Rerenders the header when we get an alive message', async () => {
  const routePayload = getCommitsRoutePayload()
  const appPayload = getAppPayload()

  render(<TestComponent />, {routePayload, appPayload})

  expect(screen.getByRole('heading', {level: 1})).toHaveTextContent(routePayload.pullRequest.title)

  const newTitle = 'Kodak T-Max P3200 is a B&W film with EI 800 meant to be pushed to 3200'
  const headerPageData = getHeaderPageData()
  const newPayload = {
    ...headerPageData,
    pullRequest: {
      ...headerPageData.pullRequest,
      title: newTitle,
      titleHtml: newTitle,
    },
  }

  const headerPageDataRoute = `${routePayload.urls.conversation}/page_data/${PageData.header}`
  mockFetch.mockRoute(headerPageDataRoute, newPayload)

  await act(() => {
    dispatchAliveTestMessage('commits-alive-channel', {event_updates: {title_updated: true}})
  })

  expect(await screen.findByRole('heading', {level: 1})).toHaveTextContent(newTitle)
})

// Flakey test!
// https://github.com/github/github/issues/340798 for more
test.skip('Fetches commit and header page data when git is updated', async () => {
  const routePayload = getCommitsRoutePayload()
  const appPayload = getAppPayload()

  render(<TestComponent />, {routePayload, appPayload})

  expect(screen.getByRole('heading', {level: 1})).toHaveTextContent(routePayload.pullRequest.title)

  const headerPageDataRoute = `${routePayload.urls.conversation}/page_data/${PageData.header}`
  mockFetch.mockRoute(headerPageDataRoute, getHeaderPageData())

  const commitsPageDataRoute = `${routePayload.urls.conversation}/page_data/${PageData.commits}`
  mockFetch.mockRoute(commitsPageDataRoute, getCommitsPageData())

  await act(() => {
    dispatchAliveTestMessage('commits-alive-channel', {event_updates: {git_updated: true}})
  })

  expectMockFetchCalledTimes(commitsPageDataRoute, 1)
  expectMockFetchCalledTimes(headerPageDataRoute, 1)
})

// TODO fix this as it's flaky and failing some CI. It does pass in isolation though.
test.skip('Only fetches header page data when title is updated', async () => {
  const routePayload = getCommitsRoutePayload()
  const appPayload = getAppPayload()

  render(<TestComponent />, {routePayload, appPayload})

  expect(screen.getByRole('heading', {level: 1})).toHaveTextContent(routePayload.pullRequest.title)

  const headerPageDataRoute = `${routePayload.urls.conversation}/page_data/${PageData.header}`
  mockFetch.mockRoute(headerPageDataRoute, getHeaderPageData())

  const commitsPageDataRoute = `${routePayload.urls.conversation}/page_data/${PageData.commits}`
  mockFetch.mockRoute(commitsPageDataRoute, getCommitsPageData())

  await act(() => {
    dispatchAliveTestMessage('commits-alive-channel', {event_updates: {title_updated: true}})
  })

  expectMockFetchCalledTimes(commitsPageDataRoute, 0)
  expectMockFetchCalledTimes(headerPageDataRoute, 1)
})

test.each(PR_ALIVE_EVENT_NAMES.filter(event => event !== 'title_updated' && event !== 'git_updated'))(
  'Does not fetches commit and header page data when %s is updated',
  async event => {
    const routePayload = getCommitsRoutePayload()
    const appPayload = getAppPayload()

    render(<TestComponent />, {routePayload, appPayload})

    expect(screen.getByRole('heading', {level: 1})).toHaveTextContent(routePayload.pullRequest.title)

    const headerPageDataRoute = `${routePayload.urls.conversation}/page_data/${PageData.header}`
    mockFetch.mockRoute(headerPageDataRoute, getHeaderPageData())

    const commitsPageDataRoute = `${routePayload.urls.conversation}/page_data/${PageData.commits}`
    mockFetch.mockRoute(commitsPageDataRoute, getCommitsPageData())

    await act(() => {
      dispatchAliveTestMessage('commits-alive-channel', {event_updates: {[event]: true}})
    })

    expectMockFetchCalledTimes(commitsPageDataRoute, 0)
    expectMockFetchCalledTimes(headerPageDataRoute, 0)
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

test('Handles keyboard navigation between commit groups', async () => {
  const routePayload = {
    ...getCommitsRoutePayload(),
    commitGroups: generateCommitGroups(2, 3),
  }
  const appPayload = getAppPayload()

  const {user} = render(<TestComponent />, {routePayload, appPayload})

  const commitElements = screen.getAllByTestId('commit-row-item')

  expect(commitElements).toHaveLength(6)

  const firstCommitElement = commitElements[0]
  const thirdCommitElement = commitElements[2]
  const fourthCommitElement = commitElements[3]

  firstCommitElement?.focus()

  expect(firstCommitElement).toHaveFocus()

  //necessary to avoid a warning about focus-visible
  const consoleWarnSpy = jest.spyOn(console, 'warn').mockImplementation(() => {})

  await user.keyboard('{ArrowDown}')
  await user.keyboard('{ArrowDown}')
  await user.keyboard('{ArrowDown}')
  expect(fourthCommitElement).toHaveFocus()

  await user.keyboard('{ArrowUp}')
  expect(thirdCommitElement).toHaveFocus()

  await user.keyboard('j')
  expect(fourthCommitElement).toHaveFocus()
  await user.keyboard('k')
  expect(thirdCommitElement).toHaveFocus()

  consoleWarnSpy.mockRestore()
})

import {AliveTestProvider, dispatchAliveTestMessage} from '@github-ui/use-alive/test-utils'
import {AppLayout} from '../AppLayout'
import {act, screen} from '@testing-library/react'
// eslint-disable-next-line no-restricted-imports
import {expectMockFetchCalledTimes, mockFetch} from '@github-ui/mock-fetch'
import {PR_ALIVE_EVENT_NAMES} from '../hooks/use-refetch-on-alive-update'
import {render} from '@github-ui/react-core/test-utils'
import {PageData} from '@github-ui/pull-request-page-data-tooling/page-data'
import {getAppPayload} from '../test-utils/app-mock-data'
import {getDiffstatPageData, getHeaderPageData} from '../test-utils/header-mock-data'

jest.mock('../page-data/loaders/use-diffstat-data', () => {
  return {
    useDiffstatData: () => ({data: getDiffstatPageData()}),
  }
})

function TestComponent() {
  return (
    <AliveTestProvider>
      <AppLayout />
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
test('Renders the Heading', async () => {
  const routePayload = getHeaderPageData()
  const appPayload = getAppPayload()

  // eslint-disable-next-line testing-library/no-unnecessary-act
  await act(() => {
    render(<TestComponent />, {routePayload, appPayload})
  })

  expect(screen.getByRole('heading', {level: 1})).toHaveTextContent(routePayload.pullRequest.title)
})

test('Rerenders the header when we get an alive message', async () => {
  const routePayload = getHeaderPageData()
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

  dispatchAliveTestMessage('pr-alive-channel', {event_updates: {git_updated: true}})

  // Data is refetched using setTimeout, so we need to wait for that to happen
  await act(() => new Promise(r => setTimeout(r, 0)))

  expect(await screen.findByRole('heading', {level: 1})).toHaveTextContent(newTitle)
})

// Flakey test!
// https://github.com/github/github/issues/340798 for more
test('Fetches header page data when git is updated', async () => {
  const routePayload = getHeaderPageData()
  const appPayload = getAppPayload()

  render(<TestComponent />, {routePayload, appPayload})

  expect(screen.getByRole('heading', {level: 1})).toHaveTextContent(routePayload.pullRequest.title)

  const headerPageDataRoute = `${routePayload.urls.conversation}/page_data/${PageData.header}`
  mockFetch.mockRoute(headerPageDataRoute, getHeaderPageData())

  await act(() => {
    dispatchAliveTestMessage('pr-alive-channel', {event_updates: {git_updated: true}})
  })

  await act(() => new Promise(r => setTimeout(r, 1000)))

  expectMockFetchCalledTimes(headerPageDataRoute, 1)
})

// TODO fix this as it's flaky and failing some CI. It does pass in isolation though.
test('Only fetches header page data when title is updated', async () => {
  const routePayload = getHeaderPageData()
  const appPayload = getAppPayload()

  render(<TestComponent />, {routePayload, appPayload})

  expect(screen.getByRole('heading', {level: 1})).toHaveTextContent(routePayload.pullRequest.title)

  const headerPageDataRoute = `${routePayload.urls.conversation}/page_data/${PageData.header}`
  mockFetch.mockRoute(headerPageDataRoute, getHeaderPageData())

  await act(() => {
    dispatchAliveTestMessage('pr-alive-channel', {event_updates: {title_updated: true}})
  })

  await act(() => new Promise(r => setTimeout(r, 1000)))

  expectMockFetchCalledTimes(headerPageDataRoute, 1)
})

test.each(PR_ALIVE_EVENT_NAMES.filter(event => event !== 'title_updated' && event !== 'git_updated'))(
  'Does not fetches header page data when %s is updated',
  async event => {
    const routePayload = getHeaderPageData()
    const appPayload = getAppPayload()

    render(<TestComponent />, {routePayload, appPayload})

    expect(screen.getByRole('heading', {level: 1})).toHaveTextContent(routePayload.pullRequest.title)

    const headerPageDataRoute = `${routePayload.urls.conversation}/page_data/${PageData.header}`
    mockFetch.mockRoute(headerPageDataRoute, getHeaderPageData())

    await act(() => {
      dispatchAliveTestMessage('pr-alive-channel', {event_updates: {[event]: true}})
    })

    expectMockFetchCalledTimes(headerPageDataRoute, 0)
  },
)

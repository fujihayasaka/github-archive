import {screen, within} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {PullRequestHeaderNavigation} from '../components/PullRequestHeaderNavigation'
import {getCommitsRoutePayload} from '../test-utils/mock-data'
import queryClient from '@github-ui/pull-request-page-data-tooling/query-client'
import {PageDataContextProvider} from '@github-ui/pull-request-page-data-tooling/page-data-context'
import {BASE_PAGE_DATA_URL} from '@github-ui/pull-request-page-data-tooling/render-with-query-client'
import {QueryClientProvider, type UseQueryResult} from '@tanstack/react-query'
import {useTabCountsPageData} from '../page-data/loaders/use-tab-counts-page-data'
import type {NavigationCounterPageData} from '../page-data/payloads/tab-counts'

jest.mock('../page-data/loaders/use-tab-counts-page-data')
const mockedUseTabCountsPageData = jest.mocked(useTabCountsPageData)

jest.mock('react-router-dom', () => ({
  ...jest.requireActual('react-router-dom'),
  useParams: () => {
    return {owner: 'monalisa', repo: 'smile', number: '1'}
  },
}))

test('renders nav with correct links', () => {
  const {urls} = getCommitsRoutePayload()

  const labelCountPayload = {
    conversationCount: 23423423,
    checksCount: 4,
    filesChangedCount: 5,
  }

  mockedUseTabCountsPageData.mockReturnValue({
    data: labelCountPayload,
  } as UseQueryResult<NavigationCounterPageData>)

  render(
    <PageDataContextProvider basePageDataUrl={BASE_PAGE_DATA_URL}>
      <QueryClientProvider client={queryClient}>
        <PullRequestHeaderNavigation commitsCount={3} urls={urls} />,
      </QueryClientProvider>
    </PageDataContextProvider>,
  )

  const conversationTab = screen.getByRole('tab', {name: /Conversation/i})
  expect(conversationTab).toHaveAttribute('href', urls.conversation)
  expect(conversationTab).toHaveTextContent(`${labelCountPayload.conversationCount}`)

  const commitsTab = screen.getByRole('tab', {name: /Commits/i})
  expect(commitsTab).toHaveAttribute('href', urls.commits)
  expect(commitsTab).toHaveTextContent('3')

  const checksTab = screen.getByRole('tab', {name: /Checks/i})
  expect(checksTab).toHaveAttribute('href', urls.checks)
  expect(checksTab).toHaveTextContent(`${labelCountPayload.checksCount}`)

  const filesTab = screen.getByRole('tab', {name: /Files/i})
  expect(filesTab).toHaveAttribute('href', urls.files)
  expect(filesTab).toHaveTextContent(`${labelCountPayload.filesChangedCount}`)
})

test('does not render the conversation, commit, checks, and files changed count if the data is not retrieved', () => {
  const {urls} = getCommitsRoutePayload()

  mockedUseTabCountsPageData.mockReturnValue({
    error: new Error('error'),
  } as UseQueryResult<NavigationCounterPageData>)

  render(
    <PageDataContextProvider basePageDataUrl={BASE_PAGE_DATA_URL}>
      <QueryClientProvider client={queryClient}>
        <PullRequestHeaderNavigation commitsCount={undefined} urls={urls} />,
      </QueryClientProvider>
    </PageDataContextProvider>,
  )

  mockedUseTabCountsPageData.mockReturnValue({
    error: new Error('error'),
  } as UseQueryResult<NavigationCounterPageData>)

  const conversationTab = screen.getByRole('tab', {name: /Conversation/i})
  expect(conversationTab).toHaveAttribute('href', urls.conversation)
  // make sure tab does not have a span element in it
  expect(within(conversationTab).queryByRole('span')).not.toBeInTheDocument()

  const commitsTab = screen.getByRole('tab', {name: /Commits/i})
  expect(commitsTab).toHaveAttribute('href', urls.commits)
  // make sure tab does not have a span element in it
  expect(within(commitsTab).queryByRole('span')).not.toBeInTheDocument()

  const checksTab = screen.getByRole('tab', {name: /Checks/i})
  expect(checksTab).toHaveAttribute('href', urls.checks)
  // make sure tab does not have a span element in it
  expect(within(checksTab).queryByRole('span')).not.toBeInTheDocument()

  const filesTab = screen.getByRole('tab', {name: /Files/i})
  expect(filesTab).toHaveAttribute('href', urls.files)
  // make sure tab does not have a span element in it
  expect(within(filesTab).queryByRole('span')).not.toBeInTheDocument()
})

import {PageDataContextProvider} from '@github-ui/pull-request-page-data-tooling/page-data-context'
import {BASE_PAGE_DATA_URL} from '@github-ui/pull-request-page-data-tooling/render-with-query-client'
import {render} from '@github-ui/react-core/test-utils'
import type {UseQueryResult} from '@github-ui/react-query'
import {screen, within} from '@testing-library/react'
import {PullRequestHeaderNavigation} from '../components/PullRequestHeaderNavigation'
import {useTabCountsPageData} from '../page-data/loaders/use-tab-counts-page-data'
import type {NavigationCounterPageData} from '../page-data/payloads/tab-counts'
import {getHeaderPageData} from '../test-utils/header-mock-data'

jest.mock('../page-data/loaders/use-tab-counts-page-data')
const mockedUseTabCountsPageData = jest.mocked(useTabCountsPageData)

describe('PullRequestHeaderNavigation (navigator router)', () => {
  test('renders nav with correct links', () => {
    const {urls} = getHeaderPageData()

    const labelCountPayload = {
      conversationCount: 23423423,
      checksCount: 4,
      filesChangedCount: 5,
      filesChangedCountLimitExceeded: false,
    }

    mockedUseTabCountsPageData.mockReturnValue({
      data: labelCountPayload,
    } as UseQueryResult<NavigationCounterPageData>)

    render(
      <PageDataContextProvider basePageDataUrl={BASE_PAGE_DATA_URL}>
        <PullRequestHeaderNavigation commitsCount={3} urls={urls} />,
      </PageDataContextProvider>,
      {
        pathname: '/monalisa/smile/pull/1',
        pathPattern: '/:org/:repo/pull/:number',
      },
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

  test('renders nav with correct count if files changed count is exceeded', () => {
    const {urls} = getHeaderPageData()

    const labelCountPayload = {
      conversationCount: 23423423,
      checksCount: 4,
      filesChangedCount: 5,
      filesChangedCountLimitExceeded: true,
    }

    mockedUseTabCountsPageData.mockReturnValue({
      data: labelCountPayload,
    } as UseQueryResult<NavigationCounterPageData>)

    render(
      <PageDataContextProvider basePageDataUrl={BASE_PAGE_DATA_URL}>
        <PullRequestHeaderNavigation commitsCount={3} urls={urls} />,
      </PageDataContextProvider>,
      {
        pathname: '/monalisa/smile/pull/1',
        pathPattern: '/:org/:repo/pull/:number',
      },
    )

    const filesTab = screen.getByRole('tab', {name: /Files/i})
    expect(filesTab).toHaveAttribute('href', urls.files)
    expect(filesTab).toHaveTextContent(`${labelCountPayload.filesChangedCount}+`)
  })

  test('does not render the conversation, commit, checks, and files changed count if the data is not retrieved', () => {
    const {urls} = getHeaderPageData()

    mockedUseTabCountsPageData.mockReturnValue({
      error: new Error('error'),
    } as UseQueryResult<NavigationCounterPageData>)

    render(
      <PageDataContextProvider basePageDataUrl={BASE_PAGE_DATA_URL}>
        <PullRequestHeaderNavigation commitsCount={undefined} urls={urls} />,
      </PageDataContextProvider>,
      {
        pathname: '/monalisa/smile/pull/1',
        pathPattern: '/:org/:repo/pull/:number',
      },
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
})

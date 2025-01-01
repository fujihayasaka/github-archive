import {expectAnalyticsEvents} from '@github-ui/analytics-test-utils'
import {render, setupUserEvent} from '@github-ui/react-core/test-utils'
import {useQueries} from '@github-ui/react-query'
import {screen} from '@testing-library/react'
import {PullRequestsList, dedupeById} from '../components/PullRequestsList'

jest.mock('@github-ui/react-query', () => ({
  useQueries: jest.fn(),
}))

jest.mock('../components/DashboardStatusChecksRollup', () => ({
  StatusChecksRollup: () => <div data-testid="status-checks-rollup">Status checks</div>,
}))
const mockUseQueries = useQueries as jest.Mock

describe('PullRequestsList', () => {
  beforeEach(() => {
    mockUseQueries.mockClear()
  })

  const pullRequests = [
    {
      id: '1',
      title: 'Update dependencies',
      permalink: 'https://github.com/github/github/pull/1',
      commentCount: 1,
      updatedAt: '2022-02-02T00:00:00Z',
      suggestedAction: 'Request reviewers',
      headSha: 'abc123',
      repoNameWithOwner: {
        ownerLogin: 'github',
        name: 'github',
      },
      inMergeQueue: false,
      isDraft: false,
    },
    {
      id: '2',
      title: 'Fix bug',
      permalink: 'https://github.com/github/github/pull/2',
      commentCount: 12,
      updatedAt: '2022-02-02T00:00:00Z',
      suggestedAction: 'Resolve comments',
      headSha: 'def456',
      repoNameWithOwner: {
        ownerLogin: 'github',
        name: 'github',
      },
      inMergeQueue: false,
      isDraft: true,
    },
  ]

  test('renders loading state', () => {
    mockUseQueries.mockReturnValue({
      isLoading: true,
      isError: false,
      data: undefined,
      error: null,
    })

    render(<PullRequestsList userDisplayLogin="monalisa" />)
    expect(screen.getByTestId('pull-requests-list-loading')).toBeInTheDocument()
  })

  test('renders error state', () => {
    const errorMessage = 'Failed to fetch pull requests'
    mockUseQueries.mockReturnValue({
      isLoading: false,
      isError: true,
      data: undefined,
      error: new Error(errorMessage),
    })

    render(<PullRequestsList userDisplayLogin="monalisa" />)
    expect(screen.getByText('Something went wrong')).toBeInTheDocument()
    expect(screen.getByText('Failed to load pull requests')).toBeInTheDocument()
  })

  test('renders pull requests list', () => {
    mockUseQueries.mockReturnValue({
      isLoading: false,
      isError: false,
      data: pullRequests,
      error: null,
    })

    render(<PullRequestsList userDisplayLogin="monalisa" />)

    // Verify pull request titles are rendered
    expect(screen.getByText('Update dependencies')).toBeInTheDocument()
    expect(screen.getByText('Fix bug')).toBeInTheDocument()

    // Verify status checks are rendered
    expect(screen.getAllByTestId('status-checks-rollup')).toHaveLength(2)

    // Verify suggested actions are rendered
    expect(screen.getByText('Request reviewers')).toBeInTheDocument()
    expect(screen.getByText('Resolve comments')).toBeInTheDocument()

    // Verify comment counts are rendered
    expect(screen.getByText('1')).toBeInTheDocument()
    expect(screen.getByText('12')).toBeInTheDocument()
  })

  test('renders empty state when no pull requests', () => {
    mockUseQueries.mockReturnValue({
      isLoading: false,
      isError: false,
      data: [],
      error: null,
    })

    render(<PullRequestsList userDisplayLogin="monalisa" />)

    expect(screen.getByText('No pull requests')).toBeInTheDocument()
  })

  test('sends click event when pull request is clicked', async () => {
    mockUseQueries.mockReturnValue({
      isLoading: false,
      isError: false,
      data: pullRequests,
      error: null,
    })
    render(<PullRequestsList userDisplayLogin="monalisa" />)

    const pullRequestTitle = 'Update dependencies'
    const userEvent = setupUserEvent()
    await userEvent.click(screen.getByText(pullRequestTitle))

    expectAnalyticsEvents({
      type: 'analytics.click',
      data: {
        category: 'productivity_dashboard',
        action: 'click.navigate_to_pr',
      },
    })
  })

  test('renders filter menu button for PRs', () => {
    render(<PullRequestsList userDisplayLogin="monalisa" />)
    expect(screen.getByTestId('pull-request-filter-menu-button')).toBeInTheDocument()
  })

  test('header links to /pulls and sends analytics on click', async () => {
    render(<PullRequestsList userDisplayLogin="monalisa" />)

    // Check that link exists and has correct text
    const pullRequestsHeader = screen.getByRole('link', {name: 'Pull requests'})
    expect(pullRequestsHeader).toBeInTheDocument()

    // Verify link URL
    expect(pullRequestsHeader).toHaveAttribute('href', '/pulls')

    // Test click analytics
    const userEvent = setupUserEvent()
    await userEvent.click(pullRequestsHeader)

    expectAnalyticsEvents({
      type: 'analytics.click',
      data: {
        category: 'productivity_dashboard',
        action: 'click.view_all_pulls',
      },
    })
  })
})

describe('dedupeById', () => {
  it('removes duplicate items by id', () => {
    const items = [
      {id: 1, value: 'a'},
      {id: 2, value: 'b'},
      {id: 1, value: 'c'},
      {id: 3, value: 'd'},
      {id: 2, value: 'e'},
    ]
    expect(dedupeById(items)).toEqual([
      {id: 1, value: 'a'},
      {id: 2, value: 'b'},
      {id: 3, value: 'd'},
    ])
  })
})

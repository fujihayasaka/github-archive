import {isFeatureEnabled} from '@github-ui/feature-flags'
import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {DashboardLists} from '../DashboardLists'

jest.mock('@github-ui/feature-flags', () => ({
  isFeatureEnabled: jest.fn(),
}))
const mockIsFeatureEnabled = jest.mocked(isFeatureEnabled)

jest.mock('../components/PullRequestsList', () => ({
  PullRequestsList: () => <div>Mocked PullRequestsList</div>,
}))
jest.mock('../components/IssuesList', () => ({
  IssuesList: () => <div>Mocked IssuesList</div>,
}))

describe('DashboardLists', () => {
  test('Renders lists of PRs and Issues', () => {
    mockIsFeatureEnabled.mockReturnValue(true)

    const issues = [
      {
        id: '3',
        title: 'Bug report',
        description: 'This is a bug report',
        permalink: 'https://github.com/github/github/issues/3',
        commentCount: 0,
        comments: [],
        updatedAt: '2022-02-02T00:00:00Z',
      },
    ]

    const props = {issues, userDisplayLogin: 'monalisa'}

    render(<DashboardLists {...props} />)

    expect(screen.getByRole('heading', {name: 'Issues'})).toBeInTheDocument()
    expect(screen.getByText('Mocked PullRequestsList')).toBeInTheDocument()
    expect(screen.getByText('Mocked IssuesList')).toBeInTheDocument()
  })
})

test('Does not render Issues unless "dashboard_lists" feature is enabled', () => {
  mockIsFeatureEnabled.mockReturnValue(false)
  const props = {issues: [], pullRequests: [], userDisplayLogin: 'monalisa'}

  render(<DashboardLists {...props} />)

  expect(screen.getByText('Mocked PullRequestsList')).toBeInTheDocument()
  expect(screen.queryByRole('heading', {name: 'Issues'})).not.toBeInTheDocument()
})

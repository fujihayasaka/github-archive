import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {IssuesList} from '../components/IssuesList'

const mockGetIssueSummariesByTitle = jest.fn()
jest.mock('../utils/copilot-api-client', () => {
  return {
    CopilotAPIClient: jest.fn().mockImplementation(() => {
      return {
        getIssueSummariesByTitle: mockGetIssueSummariesByTitle,
      }
    }),
  }
})

describe('IssuesList', () => {
  const issues = [
    {
      id: '1',
      title: 'Bug report',
      description: 'This is a bug report',
      permalink: 'https://github.com/github/github/issues/1',
      commentCount: 3,
      comments: [],
      updatedAt: '2022-02-02T00:00:00Z',
    },
    {
      id: '2',
      title: 'Feature request',
      description: 'This is a feature request',
      permalink: 'https://github.com/github/github/issues/2',
      commentCount: 0,
      comments: [],
      updatedAt: '2022-02-03T00:00:00Z',
    },
  ]

  const summaries = new Map([
    ['Bug report', 'This issue is about a bug'],
    ['Feature request', 'This issue is about a feature request'],
  ])

  beforeEach(() => {
    jest.clearAllMocks()
  })

  test('renders issues list', async () => {
    // Setup the mock to return summaries
    mockGetIssueSummariesByTitle.mockResolvedValue(summaries)

    render(<IssuesList issues={issues} prompt="Test prompt" temperature={0.5} />)

    // Verify issue titles are rendered
    expect(screen.getByText('Bug report')).toBeInTheDocument()
    expect(screen.getByText('Feature request')).toBeInTheDocument()

    // Verify comment count is rendered for the first issue
    expect(screen.getByText('3')).toBeInTheDocument()

    // Verify the CopilotAPIClient was called with the right arguments
    expect(mockGetIssueSummariesByTitle).toHaveBeenCalledWith(issues, 'Test prompt', 0.5)
  })

  test('renders empty state when no issues', () => {
    render(<IssuesList issues={[]} prompt="Test prompt" temperature={0.5} />)

    expect(screen.getByText('No Issues')).toBeInTheDocument()
  })
})

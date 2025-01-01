import {act, screen, waitFor} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {TestComponentRoot} from '../test-utils/RepositoryMilestoneTestComponent'
import {createMockEnvironment, MockPayloadGenerator} from 'relay-test-utils'
import type {RelayMockEnvironment} from 'relay-test-utils/lib/RelayModernMockEnvironment'
import {DefaultMocks} from '@github-ui/relay-test-utils/mock-resolvers'
import {VALUES} from '../constants/values'

beforeEach(() => {
  // Set a consistent date for all tests
  jest.useFakeTimers().setSystemTime(new Date('2025-03-13T10:15:30Z'))
  // Reset document title before each test
  document.title = ''
})

afterEach(() => {
  // Reset the mocked timer after each test
  jest.useRealTimers()
})

// eslint-disable-next-line @typescript-eslint/no-explicit-any
const mockFetchRepoResponse = (environment: RelayMockEnvironment, options?: any) => {
  environment.mock.resolveMostRecentOperation(operation => {
    return MockPayloadGenerator.generate(operation, {
      ...DefaultMocks,
      Repository: () => ({
        id: 'repository-id',
        name: 'issues',
        owner: {login: 'github', id: 'owner-id'},
        nameWithOwner: 'github/issues',
        search: {
          edges: [],
        },
        viewerCanPush: true,
        ...options,
        milestone: {
          ...{
            number: 3,
            title: 'v1.0 Release',
            closed: false,
            dueOn: '2026-08-30T00:00:00Z',
            updatedAt: '2025-02-20T10:15:30Z',
            description: 'First major release',
            descriptionHTML: '<p>First major release</p>',
            progressPercentage: 75,
            openIssueCount: 1,
            closedIssueCount: 3,
            repository: {
              id: 'repository-id',
              nameWithOwner: 'github/issues',
            },
          },
          ...options?.milestone,
        },
      }),
    })
  })
}

test('Renders the RepositoryMilestone', () => {
  const environment = createMockEnvironment()
  render(<TestComponentRoot environment={environment} />)
  expect(screen.getByText('...Loading')).toBeInTheDocument()
})

test('Renders milestone header data from mock Relay environment', async () => {
  const environment = createMockEnvironment()
  render(<TestComponentRoot environment={environment} />)

  // Initial loading state
  expect(screen.getByText('...Loading')).toBeInTheDocument()

  const localizedDueDate = new Date('2026-08-30T00:00:00Z').toLocaleDateString('en-US', {
    timeZone: 'UTC',
    month: 'long',
    day: 'numeric',
    year: 'numeric',
  })

  const localizedUpdatedAt = new Date('2025-02-20T10:15:30Z').toLocaleDateString('default', {
    month: 'short',
    day: 'numeric',
    year: 'numeric',
  })

  mockFetchRepoResponse(environment)

  // Wait for the milestone title to appear
  await waitFor(() => {
    expect(screen.getByRole('heading', {name: 'v1.0 Release'})).toBeInTheDocument()
  })

  // Verify other milestone fields
  expect(screen.getByTestId('milestone-status')).toHaveTextContent('Open')
  expect(screen.getByText(`Due by ${localizedDueDate}`)).toBeInTheDocument()
  expect(screen.getByText(`Last updated`)).toBeInTheDocument()
  expect(screen.getByText(localizedUpdatedAt)).toBeInTheDocument()
  expect(screen.getByText('First major release')).toBeInTheDocument()
  expect(screen.getByText('75%')).toBeInTheDocument()
})

test('renders a closed milestone with correct status', async () => {
  const environment = createMockEnvironment()
  render(<TestComponentRoot environment={environment} />)

  // Initial loading state
  expect(screen.getByText('...Loading')).toBeInTheDocument()

  mockFetchRepoResponse(environment, {milestone: {closed: true}})

  // Wait for the milestone title to appear
  await waitFor(() => {
    expect(screen.getByRole('heading', {name: 'v1.0 Release'})).toBeInTheDocument()
  })

  // This is the closed state label - there is no better way to get these. Or at least I don't know.
  expect(screen.getAllByText('Closed')[0]).toBeInTheDocument()
  // This is the closed text that will show up instead of updated at.
  expect(screen.getAllByText('Closed')[1]).toBeInTheDocument()
})

test('toggle milestone state works and performs optimistic update', async () => {
  const environment = createMockEnvironment()
  render(<TestComponentRoot environment={environment} />)

  // Initial loading state
  expect(screen.getByText('...Loading')).toBeInTheDocument()

  mockFetchRepoResponse(environment, {milestone: {id: 'M1'}})

  // Wait for the milestone title to appear
  await waitFor(() => {
    expect(screen.getByRole('heading', {name: 'v1.0 Release'})).toBeInTheDocument()
  })

  const toggleButton = screen.getByRole('button', {name: 'Close Milestone'})
  expect(toggleButton).toBeInTheDocument()
  act(() => {
    toggleButton.click()
  })

  // Optimistic update: Verify the button text changes immediately
  expect(screen.getByRole('button', {name: 'Reopen Milestone'})).toBeInTheDocument()

  // Mock the mutation response
  environment.mock.resolveMostRecentOperation(operation => {
    return MockPayloadGenerator.generate(operation, {
      UpdateMilestonePayload: () => ({
        milestone: {
          id: 'M1',
          closed: true,
        },
      }),
    })
  })

  // Verify the final state after the mutation resolves
  await waitFor(() => {
    expect(screen.getByRole('button', {name: 'Reopen Milestone'})).toBeInTheDocument()
  })
})

test('renders milestone with future due date correctly', async () => {
  const environment = createMockEnvironment()
  render(<TestComponentRoot environment={environment} />)

  // Initial loading state
  expect(screen.getByText('...Loading')).toBeInTheDocument()
  const localizedDueDate = new Date('2026-08-30T00:00:00Z').toLocaleDateString('default', {
    timeZone: 'UTC',
    month: 'long',
    day: 'numeric',
    year: 'numeric',
  })

  mockFetchRepoResponse(environment, {milestone: {closed: true, progressPercentage: 75}})

  // Wait for the milestone title to appear
  await waitFor(() => {
    expect(screen.getByRole('heading', {name: 'v1.0 Release'})).toBeInTheDocument()
  })

  expect(screen.getByText(`Due by ${localizedDueDate}`)).toBeInTheDocument()
  expect(screen.queryByText('Overdue by')).not.toBeInTheDocument()
})

test('renders No due date if the milestone does not have a due date', async () => {
  const environment = createMockEnvironment()
  render(<TestComponentRoot environment={environment} />)

  // Initial loading state
  expect(screen.getByText('...Loading')).toBeInTheDocument()

  mockFetchRepoResponse(environment, {milestone: {closed: true, dueOn: null}})

  // Wait for the milestone title to appear
  await waitFor(() => {
    expect(screen.getByRole('heading', {name: 'v1.0 Release'})).toBeInTheDocument()
  })

  expect(screen.getByText('No due date')).toBeInTheDocument()
  expect(screen.queryByText('Overdue by')).not.toBeInTheDocument()
})

test('renders milestone with past due date and shows overdue notice', async () => {
  const environment = createMockEnvironment()
  render(<TestComponentRoot environment={environment} />)

  // Initial loading state
  expect(screen.getByText('...Loading')).toBeInTheDocument()
  const localizedDueDate = new Date('2024-08-30T00:00:00Z').toLocaleDateString('default', {
    timeZone: 'UTC',
    month: 'long',
    day: 'numeric',
    year: 'numeric',
  })

  mockFetchRepoResponse(environment, {milestone: {dueOn: '2024-08-30T00:00:00Z'}})

  // Wait for the milestone title to appear
  await waitFor(() => {
    expect(screen.getByRole('heading', {name: 'v1.0 Release'})).toBeInTheDocument()
  })

  expect(screen.getByText(`Due by ${localizedDueDate}`)).toBeInTheDocument()
  expect(screen.getByText(`Overdue by 6 month(s)`)).toBeInTheDocument()
})

test('renders progress percentage correctly rounded', async () => {
  const environment = createMockEnvironment()
  render(<TestComponentRoot environment={environment} />)

  // Initial loading state
  expect(screen.getByText('...Loading')).toBeInTheDocument()

  mockFetchRepoResponse(environment, {milestone: {progressPercentage: 33.5683629}})

  // Wait for the milestone title to appear
  await waitFor(() => {
    expect(screen.getByRole('heading', {name: 'v1.0 Release'})).toBeInTheDocument()
  })

  // To match Rails experience, we floor the value
  expect(screen.getByText('33%')).toBeInTheDocument() // Should floor to 33%
})

test('displays markdown description correctly', async () => {
  const environment = createMockEnvironment()
  render(<TestComponentRoot environment={environment} />)

  // Initial loading state
  expect(screen.getByText('...Loading')).toBeInTheDocument()

  const complexMarkdownHTML = `
    <h2>Release Goals</h2>
    <ul>
      <li>Improve performance</li>
      <li>Fix critical bugs</li>
      <li><a href="https://example.com">Documentation</a></li>
    </ul>
    <p><strong>Important:</strong> Testing required</p>
  `
  mockFetchRepoResponse(environment, {
    milestone: {
      description:
        '## Release Goals\n- Improve performance\n- Fix critical bugs\n- [Documentation](https://example.com)\n\n**Important:** Testing required',
      descriptionHTML: complexMarkdownHTML,
    },
  })

  // Wait for the milestone title to appear
  await waitFor(() => {
    expect(screen.getByRole('heading', {name: 'v1.0 Release'})).toBeInTheDocument()
  })

  // Verify heading is rendered from markdown
  expect(screen.getByRole('heading', {name: 'Release Goals'})).toBeInTheDocument()

  // Verify list items are rendered
  expect(screen.getByText('Improve performance')).toBeInTheDocument()
  expect(screen.getByText('Fix critical bugs')).toBeInTheDocument()
  // Verify link is rendered properly
  const link = screen.getByRole('link', {name: 'Documentation'})
  expect(link).toBeInTheDocument()
  expect(link).toHaveAttribute('href', 'https://example.com')

  // Verify formatted text (bold)
  expect(screen.getByText('Important:')).toBeInTheDocument()
  expect(screen.getByText('Testing required')).toBeInTheDocument()
})

test('milestones navigation button exists and goes to owner/repo/milestones', async () => {
  const environment = createMockEnvironment()
  render(<TestComponentRoot environment={environment} />)
  // Initial loading state
  expect(screen.getByText('...Loading')).toBeInTheDocument()

  mockFetchRepoResponse(environment)
  // Wait for the milestone title to appear
  await waitFor(() => {
    expect(screen.getByRole('heading', {name: 'v1.0 Release'})).toBeInTheDocument()
  })
  expect(screen.getByRole('link', {name: 'Milestones'})).toBeInTheDocument()
  expect(screen.getByRole('link', {name: 'Milestones'})).toHaveAttribute('href', '/github/issues/milestones')
})

test('milestone edit navigation button exists and goes to owner/repo/milestones/<milestone_number>/edit', async () => {
  const environment = createMockEnvironment()
  render(<TestComponentRoot environment={environment} />)
  // Initial loading state
  expect(screen.getByText('...Loading')).toBeInTheDocument()
  mockFetchRepoResponse(environment)
  // Wait for the milestone title to appear
  await waitFor(() => {
    expect(screen.getByRole('heading', {name: 'v1.0 Release'})).toBeInTheDocument()
  })
  expect(screen.getByRole('link', {name: 'Edit'})).toBeInTheDocument()
  expect(screen.getByRole('link', {name: 'Edit'})).toHaveAttribute(
    'href',
    'http://localhost/github/issues/milestones/3/edit',
  )
})

test('create issue button exists', async () => {
  const environment = createMockEnvironment()
  render(<TestComponentRoot environment={environment} />)
  // Initial loading state
  expect(screen.getByText('...Loading')).toBeInTheDocument()

  mockFetchRepoResponse(environment)

  // Wait for the milestone title to appear
  await waitFor(() => {
    expect(screen.getByRole('heading', {name: 'v1.0 Release'})).toBeInTheDocument()
  })
  expect(screen.getByRole('link', {name: 'New issue'})).toBeInTheDocument()
})

test('renders issues in list', async () => {
  const environment = createMockEnvironment()
  render(<TestComponentRoot environment={environment} />)
  // Initial loading state
  expect(screen.getByText('...Loading')).toBeInTheDocument()

  mockFetchRepoResponse(environment, {
    search: {
      edges: [
        {
          node: {
            id: 'issue-id-1',
            titleHtml: 'Issue Title',
            state: 'OPEN',
            __typename: 'Issue',
          },
        },
      ],
    },
  })

  // Wait for the milestone title to appear
  await waitFor(() => {
    expect(screen.getByRole('heading', {name: 'v1.0 Release'})).toBeInTheDocument()
  })
  expect(screen.getByText('Issue Title')).toBeInTheDocument()
})

test('renders pull requests in list', async () => {
  const environment = createMockEnvironment()
  render(<TestComponentRoot environment={environment} />)
  // Initial loading state
  expect(screen.getByText('...Loading')).toBeInTheDocument()

  mockFetchRepoResponse(environment, {
    search: {
      edges: [
        {
          node: {
            id: 'pr-id-1',
            titleHTML: 'Pr Title',
            __typename: 'PullRequest',
          },
        },
      ],
    },
  })

  // Wait for the milestone title to appear
  await waitFor(() => {
    expect(screen.getByRole('heading', {name: 'v1.0 Release'})).toBeInTheDocument()
  })
  expect(screen.getByText('Pr Title')).toBeInTheDocument()
})

test('renders issues in list with load more', async () => {
  const environment = createMockEnvironment()
  render(<TestComponentRoot environment={environment} />)
  // Initial loading state
  expect(screen.getByText('...Loading')).toBeInTheDocument()
  const numberOfPages = 5
  mockFetchRepoResponse(environment, {
    search: {
      issueCount: VALUES.issuesPageSize * numberOfPages,
      pageInfo: {
        endCursor: 'cursor',
        hasNextPage: true,
      },
      edges: [
        {
          node: {
            id: 'issue-id-1',
            titleHtml: 'Issue Title',
            state: 'OPEN',
            __typename: 'Issue',
          },
        },
      ],
    },
  })

  // Wait for the milestone title to appear
  await waitFor(() => {
    expect(screen.getByRole('heading', {name: 'v1.0 Release'})).toBeInTheDocument()
  })
  expect(screen.getByText('Issue Title')).toBeInTheDocument()
  const nextPageButton = screen.getByTestId('load-more-button')
  expect(nextPageButton).toBeInTheDocument()
})

test('do not render Edit and Close/Reopen milestone buttons if user do not have push access to the repo', async () => {
  const environment = createMockEnvironment()
  render(<TestComponentRoot environment={environment} />)
  // Initial loading state
  expect(screen.getByText('...Loading')).toBeInTheDocument()

  mockFetchRepoResponse(environment, {viewerCanPush: false})

  // Wait for the milestone title to appear
  await waitFor(() => {
    expect(screen.getByRole('heading', {name: 'v1.0 Release'})).toBeInTheDocument()
  })
  // Just to make sure we still successfully render other header links
  expect(screen.getByRole('link', {name: 'New issue'})).toBeInTheDocument()
  // User shouldn't see close milestone link.
  expect(screen.queryByText('Close milestone')).not.toBeInTheDocument()
  // User shouldn't see edit link
  expect(screen.queryByText('Edit')).not.toBeInTheDocument()
})

test('sets document title correctly when milestone and repository data are available', async () => {
  const environment = createMockEnvironment()
  render(<TestComponentRoot environment={environment} />)

  mockFetchRepoResponse(environment, {
    nameWithOwner: 'github/test-repo',
    milestone: {
      title: 'Version 2.0',
      number: 5,
    },
  })

  await waitFor(() => {
    expect(screen.getByRole('heading', {name: 'Version 2.0'})).toBeInTheDocument()
  })

  expect(document.title).toBe('Version 2.0 · Milestone #5 · github/test-repo')
})

test('updates document title when milestone data changes', async () => {
  const environment = createMockEnvironment()
  const {rerender} = render(<TestComponentRoot environment={environment} />)

  // First render with initial milestone
  mockFetchRepoResponse(environment, {
    nameWithOwner: 'github/test-repo',
    milestone: {
      title: 'Version 1.0',
      number: 3,
    },
  })

  await waitFor(() => {
    expect(screen.getByRole('heading', {name: 'Version 1.0'})).toBeInTheDocument()
  })

  expect(document.title).toBe('Version 1.0 · Milestone #3 · github/test-repo')

  // Rerender with new environment and different milestone data
  const newEnvironment = createMockEnvironment()
  rerender(<TestComponentRoot environment={newEnvironment} />)

  mockFetchRepoResponse(newEnvironment, {
    nameWithOwner: 'github/test-repo',
    milestone: {
      title: 'Version 2.0',
      number: 4,
    },
  })

  await waitFor(() => {
    expect(screen.getByRole('heading', {name: 'Version 2.0'})).toBeInTheDocument()
  })

  expect(document.title).toBe('Version 2.0 · Milestone #4 · github/test-repo')
})

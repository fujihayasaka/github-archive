import {screen, waitFor} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {TestComponentRoot} from '../test-utils/RepositoryMilestoneTestComponent'
import {createMockEnvironment, MockPayloadGenerator} from 'relay-test-utils'

beforeEach(() => {
  // Set a consistent date for all tests
  jest.useFakeTimers().setSystemTime(new Date('2025-03-13T10:15:30Z'))
})

afterEach(() => {
  // Reset the mocked timer after each test
  jest.useRealTimers()
})
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

  const localizedDueDate = new Date('2026-08-30T00:00:00Z').toLocaleDateString('default', {
    month: 'short',
    day: 'numeric',
    year: 'numeric',
  })

  const localizedUpdatedAt = new Date('2025-02-20T10:15:30Z').toLocaleDateString('default', {
    month: 'short',
    day: 'numeric',
    year: 'numeric',
  })

  // Mock the response from Relay
  environment.mock.resolveMostRecentOperation(operation => {
    return MockPayloadGenerator.generate(operation, {
      Repository: () => ({
        milestone: {
          title: 'v1.0 Release',
          closed: false,
          dueOn: '2026-08-30T00:00:00Z',
          updatedAt: '2025-02-20T10:15:30Z',
          description: 'First major release',
          descriptionHTML: '<p>First major release</p>',
          progressPercentage: 75,
          issues: {
            edges: [],
          },
        },
      }),
    })
  })

  // Wait for the milestone title to appear
  await waitFor(() => {
    expect(screen.getByRole('heading', {name: 'v1.0 Release'})).toBeInTheDocument()
  })

  // Verify other milestone fields
  expect(screen.getByTestId('milestone-status')).toHaveTextContent('Open')
  expect(screen.getByText(`Due by ${localizedDueDate}`)).toBeInTheDocument()
  expect(screen.getByText(`Last updated at`)).toBeInTheDocument()
  expect(screen.getByText(localizedUpdatedAt)).toBeInTheDocument()
  expect(screen.getByText('First major release')).toBeInTheDocument()
  expect(screen.getByText('75%')).toBeInTheDocument()
})

test('renders a closed milestone with correct status', async () => {
  const environment = createMockEnvironment()
  render(<TestComponentRoot environment={environment} />)

  // Initial loading state
  expect(screen.getByText('...Loading')).toBeInTheDocument()

  environment.mock.resolveMostRecentOperation(operation => {
    return MockPayloadGenerator.generate(operation, {
      Repository: () => ({
        milestone: {
          title: 'v1.0 Release',
          closed: true,
          dueOn: '2026-08-30T00:00:00Z',
          updatedAt: '2025-02-20T10:15:30Z',
          description: 'First major release',
          descriptionHTML: '<p>First major release</p>',
          progressPercentage: 75,
          issues: {
            edges: [],
          },
        },
      }),
    })
  })

  // Wait for the milestone title to appear
  await waitFor(() => {
    expect(screen.getByRole('heading', {name: 'v1.0 Release'})).toBeInTheDocument()
  })

  // This is the closed state label - there is no better way to get these. Or at least I don't know.
  expect(screen.getAllByText('Closed')[0]).toBeInTheDocument()
  // This is the closed text that will show up instead of updated at.
  expect(screen.getAllByText('Closed')[1]).toBeInTheDocument()
})

test('renders milestone with future due date correctly', async () => {
  const environment = createMockEnvironment()
  render(<TestComponentRoot environment={environment} />)

  // Initial loading state
  expect(screen.getByText('...Loading')).toBeInTheDocument()
  const localizedDueDate = new Date('2026-08-30T00:00:00Z').toLocaleDateString('default', {
    month: 'short',
    day: 'numeric',
    year: 'numeric',
  })

  environment.mock.resolveMostRecentOperation(operation => {
    return MockPayloadGenerator.generate(operation, {
      Repository: () => ({
        milestone: {
          title: 'v1.0 Release',
          closed: true,
          dueOn: '2026-08-30T00:00:00Z',
          updatedAt: '2025-02-20T10:15:30Z',
          description: 'First major release',
          descriptionHTML: '<p>First major release</p>',
          progressPercentage: 75,
          issues: {
            edges: [],
          },
        },
      }),
    })
  })

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

  environment.mock.resolveMostRecentOperation(operation => {
    return MockPayloadGenerator.generate(operation, {
      Repository: () => ({
        milestone: {
          title: 'v1.0 Release',
          closed: true,
          dueOn: null,
          updatedAt: '2025-02-20T10:15:30Z',
          description: 'First major release',
          descriptionHTML: '<p>First major release</p>',
          progressPercentage: 75,
          issues: {
            edges: [],
          },
        },
      }),
    })
  })

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
    month: 'short',
    day: 'numeric',
    year: 'numeric',
  })

  environment.mock.resolveMostRecentOperation(operation => {
    return MockPayloadGenerator.generate(operation, {
      Repository: () => ({
        milestone: {
          title: 'v1.0 Release',
          closed: false,
          dueOn: '2024-08-30T00:00:00Z',
          updatedAt: '2025-02-20T10:15:30Z',
          description: 'First major release',
          descriptionHTML: '<p>First major release</p>',
          progressPercentage: 75,
          issues: {
            edges: [],
          },
        },
      }),
    })
  })

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

  environment.mock.resolveMostRecentOperation(operation => {
    return MockPayloadGenerator.generate(operation, {
      Repository: () => ({
        milestone: {
          title: 'v1.0 Release',
          closed: false,
          dueOn: '2024-08-30T00:00:00Z',
          updatedAt: '2025-02-20T10:15:30Z',
          description: 'First major release',
          descriptionHTML: '<p>First major release</p>',
          progressPercentage: 33.5683629,
          issues: {
            edges: [],
          },
        },
      }),
    })
  })

  // Wait for the milestone title to appear
  await waitFor(() => {
    expect(screen.getByRole('heading', {name: 'v1.0 Release'})).toBeInTheDocument()
  })

  expect(screen.getByText('34%')).toBeInTheDocument() // Should round to 34%
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

  environment.mock.resolveMostRecentOperation(operation => {
    return MockPayloadGenerator.generate(operation, {
      Repository: () => ({
        milestone: {
          title: 'v1.0 Release',
          closed: false,
          dueOn: '2026-08-30T00:00:00Z',
          updatedAt: '2025-02-20T10:15:30Z',
          description:
            '## Release Goals\n- Improve performance\n- Fix critical bugs\n- [Documentation](https://example.com)\n\n**Important:** Testing required',
          descriptionHTML: complexMarkdownHTML,
          progressPercentage: 75,
          issues: {
            edges: [],
          },
        },
      }),
    })
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

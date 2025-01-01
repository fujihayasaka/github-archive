import {act, screen, waitFor} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {TestComponentRoot} from '../test-utils/RepositoryMilestoneTestComponent'
import {createMockEnvironment, MockPayloadGenerator} from 'relay-test-utils'
import type {RelayMockEnvironment} from 'relay-test-utils/lib/RelayModernMockEnvironment'
import {DefaultMocks} from '@github-ui/relay-test-utils/mock-resolvers'

// eslint-disable-next-line @typescript-eslint/no-explicit-any
const mockFetchRepoResponse = (environment: RelayMockEnvironment, options?: any) => {
  environment.mock.resolveMostRecentOperation(operation => {
    return MockPayloadGenerator.generate(operation, {
      ...DefaultMocks,
      Repository: () => ({
        id: 'repository-id',
        name: 'issues',
        owner: {login: 'github', id: 'owner-id'},
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
          },
          ...options?.milestone,
        },
      }),
    })
  })
}

test('toggles bulk actions based on issue and PR checkbox selections', async () => {
  const environment = createMockEnvironment()
  render(<TestComponentRoot environment={environment} />)

  mockFetchRepoResponse(environment, {
    search: {
      edges: [
        {
          node: {
            id: 'issue-1',
            titleHtml: 'Issue Title',
            state: 'OPEN',
            __typename: 'Issue',
            number: 1,
          },
        },
        {
          node: {
            id: 'pr-1',
            titleHTML: 'PR Title',
            __typename: 'PullRequest',
            number: 2,
          },
        },
      ],
    },
  })

  // Wait for the milestone title to appear
  await waitFor(() => {
    expect(screen.getByRole('heading', {name: 'v1.0 Release'})).toBeInTheDocument()
  })

  // The issue should be there, but as it is not yet selected, the bulk actions header is not yet present
  await waitFor(() => {
    expect(screen.getByText('Issue Title')).toBeInTheDocument()
  })
  expect(screen.queryByLabelText('Bulk actions')).not.toBeInTheDocument()

  // Bulk actions header is present when only issues are selected
  const issueCheckbox = screen.getByRole('checkbox', {name: 'Select: Issue Title'})
  act(() => {
    issueCheckbox.click()
  })
  await waitFor(() => {
    expect(screen.getByTestId('action-bar-container')).toBeInTheDocument()
  })

  // Bulk actions header is not present when at least one PR is selected
  const prCheckbox = screen.getByRole('checkbox', {name: 'Select: PR Title'})
  act(() => {
    prCheckbox.click()
  })
  await waitFor(() => {
    expect(screen.queryByTestId('action-bar-container')).not.toBeInTheDocument()
  })

  // Deselect PR and expect the bulk action header to be present again
  act(() => {
    prCheckbox.click()
  })
  await waitFor(() => {
    expect(screen.getByTestId('action-bar-container')).toBeInTheDocument()
  })
})

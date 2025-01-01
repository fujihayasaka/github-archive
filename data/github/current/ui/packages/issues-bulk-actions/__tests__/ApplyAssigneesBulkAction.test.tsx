import {renderRelay} from '@github-ui/relay-test-utils'
import {act, screen} from '@testing-library/react'
import {graphql, requestSubscription} from 'relay-runtime'
import {ApplyAssigneesBulkAction} from '../actions/ApplyAssigneesBulkAction'
import {MockPayloadGenerator, createMockEnvironment} from 'relay-test-utils'
import type {RelayMockEnvironment} from 'relay-test-utils/lib/RelayModernMockEnvironment'
import {Wrapper} from '@github-ui/react-core/test-utils'
import {noop} from '@github-ui/noop'

const mockSearchQuery = graphql`
  query ApplyAssigneesBulkActionTestQuery($ids: [ID!]!) @relay_test_operation {
    nodes(ids: $ids) {
      ... on Issue {
        # eslint-disable-next-line relay/unused-fields
        id
        # eslint-disable-next-line relay/unused-fields
        assignedActors(first: 20) {
          edges {
            node {
              # It is used but by readInlineData
              # eslint-disable-next-line relay/must-colocate-fragment-spreads
              ...AssigneePickerAssignee @dangerously_unaliased_fixme
            }
          }
        }
      }
    }
  }
`

const mockSubscription = (environment: RelayMockEnvironment, issueId: string) => {
  requestSubscription(environment, {
    subscription: graphql`
      subscription ApplyAssigneesBulkActionIssueRowTestSubscription($issueId: ID!) @relay_test_operation {
        issueUpdated(id: $issueId) {
          issueMetadataUpdated {
            ...Assignees @arguments(assigneePageSize: 10)
          }
        }
      }
    `,
    onNext: noop,
    onError: noop,
    variables: {issueId},
  })

  return environment.mock.getMostRecentOperation()
}

test('updates pre-selected assignees on the picker with live update', async () => {
  const mockIssueId = 'issue-1'
  const mockUser = {
    id: 'user-1',
    login: 'monalisa',
    name: 'Mona Lisa',
  }

  const environment = createMockEnvironment()
  const subscriptionOperation = mockSubscription(environment, mockIssueId)

  renderRelay(
    () => (
      <ApplyAssigneesBulkAction
        issueIds={[mockIssueId]}
        issuesToActOn={[mockIssueId]}
        repo="repo"
        owner="owner"
        disabled={false}
        singleKeyShortcutsEnabled={false}
        useQueryForAction={false}
      />
    ),
    {
      relay: {
        queries: {
          search: {
            type: 'lazy',
          },
          subscription: {
            type: 'preloaded',
            query: mockSearchQuery,
            variables: {
              ids: [mockIssueId],
            },
          },
        },
        mockResolvers: {
          Issue: () => ({
            id: mockIssueId,
            // Mock no assignees for issue initially
            assignedActors: {
              edges: [],
            },
          }),
          User: () => mockUser,
        },
        environment,
      },
      wrapper: Wrapper,
    },
  )

  // Find assign picker button and click it
  const assignButton = screen.getByText('Assign')
  expect(assignButton).toBeVisible()
  act(() => assignButton.click())

  // eslint-disable-next-line testing-library/no-node-access
  const monalisaUser = screen.getByText('monalisa', {selector: 'span'}).closest('li')
  expect(monalisaUser).toHaveAttribute('aria-selected', 'false')

  // Trigger subscription update with new assignee
  act(() => {
    environment.mock.nextValue(
      subscriptionOperation,
      MockPayloadGenerator.generate(subscriptionOperation, {
        Issue: () => ({
          id: mockIssueId,
          assignedActors: {
            edges: [
              {
                node: mockUser,
              },
            ],
          },
        }),
      }),
    )
  })

  // Expect mock user to be pre-selected because of the subscription update
  expect(monalisaUser).toHaveAttribute('aria-selected', 'true')
})

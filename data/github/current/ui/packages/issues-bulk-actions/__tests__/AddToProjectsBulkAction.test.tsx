import {Wrapper} from '@github-ui/react-core/test-utils'
import {renderRelay} from '@github-ui/relay-test-utils'
import {graphql, requestSubscription} from 'relay-runtime'
import {MockPayloadGenerator} from 'relay-test-utils'
import type {RelayMockEnvironment} from 'relay-test-utils/lib/RelayModernMockEnvironment'
import {AddToProjectsBulkAction} from '../actions/AddToProjectsBulkAction'
import {act, screen, waitFor, within} from '@testing-library/react'
import {buildProject} from '@github-ui/item-picker/test-utils/ProjectPickerHelpers'
import type {ProjectPickerQuery} from '@github-ui/item-picker/ProjectPickerQuery.graphql'
import type {AddToProjectsBulkActionTestQuery} from './__generated__/AddToProjectsBulkActionTestQuery.graphql'
import {createRelayMockEnvironment} from '@github-ui/relay-test-utils/RelayMockEnvironment'
import {noop} from '@github-ui/noop'

const mockSubscription = (environment: RelayMockEnvironment, issueId: string) => {
  requestSubscription(environment, {
    subscription: graphql`
      subscription AddToProjectsBulkActionTestSubscription($issueId: ID!) @relay_test_operation {
        issueUpdated(id: $issueId) {
          issueMetadataUpdated {
            ...ProjectsSectionFragment
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

const mockSearchQuery = graphql`
  query AddToProjectsBulkActionTestQuery($ids: [ID!]!) @relay_test_operation {
    nodes(ids: $ids) {
      ... on Issue {
        # eslint-disable-next-line relay/unused-fields
        id
        # eslint-disable-next-line relay/unused-fields
        projectItemsNext(first: 10) {
          edges {
            node {
              id
              project {
                # eslint-disable-next-line relay/must-colocate-fragment-spreads
                ...ProjectPickerProject
              }
            }
          }
        }
      }
    }
  }
`

test('updates pre-selected projects on the picker with live update', async () => {
  const mockIssueId = 'issue-1'
  const mockProject = buildProject({title: 'projectA', closed: false})
  const mockProjectV2Item = {
    id: 'project-item-1',
    project: mockProject,
  }

  const {environment} = createRelayMockEnvironment()
  const subscriptionOperation = mockSubscription(environment, mockIssueId)

  const {user} = renderRelay<{
    projectPickerQuery: ProjectPickerQuery
    subscription: AddToProjectsBulkActionTestQuery
  }>(
    () => (
      <AddToProjectsBulkAction
        issueIds={[mockIssueId]}
        owner="owner"
        repo="repo"
        disabled={false}
        singleKeyShortcutsEnabled={false}
        issuesToActOn={[mockIssueId]}
        useQueryForAction={false}
      />
    ),
    {
      relay: {
        queries: {
          projectPickerQuery: {
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
            projectItemsNext: {
              edges: [{node: null}],
            },
          }),
          ProjectV2: () => mockProject,
          ProjectV2Item: () => mockProjectV2Item,
        },
        environment,
      },
      wrapper: Wrapper,
    },
  )

  const projectsButton = screen.getByRole('button', {name: 'Project'})
  expect(projectsButton).toBeInTheDocument()
  await user.click(projectsButton)

  const list = screen.getByLabelText('Project results')
  expect(list).toBeInTheDocument()
  expect(list).toBeVisible()

  const project = within(list).queryAllByRole('option', {name: 'projectA'})

  // projects are listed in different sections e.g Recent and Repository
  const projectA = project[0]

  expect(projectA).toBeInTheDocument()
  expect(projectA).toHaveAttribute('aria-selected', 'false')

  // Trigger subscription update with new project
  await act(async () => {
    environment.mock.nextValue(
      subscriptionOperation,
      MockPayloadGenerator.generate(subscriptionOperation, {
        Issue: () => ({
          id: mockIssueId,
          projectItemsNext: {
            edges: [{node: mockProjectV2Item}],
          },
        }),
      }),
    )
  })

  const updatedProject = within(list).queryAllByRole('option', {name: 'projectA'})

  // projects are listed in different sections e.g Recent and Repository
  const updatedProjectA = updatedProject[0]

  expect(updatedProjectA).toBeInTheDocument()

  await waitFor(() => expect(updatedProjectA).toHaveAttribute('aria-selected', 'true'))
})

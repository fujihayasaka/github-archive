import {renderRelay} from '@github-ui/relay-test-utils'
import {act, screen} from '@testing-library/react'
import {graphql, requestSubscription} from 'relay-runtime'
import {MockPayloadGenerator, createMockEnvironment} from 'relay-test-utils'
import type {RelayMockEnvironment} from 'relay-test-utils/lib/RelayModernMockEnvironment'
import {Wrapper} from '@github-ui/react-core/test-utils'
import {noop} from '@github-ui/noop'
import type {MilestonePickerQuery} from '@github-ui/item-picker/MilestonePickerQuery.graphql'
import {ApplyMilestoneBulkAction} from '../actions/ApplyMilestoneBulkAction'
import type {ApplyMilestoneBulkActionTestQuery} from './__generated__/ApplyMilestoneBulkActionTestQuery.graphql'

const mockSearchQuery = graphql`
  query ApplyMilestoneBulkActionTestQuery($ids: [ID!]!) @relay_test_operation {
    nodes(ids: $ids) {
      ... on Issue {
        # eslint-disable-next-line relay/unused-fields
        id
        # eslint-disable-next-line relay/unused-fields
        milestone {
          # eslint-disable-next-line relay/must-colocate-fragment-spreads
          ...MilestonePickerMilestone
        }
      }
    }
  }
`

const mockSubscription = (environment: RelayMockEnvironment, issueId: string) => {
  requestSubscription(environment, {
    subscription: graphql`
      subscription ApplyMilestoneBulkActionIssueRowTestSubscription($issueId: ID!) @relay_test_operation {
        issueUpdated(id: $issueId) {
          issueMetadataUpdated {
            ...MilestonesSectionMilestone
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

const mockIssueAId = 'issue-2'
const mockIssueBId = 'issue-3'
const mockMilestone = {
  id: `milestone-2`,
  title: `Beta ship`,
  closed: false,
}

const setup = (mockResolverOverride = {}) => {
  const {relayMockEnvironment} = renderRelay<{
    search: ApplyMilestoneBulkActionTestQuery
    picker: MilestonePickerQuery
  }>(
    () => (
      <ApplyMilestoneBulkAction
        owner="github"
        repo="issues"
        issueIds={[mockIssueAId, mockIssueBId]}
        issuesToActOn={[mockIssueAId, mockIssueBId]}
        disabled={false}
        singleKeyShortcutsEnabled={false}
        useQueryForAction={false}
      />
    ),
    {
      relay: {
        queries: {
          search: {
            type: 'preloaded',
            query: mockSearchQuery,
            variables: {
              ids: [mockIssueAId, mockIssueBId],
            },
          },
          picker: {
            type: 'lazy',
          },
        },
        mockResolvers: mockResolverOverride || {
          Issue: () => ({
            id: mockIssueAId,
            milestone: null,
          }),
          Milestone: () => mockMilestone,
        },
      },
      wrapper: Wrapper,
    },
  )

  return relayMockEnvironment
}

test('updates pre-selected milestone on the picker with live update', async () => {
  const environment = createMockEnvironment()
  const subscriptionOperation = mockSubscription(environment, mockIssueAId)

  renderRelay<{
    search: ApplyMilestoneBulkActionTestQuery
    picker: MilestonePickerQuery
  }>(
    () => (
      <ApplyMilestoneBulkAction
        owner="github"
        repo="issues"
        issueIds={[mockIssueAId]}
        issuesToActOn={[mockIssueAId]}
        disabled={false}
        singleKeyShortcutsEnabled={false}
        useQueryForAction={false}
      />
    ),
    {
      relay: {
        queries: {
          search: {
            type: 'preloaded',
            query: mockSearchQuery,
            variables: {
              ids: [mockIssueAId],
            },
          },
          picker: {
            type: 'lazy',
          },
        },
        mockResolvers: {
          Issue: () => ({
            id: mockIssueAId,
            milestone: null,
          }),
          Milestone: () => mockMilestone,
        },
        environment,
      },
      wrapper: Wrapper,
    },
  )

  // Find milestone picker button and click it
  const milestoneButton = screen.getByText('Milestone')
  expect(milestoneButton).toBeVisible()
  act(() => milestoneButton.click())

  // Expect mock milestone not to be pre-selected
  const betaMilestone = screen.getByRole('option', {name: 'Beta ship'})
  expect(betaMilestone).toHaveAttribute('aria-selected', 'false')

  // Trigger subscription update with new milestone
  act(() => {
    environment.mock.nextValue(
      subscriptionOperation,
      MockPayloadGenerator.generate(subscriptionOperation, {
        Issue: () => ({
          id: mockIssueAId,
          milestone: mockMilestone,
        }),
      }),
    )
  })

  // Expect mock milestone to be pre-selected after subscription updates
  expect(betaMilestone).toHaveAttribute('aria-selected', 'true')
})

test('"No milestone" item is available as an option in the "Set Milestone" picker', async () => {
  setup()

  // Find milestone picker button and click it
  const milestoneButton = screen.getByText('Milestone')
  expect(milestoneButton).toBeVisible()
  act(() => milestoneButton.click())

  const noMilestone = screen.getByRole('option', {name: 'No milestone'})
  expect(noMilestone).toBeVisible()
})

test('clears milestones of the selected issues when "No milestone" item is selected', async () => {
  const environment = setup({
    Issue: () => ({
      id: mockIssueAId,
      milestone: mockMilestone,
    }),
    Milestone: () => mockMilestone,
  })

  // Find milestone picker button and click it
  const milestoneButton = screen.getByText('Milestone')
  expect(milestoneButton).toBeVisible()
  act(() => milestoneButton.click())
  const noMilestone = screen.getByRole('option', {name: 'No milestone'})
  expect(noMilestone).toBeVisible()
  act(() => noMilestone.click())
  // Assert that the expected mutation is called and returned with the clearMilestone true
  const {clearMilestone} = environment.mock.getMostRecentOperation().fragment.variables.input
  const mutationName = environment.mock.getMostRecentOperation().fragment.node.name
  expect(mutationName).toBe('updateIssueMilestoneBulkMutation')
  expect(clearMilestone).toBe(true)
})

test('when selected issues have no milestone, nothing comes as selected', async () => {
  setup({
    Issue: () => {
      return [
        {
          id: mockIssueAId,
          milestone: null,
        },
        {id: mockIssueBId, milestone: null},
      ]
    },
    Milestone: () => mockMilestone,
  })

  // Find milestone picker button and click it
  const milestoneButton = screen.getByText('Milestone')
  expect(milestoneButton).toBeVisible()
  act(() => milestoneButton.click())
  const noMilestone = screen.getByRole('option', {name: 'No milestone'})
  expect(noMilestone).toBeVisible()
  expect(noMilestone).toHaveAttribute('aria-selected', 'false')
})

test('when all selected issues have the same milestone, marks the milestone as selected in the picker', async () => {
  setup({
    Issue: () => {
      return [
        {
          id: mockIssueAId,
          milestone: mockMilestone,
        },
        {id: mockIssueBId, milestone: mockMilestone},
      ]
    },
    Milestone: () => mockMilestone,
  })

  // Find milestone picker button and click it
  const milestoneButton = screen.getByText('Milestone')
  expect(milestoneButton).toBeVisible()
  act(() => milestoneButton.click())
  const betaMilestone = screen.getByRole('option', {name: 'Beta ship'})
  expect(betaMilestone).toHaveAttribute('aria-selected', 'true')
})

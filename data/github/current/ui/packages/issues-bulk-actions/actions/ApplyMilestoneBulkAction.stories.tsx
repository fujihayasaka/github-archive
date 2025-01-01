import {ApplyMilestoneBulkAction, ApplyMilestoneQuery} from './ApplyMilestoneBulkAction'
import type {Meta} from '@storybook/react'
import {createRelayMockEnvironment} from '@github-ui/relay-test-utils/RelayMockEnvironment'
import {type OperationDescriptor, RelayEnvironmentProvider} from 'react-relay'
import {MockPayloadGenerator} from 'relay-test-utils'
import {Suspense} from 'react'
import {MilestonesPickerGraphqlQuery} from '@github-ui/item-picker/MilestonePicker'
import {mockRelayId} from '@github-ui/relay-test-utils/RelayComponents'

// Create a mock Relay environment
const {environment} = createRelayMockEnvironment()

function EntryPoint() {
  return (
    <RelayEnvironmentProvider environment={environment}>
      <Suspense fallback="...Loading">
        <TestComponent />
      </Suspense>
    </RelayEnvironmentProvider>
  )
}

function TestComponent() {
  return (
    <ApplyMilestoneBulkAction
      issueIds={[mockIssueId]}
      owner="github"
      repo="issues"
      disabled={false}
      singleKeyShortcutsEnabled={false}
      issuesToActOn={[mockIssueId]}
      useQueryForAction={false}
    />
  )
}

const mockIssueId = 'issue-1'
const milestoneA = {id: mockRelayId(), title: 'milestone A', closed: false, __typename: 'Milestone'}
const milestoneB = {id: mockRelayId(), title: 'milestone B', closed: false, __typename: 'Milestone'}

const meta = {
  title: 'BulkActions/ApplyMilestoneBulkAction',
  component: ApplyMilestoneBulkAction,
  parameters: {
    controls: {
      expanded: true,
    },
  },
} satisfies Meta<typeof ApplyMilestoneBulkAction>

export default meta

export const Default = {
  args: {},
  render: () => {
    environment.mock.queuePendingOperation(ApplyMilestoneQuery, {
      ids: [mockIssueId],
    })
    environment.mock.queueOperationResolver((operation: OperationDescriptor) => {
      return MockPayloadGenerator.generate(operation, {
        Issue: () => ({
          id: mockIssueId,
          milestone: milestoneA,
        }),
        Milestone: () => milestoneA,
      })
    })

    environment.mock.queuePendingOperation(MilestonesPickerGraphqlQuery, {owner: 'github', repo: 'issues'})
    environment.mock.queueOperationResolver((operation: OperationDescriptor) => {
      return MockPayloadGenerator.generate(operation, {
        Repository: () => ({
          id: mockRelayId(),
          viewerIssueCreationPermissions: {milestoneable: true},
          milestones: {
            nodes: [milestoneA, milestoneB],
          },
        }),
      })
    })
    return <EntryPoint />
  },
}

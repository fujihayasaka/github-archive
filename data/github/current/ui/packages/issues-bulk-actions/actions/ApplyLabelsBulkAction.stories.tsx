import {ApplyLabelsBulkAction, ApplyLabelsQuery} from './ApplyLabelsBulkAction'
import type {Meta} from '@storybook/react'
import {createRelayMockEnvironment} from '@github-ui/relay-test-utils/RelayMockEnvironment'
import {type OperationDescriptor, RelayEnvironmentProvider} from 'react-relay'
import {MockPayloadGenerator} from 'relay-test-utils'
import {Suspense} from 'react'
import {LabelPickerGraphqlQuery} from '@github-ui/item-picker/LabelPicker'
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
    <ApplyLabelsBulkAction
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

const mockLabels = [
  {node: {id: mockRelayId(), name: 'labelA', nameHTML: 'labelA', description: '', color: 'ff0000', url: `/labelA`}},
  {node: {id: mockRelayId(), name: 'labelB', nameHTML: 'labelB', description: '', color: '000000', url: `/labelB`}},
]
const mockLabelA = mockLabels[0]

const meta = {
  title: 'BulkActions/ApplyLabelsBulkAction',
  component: ApplyLabelsBulkAction,
  parameters: {
    controls: {
      expanded: true,
    },
  },
} satisfies Meta<typeof ApplyLabelsBulkAction>

export default meta

export const Default = {
  args: {},
  render: () => {
    environment.mock.queuePendingOperation(ApplyLabelsQuery, {
      ids: [mockIssueId],
    })
    environment.mock.queueOperationResolver((operation: OperationDescriptor) => {
      return MockPayloadGenerator.generate(operation, {
        Issue: () => ({
          id: mockIssueId,
          labels: null,
        }),
        Label: () => mockLabelA,
      })
    })

    environment.mock.queuePendingOperation(LabelPickerGraphqlQuery, {owner: 'github', query: null, repo: 'issues'})
    environment.mock.queueOperationResolver((operation: OperationDescriptor) => {
      return MockPayloadGenerator.generate(operation, {
        Repository: () => ({
          id: 'repo-1',
          viewerIssueCreationPermissions: {
            labelable: true,
          },
          labels: {
            nodes: mockLabels.map(n => n.node),
            totalCount: 2,
          },
        }),
      })
    })
    return <EntryPoint />
  },
}

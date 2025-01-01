import {ApplyIssueTypeBulkAction, ApplyIssueTypeQuery} from './ApplyIssueTypeBulkAction'
import type {Meta} from '@storybook/react'
import {createRelayMockEnvironment} from '@github-ui/relay-test-utils/RelayMockEnvironment'
import {type OperationDescriptor, RelayEnvironmentProvider} from 'react-relay'
import {MockPayloadGenerator} from 'relay-test-utils'
import {Suspense} from 'react'
import {IssueTypePickerGraphqlQuery} from '@github-ui/item-picker/IssueTypePicker'

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
    <ApplyIssueTypeBulkAction
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

const mockIssueType = {
  color: 'ORANGE',
  description: 'A group of work that can be broken down into multiple batches',
  id: 'IT_kwDNJr9E',
  isEnabled: true,
  name: 'Epic',
  __typename: 'IssueType',
}

const meta = {
  title: 'BulkActions/ApplyIssueTypeBulkAction',
  component: ApplyIssueTypeBulkAction,
  parameters: {
    controls: {
      expanded: true,
    },
  },
} satisfies Meta<typeof ApplyIssueTypeBulkAction>

export default meta

export const Default = {
  args: {},
  render: () => {
    environment.mock.queuePendingOperation(ApplyIssueTypeQuery, {
      ids: [mockIssueId],
    })
    environment.mock.queueOperationResolver((operation: OperationDescriptor) => {
      return MockPayloadGenerator.generate(operation, {
        Issue: () => ({
          id: mockIssueId,
          issueTypes: {
            edges: [{node: null}],
          },
        }),
        IssueType: () => mockIssueType,
      })
    })

    environment.mock.queuePendingOperation(IssueTypePickerGraphqlQuery, {
      owner: 'github',
      query: null,
      repo: 'issues',
      issueTypesPageSize: 1,
    })
    environment.mock.queueOperationResolver((operation: OperationDescriptor) => {
      return MockPayloadGenerator.generate(operation, {
        Repository() {
          return {
            issueTypes: {
              nodes: [mockIssueType],
            },
          }
        },
      })
    })
    return <EntryPoint />
  },
}

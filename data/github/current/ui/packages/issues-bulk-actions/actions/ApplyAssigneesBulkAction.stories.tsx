import {ApplyAssigneesBulkAction, ApplyAssigneesQuery} from './ApplyAssigneesBulkAction'
import type {Meta} from '@storybook/react'
import {createRelayMockEnvironment} from '@github-ui/relay-test-utils/RelayMockEnvironment'
import {type OperationDescriptor, RelayEnvironmentProvider} from 'react-relay'
import {MockPayloadGenerator} from 'relay-test-utils'
import {Suspense} from 'react'
import {SearchAssignableUsersQuery} from '@github-ui/item-picker/AssigneePicker'
import {mockRelayId} from '@github-ui/relay-test-utils/RelayComponents'

function buildAssignee({login, name}: {login: string; name: string}) {
  return {
    id: mockRelayId(),
    login,
    name,
    avatarUrl: '',
  }
}

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
    <ApplyAssigneesBulkAction
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
const mockUser = {
  id: 'user-1',
  login: 'monalisa',
  name: 'Mona Lisa',
}

const meta = {
  title: 'BulkActions/ApplyAssigneesBulkAction',
  component: ApplyAssigneesBulkAction,
  parameters: {
    controls: {
      expanded: true,
    },
  },
} satisfies Meta<typeof ApplyAssigneesBulkAction>

export default meta

const assigneesFromTokens = [
  buildAssignee({login: 'loginA', name: 'nameA'}),
  buildAssignee({login: 'loginB', name: 'nameB'}),
  buildAssignee({login: 'loginC', name: 'nameC'}),
]

export const Default = {
  args: {},
  render: () => {
    environment.mock.queuePendingOperation(ApplyAssigneesQuery, {
      ids: [mockIssueId],
    })
    environment.mock.queueOperationResolver((operation: OperationDescriptor) => {
      return MockPayloadGenerator.generate(operation, {
        Issue: () => ({
          id: mockIssueId,
          // Mock no assignees for issue initially
          assignees: {
            edges: [],
          },
        }),
        User: () => mockUser,
      })
    })

    environment.mock.queuePendingOperation(SearchAssignableUsersQuery, {
      owner: 'github',
      query: null,
      number: mockIssueId,
      repo: 'issues',
    })
    environment.mock.queueOperationResolver((operation: OperationDescriptor) => {
      return MockPayloadGenerator.generate(operation, {
        Repository() {
          return {assignableUsers: {nodes: assigneesFromTokens}}
        },
      })
    })
    return <EntryPoint />
  },
}

import {AddToProjectsBulkAction, AddToProjectsQuery} from './AddToProjectsBulkAction'
import type {Meta} from '@storybook/react'
import {createRelayMockEnvironment} from '@github-ui/relay-test-utils/RelayMockEnvironment'
import {buildProject} from '@github-ui/item-picker/test-utils/ProjectPickerHelpers'
import {type OperationDescriptor, RelayEnvironmentProvider} from 'react-relay'
import {MockPayloadGenerator} from 'relay-test-utils'
import {Suspense} from 'react'
import {ProjectPickerGraphqlQuery} from '@github-ui/item-picker/ProjectPicker'

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
    <AddToProjectsBulkAction
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
const mockProject = buildProject({title: 'projectA', closed: false})
const mockProjectV2Item = {
  id: 'project-item-1',
  project: mockProject,
}

const meta = {
  title: 'BulkActions/AddToProjects',
  component: AddToProjectsBulkAction,
  parameters: {
    controls: {
      expanded: true,
    },
  },
} satisfies Meta<typeof AddToProjectsBulkAction>

export default meta

export const Default = {
  args: {},
  render: () => {
    environment.mock.queuePendingOperation(AddToProjectsQuery, {
      ids: [mockIssueId],
    })
    environment.mock.queueOperationResolver((operation: OperationDescriptor) => {
      return MockPayloadGenerator.generate(operation, {
        Issue: () => ({
          id: mockIssueId,
          projectItemsNext: {
            edges: [{node: null}],
          },
        }),
        ProjectV2: () => mockProject,
        ProjectV2Item: () => mockProjectV2Item,
      })
    })

    environment.mock.queuePendingOperation(ProjectPickerGraphqlQuery, {owner: 'github', query: null, repo: 'issues'})
    environment.mock.queueOperationResolver((operation: OperationDescriptor) => {
      return MockPayloadGenerator.generate(operation, {
        Repository() {
          return {
            projectsV2: {
              nodes: [
                buildProject({title: 'projectA', closed: false, viewerCanUpdate: true}),
                buildProject({title: 'projectB', closed: false, viewerCanUpdate: false}),
              ],
            },
            recentProjects: {edges: []},
            owner: {
              projectsV2: {edges: []},
              recentProjects: {edges: []},
            },
          }
        },
      })
    })
    return <EntryPoint />
  },
}

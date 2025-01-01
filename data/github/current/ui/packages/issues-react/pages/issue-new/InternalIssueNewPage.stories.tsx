import type {Meta} from '@storybook/react'
import {relayDecorator, type RelayStoryObj} from '@github-ui/relay-test-utils/storybook'
import {graphql} from 'react-relay'
import {createMockEnvironment} from 'relay-test-utils'
import type {InternalIssueNewPageWithUrlParamsStoryQuery} from './__generated__/InternalIssueNewPageWithUrlParamsStoryQuery.graphql'
import type {InternalIssueNewPageProps} from './InternalIssueNewPage'
import {InternalIssueNewPageWithUrlParams} from './InternalIssueNewPage'
import {IssueCreateContextProvider} from '@github-ui/issue-create/IssueCreateContext'
import {getDefaultConfig} from '@github-ui/issue-create/getSafeConfig'
import {Wrapper} from '@github-ui/react-core/test-utils'
import type {UserHookPayload} from '@github-ui/use-user'

type InternalIssueNewPageWithUrlParamsQueries = {
  internalIssueNewPageQuery: InternalIssueNewPageWithUrlParamsStoryQuery
}

const currentUser: Partial<UserHookPayload['current_user']> = {
  name: 'Monalisa Octocat',
  avatarUrl: 'https://github.com/octocat.png',
  login: 'octocat',
}

const wrapped = (props: InternalIssueNewPageProps) => (
  <Wrapper appPayload={{current_user: currentUser}}>
    <IssueCreateContextProvider optionConfig={getDefaultConfig()} preselectedData={undefined}>
      <InternalIssueNewPageWithUrlParams {...props} />
    </IssueCreateContextProvider>
  </Wrapper>
)

// Create a mock Relay environment
const mockEnvironment = createMockEnvironment()

const meta = {
  title: 'Issues/InternalIssueNewPage',
  component: wrapped,
  parameters: {
    layout: 'fullscreen',
    docs: {
      description: {
        component: 'Page for creating a new issue with various initialization options via URL parameters.',
      },
    },
  },
  tags: ['autodocs'],
} satisfies Meta<typeof InternalIssueNewPageWithUrlParams>

export default meta

// Mock data setup for the preloaded query
const mockQueryData = {
  name: 'some',
  owner: 'owner',
  assigneeLogins: '',
  labelNames: '',
  milestoneTitle: '',
  type: '',
  projectNumbers: [],
  withAssignees: false,
  withLabels: false,
  withMilestone: false,
  withType: false,
  withProjects: false,
  discussionNumber: 0,
  includeDiscussion: false,
  templateFilter: '',
  withTemplate: false,
  withTriagePermission: false,
}

const defaultArgs: Partial<typeof InternalIssueNewPageWithUrlParams> = {
  urlParameterQueryData: {
    dispose: () => {},
    environment: mockEnvironment,
    fetchKey: 1,
    fetchPolicy: 'store-or-network',
    isDisposed: false,
    name: 'InternalIssueNewPageUrlArgumentsMetadataQuery',
    kind: 'PreloadedQuery',
    variables: mockQueryData,
  },
}

// Base story with default setup
export const Default = {
  decorators: [relayDecorator<typeof InternalIssueNewPageWithUrlParams, InternalIssueNewPageWithUrlParamsQueries>],
  args: {
    ...defaultArgs,
  },
  parameters: {
    relay: {
      queries: {
        internalIssueNewPageQuery: {
          type: 'fragment',
          variables: mockQueryData,
          query: graphql`
            query InternalIssueNewPageWithUrlParamsStoryQuery(
              $owner: String!
              $name: String!
              $withAssignees: Boolean = false
              $assigneeLogins: String = ""
              $withLabels: Boolean = false
              $labelNames: String = ""
              $withMilestone: Boolean = false
              $milestoneTitle: String = ""
              $type: String = ""
              $withType: Boolean = false
              $withProjects: Boolean = false
              $projectNumbers: [Int!] = []
              $withTriagePermission: Boolean = false
              $discussionNumber: Int = 0
              $includeDiscussion: Boolean = false
              $templateFilter: String = ""
              $withTemplate: Boolean = false
            ) @relay_test_operation {
              repository(owner: $owner, name: $name) {
                ...InternalIssueNewPageUrlArgumentsMetadata
                  @arguments(
                    withAssignees: $withAssignees
                    assigneeLogins: $assigneeLogins
                    withLabels: $withLabels
                    labelNames: $labelNames
                    withMilestone: $withMilestone
                    milestoneTitle: $milestoneTitle
                    type: $type
                    withType: $withType
                    withProjects: $withProjects
                    projectNumbers: $projectNumbers
                    withTriagePermission: $withTriagePermission
                    discussionNumber: $discussionNumber
                    includeDiscussion: $includeDiscussion
                    templateFilter: $templateFilter
                    withTemplate: $withTemplate
                  )
              }
            }
          `,
        },
      },
      mockResolvers: {
        Repository: () => ({
          issueTemplates: {
            nodes: [],
          },
          defaultBranchRef: {
            name: 'main',
          },
          hasIssuesEnabled: true,
          name: 'some',
          owner: {
            login: 'owner',
          },
          viewerIssueCreationPermissions: {
            actions: ['READ'],
          },
        }),
      },
    },
  },
} satisfies RelayStoryObj<typeof InternalIssueNewPageWithUrlParams, InternalIssueNewPageWithUrlParamsQueries>

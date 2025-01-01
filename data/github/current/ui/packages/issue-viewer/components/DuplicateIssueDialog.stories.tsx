import type {Meta} from '@storybook/react'
import {DuplicateIssueDialog} from './DuplicateIssueDialog'
import {relayDecorator, type RelayStoryObj} from '@github-ui/relay-test-utils/storybook'
import type {DuplicateIssueDialogProps} from './DuplicateIssueDialog'
import {noop} from '@github-ui/noop'
import {
  DEFAULT_ASSIGNEES,
  DEFAULT_ISSUE_TYPE,
  DEFAULT_LABELS,
  DEFAULT_MILESTONE,
  DEFAULT_PROJECTS,
  makeIssueMetadataFields,
} from '../test-utils/Mocks'
import {graphql} from 'relay-runtime'
import type {DuplicateIssueDialogEntryTestQuery} from './__generated__/DuplicateIssueDialogEntryTestQuery.graphql'
import {CreateIssueDialogEntryGraphQLQuery} from '@github-ui/issue-create/CreateIssueDialogEntry'
import {buildMockRepository} from '@github-ui/issue-create/__tests__/helpers'

import {IssueSidebarPrimaryGraphqlQuery} from './IssueSidebar'
import type {IssueSidebarPrimaryQuery$key} from './__generated__/IssueSidebarPrimaryQuery.graphql'
import {useFragment} from 'react-relay'
import {ISSUE_VIEWER_DEFAULT_CONFIG} from './OptionConfig'
import {Wrapper} from '@github-ui/react-core/test-utils'
import type {
  DuplicateIssueDialogStoryQuery,
  DuplicateIssueDialogStoryQuery$data,
} from './__generated__/DuplicateIssueDialogStoryQuery.graphql'

// eslint-disable-next-line @typescript-eslint/no-unused-expressions
graphql`
  query DuplicateIssueDialogEntryTestQuery($owner: String!, $name: String!, $includeTemplates: Boolean = false)
  @relay_test_operation {
    repository(owner: $owner, name: $name) {
      # eslint-disable-next-line relay/unused-fields
      hasAnyTemplates
      # eslint-disable-next-line relay/must-colocate-fragment-spreads
      ...RepositoryPickerRepository
      # eslint-disable-next-line relay/must-colocate-fragment-spreads
      ...CreateIssueDialog @arguments(includeTemplates: $includeTemplates)
    }
  }
`

type DuplicateIssueDialogQueries = {
  issue: DuplicateIssueDialogStoryQuery
  createIssueDialogEntryQuery: DuplicateIssueDialogEntryTestQuery
}

type DuplicateIssueDialogStoryComponentProps = Omit<DuplicateIssueDialogProps, 'issue'> & {
  issue: DuplicateIssueDialogStoryQuery$data
}

function DuplicateIssueDialogStoryComponent({issue, ...args}: DuplicateIssueDialogStoryComponentProps) {
  const issueKey = useFragment<IssueSidebarPrimaryQuery$key>(IssueSidebarPrimaryGraphqlQuery, issue.node)

  if (!issueKey) {
    return null
  }

  return (
    <Wrapper routePayload={{}}>
      <DuplicateIssueDialog issue={issueKey} {...args} />
    </Wrapper>
  )
}

const meta: Meta<typeof DuplicateIssueDialogStoryComponent> = {
  title: 'IssueViewer/DuplicateIssueDialog',
  render: args => <DuplicateIssueDialogStoryComponent {...args} />,
}

export default meta

const defaultArgs: Omit<DuplicateIssueDialogProps, 'issue'> = {
  repositoryOwner: 'monalisa',
  repositoryName: 'smile',
  showDuplicateIssueDialog: true,
  setShowDuplicateIssueDialog: noop,
  optionConfig: ISSUE_VIEWER_DEFAULT_CONFIG,
  title: 'My issue title',
  body: 'Issue description to be duplicated',
}

export const Example = {
  decorators: [relayDecorator<typeof DuplicateIssueDialogStoryComponent, DuplicateIssueDialogQueries>],
  parameters: {
    a11y: {
      test: 'todo',
    },
    relay: {
      queries: {
        issue: {
          type: 'fragment',
          query: graphql`
            query DuplicateIssueDialogStoryQuery @relay_test_operation {
              node(id: "test-id") {
                ... on Issue {
                  ...IssueSidebarPrimaryQuery @dangerously_unaliased_fixme
                }
              }
            }
          `,
          variables: {},
        },
        createIssueDialogEntryQuery: {
          type: 'fragment',
          query: CreateIssueDialogEntryGraphQLQuery,
          variables: {
            name: 'smile',
            owner: 'monalisa',
            includeTemplates: false,
          },
        },
      },
      mockResolvers: {
        Issue(_ctx, id) {
          return {
            title: `My issue title ${id()}`,
            body: 'Issue description to be duplicated',
            ...makeIssueMetadataFields({
              assignees: DEFAULT_ASSIGNEES,
              labels: DEFAULT_LABELS,
              projects: DEFAULT_PROJECTS,
              issueType: DEFAULT_ISSUE_TYPE,
              milestone: DEFAULT_MILESTONE,
            }).Issue(),
          }
        },
        Repository() {
          return buildMockRepository({
            id: 'R_123',
            owner: 'monalisa',
            name: 'smile',
          })
        },
      },
      mapStoryArgs: ({queryData: {issue}}) => {
        return {
          issue,
          ...defaultArgs,
        }
      },
    },
  },
} satisfies RelayStoryObj<typeof DuplicateIssueDialogStoryComponent, DuplicateIssueDialogQueries>

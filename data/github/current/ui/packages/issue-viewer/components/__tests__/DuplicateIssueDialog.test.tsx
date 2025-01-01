import {Wrapper} from '@github-ui/react-core/test-utils'
import {renderRelay} from '@github-ui/relay-test-utils'
import {screen} from '@testing-library/react'
import {CreateIssueDialogEntryGraphQLQuery} from '@github-ui/issue-create/CreateIssueDialogEntry'
import {noop} from '@github-ui/noop'
import {ISSUE_VIEWER_DEFAULT_CONFIG, type OptionConfig} from '../OptionConfig'
import {
  DEFAULT_ASSIGNEES,
  DEFAULT_ISSUE_TYPE,
  DEFAULT_LABELS,
  DEFAULT_MILESTONE,
  DEFAULT_PROJECTS,
  makeIssueMetadataFields,
} from '../../test-utils/Mocks'
import type {IssueMetadataFields} from '../../test-utils/types'
import {buildMockRepository} from '@github-ui/issue-create/__tests__/helpers'
import {graphql} from 'relay-runtime'
import type {DuplicateIssueDialogEntryTestQuery} from '../__generated__/DuplicateIssueDialogEntryTestQuery.graphql'
import type {
  DuplicateIssueDialogTestQuery,
  DuplicateIssueDialogTestQuery$data,
} from './__generated__/DuplicateIssueDialogTestQuery.graphql'
import {DuplicateIssueDialog, type DuplicateIssueDialogProps} from '../DuplicateIssueDialog'
import {useFragment} from 'react-relay'
import type {IssueSidebarPrimaryQuery$key} from '../__generated__/IssueSidebarPrimaryQuery.graphql'
import {IssueSidebarPrimaryGraphqlQuery} from '../IssueSidebar'

it('should have the correct dialog title', async () => {
  setup({
    repositoryName: 'smile',
    repositoryOwner: 'monalisa',
  })

  expect(screen.getByText('Duplicate current issue in monalisa/smile')).toBeInTheDocument()
})

it('should prefill the dialog with current issue data', async () => {
  setup({
    title: 'My issue title',
    body: 'Issue description to be duplicated',
    issueMetadata: {
      assignees: DEFAULT_ASSIGNEES,
      labels: DEFAULT_LABELS,
      projects: DEFAULT_PROJECTS,
      issueType: DEFAULT_ISSUE_TYPE,
      milestone: DEFAULT_MILESTONE,
    },
  })

  expect(screen.getByLabelText('Add a title')).toHaveValue('My issue title')
  expect(screen.getByLabelText('Markdown value')).toHaveValue('Issue description to be duplicated')
  // Assignees
  expect(screen.getByTitle('mona, hubot')).toBeInTheDocument()
  // Labels
  expect(screen.getByTitle('accessibility, good first issue, 2+')).toBeInTheDocument()
  // Issue type
  expect(screen.getByTitle('Bug')).toBeInTheDocument()
  // Project
  expect(screen.getByTitle('Backlog')).toBeInTheDocument()
  // Milestone
  expect(screen.getByTitle('v1.0')).toBeInTheDocument()
})

it('does not prefill the pickers when there is no data', async () => {
  setup({
    issueMetadata: {
      assignees: DEFAULT_ASSIGNEES,
      labels: DEFAULT_LABELS,
      milestone: DEFAULT_MILESTONE,
    },
  })

  // Assignees
  expect(screen.getByTitle('mona, hubot')).toBeInTheDocument()
  // Labels
  expect(screen.getByTitle('accessibility, good first issue, 2+')).toBeInTheDocument()
  // Issue type is not set
  expect(screen.getByRole('button', {name: 'Select issue type'})).toHaveTextContent('Issue Type')
  // Project is not set
  expect(screen.getByRole('button', {name: 'Select projects'})).toHaveTextContent('Project')
  // Milestone
  expect(screen.getByTitle('v1.0')).toBeInTheDocument()
})

type DuplicateIssueDialogQueries = {
  issue: DuplicateIssueDialogTestQuery
  createIssueDialogEntryGraphQLQuery: DuplicateIssueDialogEntryTestQuery
}

const setup = ({
  repositoryName = 'smile',
  repositoryOwner = 'monalisa',
  title = 'My issue title',
  body = 'Issue description to be duplicated',
  issueMetadata = {},
  optionConfig = ISSUE_VIEWER_DEFAULT_CONFIG,
}: {
  repositoryName?: string
  repositoryOwner?: string
  title?: string
  body?: string
  issueMetadata?: IssueMetadataFields
  optionConfig?: OptionConfig
}) => {
  return renderRelay<DuplicateIssueDialogQueries>(
    ({queryData: {issue}}) => (
      <DuplicateIssueDialogTestComponent
        issue={issue}
        repositoryName={repositoryName}
        repositoryOwner={repositoryOwner}
        showDuplicateIssueDialog
        setShowDuplicateIssueDialog={noop}
        optionConfig={optionConfig}
        title={title}
        body={body}
      />
    ),
    {
      relay: {
        queries: {
          issue: {
            type: 'fragment',
            query: graphql`
              query DuplicateIssueDialogTestQuery @relay_test_operation {
                node(id: "test-id") {
                  ... on Issue {
                    ...IssueSidebarPrimaryQuery @dangerously_unaliased_fixme
                  }
                }
              }
            `,
            variables: {},
          },
          createIssueDialogEntryGraphQLQuery: {
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
          Issue() {
            return {
              id: 'I_123',
              title,
              body,
              ...makeIssueMetadataFields(issueMetadata).Issue(),
            }
          },
          Repository() {
            return buildMockRepository({
              id: 'R_123',
              name: repositoryName,
              owner: repositoryOwner,
              overrides: {
                owner: {
                  __typename: 'User',
                  id: repositoryOwner,
                  databaseId: 1,
                  login: repositoryOwner,
                  avatarUrl: 'https://avatars.githubusercontent.com/u/1?v=4',
                  issueTypesEnabled: true,
                },
              },
            })
          },
        },
      },
      wrapper: Wrapper,
    },
  )
}

type DuplicateIssueDialogTestComponentProps = Omit<DuplicateIssueDialogProps, 'issue'> & {
  issue: DuplicateIssueDialogTestQuery$data
}

function DuplicateIssueDialogTestComponent({issue, ...args}: DuplicateIssueDialogTestComponentProps) {
  const issueKey = useFragment<IssueSidebarPrimaryQuery$key>(IssueSidebarPrimaryGraphqlQuery, issue.node)

  if (!issueKey) {
    return null
  }

  return <DuplicateIssueDialog issue={issueKey} {...args} />
}

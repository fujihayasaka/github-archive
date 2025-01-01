import type {Meta, StoryObj} from '@storybook/react'
import {storyWrapper} from '@github-ui/react-core/test-utils'
import {graphql} from 'react-relay'
import {relayDecorator, type RelayStoryObj} from '@github-ui/relay-test-utils/storybook'
import type {RepositoryPickerTopRepositoriesQuery} from '@github-ui/item-picker/RepositoryPickerTopRepositoriesQuery.graphql'
import {GlobalCreateMenu, type GlobalCreateMenuProps} from './GlobalCreateMenu'
import {TopRepositories} from '@github-ui/item-picker/RepositoryPicker'
import type {GlobalCreateMenuCreateIssueDialogEntryQuery} from './__generated__/GlobalCreateMenuCreateIssueDialogEntryQuery.graphql'
import type {GlobalCreateMenuStoriesRepositoryAndTemplatePickerDialogQuery} from './__generated__/GlobalCreateMenuStoriesRepositoryAndTemplatePickerDialogQuery.graphql'

const DEFAULT_TEMPLATE_NAME = 'template name 1'
const DEFAULT_REPO_MOCK = {
  __typename: 'Repository',
  nameWithOwner: 'orgA/repoA',
  owner: {login: 'orgA'},
  name: 'repoA',
  id: 'R1',
  __id: 'R1',
  isArchived: false,
  hasIssuesEnabled: true,
  hasAnyTemplates: true,
  isSecurityPolicyEnabled: true,
  securityPolicyUrl: '/security/policy',
  issueTemplates: [
    {
      filename: 'templatename1.yml',
      name: DEFAULT_TEMPLATE_NAME,
      about: 'about template 1',
    },
    {
      filename: 'templatename2.yml',
      name: 'template name 2',
      about: 'about template 2',
    },
  ],
  issueForms: [],
  contactLinks: [
    {
      name: 'external link 1',
      url: 'https://github.com',
    },
    {
      name: 'link name 2',
      url: 'https://github.com/foo',
    },
  ],
  viewerCanPush: true,
  viewerIssueCreationPermissions: {
    typeable: true,
    triageable: true,
  },
  templateTreeUrl: '/template/tree/url',
  planFeatures: {maximumAssignees: 10},
}

const WrappedComponent = (props: GlobalCreateMenuProps) => (
  <div data-a11y-link-underlines="true">
    <GlobalCreateMenu {...props} />
  </div>
)

type Story = StoryObj<typeof GlobalCreateMenu>

const meta = {
  title: 'Apps/Global Nav/Create Menu',
  component: WrappedComponent,
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
  },
  decorators: [storyWrapper()],
  tags: ['globalCreateMenu'],
} satisfies Meta<typeof GlobalCreateMenu>

export default meta

// this is require to generate the relay queries
// eslint-disable-next-line unused-imports/no-unused-vars
const repositoryAndTemplatePickerDialogQuery = graphql`
  query GlobalCreateMenuStoriesRepositoryAndTemplatePickerDialogQuery($id: ID!) @relay_test_operation {
    node(id: $id) {
      ... on Repository {
        # eslint-disable-next-line relay/must-colocate-fragment-spreads
        ...TemplateListPane
      }
    }
  }
`

const GlobalCreateMenuCreateIssueDialogEntryGraphQLQuery = graphql`
  query GlobalCreateMenuCreateIssueDialogEntryQuery($owner: String!, $name: String!, $includeTemplates: Boolean = false)
  @relay_test_operation {
    repository(owner: $owner, name: $name) {
      ...RepositoryPickerRepository
      # eslint-disable-next-line relay/must-colocate-fragment-spreads
      ...CreateIssueDialog @arguments(includeTemplates: $includeTemplates)
    }
  }
`

type CreateIssueDialogEntryQueries = {
  currentRepositoryRef: GlobalCreateMenuCreateIssueDialogEntryQuery
  topReposQueryRef: RepositoryPickerTopRepositoriesQuery
  lazyTemplateListQuery: GlobalCreateMenuStoriesRepositoryAndTemplatePickerDialogQuery
}

export const AllLinks = {
  args: {
    codespaces: true,
    gist: true,
    importRepo: true,
    createOrg: true,
    createProject: true,
    createProjectUrl: '/monalisa?tab=projects',
    createLegacyProject: false,
    createIssue: true,
    org: {
      addWord: 'Invite',
      login: 'my-org',
    },
  } as GlobalCreateMenuProps,
  decorators: [relayDecorator<typeof GlobalCreateMenu, CreateIssueDialogEntryQueries>],
  parameters: {
    relay: {
      queries: {
        currentRepositoryRef: {
          type: 'preloaded',
          query: GlobalCreateMenuCreateIssueDialogEntryGraphQLQuery,
          variables: {
            owner: DEFAULT_REPO_MOCK.owner.login,
            name: DEFAULT_REPO_MOCK.name,
            includeTemplates: true,
          },
        },
        topReposQueryRef: {
          type: 'preloaded',
          query: TopRepositories,
          variables: {
            topRepositoriesFirst: 5,
            hasIssuesEnabled: true,
            owner: null,
          },
        },
        lazyTemplateListQuery: {
          type: 'lazy',
        },
      },
      mockResolvers: {
        // templatelist for that repo
        Node() {
          return DEFAULT_REPO_MOCK
        },
        // TopReposQuery
        Repository() {
          return DEFAULT_REPO_MOCK
        },
      },
    },
  },
} satisfies RelayStoryObj<typeof GlobalCreateMenu, CreateIssueDialogEntryQueries>

export const LegacyProjectLink = {
  args: {createLegacyProject: true} as GlobalCreateMenuProps,
} satisfies Story

export const MinimumLinks = {
  args: {} as GlobalCreateMenuProps,
} satisfies Story

export const CreateIssueDialog = {
  ...AllLinks,
  args: {
    createIssue: true,
  },
} satisfies RelayStoryObj<typeof GlobalCreateMenu, CreateIssueDialogEntryQueries>

export const CreateIssueDialogWithRepo = {
  ...CreateIssueDialog,
  args: {
    createIssue: true,
    owner: 'orgA',
    repo: 'repoA',
  },
} satisfies RelayStoryObj<typeof GlobalCreateMenu, CreateIssueDialogEntryQueries>

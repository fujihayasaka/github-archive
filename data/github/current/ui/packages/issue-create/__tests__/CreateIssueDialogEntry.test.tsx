import {noop} from '@github-ui/noop'
import {AnalyticsProvider} from '@github-ui/analytics-provider'
import {TopRepositories} from '@github-ui/item-picker/RepositoryPicker'
import type {RepositoryPickerTopRepositoriesQuery} from '@github-ui/item-picker/RepositoryPickerTopRepositoriesQuery.graphql'
import {renderRelay} from '@github-ui/relay-test-utils'
import {screen} from '@testing-library/react'
import {graphql} from 'react-relay'
import {MemoryRouter} from 'react-router-dom'
import type {TemplateListPaneQuery} from '../__generated__/TemplateListPaneQuery.graphql'
import {getSafeConfig} from '../utils/option-config'
import {DisplayMode} from '../utils/display-mode'
import {CreateIssueDialogEntry} from '../dialog/CreateIssueDialogEntry'
import type {CreateIssueDialogEntryTestQuery} from './__generated__/CreateIssueDialogEntryTestQuery.graphql'
import {TEST_IDS} from '../constants/test-ids'

const CreateIssueDialogEntryTestGraphQLQuery = graphql`
  query CreateIssueDialogEntryTestQuery($owner: String!, $name: String!, $includeTemplates: Boolean = false)
  @relay_test_operation {
    repository(owner: $owner, name: $name) {
      ...RepositoryPickerRepository
      # eslint-disable-next-line relay/must-colocate-fragment-spreads
      ...CreateIssueDialog @arguments(includeTemplates: $includeTemplates)
    }
  }
`

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

function setup({options = {}, mockResolvers = {}, navigate = noop}) {
  return renderRelay<{
    topReposQueryRef: RepositoryPickerTopRepositoriesQuery
    currentRepositoryRef: CreateIssueDialogEntryTestQuery
    lazyTemplateListQuery: TemplateListPaneQuery
  }>(
    () => {
      let isOpen = true
      return (
        <MemoryRouter
          future={{v7_relativeSplatPath: true, v7_startTransition: true}}
          initialEntries={[{pathname: '/'}]}
        >
          <AnalyticsProvider appName="issue-create" category="" metadata={{}}>
            <CreateIssueDialogEntry
              navigate={navigate}
              isCreateDialogOpen={isOpen}
              setIsCreateDialogOpen={v => (isOpen = v)}
              optionConfig={getSafeConfig(options)}
            />
          </AnalyticsProvider>
        </MemoryRouter>
      )
    },
    {
      relay: {
        queries: {
          currentRepositoryRef: {
            type: 'preloaded',
            query: CreateIssueDialogEntryTestGraphQLQuery,
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
              topRepositoriesFirst: 10,
              hasIssuesEnabled: true,
              owner: null,
            },
          },
          lazyTemplateListQuery: {
            type: 'lazy',
          },
        },
        mockResolvers: {
          ...mockResolvers,
        },
      },
    },
  )
}

test('does not render the repo picker in issue creation mode', async () => {
  const repo = DEFAULT_REPO_MOCK
  setup({
    options: {
      defaultDisplayMode: DisplayMode.IssueCreation,
      insidePortal: true,
      issueCreateArguments: {
        repository: {
          owner: repo.owner.login,
          name: repo.name,
        },
      },
    },
    mockResolvers: {
      // templatelist for that repo
      Node() {
        return repo
      },
      // TopReposQuery
      Repository() {
        return repo
      },
    },
  })
  expect(screen.queryByTestId(TEST_IDS.repositoryAndTemplateDialog)).not.toBeInTheDocument()
})

test('navigates directly to issue create with single template option', async () => {
  const navigateFn = jest.fn()
  const repo = {
    ...DEFAULT_REPO_MOCK,
    issueTemplates: [
      {
        filename: 'templatename1.yml',
        name: DEFAULT_TEMPLATE_NAME,
        about: 'about template 1',
      },
    ],
    issueForms: [],
    contactLinks: [],
    isBlankIssuesEnabled: false,
    isSecurityPolicyEnabled: false,
  }

  setup({
    options: {
      defaultDisplayMode: DisplayMode.TemplatePicker,
      insidePortal: true,
      canBypassTemplateSelection: true,
      showRepositoryPicker: false,
      navigate: navigateFn,
      issueCreateArguments: {
        repository: {
          owner: repo.owner.login,
          name: repo.name,
        },
      },
    },
    mockResolvers: {
      // templatelist for that repo
      Node() {
        return repo
      },
      // TopReposQuery
      Repository() {
        return repo
      },
    },
  })

  expect(navigateFn).toHaveBeenCalledWith(`http://localhost/orgA/repoA/issues/new?template=templatename1.yml`)
})

test('navigates directly to issue create with no template', async () => {
  const navigateFn = jest.fn()
  const repo = {
    ...DEFAULT_REPO_MOCK,
    hasAnyTemplates: false,
    issueTemplates: [],
    issueForms: [],
    contactLinks: [],
    isBlankIssuesEnabled: false,
    isSecurityPolicyEnabled: false,
  }

  setup({
    options: {
      defaultDisplayMode: DisplayMode.TemplatePicker,
      insidePortal: true,
      canBypassTemplateSelection: true,
      showRepositoryPicker: false,
      navigate: navigateFn,
      issueCreateArguments: {
        repository: {
          owner: repo.owner.login,
          name: repo.name,
          hasAnyTemplates: false,
          isSecurityPolicyEnabled: false,
        },
      },
    },
    mockResolvers: {
      // templatelist for that repo
      Node() {
        return repo
      },
      // TopReposQuery
      Repository() {
        return repo
      },
    },
    navigate: navigateFn,
  })

  expect(navigateFn).toHaveBeenCalledWith(`/orgA/repoA/issues/new`)
})

test('preserves config initial options when navigating directly to issue create with no template', async () => {
  const navigateFn = jest.fn()
  const repo = {
    ...DEFAULT_REPO_MOCK,
    hasAnyTemplates: false,
    issueTemplates: [],
    issueForms: [],
    contactLinks: [],
    isBlankIssuesEnabled: false,
    isSecurityPolicyEnabled: false,
  }

  setup({
    options: {
      defaultDisplayMode: DisplayMode.TemplatePicker,
      insidePortal: true,
      canBypassTemplateSelection: true,
      showRepositoryPicker: false,
      navigate: navigateFn,
      issueCreateArguments: {
        repository: {
          owner: repo.owner.login,
          name: repo.name,
          hasAnyTemplates: false,
          isSecurityPolicyEnabled: false,
        },
        initialValues: {
          title: 'xtitle',
          body: 'xbody',
        },
      },
    },
    mockResolvers: {
      // templatelist for that repo
      Node() {
        return repo
      },
      // TopReposQuery
      Repository() {
        return repo
      },
    },
    navigate: navigateFn,
  })

  expect(navigateFn).toHaveBeenCalledWith(`/orgA/repoA/issues/new?title=xtitle&body=xbody`)
})

test('can render scoped assignees', async () => {
  const repo = DEFAULT_REPO_MOCK
  setup({
    options: {
      defaultDisplayMode: DisplayMode.IssueCreation,
      insidePortal: true,
      issueCreateArguments: {
        repository: {
          owner: repo.owner.login,
          name: repo.name,
        },
      },
      scopedAssignees: [
        {avatarUrl: 'https://avatars.githubusercontent.com/u/1', login: 'octocat'},
        {avatarUrl: 'https://avatars.githubusercontent.com/u/2', login: 'copilot'},
      ],
    },
    mockResolvers: {
      // templatelist for that repo
      Node() {
        return repo
      },
      // TopReposQuery
      Repository() {
        return repo
      },
    },
  })

  const button = await screen.findByLabelText('Select assignees')
  expect(button).toBeDisabled()
  expect(button).toHaveTextContent(/octocat, copilot/)
})

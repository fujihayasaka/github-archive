import {noop} from '@github-ui/noop'
import {CreateIssueDialog} from '../dialog/CreateIssueDialog'
import {AnalyticsProvider} from '@github-ui/analytics-provider'
import type {IssueFormRef} from '@github-ui/issue-form/Types'
import {TopRepositories} from '@github-ui/item-picker/RepositoryPicker'
import type {RepositoryPickerTopRepositoriesQuery} from '@github-ui/item-picker/RepositoryPickerTopRepositoriesQuery.graphql'
import {renderRelay} from '@github-ui/relay-test-utils'
import {useRef} from 'react'
import {screen} from '@testing-library/react'
import {graphql, usePreloadedQuery} from 'react-relay'
import {MemoryRouter} from 'react-router-dom'
import type {TemplateListPaneQuery} from '../__generated__/TemplateListPaneQuery.graphql'
import {IssueCreateContextProvider} from '../contexts/IssueCreateContext'
import {getSafeConfig} from '../utils/option-config'
import type {CreateIssueDialogTestQuery} from './__generated__/CreateIssueDialogTestQuery.graphql'
import {isMacOS} from '@github-ui/get-os'
import {getBlankIssue} from '../utils/model'
import {DisplayMode} from '../utils/display-mode'

jest.mock('@github-ui/get-os')

const CreateIssueDialogTestGraphQLQuery = graphql`
  query CreateIssueDialogTestQuery @relay_test_operation {
    repository(name: "name", owner: "owner") {
      ...CreateIssueDialog @arguments(includeTemplates: true)
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

function setupWithRepo({
  options = {},
  mockResolvers = {},
  preselectedData = {},
  onCreateSuccess = noop,
  navigate = noop,
}) {
  return renderRelay<{
    topReposQueryRef: RepositoryPickerTopRepositoriesQuery
    currentRepositoryRef: CreateIssueDialogTestQuery
    lazyTemplateListQuery: TemplateListPaneQuery
  }>(
    ({queryRefs: {topReposQueryRef, currentRepositoryRef}}) => {
      const issueFormRef = useRef<IssueFormRef>(null)
      const data = usePreloadedQuery<CreateIssueDialogTestQuery>(
        CreateIssueDialogTestGraphQLQuery,
        currentRepositoryRef,
      )
      return (
        <MemoryRouter
          future={{v7_relativeSplatPath: true, v7_startTransition: true}}
          initialEntries={[{pathname: '/'}]}
        >
          <AnalyticsProvider appName="issue-create" category="" metadata={{}}>
            <IssueCreateContextProvider optionConfig={getSafeConfig(options)} preselectedData={preselectedData}>
              <CreateIssueDialog
                topReposQueryRef={topReposQueryRef}
                currentRepository={data.repository}
                issueFormRef={issueFormRef}
                navigate={navigate}
                onCreateSuccess={onCreateSuccess}
                onCreateError={noop}
                onCancel={noop}
              />
            </IssueCreateContextProvider>
          </AnalyticsProvider>
        </MemoryRouter>
      )
    },
    {
      relay: {
        queries: {
          currentRepositoryRef: {
            type: 'preloaded',
            query: CreateIssueDialogTestGraphQLQuery,
            variables: {},
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

test('create issue using meta+enter on mac', async () => {
  const createIssue = jest.fn()
  const isMacOSMock = isMacOS as jest.Mock
  isMacOSMock.mockReturnValue(true)
  const repo = DEFAULT_REPO_MOCK
  const preselectedTemplate = getBlankIssue()
  const updatedTemplate = {
    ...preselectedTemplate,
    data: {
      ...preselectedTemplate.data,
      __typename: 'IssueTemplate',
      title: 'template title 1',
      body: 'template body 1',
    },
  }
  const {user} = setupWithRepo({
    preselectedData: {
      template: updatedTemplate,
      repository: repo,
    },
    options: {
      defaultDisplayMode: DisplayMode.IssueCreation,
      insidePortal: true,
      showRepositoryPicker: false,
    },
    onCreateSuccess: createIssue,
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
  // set a title
  const titleInput = await screen.findByLabelText('Add a title')
  await user.type(titleInput, 'test title')
  // set a body
  const bodyInput = await screen.findByLabelText('Markdown value')
  await user.type(bodyInput, 'test body')
  // focus non input element
  const addMoreCheckbox = screen.getByRole('checkbox')
  addMoreCheckbox.focus()
  // simulater Meta+Enter
  await user.keyboard('{Control>}{Enter}{/Control}')
  expect(createIssue).toHaveBeenCalled()
})

test('create issue using ctrl+enter on non-mac', async () => {
  const createIssue = jest.fn()
  const isMacOSMock = isMacOS as jest.Mock
  isMacOSMock.mockReturnValue(false)
  const repo = DEFAULT_REPO_MOCK
  const preselectedTemplate = getBlankIssue()
  const updatedTemplate = {
    ...preselectedTemplate,
    data: {
      ...preselectedTemplate.data,
      __typename: 'IssueTemplate',
      title: 'template title 1',
      body: 'template body 1',
    },
  }
  const {user} = setupWithRepo({
    preselectedData: {
      template: updatedTemplate,
      repository: repo,
    },
    options: {
      defaultDisplayMode: DisplayMode.IssueCreation,
      insidePortal: true,
      showRepositoryPicker: false,
    },
    onCreateSuccess: createIssue,
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
  // set a title
  const titleInput = await screen.findByLabelText('Add a title')
  await user.type(titleInput, 'test title')
  // set a body
  const bodyInput = await screen.findByLabelText('Markdown value')
  await user.type(bodyInput, 'test body')
  // focus non input element
  const addMoreCheckbox = screen.getByRole('checkbox')
  addMoreCheckbox.focus()
  // // simulate Control+Enter
  await user.keyboard('{Control>}[Enter]{/Control}')
  expect(createIssue).toHaveBeenCalled()
})

test('submit button is inactive when a file is still being uploaded', async () => {
  const repo = DEFAULT_REPO_MOCK
  const preselectedTemplate = getBlankIssue()

  const {user} = setupWithRepo({
    preselectedData: {
      template: preselectedTemplate,
      repository: repo,
    },
    options: {
      defaultDisplayMode: DisplayMode.IssueCreation,
      insidePortal: true,
      showRepositoryPicker: false,
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

  const bodyInput = await screen.findByLabelText('Markdown value')
  await user.type(bodyInput, '<!-- Uploading "image.png"... -->')
  const commitButton = screen.getByTestId('create-issue-button')
  expect(commitButton.getAttribute('data-inactive')).toBeTruthy()
})

test('footer invisible on template selection', async () => {
  const repo = DEFAULT_REPO_MOCK

  setupWithRepo({
    preselectedData: {
      repository: repo,
    },
    options: {
      defaultDisplayMode: DisplayMode.TemplatePicker,
      insidePortal: true,
      showRepositoryPicker: false,
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

  // Create should not be in the document
  expect(screen.queryByText('Create')).toBeNull()
})

test('skips template picker when default display mode is set to issue creation', async () => {
  const repo = DEFAULT_REPO_MOCK

  setupWithRepo({
    preselectedData: {
      repository: repo,
    },
    options: {
      defaultDisplayMode: DisplayMode.IssueCreation,
      insidePortal: true,
      showRepositoryPicker: false,
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

  // Create should not be in the document
  expect(screen.queryByText('Create')).toBeVisible()
})

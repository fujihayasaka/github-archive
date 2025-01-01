import {renderRelay} from '@github-ui/relay-test-utils'
import {IssueCreateContextProvider} from '../contexts/IssueCreateContext'
import {CreateIssue} from '../CreateIssue'
import {MemoryRouter} from 'react-router-dom'
import {getSafeConfig} from '../utils/option-config'
import type {RepositoryPickerTopRepositoriesQuery} from '@github-ui/item-picker/RepositoryPickerTopRepositoriesQuery.graphql'
import {noop} from '@github-ui/noop'
import type {IssueFormRef} from '@github-ui/issue-form/Types'
import {useRef} from 'react'
import {graphql} from 'relay-runtime'
import {act, screen} from '@testing-library/react'
import {TopRepositories} from '@github-ui/item-picker/RepositoryPicker'
import {usePreloadedQuery} from 'react-relay'
import type {CreateIssueTestQuery} from './__generated__/CreateIssueTestQuery.graphql'
import type {TemplateListPaneQuery} from '../__generated__/TemplateListPaneQuery.graphql'
import {LABELS} from '../constants/labels'
import {DisplayMode} from '../utils/display-mode'
import {getBlankIssue} from '../utils/model'
import {AnalyticsProvider} from '@github-ui/analytics-provider'
import {TEST_IDS} from '../constants/test-ids'
import {MockPayloadGenerator} from 'relay-test-utils'
import {DefaultMocks} from '@github-ui/relay-test-utils/mock-resolvers'

jest.mock('@github-ui/get-os')

const CreateIssueTestGraphQLQuery = graphql`
  query CreateIssueTestQuery @relay_test_operation {
    repository(name: "name", owner: "owner") {
      ...CreateIssue @arguments(includeTemplates: true)
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

function setup({
  options = {},
  repo = DEFAULT_REPO_MOCK,
  preselectedData = {},
  onCreateSuccess = noop,
  navigate = noop,
  withRepository = true,
}) {
  return renderRelay<{
    topReposQueryRef: RepositoryPickerTopRepositoriesQuery
    currentRepositoryRef: CreateIssueTestQuery
    lazyTemplateListQuery: TemplateListPaneQuery
  }>(
    ({queryRefs: {topReposQueryRef, currentRepositoryRef}}) => {
      const issueFormRef = useRef<IssueFormRef>(null)
      const data = usePreloadedQuery<CreateIssueTestQuery>(CreateIssueTestGraphQLQuery, currentRepositoryRef)
      return (
        <MemoryRouter
          future={{v7_relativeSplatPath: true, v7_startTransition: true}}
          initialEntries={[{pathname: '/'}]}
        >
          <AnalyticsProvider appName="issue-create" category="" metadata={{}}>
            <IssueCreateContextProvider optionConfig={getSafeConfig(options)} preselectedData={preselectedData}>
              <CreateIssue
                topReposQueryRef={topReposQueryRef}
                currentRepository={withRepository ? data.repository : undefined}
                issueFormRef={issueFormRef}
                navigate={navigate}
                onSafeClose={noop}
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
            query: CreateIssueTestGraphQLQuery,
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
          // templatelist for that repo
          Node() {
            return repo
          },
          // TopReposQuery
          Repository() {
            return repo
          },
        },
      },
    },
  )
}

function getActionListRowForTemplate(templateName: string) {
  return screen.getByRole('link', {name: templateName})
}

describe('test the issue create dialog with a repository picker (no preselected repo)', () => {
  test('renders issue create, autoselectes the first repository from the top repos and shows template picker', async () => {
    setup({
      withRepository: false,
      options: {
        defaultDisplayMode: DisplayMode.TemplatePicker,
        insidePortal: false,
      },
    })
    // find the repository picker
    expect(screen.getByText('orgA/repoA')).toBeInTheDocument()

    // find the first template
    expect(screen.getByText('about template 1', {exact: false})).toBeInTheDocument()
    expect(screen.getByText('template name 1', {exact: false})).toBeInTheDocument()

    // find the second template
    expect(screen.getByText('about template 2', {exact: false})).toBeInTheDocument()
    expect(screen.getByText('template name 2', {exact: false})).toBeInTheDocument()

    // // The security policy is shown as it exists in this repo
    screen.getByText(LABELS.securityPolicyName, {exact: false})
    screen.getByText(LABELS.securityPolicyDescription, {exact: false})

    const templateLink = await screen.findByText(LABELS.editTemplates, {exact: false})
    expect(templateLink.getAttribute('href')).toBe('/template/tree/url')

    // // The security href correct points the the supplied security URL
    const securityLink = getActionListRowForTemplate(LABELS.securityPolicyName)
    expect(securityLink.getAttribute('href')).toBe('/security/policy')

    const link = getActionListRowForTemplate('external link 1')
    expect(link.getAttribute('href')).toBe('https://github.com')
    const link2 = getActionListRowForTemplate('link name 2')
    expect(link2.getAttribute('href')).toBe('https://github.com/foo')
  })

  test('ensure security policy is not shown without a policy defined', async () => {
    const repo = {...DEFAULT_REPO_MOCK, isSecurityPolicyEnabled: false, viewerCanPush: false}
    setup({
      withRepository: false,
      repo,
      options: {
        defaultDisplayMode: DisplayMode.TemplatePicker,
        insidePortal: false,
      },
    })

    const securityPolicy = screen.queryByText(LABELS.securityPolicyName, {exact: false})
    expect(securityPolicy).toBe(null)

    // For repoB, they don't have push permissions so show 'view' text instead of edit.
    const templateLink = await screen.findByText(LABELS.viewTemplates, {exact: false})
    expect(templateLink.getAttribute('href')).toBe('/template/tree/url')
  })

  test('renders issue create, show template selector and the repository selector', async () => {
    setup({
      withRepository: false,
      preselectedData: {
        repository: DEFAULT_REPO_MOCK,
      },
      options: {
        defaultDisplayMode: DisplayMode.TemplatePicker,
        insidePortal: false,
      },
    })
    // find the selected repo
    expect(screen.getByText('orgA/repoA')).toBeInTheDocument()
  })
})

describe('test the issue create dialog with a preselected repo', () => {
  test('renders issue create, show template selector but not the repository selector', async () => {
    setup({
      options: {
        defaultDisplayMode: DisplayMode.TemplatePicker,
        insidePortal: false,
      },
    })

    // find the first template
    expect(screen.getByText('about template 1', {exact: false})).toBeInTheDocument()
    expect(screen.getByText('template name 1', {exact: false})).toBeInTheDocument()

    // find the second template
    expect(screen.getByText('about template 2', {exact: false})).toBeInTheDocument()
    expect(screen.getByText('template name 2', {exact: false})).toBeInTheDocument()
  })

  test('warning is shown for repository with issues disabled', async () => {
    const repo = {...DEFAULT_REPO_MOCK, hasIssuesEnabled: false}
    setup({
      options: {
        defaultDisplayMode: DisplayMode.TemplatePicker,
        insidePortal: false,
      },
      repo,
    })
    // Information about disabled issues is shown
    await expect(
      screen.getByText('Issues are disabled for the selected repository. Please select a different repository.', {
        exact: false,
      }),
    ).toBeInTheDocument()
  })

  test('warning is not shown for repository with issues enabled', async () => {
    const repo = {...DEFAULT_REPO_MOCK, hasIssuesEnabled: true}
    setup({
      options: {
        defaultDisplayMode: DisplayMode.TemplatePicker,
        insidePortal: false,
      },
      preselectedData: {
        repository: repo,
      },
      repo,
    })
    // Information about disabled issues is shown
    expect(
      screen.queryByText('Issues are disabled for the selected repository. Please select a different repository.', {
        exact: false,
      }),
    ).not.toBeInTheDocument()
  })

  test('renders issue create, predefined repository and template, prefill title and body', async () => {
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

    setup({
      preselectedData: {
        template: updatedTemplate,
        repository: DEFAULT_REPO_MOCK,
      },
      options: {
        defaultDisplayMode: DisplayMode.IssueCreation,
        insidePortal: true,
      },
    })
    // title is set from template
    const titleInput = await screen.findByLabelText('Add a title')
    expect(titleInput).toHaveValue('template title 1')

    // body is set from template
    const bodyInput = await screen.findByLabelText('Markdown value')
    expect(bodyInput).toHaveValue('template body 1')
  })

  test('clicking on template picker renders issue create dialog', async () => {
    const {relayMockEnvironment} = setup({
      options: {
        defaultDisplayMode: DisplayMode.TemplatePicker,
        insidePortal: false,
      },
      preselectedData: {
        repository: DEFAULT_REPO_MOCK,
      },
    })

    // click on the first template
    const template = getActionListRowForTemplate(DEFAULT_TEMPLATE_NAME)

    // Now simulate the network response
    act(() => {
      template.click()
      relayMockEnvironment.mock.resolveMostRecentOperation(operation => {
        expect(operation.request.node.operation.name).toBe('CreateIssueQuery')
        return MockPayloadGenerator.generate(operation, {
          ...DefaultMocks,
          IssueTemplate() {
            return {
              title: 'template prefix',
              body: 'template body 1',
            }
          },
        })
      })
    })
    // issue create is shown
    const titleInput = await screen.findByLabelText('Add a title')

    // title is set
    expect(titleInput).toBeInTheDocument()
    expect(titleInput).toHaveValue('template prefix')

    // body is set
    const bodyInput = await screen.findByLabelText('Markdown value')
    expect(bodyInput).toHaveValue('template body 1')

    // template picker is no longer shown
    expect(screen.queryByTestId(TEST_IDS.templateList)).not.toBeInTheDocument()
  })

  test('selecting a template with an initial title will append the initial title to the template title', async () => {
    const {relayMockEnvironment} = setup({
      options: {
        defaultDisplayMode: DisplayMode.TemplatePicker,
        insidePortal: false,

        issueCreateArguments: {
          initialValues: {
            appendTitleToTemplate: 'title-to-append',
          },
        },
      },
      preselectedData: {
        repository: DEFAULT_REPO_MOCK,
      },
    })

    // click on the first template
    const template = getActionListRowForTemplate(DEFAULT_TEMPLATE_NAME)

    // Now simulate the network response
    act(() => {
      template.click()
      relayMockEnvironment.mock.resolveMostRecentOperation(operation => {
        expect(operation.request.node.operation.name).toBe('CreateIssueQuery')
        return MockPayloadGenerator.generate(operation, {
          ...DefaultMocks,
          IssueTemplate() {
            return {
              title: 'template prefix',
              body: 'template body 1',
            }
          },
        })
      })
    })
    const titleInput = await screen.findByLabelText('Add a title')
    expect(titleInput).toHaveValue('template prefix title-to-append')
  })

  test('focuses template picker button if it is the first input', async () => {
    const template = getBlankIssue()

    setup({
      preselectedData: {
        template,
        repository: DEFAULT_REPO_MOCK,
      },
      options: {
        defaultDisplayMode: DisplayMode.IssueCreation,
        insidePortal: true,
      },
    })
    // find the first input
    const focusedInput = screen.getByTestId('template-picker-button-el')
    expect(focusedInput).toHaveFocus()
  })

  test('repository without any templates doesnt show the template edit button', async () => {
    const repo = {
      ...DEFAULT_REPO_MOCK,
      issueTemplates: [],
      issueForms: [],
      contactLinks: [],
      hasAnyTemplates: false,
      isBlankIssuesEnabled: false,
    }
    setup({
      preselectedData: {
        repository: repo,
      },
      repo,
      options: {
        defaultDisplayMode: DisplayMode.TemplatePicker,
        insidePortal: true,
      },
    })

    let templateButton = screen.queryByText(LABELS.viewTemplates, {exact: false})
    expect(templateButton).not.toBeInTheDocument()

    templateButton = screen.queryByText(LABELS.editTemplates, {exact: false})
    expect(templateButton).not.toBeInTheDocument()
  })

  test('repository where user doesnt have write access show readonly metadata pickers', async () => {
    const repo = {
      ...DEFAULT_REPO_MOCK,
      viewerIssueCreationPermissions: {
        labelable: false,
        milestoneable: false,
        assignable: false,
        triageable: false,
        typeable: false,
      },
    }
    const template = getBlankIssue()

    setup({
      preselectedData: {
        template,
        repository: repo,
      },
      options: {
        defaultDisplayMode: DisplayMode.IssueCreation,
        insidePortal: false,
      },
      repo,
    })
    // metadata pickers are not shown as button
    const assigneePicker = screen.queryByRole('button', {name: 'Edit Assignees'})
    expect(assigneePicker).not.toBeInTheDocument()

    const labelPicker = screen.queryByRole('button', {name: 'Edit Labels'})
    expect(labelPicker).not.toBeInTheDocument()

    const projectPicker = screen.queryByRole('button', {name: 'Edit Projects'})
    expect(projectPicker).not.toBeInTheDocument()

    const milestonePicker = screen.queryByRole('button', {name: 'Edit Milestone'})
    expect(milestonePicker).not.toBeInTheDocument()

    const typePicker = screen.queryByRole('button', {name: 'Edit Type'})
    expect(typePicker).not.toBeInTheDocument()
  })

  test('repository where user have write access show editable metadata pickers', async () => {
    const repo = {
      ...DEFAULT_REPO_MOCK,
      viewerIssueCreationPermissions: {
        labelable: true,
        milestoneable: true,
        assignable: true,
        triageable: true,
        typeable: true,
      },
    }
    const template = getBlankIssue()

    setup({
      preselectedData: {
        template,
        repository: repo,
      },
      options: {
        defaultDisplayMode: DisplayMode.IssueCreation,
        insidePortal: false,
      },
      repo,
    })
    // metadata pickers are not shown as button
    const assigneePicker = screen.queryByRole('button', {name: 'Edit Assignees'})
    expect(assigneePicker).toBeInTheDocument()

    const labelPicker = screen.queryByRole('button', {name: 'Edit Labels'})
    expect(labelPicker).toBeInTheDocument()

    const projectPicker = screen.queryByRole('button', {name: 'Edit Projects'})
    expect(projectPicker).toBeInTheDocument()

    const milestonePicker = screen.queryByRole('button', {name: 'Edit Milestone'})
    expect(milestonePicker).toBeInTheDocument()

    const typePicker = screen.queryByRole('button', {name: 'Edit Type'})
    expect(typePicker).toBeInTheDocument()
  })

  test('focuses title input if it is the first input', async () => {
    const repo = {...DEFAULT_REPO_MOCK, hasAnyTemplates: false}
    const template = getBlankIssue()

    setup({
      preselectedData: {
        template,
        repository: repo,
      },
      options: {
        defaultDisplayMode: DisplayMode.IssueCreation,
        insidePortal: true,
      },
      repo,
    })
    const focusedInput = screen.queryByLabelText('Add a title')
    expect(focusedInput).toHaveFocus()
  })

  test('clicking on an issue template doesnt show the back button by default', async () => {
    const repo = DEFAULT_REPO_MOCK
    const {relayMockEnvironment} = setup({
      options: {
        defaultDisplayMode: DisplayMode.TemplatePicker,
        insidePortal: false,
      },
      preselectedData: {
        repository: repo,
      },
      repo,
    })

    // click on the first template
    const template = getActionListRowForTemplate(DEFAULT_TEMPLATE_NAME)

    // Now simulate the network response
    act(() => {
      template.click()
      relayMockEnvironment.mock.resolveMostRecentOperation(operation => {
        expect(operation.request.node.operation.name).toBe('CreateIssueQuery')
        return MockPayloadGenerator.generate(operation, {
          ...DefaultMocks,
          IssueTemplate() {
            return {
              name: 'template name 1',
              title: 'template prefix',
              body: 'template body 1',
            }
          },
        })
      })
    })
    // The back button is not shown
    expect(screen.queryByText('template name 1', {exact: false})).not.toBeInTheDocument()
    expect(screen.queryByText('in', {exact: true})).not.toBeInTheDocument()
    expect(screen.queryByText('orgA/repoA', {exact: false})).not.toBeInTheDocument()

    // title is shown, indicating we are in the issue create flow
    const titleInput = await screen.findByLabelText('Add a title')
    expect(titleInput).toHaveValue('template prefix')
  })

  test('clicking on an issue template stays within the modal if `navigateToFullScreenOnTemplateChoice` is false', async () => {
    const navigateFn = jest.fn()
    const repo = DEFAULT_REPO_MOCK
    setup({
      options: {
        defaultDisplayMode: DisplayMode.TemplatePicker,
        insidePortal: false,
        navigateToFullScreenOnTemplateChoice: false,
      },
      navigate: navigateFn,
      preselectedData: {
        repository: repo,
      },
      repo,
    })

    // click on the first template
    const template = getActionListRowForTemplate(DEFAULT_TEMPLATE_NAME)

    // Now simulate the network response
    act(() => {
      template.click()
    })

    expect(navigateFn).not.toHaveBeenCalled()
  })

  test('clicking on an issue template stays navigates to fullscreen if `navigateToFullScreenOnTemplateChoice` is true', async () => {
    const navigateFn = jest.fn()
    const {relayMockEnvironment} = setup({
      options: {
        defaultDisplayMode: DisplayMode.TemplatePicker,
        insidePortal: false,
        navigateToFullScreenOnTemplateChoice: true,
      },
      navigate: navigateFn,
      preselectedData: {
        repository: DEFAULT_REPO_MOCK,
      },
    })

    // click on the first template
    const template = getActionListRowForTemplate(DEFAULT_TEMPLATE_NAME)

    // Now simulate the network response
    act(() => {
      template.click()
      relayMockEnvironment.mock.resolveMostRecentOperation(operation => {
        expect(operation.request.node.operation.name).toBe('CreateIssueQuery')
        return MockPayloadGenerator.generate(operation, {
          ...DefaultMocks,
          IssueTemplate() {
            return {
              name: 'template name 1',
              title: 'template prefix',
              body: 'template body 1',
            }
          },
        })
      })
    })

    expect(navigateFn).toHaveBeenCalled()
  })
})

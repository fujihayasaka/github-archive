import {copilotFeatureFlags} from '@github-ui/copilot-chat/utils/copilot-feature-flags'
import {getSafeConfig} from '@github-ui/issue-create/getSafeConfig'
import {IssueCreateContextProvider} from '@github-ui/issue-create/IssueCreateContext'
import type {RepositoryPickerRepository$data} from '@github-ui/item-picker/RepositoryPickerRepository.graphql'
import {renderRelay} from '@github-ui/relay-test-utils'
import {ScopedCommands} from '@github-ui/ui-commands'
import {useAnalytics} from '@github-ui/use-analytics'
import {act, screen} from '@testing-library/react'

import type {DraftIssue} from '../../content-preview-types'
import {CreateIssueButton} from '../CreateIssueButton'
import type {TreeNode} from '../use-draft-issue-tree-map'

const DEFAULT_TEMPLATE_NAME = 'template name 1'
const DEFAULT_REPO_MOCK = {
  __typename: 'Repository',
  nameWithOwner: 'orgA/repoA',
  owner: {login: 'orgA', issueTypesEnabled: true, avatarUrl: '', databaseId: 0},
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
  isBlankIssuesEnabled: false,
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
  viewerInteractionLimitReasonHTML: '',
  viewerIssueCreationPermissions: {
    typeable: true,
    triageable: true,
    assignable: true,
    labelable: true,
    milestoneable: true,
  },
  templateTreeUrl: '/template/tree/url',
  planFeatures: {maximumAssignees: 10},
  codeOfConductFileUrl: '',
  contributingFileUrl: '',
  databaseId: 0,
  isInOrganization: true,
  isPrivate: true,
  shortDescriptionHTML: '',
  slashCommandsEnabled: true,
  supportFileUrl: '',
  visibility: 'PRIVATE',
  ' $fragmentType': 'RepositoryPickerRepository',
} as RepositoryPickerRepository$data

function createIssueNode() {
  const baseProps: DraftIssue = {
    repository: 'repoA',
    type: 'new-issue',
    name: 'Issue Title',
    body: 'Issue Body',
    assignees: [],
    labels: [],
    projects: [],
    isUserEdited: false,
    tag: 'root',
    id: 'new-issue:root#1',
    messageId: 'message-id-1',
  }
  const parentIssue: DraftIssue = {
    ...baseProps,
    tag: 'root',
    id: 'new-issue:root#1',
    messageId: 'message-id-1',
  }
  const childIssue: DraftIssue = {
    ...baseProps,
    tag: 'child',
    id: 'new-issue:child#1',
    messageId: 'message-id-2',
    parentTag: 'root',
  }
  const grandChildIssue: DraftIssue = {
    ...baseProps,
    tag: 'grandchild',
    id: 'new-issue:grandchild#1',
    messageId: 'message-id-2',
    parentTag: 'child',
  }
  const draftIssues: DraftIssue[] = [parentIssue, childIssue, grandChildIssue]
  const draftIssuesMap = draftIssues.reduce((acc, issue) => {
    acc.set(issue.tag, {item: issue, parent: null, children: []})
    return acc
  }, new Map<string, TreeNode<DraftIssue>>())

  for (const draftIssue of draftIssues) {
    if (!draftIssue.parentTag) continue
    const parentNode = draftIssuesMap.get(draftIssue.parentTag)
    const currentNode = draftIssuesMap.get(draftIssue.tag)
    if (parentNode && currentNode) {
      currentNode.parent = parentNode
      // eslint-disable-next-line testing-library/no-node-access
      parentNode.children.push(currentNode)
    }
  }

  return draftIssuesMap
}

const rootNode = createIssueNode().get('root') as TreeNode<DraftIssue>

const mockOnClose = jest.fn()
const mockOnCreateSuccess = jest.fn()
const mockOnCreateBulkSuccess = jest.fn()

jest.mock('@github-ui/use-analytics')
jest.mocked(useAnalytics).mockReturnValue({sendAnalyticsEvent: jest.fn()})

function setupAndRender({
  issueTemplate = DEFAULT_TEMPLATE_NAME,
  repo = DEFAULT_REPO_MOCK,
  issueNode = rootNode,
  isBulkCreate = false,
}) {
  return renderRelay(
    () => {
      return (
        <ScopedCommands commands={{'github:submit-form': handler}}>
          <IssueCreateContextProvider optionConfig={getSafeConfig({})} preselectedData={{repository: repo}}>
            <CreateIssueButton
              issueTemplate={issueTemplate}
              issueNode={issueNode}
              isBulkCreate={isBulkCreate}
              onClose={mockOnClose}
              onCreateSuccess={mockOnCreateSuccess}
              onCreateBulkSuccess={mockOnCreateBulkSuccess}
            />
          </IssueCreateContextProvider>
        </ScopedCommands>
      )
    },
    {
      relay: {
        queries: {},
        mockResolvers: {},
      },
    },
  )
}

const handler = jest.fn()

describe('CreateIssueButton', () => {
  it('renders the dialog if no template selected but template is required', async () => {
    setupAndRender({
      issueTemplate: '',
      repo: {...DEFAULT_REPO_MOCK, isBlankIssuesEnabled: false},
    })

    const button = screen.getByRole('button')
    expect(button).toBeInTheDocument()
    expect(button).toHaveTextContent('Create')

    // check that it's the dialog button and not the submit button
    expect(await screen.findByTestId('create-issue-dialog-button')).toBeInTheDocument()

    // check that we don't submit
    act(() => {
      button.click()
    })
    expect(handler).not.toHaveBeenCalled()
  })

  it('renders the submit button if template selected and template required', async () => {
    setupAndRender({
      issueTemplate: DEFAULT_TEMPLATE_NAME,
      repo: {...DEFAULT_REPO_MOCK, isBlankIssuesEnabled: false},
    })

    const button = screen.getByRole('button')
    expect(button).toBeInTheDocument()
    expect(button).toHaveTextContent('Create')

    // check that it's the submit button and not the dialog button
    expect(await screen.findByTestId('create-issue-button')).toBeInTheDocument()

    // check that we submit
    button.click()
    expect(handler).toHaveBeenCalled()
  })

  it('renders the submit button if template selected and template not required', async () => {
    setupAndRender({
      issueTemplate: DEFAULT_TEMPLATE_NAME,
      repo: {...DEFAULT_REPO_MOCK, isBlankIssuesEnabled: true},
    })

    const button = screen.getByRole('button')
    expect(button).toBeInTheDocument()
    expect(button).toHaveTextContent('Create')

    // check that it's the submit button and not the dialog button
    expect(await screen.findByTestId('create-issue-button')).toBeInTheDocument()

    // check that we submit
    button.click()
    expect(handler).toHaveBeenCalled()
  })

  it('renders the submit button if no template selected and template not required', async () => {
    setupAndRender({
      issueTemplate: '',
      repo: {...DEFAULT_REPO_MOCK, isBlankIssuesEnabled: true},
    })

    const button = screen.getByRole('button')
    expect(button).toBeInTheDocument()
    expect(button).toHaveTextContent('Create')

    // check that it's the submit button and not the dialog button
    expect(await screen.findByTestId('create-issue-button')).toBeInTheDocument()

    // check that we submit
    button.click()
    expect(handler).toHaveBeenCalled()
  })

  describe('In Draft Issue Tree mode', () => {
    beforeEach(() => {
      jest.spyOn(copilotFeatureFlags, 'draftIssueTree', 'get').mockReturnValue(true)
    })

    it('renders the bulk create button in bulk create mode, template selected and template required', async () => {
      setupAndRender({
        issueTemplate: DEFAULT_TEMPLATE_NAME,
        repo: {...DEFAULT_REPO_MOCK, isBlankIssuesEnabled: false},
        isBulkCreate: true,
      })

      const button = screen.getByRole('button')
      expect(button).toBeInTheDocument()
      expect(button).toHaveTextContent('Create all')

      // check that it's the submit button and not the dialog button
      expect(await screen.findByTestId('create-issue-with-bulk-option-button')).toBeInTheDocument()

      // check that we submit
      act(() => {
        button.click()
      })
      expect(handler).toHaveBeenCalled()
    })

    it('renders the bulk create button in bulk create mode, template selected and template not required', async () => {
      setupAndRender({
        issueTemplate: DEFAULT_TEMPLATE_NAME,
        repo: {...DEFAULT_REPO_MOCK, isBlankIssuesEnabled: true},
        isBulkCreate: true,
      })

      const button = screen.getByRole('button')
      expect(button).toBeInTheDocument()
      expect(button).toHaveTextContent('Create all')

      // check that it's the submit button and not the dialog button
      expect(await screen.findByTestId('create-issue-with-bulk-option-button')).toBeInTheDocument()

      // check that we submit
      act(() => {
        button.click()
      })
      expect(handler).toHaveBeenCalled()
    })

    it('renders the bulk create button in bulk create mode, no template selected and template not required', async () => {
      setupAndRender({
        issueTemplate: '',
        repo: {...DEFAULT_REPO_MOCK, isBlankIssuesEnabled: true},
        isBulkCreate: true,
      })

      const button = screen.getByRole('button')
      expect(button).toBeInTheDocument()
      expect(button).toHaveTextContent('Create all')

      // check that it's the submit button and not the dialog button
      expect(await screen.findByTestId('create-issue-with-bulk-option-button')).toBeInTheDocument()

      // check that we submit
      act(() => {
        button.click()
      })
      expect(handler).toHaveBeenCalled()
    })
    it('renders the single create button in single create mode, template selected and template required', async () => {
      setupAndRender({
        issueTemplate: DEFAULT_TEMPLATE_NAME,
        repo: {...DEFAULT_REPO_MOCK, isBlankIssuesEnabled: false},
        isBulkCreate: false,
      })

      const button = screen.getByRole('button')
      expect(button).toBeInTheDocument()
      expect(button).toHaveTextContent('Create')

      // check that it's the submit button and not the dialog button
      expect(await screen.findByTestId('create-issue-with-bulk-option-button')).toBeInTheDocument()

      // check that we submit
      act(() => {
        button.click()
      })
      expect(handler).toHaveBeenCalled()
    })

    it('renders the single create button in single create mode, template selected and template not required', async () => {
      setupAndRender({
        issueTemplate: DEFAULT_TEMPLATE_NAME,
        repo: {...DEFAULT_REPO_MOCK, isBlankIssuesEnabled: true},
        isBulkCreate: false,
      })

      const button = screen.getByRole('button')
      expect(button).toBeInTheDocument()
      expect(button).toHaveTextContent('Create')

      // check that it's the submit button and not the dialog button
      expect(await screen.findByTestId('create-issue-with-bulk-option-button')).toBeInTheDocument()

      // check that we submit
      act(() => {
        button.click()
      })
      expect(handler).toHaveBeenCalled()
    })

    it('renders the single create button in single create mode, no template selected and template not required', async () => {
      setupAndRender({
        issueTemplate: '',
        repo: {...DEFAULT_REPO_MOCK, isBlankIssuesEnabled: true},
        isBulkCreate: false,
      })

      const button = screen.getByRole('button')
      expect(button).toBeInTheDocument()
      expect(button).toHaveTextContent('Create')

      // check that it's the submit button and not the dialog button
      expect(await screen.findByTestId('create-issue-with-bulk-option-button')).toBeInTheDocument()

      // check that we submit
      act(() => {
        button.click()
      })
      expect(handler).toHaveBeenCalled()
    })

    it('does not render anything if issue is a sub-issue', () => {
      const issueNode = createIssueNode().get('child') as TreeNode<DraftIssue>
      const {container} = setupAndRender({
        issueNode,
        issueTemplate: DEFAULT_TEMPLATE_NAME,
        repo: {...DEFAULT_REPO_MOCK, isBlankIssuesEnabled: true},
        isBulkCreate: true,
      })

      // Check the first child because ScopedCommands wrap contents in a `div` with `display: contents` by default.
      // eslint-disable-next-line testing-library/no-node-access
      expect(container.firstChild).toBeEmptyDOMElement()
    })
  })
})

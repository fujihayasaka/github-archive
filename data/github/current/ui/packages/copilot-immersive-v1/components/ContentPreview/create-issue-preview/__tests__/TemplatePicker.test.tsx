import {CopilotChatProvider} from '@github-ui/copilot-chat/CopilotChatContext'
import {useSelectedCustomCopilotId} from '@github-ui/copilot-chat/hooks/use-selected-custom-copilot-id'
import {getCopilotChatProviderProps} from '@github-ui/copilot-chat/test-utils/mock-data'
import type {CustomCopilotId} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {copilotFeatureFlags} from '@github-ui/copilot-chat/utils/copilot-feature-flags'
import {useIssueCreateDataContext} from '@github-ui/issue-create/IssueCreateDataContext'
import type {Repository} from '@github-ui/item-picker/RepositoryPicker'
import type {RepositoryPickerRepository$data} from '@github-ui/item-picker/RepositoryPickerRepository.graphql'
import {Wrapper} from '@github-ui/react-core/test-utils'
import {renderRelay} from '@github-ui/relay-test-utils'
import {act, screen} from '@testing-library/react'

import type {DraftIssue} from '../../content-preview-types'
import type {TemplatePickerQuery} from '../__generated__/TemplatePickerQuery.graphql'
import {TemplatePicker} from '../TemplatePicker'

jest.mock('@github-ui/issue-create/IssueCreateDataContext', () => ({
  ...jest.requireActual('@github-ui/issue-create/IssueCreateDataContext'),
  useIssueCreateDataContext: jest.fn(),
}))

const sendChatMessage = jest.fn()
jest.mock('@github-ui/copilot-chat/CopilotChatManagerContext', () => ({
  ...jest.requireActual('@github-ui/copilot-chat/CopilotChatManagerContext'),
  useChatManager: () => {
    return {
      sendChatMessage,
      getSelectedThread: jest.fn().mockReturnValue(null),
    }
  },
}))

jest.mock('@github-ui/copilot-chat/hooks/use-selected-custom-copilot-id', () => ({
  ...jest.requireActual('@github-ui/copilot-chat/hooks/use-selected-custom-copilot-id'),
  useSelectedCustomCopilotId: jest.fn().mockReturnValue(null),
}))

const updateItem = jest.fn()
const openItem = jest.fn()
const openPreviewPane = jest.fn()
const closeItem = jest.fn()
const mockContentPreview = {
  items: new Map(),
  updateItem,
  openItem,
  closeItem,
  openPreviewPane,
}
jest.mock('../../ContentPreviewContext', () => ({
  useContentPreview: jest.fn(() => mockContentPreview),
}))

const draftIssue: DraftIssue = {
  type: 'new-issue',
  tag: 'tag1',
  id: 'new-issue:tag1#123',
  repository: `orgA/repoA`,
  name: 'Issue Title',
  body: 'Issue Description',
  assignees: [],
  labels: [],
  issueType: 'bug',
  projects: [],
  milestone: undefined,
  messageId: '123',
  isUserEdited: false,
}

const mockRepo = {
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
      name: 'template name 1',
      about: 'about template 1',
    },
    {
      filename: 'templatename2.yml',
      name: 'template name 2',
      about: 'about template 2',
    },
  ],
  isBlankIssuesEnabled: true,
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

async function setupAndRender(
  repository: Repository | undefined,
  template: string | undefined,
  repositoryResolver: Record<string, unknown>,
) {
  ;(useIssueCreateDataContext as jest.Mock).mockReturnValue({
    repository,
  })

  const updatedIssue: DraftIssue = {
    ...draftIssue,
    template,
  }

  const view = renderRelay<{
    templatePickerQuery: TemplatePickerQuery
  }>(
    () => {
      return (
        <CopilotChatProvider {...getCopilotChatProviderProps()} topic={undefined} threadId="2" mode="immersive">
          <TemplatePicker draftIssue={updatedIssue} />
        </CopilotChatProvider>
      )
    },
    {
      relay: {
        queries: {
          templatePickerQuery: {
            type: 'lazy',
          },
        },
        mockResolvers: {
          Repository() {
            return repositoryResolver
          },
        },
      },
      wrapper: Wrapper,
    },
  )

  await act(() => jest.runAllTimersAsync())

  return view
}

describe('TemplatePicker', () => {
  beforeEach(() => {
    jest.clearAllMocks()
    jest.useFakeTimers()
    jest.mocked(useSelectedCustomCopilotId).mockReturnValue(null)
  })

  afterEach(() => {
    jest.useRealTimers()
  })

  it('renders nothing if no repository is provided', async () => {
    const repository = undefined

    const {container} = await setupAndRender(repository, undefined, {
      issueTemplates: [
        {
          __typename: 'IssueTemplate',
          filename: 'feature-request.md',
          name: 'Feature Request',
          about: 'Request a feature for this application.',
        },
      ],
      issueForms: [
        {
          __typename: 'IssueForm',
          filename: 'bug.yml',
          name: 'Bug Report',
          about: 'Report a bug for this application.',
        },
      ],
    })

    expect(container).toBeEmptyDOMElement()
  })

  it('renders nothing if no templates are found', async () => {
    const {container} = await setupAndRender(mockRepo, undefined, {
      issueTemplates: [],
      issueForms: [],
    })

    expect(container).toBeEmptyDOMElement()
  })

  it('renders nothing in Spaces', async () => {
    jest.mocked(useSelectedCustomCopilotId).mockReturnValue({id: 1} satisfies CustomCopilotId)

    const {container} = await setupAndRender(mockRepo, undefined, {
      issueTemplates: [
        {
          __typename: 'IssueTemplate',
          filename: 'feature-request.md',
          name: 'Feature Request',
          about: 'Request a feature for this application.',
        },
      ],
      issueForms: [
        {
          __typename: 'IssueForm',
          filename: 'bug.yml',
          name: 'Bug Report',
          about: 'Report a bug for this application.',
        },
      ],
    })

    expect(container).toBeEmptyDOMElement()
  })

  it('filters the templates based on the search term', async () => {
    const {user} = await setupAndRender(mockRepo, undefined, {
      issueTemplates: [
        {
          __typename: 'IssueTemplate',
          filename: 'feature-request.md',
          name: 'Feature Request',
          about: 'Request a feature for this application.',
        },
      ],
      issueForms: [
        {
          __typename: 'IssueForm',
          filename: 'bug.yml',
          name: 'Bug Report',
          about: 'Report a bug for this application.',
        },
      ],
    })

    const button = await screen.findByRole('button')
    expect(button).toBeInTheDocument()

    // Open the template picker dialog
    await user.click(button)

    const dialog = await screen.findByRole('dialog')
    expect(dialog).toBeInTheDocument()

    let options = await screen.findAllByRole('option')
    expect(options).toHaveLength(2)
    expect(options[0]).toHaveTextContent('Bug Report')
    expect(options[1]).toHaveTextContent('Feature Request')

    const input = screen.getByRole('combobox')
    expect(input).toBeInTheDocument()

    // Filter the templates
    await user.type(input, 'bu')
    expect(input).toHaveValue('bu')

    // Confirm updated results
    options = await screen.findAllByRole('option')
    expect(options).toHaveLength(1)
    expect(options[0]).toHaveTextContent('Bug Report')
  })

  it('renders the template picker without a selected template', async () => {
    const {user} = await setupAndRender(mockRepo, undefined, {
      issueTemplates: [
        {
          __typename: 'IssueTemplate',
          filename: 'feature-request.md',
          name: 'Feature Request',
          about: 'Request a feature for this application.',
        },
      ],
      issueForms: [
        {
          __typename: 'IssueForm',
          filename: 'bug.yml',
          name: 'Bug Report',
          about: 'Report a bug for this application.',
        },
      ],
    })

    const button = await screen.findByRole('button')
    expect(button).toBeInTheDocument()
    expect(button).not.toHaveTextContent('*')

    // Open the template picker dialog
    await user.click(button)

    const dialog = await screen.findByRole('dialog')
    expect(dialog).toBeInTheDocument()

    const options = await screen.findAllByRole('option')
    expect(options).toHaveLength(2)
    expect(options[0]).toHaveTextContent('Bug Report')
    expect(options[0]).toHaveAttribute('aria-selected', 'false')
    expect(options[1]).toHaveTextContent('Feature Request')
    expect(options[1]).toHaveAttribute('aria-selected', 'false')
  })

  it('renders the template picker without a selected template and includes "required" symbol', async () => {
    jest.spyOn(copilotFeatureFlags, 'draftIssueTemplateRequiredIfBlankIssuesDisabled', 'get').mockReturnValue(true)

    const {user} = await setupAndRender({...mockRepo, isBlankIssuesEnabled: false}, undefined, {
      issueTemplates: [
        {
          __typename: 'IssueTemplate',
          filename: 'feature-request.md',
          name: 'Feature Request',
          about: 'Request a feature for this application.',
        },
      ],
      issueForms: [
        {
          __typename: 'IssueForm',
          filename: 'bug.yml',
          name: 'Bug Report',
          about: 'Report a bug for this application.',
        },
      ],
    })

    const button = await screen.findByRole('button')
    expect(button).toBeInTheDocument()
    expect(button).toHaveTextContent('*')

    // Open the template picker dialog
    await user.click(button)

    const dialog = await screen.findByRole('dialog')
    expect(dialog).toBeInTheDocument()

    const options = await screen.findAllByRole('option')
    expect(options).toHaveLength(2)
    expect(options[0]).toHaveTextContent('Bug Report')
    expect(options[0]).toHaveAttribute('aria-selected', 'false')
    expect(options[1]).toHaveTextContent('Feature Request')
    expect(options[1]).toHaveAttribute('aria-selected', 'false')
  })

  const cases = [
    ['absolute path', '.github/ISSUE_TEMPLATE/feature-request.md'],
    ['relative path', 'feature-request.md'],
  ]
  test.each(cases)('renders the template picker with a selected template (%s)', async (_, initTemplate) => {
    const {user} = await setupAndRender(mockRepo, initTemplate, {
      issueTemplates: [
        {
          __typename: 'IssueTemplate',
          filename: 'feature-request.md',
          name: 'Feature Request',
          about: 'Request a feature for this application.',
        },
      ],
      issueForms: [
        {
          __typename: 'IssueForm',
          filename: 'bug.yml',
          name: 'Bug Report',
          about: 'Report a bug for this application.',
        },
      ],
    })

    const button = await screen.findByRole('button')
    expect(button).toBeInTheDocument()
    expect(button).not.toHaveTextContent('*')

    // Open the template picker dialog
    await user.click(button)

    const dialog = await screen.findByRole('dialog')
    expect(dialog).toBeInTheDocument()

    const options = await screen.findAllByRole('option')
    expect(options).toHaveLength(2)
    expect(options[0]).toHaveTextContent('Bug Report')
    expect(options[0]).toHaveAttribute('aria-selected', 'false')
    expect(options[1]).toHaveTextContent('Feature Request')
    expect(options[1]).toHaveAttribute('aria-selected', 'true')
  })

  it('sends a message when a template is selected', async () => {
    const {user} = await setupAndRender(mockRepo, undefined, {
      issueTemplates: [],
      issueForms: [
        {
          __typename: 'IssueForm',
          filename: 'bug.yml',
          name: 'Bug Report',
          about: 'Report a bug for this application.',
        },
      ],
    })

    const button = await screen.findByRole('button')
    expect(button).toBeInTheDocument()

    // Open the template picker dialog
    await user.click(button)

    const dialog = await screen.findByRole('dialog')
    expect(dialog).toBeInTheDocument()

    const options = await screen.findAllByRole('option')
    expect(options).toHaveLength(1)

    // Confirm the option is not currently selected
    const option = options[0]!
    expect(option).toHaveTextContent('Bug Report')
    expect(option).toHaveAttribute('aria-selected', 'false')

    // Select the template
    await user.click(option)

    expect(updateItem).toHaveBeenCalledWith({...draftIssue, template: 'bug.yml', isUserEdited: false})
    expect(sendChatMessage).toHaveBeenCalledWith(
      expect.objectContaining({
        content: "Use the 'Bug Report' template",
        references: expect.arrayContaining([
          expect.objectContaining({
            type: 'text',
            name: `timeline-event: {"type": "switch-issue-template", "markdownContent": "Changing template to 'Bug Report'…"}`,
          }),
          expect.objectContaining({type: 'draft-issue', template: 'bug.yml'}),
        ]),
      }),
    )
  })

  it('sends a message when no template is selected', async () => {
    const {user} = await setupAndRender(mockRepo, 'bug.yml', {
      issueTemplates: [],
      issueForms: [
        {
          __typename: 'IssueForm',
          filename: 'bug.yml',
          name: 'Bug Report',
          about: 'Report a bug for this application.',
        },
      ],
    })

    const button = await screen.findByRole('button')
    expect(button).toBeInTheDocument()

    // Open the template picker dialog
    await user.click(button)

    const dialog = await screen.findByRole('dialog')
    expect(dialog).toBeInTheDocument()

    const options = await screen.findAllByRole('option')
    expect(options).toHaveLength(1)

    // Confirm the option is currently selected
    const option = options[0]!
    expect(option).toHaveTextContent('Bug Report')
    expect(option).toHaveAttribute('aria-selected', 'true')

    // Deselect the template, resulting in no template selected
    await user.click(option)

    expect(updateItem).toHaveBeenCalledWith({...draftIssue, isUserEdited: false})
    expect(sendChatMessage).toHaveBeenCalledWith(
      expect.objectContaining({
        content: 'Remove the template',
        references: expect.arrayContaining([
          expect.objectContaining({
            type: 'text',
            name: 'timeline-event: {"type": "switch-issue-template", "markdownContent": "Removing template…"}',
          }),
          expect.objectContaining({type: 'draft-issue', template: undefined}),
        ]),
      }),
    )
  })
})

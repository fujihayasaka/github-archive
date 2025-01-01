import {render} from '@github-ui/react-core/test-utils'
import {CreateIssueForm, type CreateIssueFormProps} from '../CreateIssueForm'
import {noop} from '@github-ui/noop'
import {act, screen} from '@testing-library/react'
import {RelayEnvironmentProvider, type OperationDescriptor} from 'react-relay'
import {type RelayMockEnvironment, createMockEnvironment} from 'relay-test-utils/lib/RelayModernMockEnvironment'
import {type MockRepository, buildMockRepository, buildMockTemplate} from './helpers'
import type {
  RepositoryPickerRepository$data,
  RepositoryVisibility,
} from '@github-ui/item-picker/RepositoryPickerRepository.graphql'
import {useRef, type ReactNode} from 'react'
import {getDefaultConfig, type IssueCreateOptionConfig} from '../utils/option-config'
import {useAnalytics} from '@github-ui/use-analytics'
import {commitCreateIssueMutation} from '../mutations/create-issue-mutation'
import {useIssueCreateConfigContext} from '../contexts/IssueCreateConfigContext'
import {IssueCreateContextProvider} from '../contexts/IssueCreateContext'
import {MockPayloadGenerator} from 'relay-test-utils'
import {IssueTypePickerGraphqlQuery} from '@github-ui/item-picker/IssueTypePicker'
import {mockRelayId} from '@github-ui/relay-test-utils/RelayComponents'
import type {IssueFormRef} from '@github-ui/issue-form/Types'
import {IssueCreationKind, type IssueCreatePayload} from '../utils/model'
import {isFeatureEnabled} from '@github-ui/feature-flags'
import {LABELS} from '../constants/labels'

const mockRepository: MockRepository = buildMockRepository({
  owner: 'github',
  name: 'issues',
})

jest.mock('@github-ui/feature-flags', () => ({
  isFeatureEnabled: jest.fn(),
}))
const mockIsFeatureEnabled = jest.mocked(isFeatureEnabled)

const navigateFn = jest.fn()
jest.mock('@github-ui/use-navigate', () => {
  return {
    ...jest.requireActual('@github-ui/use-navigate'),
    useNavigate: () => navigateFn,
  }
})

jest.mock('@github-ui/use-analytics')
const sendAnalyticsEventMock = jest.fn()
jest.mocked(useAnalytics).mockReturnValue({sendAnalyticsEvent: sendAnalyticsEventMock})

jest.mock('../mutations/create-issue-mutation.ts')
const createIssueMutationMock = jest.mocked(commitCreateIssueMutation)

type CreateIssueFormWrapper = Omit<CreateIssueFormProps, 'repository' | 'issueFormRef'> & {
  environment: RelayMockEnvironment
  repository: MockRepository
  children?: ReactNode
  optionConfigOverrides?: Partial<IssueCreateOptionConfig>
}

const CreateIssueFormWrapper = ({
  environment,
  repository,
  children,
  // eslint-disable-next-line @eslint-react/no-unstable-default-props
  optionConfigOverrides = {},
  ...props
}: CreateIssueFormWrapper) => {
  const issueFormRef = useRef<IssueFormRef>(null)
  return (
    <RelayEnvironmentProvider environment={environment}>
      <IssueCreateContextProvider
        optionConfig={{...getDefaultConfig(), ...optionConfigOverrides}}
        preselectedData={undefined}
      >
        <CreateIssueForm
          {...props}
          issueFormRef={issueFormRef}
          repository={repository as unknown as RepositoryPickerRepository$data}
        />
        {children}
      </IssueCreateContextProvider>
    </RelayEnvironmentProvider>
  )
}

const CreateIssueFormWrapperWithPredefinedData = ({
  environment,
  repository,
  children,
  // eslint-disable-next-line @eslint-react/no-unstable-default-props
  optionConfigOverrides = {},
  ...props
}: CreateIssueFormWrapper) => {
  const issueFormRef = useRef<IssueFormRef>(null)
  return (
    <RelayEnvironmentProvider environment={environment}>
      <IssueCreateContextProvider
        optionConfig={{...getDefaultConfig(), ...optionConfigOverrides}}
        preselectedData={{repository: mockRepository as unknown as RepositoryPickerRepository$data}}
      >
        <CreateIssueForm
          {...props}
          issueFormRef={issueFormRef}
          repository={repository as unknown as RepositoryPickerRepository$data}
        />
        {children}
      </IssueCreateContextProvider>
    </RelayEnvironmentProvider>
  )
}
let environment: RelayMockEnvironment

beforeEach(() => {
  environment = createMockEnvironment()
  jest.clearAllMocks()

  window.sessionStorage.clear()
})

function setIssueTypeReferenceMock() {
  environment.mock.queuePendingOperation(IssueTypePickerGraphqlQuery, {owner: 'github', repo: 'issues'})

  environment.mock.queueOperationResolver((operation: OperationDescriptor) => {
    return MockPayloadGenerator.generate(operation, {
      Repository() {
        return {
          issueTypes: {
            edges: [
              {
                node: {
                  id: mockRelayId(),
                  name: 'Bug',
                },
              },
            ],
          },
        }
      },
    })
  })
}

function mockCreateIssueWithError(errorMessage?: string) {
  createIssueMutationMock.mockImplementation(({onError}) => {
    const error = new Error('Issue create error')
    error.cause = [new Error(errorMessage)]
    onError?.(error)
    return {dispose: noop}
  })
}

const CreateButtonComponent = () => {
  const {onCreateAction} = useIssueCreateConfigContext()

  return <button onClick={() => onCreateAction.current?.onCreate(false, false)}>Mock create</button>
}

test('renders the contributors footer', () => {
  render(
    <CreateIssueFormWrapper
      environment={environment}
      repository={mockRepository}
      title="title"
      setTitle={noop}
      body="body"
      setBody={noop}
      clearOnCreate={noop}
      onCreateSuccess={noop}
      onCreateError={noop}
      onCancel={noop}
    />,
  )

  expect(screen.getByText(/Remember, contributions to this repository should follow/)).toBeInTheDocument()
})

test('focuses title input when loading the page', () => {
  render(
    <CreateIssueFormWrapper
      environment={environment}
      repository={mockRepository}
      title=""
      setTitle={noop}
      body=""
      setBody={noop}
      clearOnCreate={noop}
      onCreateSuccess={noop}
      onCreateError={noop}
      onCancel={noop}
    >
      <CreateButtonComponent />
    </CreateIssueFormWrapper>,
  )

  expect(screen.getByLabelText('Add a title')).toHaveFocus()
})

test('focuses title input if not filled on create click', () => {
  render(
    <CreateIssueFormWrapper
      environment={environment}
      repository={mockRepository}
      title=""
      setTitle={noop}
      body=""
      setBody={noop}
      clearOnCreate={noop}
      onCreateSuccess={noop}
      onCreateError={noop}
      onCancel={noop}
    >
      <CreateButtonComponent />
    </CreateIssueFormWrapper>,
  )

  act(() => {
    screen.getByText('Mock create').click()
  })

  expect(screen.getByLabelText('Add a title')).toHaveFocus()
})

test('sends analytics event on submit', async () => {
  createIssueMutationMock.mockImplementation(({onCompleted}) => {
    onCompleted?.({
      createIssue: {
        errors: [],
        issue: {
          id: 'issue-id',
          number: 1,
          databaseId: 1,
          title: 'title',
          url: '',
          repository: {
            id: 'repository-id',
            databaseId: 1,
            name: 'repository',
            owner: {
              login: 'owner',
            },
          },
        },
      },
    })
    return {dispose: noop}
  })

  const {user} = render(
    <CreateIssueFormWrapper
      environment={environment}
      repository={mockRepository}
      title="cool title"
      setTitle={noop}
      body=""
      setBody={noop}
      clearOnCreate={noop}
      onCreateSuccess={noop}
      onCreateError={noop}
      onCancel={noop}
    >
      <CreateButtonComponent />
    </CreateIssueFormWrapper>,
  )

  await user.click(screen.getByText('Mock create'))

  expect(sendAnalyticsEventMock).toHaveBeenCalledTimes(1)
  expect(sendAnalyticsEventMock).toHaveBeenCalledWith('analytics.click', 'ISSUE_CREATE_NEW_ISSUE_BUTTON', {
    issueId: 'issue-id',
    issueNWO: 'owner/repository',
    issueNumber: 1,
  })
})

test('can have a preselected disabled milestone', async () => {
  setIssueTypeReferenceMock()

  render(
    <CreateIssueFormWrapper
      environment={environment}
      repository={mockRepository}
      title="title"
      optionConfigOverrides={{scopedMilestone: 'Milestone 1'}}
      setTitle={noop}
      body="body"
      setBody={noop}
      clearOnCreate={noop}
      onCreateSuccess={noop}
      onCreateError={noop}
      onCancel={noop}
    />,
  )

  const button = screen.getByRole('button', {name: 'Milestone 1'})
  expect(button).toBeInTheDocument()
  expect(button).toHaveAttribute('disabled')
})

test('type selector can be seen when metadata is shown', async () => {
  setIssueTypeReferenceMock()

  render(
    <CreateIssueFormWrapperWithPredefinedData
      environment={environment}
      repository={mockRepository}
      title="title"
      optionConfigOverrides={{insidePortal: false}}
      setTitle={noop}
      body="body"
      setBody={noop}
      clearOnCreate={noop}
      onCreateSuccess={noop}
      onCreateError={noop}
      onCancel={noop}
    />,
  )

  expect(screen.getByText('Type')).toBeInTheDocument()
})

test('type selector is hidden when issue types are not enabled for repo owner', async () => {
  mockRepository.owner.issueTypesEnabled = false

  render(
    <CreateIssueFormWrapperWithPredefinedData
      environment={environment}
      repository={mockRepository}
      title="title"
      optionConfigOverrides={{insidePortal: false}}
      setTitle={noop}
      body="body"
      setBody={noop}
      clearOnCreate={noop}
      onCreateSuccess={noop}
      onCreateError={noop}
      onCancel={noop}
    />,
  )

  expect(screen.queryByText('Type')).not.toBeInTheDocument()
})

test('displays collaborator only restriction error', async () => {
  mockCreateIssueWithError(
    'could not be created. Interactions on this repository have been restricted to collaborators only.',
  )

  const {user} = render(
    <CreateIssueFormWrapper
      environment={environment}
      repository={mockRepository}
      title="cool title"
      setTitle={noop}
      body=""
      setBody={noop}
      clearOnCreate={noop}
      onCreateSuccess={noop}
      onCreateError={noop}
      onCancel={noop}
      optionConfigOverrides={{insidePortal: true}}
    >
      <CreateButtonComponent />
    </CreateIssueFormWrapper>,
  )

  await user.click(screen.getByText('Mock create'))

  expect(
    screen.getByText(
      'Could not be created. Interactions on this repository have been restricted to collaborators only.',
    ),
  ).toBeInTheDocument()
})

test('displays prior contributors restriction error', async () => {
  mockCreateIssueWithError(
    'could not be created. Interactions on this repository have been restricted to prior contributors only.',
  )

  const {user} = render(
    <CreateIssueFormWrapper
      environment={environment}
      repository={mockRepository}
      title="cool title"
      setTitle={noop}
      body=""
      setBody={noop}
      clearOnCreate={noop}
      onCreateSuccess={noop}
      onCreateError={noop}
      onCancel={noop}
      optionConfigOverrides={{insidePortal: true}}
    >
      <CreateButtonComponent />
    </CreateIssueFormWrapper>,
  )

  await user.click(screen.getByText('Mock create'))

  expect(
    screen.getByText(
      'Could not be created. Interactions on this repository have been restricted to prior contributors only.',
    ),
  ).toBeInTheDocument()
})

test('displays issues disabled error', async () => {
  mockCreateIssueWithError('Issues has been disabled in this repository')

  const {user} = render(
    <CreateIssueFormWrapper
      environment={environment}
      repository={mockRepository}
      title="cool title"
      setTitle={noop}
      body=""
      setBody={noop}
      clearOnCreate={noop}
      onCreateSuccess={noop}
      onCreateError={noop}
      onCancel={noop}
      optionConfigOverrides={{insidePortal: true}}
    >
      <CreateButtonComponent />
    </CreateIssueFormWrapper>,
  )

  await user.click(screen.getByText('Mock create'))

  expect(screen.getByText('Issues has been disabled in this repository')).toBeInTheDocument()
})

test('displays new user restriction error', async () => {
  mockCreateIssueWithError('could not be created. Interactions on this repository have been restricted from new users.')

  const {user} = render(
    <CreateIssueFormWrapper
      environment={environment}
      repository={mockRepository}
      title="cool title"
      setTitle={noop}
      body=""
      setBody={noop}
      clearOnCreate={noop}
      onCreateSuccess={noop}
      onCreateError={noop}
      onCancel={noop}
      optionConfigOverrides={{insidePortal: true}}
    >
      <CreateButtonComponent />
    </CreateIssueFormWrapper>,
  )

  await user.click(screen.getByText('Mock create'))

  expect(
    screen.getByText('Could not be created. Interactions on this repository have been restricted from new users.'),
  ).toBeInTheDocument()
})

test('displays fallback error message when error message is empty or undefined', async () => {
  mockCreateIssueWithError('')

  const {user} = render(
    <CreateIssueFormWrapper
      environment={environment}
      repository={mockRepository}
      title="cool title"
      setTitle={noop}
      body=""
      setBody={noop}
      clearOnCreate={noop}
      onCreateSuccess={noop}
      onCreateError={noop}
      onCancel={noop}
      optionConfigOverrides={{insidePortal: true}}
    >
      <CreateButtonComponent />
    </CreateIssueFormWrapper>,
  )

  await user.click(screen.getByText('Mock create'))

  expect(screen.getByText('Unable to create issue.')).toBeInTheDocument()

  mockCreateIssueWithError(undefined)

  await user.click(screen.getByText('Mock create'))

  expect(screen.getByText('Unable to create issue.')).toBeInTheDocument()
})

describe('Copilot prompt footer', () => {
  const testMatrix = new Array<{
    name: string
    buttonVisibile: boolean
    template: IssueCreatePayload | undefined
    repoVisibility: RepositoryVisibility
    viewerCanPush: boolean
    copilotShowFunctionality: boolean
  }>(
    {
      name: 'Renders button when no template',
      buttonVisibile: true,
      template: undefined,
      repoVisibility: 'PUBLIC',
      viewerCanPush: true,
      copilotShowFunctionality: true,
    },
    {
      name: 'Renders button when blankslate template',
      buttonVisibile: true,
      template: buildMockTemplate({kind: IssueCreationKind.BlankIssue}),
      repoVisibility: 'PUBLIC',
      viewerCanPush: true,
      copilotShowFunctionality: true,
    },
    {
      name: 'Does not render if template is used',
      buttonVisibile: false,
      template: buildMockTemplate(),
      repoVisibility: 'PRIVATE',
      viewerCanPush: true,
      copilotShowFunctionality: true,
    },
    {
      name: 'Renders button when repo is private',
      buttonVisibile: true,
      template: undefined,
      repoVisibility: 'PRIVATE',
      viewerCanPush: false,
      copilotShowFunctionality: true,
    },
    {
      name: 'Renders button when repo is internal',
      buttonVisibile: true,
      template: undefined,
      repoVisibility: 'INTERNAL',
      viewerCanPush: false,
      copilotShowFunctionality: true,
    },
    {
      name: 'Renders if repo is public and viewer can push',
      buttonVisibile: true,
      template: undefined,
      repoVisibility: 'PUBLIC',
      viewerCanPush: true,
      copilotShowFunctionality: true,
    },
    {
      name: 'Does not render if repo is public and viewer cannot push',
      buttonVisibile: false,
      template: undefined,
      repoVisibility: 'PUBLIC',
      viewerCanPush: false,
      copilotShowFunctionality: true,
    },
    {
      name: 'Does not render if user has disabled Copilot',
      buttonVisibile: true,
      template: undefined,
      repoVisibility: 'PRIVATE',
      viewerCanPush: true,
      copilotShowFunctionality: false,
    },
  )

  test.each(testMatrix)('$name', async scenario => {
    mockIsFeatureEnabled.mockReturnValue(true)

    render(
      <CreateIssueFormWrapper
        environment={environment}
        repository={{...mockRepository, viewerCanPush: scenario.viewerCanPush, visibility: scenario.repoVisibility}}
        selectedTemplate={scenario.template}
        title="title"
        optionConfigOverrides={{insidePortal: false, copilotShowFunctionality: true}}
        setTitle={noop}
        body="body"
        setBody={noop}
        clearOnCreate={noop}
        onCreateSuccess={noop}
        onCreateError={noop}
        onCancel={noop}
      />,
    )

    const button = screen.queryByRole('button', {name: LABELS.copilotCTAButton})
    expect(button instanceof HTMLElement).toBe(scenario.buttonVisibile)
  })

  test('Does not render if feature flag is disabled', async () => {
    mockIsFeatureEnabled.mockReturnValue(false)

    render(
      <CreateIssueFormWrapper
        environment={environment}
        repository={{...mockRepository, viewerCanPush: true}}
        title="title"
        optionConfigOverrides={{insidePortal: false, copilotShowFunctionality: true}}
        setTitle={noop}
        body="body"
        setBody={noop}
        clearOnCreate={noop}
        onCreateSuccess={noop}
        onCreateError={noop}
        onCancel={noop}
      />,
    )

    expect(screen.queryByRole('button', {name: LABELS.copilotCTAButton})).not.toBeInTheDocument()
  })

  test('Button triggers dialog if draft has title', async () => {
    mockIsFeatureEnabled.mockReturnValue(true)

    const {user} = render(
      <CreateIssueFormWrapper
        environment={environment}
        repository={{...mockRepository, viewerCanPush: true}}
        title="title"
        optionConfigOverrides={{insidePortal: false, copilotShowFunctionality: true}}
        setTitle={noop}
        body=""
        setBody={noop}
        clearOnCreate={noop}
        onCreateSuccess={noop}
        onCreateError={noop}
        onCancel={noop}
      />,
    )

    const copilotPromptButton = screen.getByRole('button', {name: LABELS.copilotCTAButton})
    await user.click(copilotPromptButton)

    const dialogConfirmButton = screen.getByRole('button', {name: LABELS.copilotCTADialogContinueButton})
    await user.click(dialogConfirmButton)

    expect(navigateFn).toHaveBeenCalledWith('/copilot?prompt=Create an issue in github/issues to')
    expect(sendAnalyticsEventMock).toHaveBeenCalledTimes(1)
    expect(sendAnalyticsEventMock).toHaveBeenCalledWith(
      'analytics.click',
      'ISSUE_CREATE_NEW_ISSUE_WITH_COPILOT_BUTTON',
      {
        repoNWO: 'github/issues',
      },
    )
  })

  test('Button triggers dialog if draft has body', async () => {
    mockIsFeatureEnabled.mockReturnValue(true)

    const {user} = render(
      <CreateIssueFormWrapper
        environment={environment}
        repository={{...mockRepository, viewerCanPush: true}}
        title=""
        optionConfigOverrides={{insidePortal: false, copilotShowFunctionality: true}}
        setTitle={noop}
        body="body"
        setBody={noop}
        clearOnCreate={noop}
        onCreateSuccess={noop}
        onCreateError={noop}
        onCancel={noop}
      />,
    )

    const copilotPromptButton = screen.getByRole('button', {name: LABELS.copilotCTAButton})
    await user.click(copilotPromptButton)

    const dialogConfirmButton = screen.getByRole('button', {name: LABELS.copilotCTADialogContinueButton})
    await user.click(dialogConfirmButton)

    expect(navigateFn).toHaveBeenCalledWith('/copilot?prompt=Create an issue in github/issues to')
    expect(sendAnalyticsEventMock).toHaveBeenCalledTimes(1)
    expect(sendAnalyticsEventMock).toHaveBeenCalledWith(
      'analytics.click',
      'ISSUE_CREATE_NEW_ISSUE_WITH_COPILOT_BUTTON',
      {
        repoNWO: 'github/issues',
      },
    )
  })

  test('Button navigates straight to Copilot if draft is blank', async () => {
    mockIsFeatureEnabled.mockReturnValue(true)

    const {user} = render(
      <CreateIssueFormWrapper
        environment={environment}
        repository={{...mockRepository, viewerCanPush: true}}
        title=""
        optionConfigOverrides={{insidePortal: false, copilotShowFunctionality: true}}
        setTitle={noop}
        body=""
        setBody={noop}
        clearOnCreate={noop}
        onCreateSuccess={noop}
        onCreateError={noop}
        onCancel={noop}
      />,
    )

    const copilotPromptButton = screen.getByRole('button', {name: LABELS.copilotCTAButton})
    await user.click(copilotPromptButton)

    expect(navigateFn).toHaveBeenCalledWith('/copilot?prompt=Create an issue in github/issues to')
    expect(sendAnalyticsEventMock).toHaveBeenCalledTimes(1)
    expect(sendAnalyticsEventMock).toHaveBeenCalledWith(
      'analytics.click',
      'ISSUE_CREATE_NEW_ISSUE_WITH_COPILOT_BUTTON',
      {
        repoNWO: 'github/issues',
      },
    )
  })
})

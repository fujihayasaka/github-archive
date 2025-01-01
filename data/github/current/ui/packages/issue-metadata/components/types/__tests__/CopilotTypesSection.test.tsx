import {commitUpdateIssueIssueTypeMutation} from '@github-ui/item-picker/commitUpdateIssueIssueTypeMutation'
import {render, setupUserEvent} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {RelayEnvironmentProvider} from 'react-relay/hooks'
import {createMockEnvironment} from 'relay-test-utils'
import {useCopilot} from '../../../utils/useCopilot'
import {CopilotTypesSection} from '../CopilotTypesSection'

const userEvent = setupUserEvent()

jest.mock('./../../../utils/useCopilot')
jest.mock('@github-ui/item-picker/commitUpdateIssueIssueTypeMutation')

describe('CopilotTypesSection', () => {
  const environment = createMockEnvironment()
  const mockOnIssueUpdate = jest.fn()
  const mockSetShouldCopilotComponent = jest.fn()

  const renderComponent = (props = {}) => {
    return render(
      <RelayEnvironmentProvider environment={environment}>
        <CopilotTypesSection
          issueId="test-issue-id"
          setShouldShowCopilotComponent={mockSetShouldCopilotComponent}
          onIssueUpdate={mockOnIssueUpdate}
          sectionHeader={<div>Test Section Header</div>}
          {...props}
        />
      </RelayEnvironmentProvider>,
    )
  }

  it('renders loading state initially', () => {
    jest.mocked(useCopilot).mockReturnValue({
      getSuggestions: jest.fn(),
      getStatusForType: jest.fn().mockReturnValue('loading'),
      getTypeSuggestion: jest.fn(),
      getLabelSuggestions: jest.fn(),
      typeStatus: 'loading',
      labelsStatus: 'loading',
      suggestedLabels: [],
      suggestedType: undefined,
    })
    renderComponent()
    expect(screen.getByText(/Copilot is thinking …/i)).toBeInTheDocument()
  })

  it('makes a request to fetch the suggested type on mount', () => {
    const getSuggestions = jest.fn()
    jest.mocked(useCopilot).mockReturnValue({
      getSuggestions,
      getStatusForType: jest.fn().mockReturnValue('loading'),
      getTypeSuggestion: jest.fn(),
      getLabelSuggestions: jest.fn(),
      typeStatus: 'loading',
      labelsStatus: 'loading',
      suggestedLabels: [],
      suggestedType: undefined,
    })
    renderComponent()
    expect(getSuggestions).toHaveBeenCalledTimes(1)
    expect(getSuggestions).toHaveBeenCalledWith({issueId: 'test-issue-id', environment, type: 'issueType'})
  })

  it('renders suggested type and confirm/cancel button after successfully fetching the suggested type', () => {
    jest.mocked(useCopilot).mockReturnValue({
      getSuggestions: jest.fn(),
      getStatusForType: jest.fn().mockReturnValue('success'),
      getTypeSuggestion: jest.fn(),
      getLabelSuggestions: jest.fn(),
      typeStatus: 'success',
      labelsStatus: 'loading',
      suggestedLabels: [],
      suggestedType: {
        color: 'RED',
        description: 'description',
        id: '1',
        isEnabled: true,
        name: 'Bug',
        ' $fragmentType': 'IssueTypePickerIssueType',
      },
    })
    renderComponent()
    expect(screen.queryByText(/Copilot is thinking.../i)).not.toBeInTheDocument()
    expect(screen.getByText(/Bug/i)).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Accept suggestion'})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Dismiss suggestion'})).toBeInTheDocument()
  })

  it('renders error state if failed to fetch suggested type', () => {
    jest.mocked(useCopilot).mockReturnValue({
      getSuggestions: jest.fn(),
      getStatusForType: jest.fn().mockReturnValue('error'),
      getTypeSuggestion: jest.fn(),
      getLabelSuggestions: jest.fn(),
      typeStatus: 'error',
      labelsStatus: 'loading',
      suggestedLabels: [],
      suggestedType: undefined,
    })
    renderComponent()
    expect(screen.queryByText(/Copilot is thinking.../i)).not.toBeInTheDocument()
    expect(screen.getByText(/Error. Please try again./i)).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Retry'})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Dismiss'})).toBeInTheDocument()
  })

  it('calls getSuggestions with issueId and type on retry', async () => {
    const getSuggestions = jest.fn()
    jest.mocked(useCopilot).mockReturnValue({
      getSuggestions,
      getStatusForType: jest.fn().mockReturnValue('error'),
      getTypeSuggestion: jest.fn(),
      getLabelSuggestions: jest.fn(),
      typeStatus: 'error',
      labelsStatus: 'loading',
      suggestedLabels: [],
      suggestedType: undefined,
    })

    renderComponent()
    expect(screen.getByRole('button', {name: 'Retry'})).toBeInTheDocument()

    const retryButton = screen.getByRole('button', {name: 'Retry'})
    await userEvent.click(retryButton)
    // first call is made after the component mounts
    expect(getSuggestions).toHaveBeenCalledTimes(2)
    expect(getSuggestions).toHaveBeenCalledWith({issueId: 'test-issue-id', environment, type: 'issueType'})
  })

  it('calls setShouldShowCopilotComponent to hide the component when rejecting suggestions', async () => {
    jest.mocked(useCopilot).mockReturnValue({
      getSuggestions: jest.fn(),
      getStatusForType: jest.fn().mockReturnValue('error'),
      getTypeSuggestion: jest.fn(),
      getLabelSuggestions: jest.fn(),
      typeStatus: 'error',
      labelsStatus: 'loading',
      suggestedLabels: [],
      suggestedType: {
        color: 'RED',
        description: 'description',
        id: '1',
        isEnabled: true,
        name: 'Bug',
        ' $fragmentType': 'IssueTypePickerIssueType',
      },
    })
    renderComponent()
    const cancelButton = screen.getByRole('button', {name: 'Dismiss'})
    await userEvent.click(cancelButton)
    expect(mockSetShouldCopilotComponent).toHaveBeenCalledTimes(1)
    expect(mockSetShouldCopilotComponent).toHaveBeenCalledWith(false)
  })

  it('calls setShouldShowCopilotComponent to hide the component when no type is returned', () => {
    mockSetShouldCopilotComponent.mockReset()

    jest.mocked(useCopilot).mockReturnValue({
      getSuggestions: jest.fn(),
      getStatusForType: jest.fn().mockReturnValue('success'),
      getTypeSuggestion: jest.fn(),
      getLabelSuggestions: jest.fn(),
      typeStatus: 'success',
      labelsStatus: 'loading',
      suggestedLabels: [],
      suggestedType: undefined,
    })
    renderComponent()
    const cancelButton = screen.queryByRole('button', {name: 'Dismiss suggestion'})
    expect(cancelButton).not.toBeInTheDocument()
    expect(mockSetShouldCopilotComponent).toHaveBeenCalledWith(false)
  })

  it('calls commitUpdateIssueIssueTypeMutation after confirming', async () => {
    const mockedUpdateIssueIssueTypeMutation = jest.mocked(commitUpdateIssueIssueTypeMutation)
    jest.mocked(useCopilot).mockReturnValue({
      getSuggestions: jest.fn(),
      getStatusForType: jest.fn().mockReturnValue('success'),
      getTypeSuggestion: jest.fn(),
      getLabelSuggestions: jest.fn(),
      typeStatus: 'success',
      labelsStatus: 'loading',
      suggestedLabels: [],
      suggestedType: {
        color: 'RED',
        description: 'description',
        id: '1',
        isEnabled: true,
        name: 'Bug',
        ' $fragmentType': 'IssueTypePickerIssueType',
      },
    })

    renderComponent()

    const confirmButton = screen.getByRole('button', {name: 'Accept suggestion'})
    await userEvent.click(confirmButton)

    expect(mockedUpdateIssueIssueTypeMutation).toHaveBeenCalledTimes(1)
  })
})

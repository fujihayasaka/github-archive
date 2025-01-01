import {render, screen} from '@testing-library/react'
import {RelayEnvironmentProvider} from 'react-relay/hooks'
import {createMockEnvironment} from 'relay-test-utils'
import {CopilotTypesSection} from '../CopilotTypesSection'
// eslint-disable-next-line unused-imports/no-unused-imports
import React from 'react'
import {useCopilot} from '../../../utils/useCopilot'
import {commitUpdateIssueIssueTypeMutation} from '@github-ui/item-picker/commitUpdateIssueIssueTypeMutation'

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
          nameWithOwner="test/repo"
          {...props}
        />
      </RelayEnvironmentProvider>,
    )
  }

  it('renders loading state initially', () => {
    jest.mocked(useCopilot).mockReturnValue({
      fetchSuggestions: jest.fn(),
      copilotRequestSuccess: 'loading',
      copilotLabels: [],
      copilotType: undefined,
    })
    renderComponent()
    expect(screen.getByText(/Copilot is thinking.../i)).toBeInTheDocument()
  })

  it('makes a request to fetch the suggested type on mount', () => {
    const fetchSuggestions = jest.fn()
    jest.mocked(useCopilot).mockReturnValue({
      fetchSuggestions,
      copilotRequestSuccess: 'loading',
      copilotLabels: [],
      copilotType: undefined,
    })
    renderComponent()
    expect(fetchSuggestions).toHaveBeenCalledTimes(1)
    expect(fetchSuggestions).toHaveBeenCalledWith({issueId: 'test-issue-id', environment, type: 'issueType'})
  })

  it('renders suggested type and confirm/cancel button after successfully fetching the suggested type', () => {
    jest.mocked(useCopilot).mockReturnValue({
      fetchSuggestions: jest.fn(),
      copilotRequestSuccess: 'success',
      copilotLabels: [],
      copilotType: {
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
    expect(screen.getByRole('button', {name: 'Confirm'})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Cancel'})).toBeInTheDocument()
  })

  it('renders error state if failed to fetch suggested type', () => {
    jest.mocked(useCopilot).mockReturnValue({
      fetchSuggestions: jest.fn(),
      copilotRequestSuccess: 'error',
      copilotLabels: [],
      copilotType: undefined,
    })
    renderComponent()
    expect(screen.queryByText(/Copilot is thinking.../i)).not.toBeInTheDocument()
    expect(screen.getByText(/Error. Please try again./i)).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Retry'})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Cancel'})).toBeInTheDocument()
  })

  it('calls fetchSuggestions with issueId and type on retry', async () => {
    const fetchSuggestions = jest.fn()
    jest.mocked(useCopilot).mockReturnValue({
      fetchSuggestions,
      copilotRequestSuccess: 'error',
      copilotLabels: [],
      copilotType: undefined,
    })

    renderComponent()
    expect(screen.getByRole('button', {name: 'Retry'})).toBeInTheDocument()

    const retryButton = screen.getByRole('button', {name: 'Retry'})
    retryButton.click()

    // first call is made after the component mounts
    expect(fetchSuggestions).toHaveBeenCalledTimes(2)
    expect(fetchSuggestions).toHaveBeenCalledWith({issueId: 'test-issue-id', environment, type: 'issueType'})
  })

  it('calls setShouldShowCopilotComponent to hide the component when rejecting suggestions', () => {
    jest.mocked(useCopilot).mockReturnValue({
      fetchSuggestions: jest.fn(),
      copilotRequestSuccess: 'success',
      copilotLabels: [],
      copilotType: undefined,
    })
    renderComponent()
    const cancelButton = screen.getByRole('button', {name: 'Cancel'})
    cancelButton.click()
    expect(mockSetShouldCopilotComponent).toHaveBeenCalledTimes(1)
    expect(mockSetShouldCopilotComponent).toHaveBeenCalledWith(false)
  })

  it('calls commitUpdateIssueIssueTypeMutation after confirming', async () => {
    const mockedUpdateIssueIssueTypeMutation = jest.mocked(commitUpdateIssueIssueTypeMutation)
    jest.mocked(useCopilot).mockReturnValue({
      fetchSuggestions: jest.fn(),
      copilotRequestSuccess: 'success',
      copilotLabels: [],
      copilotType: {
        color: 'RED',
        description: 'description',
        id: '1',
        isEnabled: true,
        name: 'Bug',
        ' $fragmentType': 'IssueTypePickerIssueType',
      },
    })

    renderComponent()

    const confirmButton = screen.getByRole('button', {name: 'Confirm'})
    confirmButton.click()

    expect(mockedUpdateIssueIssueTypeMutation).toHaveBeenCalledTimes(1)
  })
})

import {render, screen} from '@testing-library/react'
import {RelayEnvironmentProvider} from 'react-relay/hooks'
import {createMockEnvironment} from 'relay-test-utils'
import {CopilotLabelsSection} from '../CopilotLabelsSection'
// eslint-disable-next-line unused-imports/no-unused-imports
import React from 'react'
import {useCopilot} from '../../../utils/useCopilot'
import {commitSetLabelsForLabelableMutation} from '@github-ui/item-picker/commitSetLabelsForLabelableMutation'

jest.mock('../../../utils/useCopilot')
jest.mock('@github-ui/item-picker/commitSetLabelsForLabelableMutation')

describe('CopilotLabelsSection', () => {
  const environment = createMockEnvironment()
  const mockOnIssueUpdate = jest.fn()
  const mockSetShouldCopilotComponent = jest.fn()

  const renderComponent = (props = {}) => {
    return render(
      <RelayEnvironmentProvider environment={environment}>
        <CopilotLabelsSection
          issueId="test-issue-id"
          setShouldShowCopilotComponent={mockSetShouldCopilotComponent}
          onIssueUpdate={mockOnIssueUpdate}
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

  it('makes a request to fetch the suggested labels on mount', () => {
    const fetchSuggestions = jest.fn()
    jest.mocked(useCopilot).mockReturnValue({
      fetchSuggestions,
      copilotRequestSuccess: 'loading',
      copilotLabels: [],
      copilotType: undefined,
    })
    renderComponent()
    expect(fetchSuggestions).toHaveBeenCalledTimes(1)
    expect(fetchSuggestions).toHaveBeenCalledWith({issueId: 'test-issue-id', environment, type: 'labels'})
  })

  it('renders suggested labels and confirm/cancel button after successfully fetching the suggested labels', () => {
    jest.mocked(useCopilot).mockReturnValue({
      fetchSuggestions: jest.fn(),
      copilotRequestSuccess: 'success',
      copilotLabels: [
        {
          id: '1',
          name: 'Bug',
          color: '000000',
          description: 'description',
          nameHTML: 'Bug',
          url: '/test/repo/labels/bug',
          ' $fragmentType': 'LabelPickerLabel',
        },
        {
          id: '2',
          name: 'Feature',
          color: '000000',
          description: 'description',
          nameHTML: 'Feature',
          url: '/test/repo/labels/feature',
          ' $fragmentType': 'LabelPickerLabel',
        },
      ],
      copilotType: undefined,
    })
    renderComponent()
    expect(screen.getByText('Bug')).toBeInTheDocument()
    expect(screen.getByText('Feature')).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Confirm'})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Cancel'})).toBeInTheDocument()
  })

  it('renders error state if failed to fetch suggested labels', () => {
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

  it('calls fetchSuggestions with issueId and type on retry', () => {
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

    expect(fetchSuggestions).toHaveBeenCalledTimes(2)
    expect(fetchSuggestions).toHaveBeenCalledWith({issueId: 'test-issue-id', environment, type: 'labels'})
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
    const mockCommitSetLabelsForLabelableMutation = jest.mocked(commitSetLabelsForLabelableMutation)
    jest.mocked(useCopilot).mockReturnValue({
      fetchSuggestions: jest.fn(),
      copilotRequestSuccess: 'success',
      copilotLabels: [
        {
          id: '1',
          name: 'Bug',
          color: '000000',
          description: 'description',
          nameHTML: 'Bug',
          url: '/test/repo/labels/bug',
          ' $fragmentType': 'LabelPickerLabel',
        },
      ],
      copilotType: undefined,
    })

    renderComponent()

    const confirmButton = screen.getByRole('button', {name: 'Confirm'})
    confirmButton.click()

    expect(mockCommitSetLabelsForLabelableMutation).toHaveBeenCalledTimes(1)
    expect(mockCommitSetLabelsForLabelableMutation).toHaveBeenCalledWith(
      expect.objectContaining({
        environment,
        input: {
          labelableId: 'test-issue-id',
          labelableTypeName: 'Issue',
          labels: [
            {
              id: '1',
              name: 'Bug',
              color: '000000',
              description: 'description',
              nameHTML: 'Bug',
              url: '/test/repo/labels/bug',
              ' $fragmentType': 'LabelPickerLabel',
            },
          ],
        },
      }),
    )
  })
})

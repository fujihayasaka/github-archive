import {render, setupUserEvent} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {RelayEnvironmentProvider} from 'react-relay/hooks'
import {createMockEnvironment} from 'relay-test-utils'
import {useCopilot} from '../../../utils/useCopilot'
import {CopilotLabelsSection} from '../CopilotLabelsSection'

const userEvent = setupUserEvent()

jest.mock('../../../utils/useCopilot')

describe('CopilotLabelsSection', () => {
  beforeEach(() => {
    jest.clearAllMocks()
  })

  const environment = createMockEnvironment()
  const mockSetShouldShowCopilotComponent = jest.fn()
  const mockOnConfirmLabels = jest.fn()
  const mockOnErrorRetry = jest.fn()

  const renderComponent = (props = {}) => {
    return render(
      <RelayEnvironmentProvider environment={environment}>
        <CopilotLabelsSection
          issueBody="test issue body"
          issueTitle="test issue title"
          issueId="test-issue-id"
          repositoryName="test-repo"
          repositoryOwner="test-owner"
          suggestedLabels={[]}
          labelsStatus="loading"
          onConfirmLabels={mockOnConfirmLabels}
          onErrorRetry={mockOnErrorRetry}
          setShouldShowCopilotComponent={mockSetShouldShowCopilotComponent}
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

    // Use a custom matcher because text might be split across nodes
    expect(screen.getByText('Copilot is thinking …')).toBeInTheDocument()
  })

  it('renders suggested labels and confirm/cancel button after successfully fetching the suggested labels', () => {
    jest.mocked(useCopilot).mockReturnValue({
      getSuggestions: jest.fn(),
      getStatusForType: jest.fn().mockReturnValue('success'),
      getTypeSuggestion: jest.fn(),
      getLabelSuggestions: jest.fn(),
      typeStatus: 'loading',
      labelsStatus: 'success',
      suggestedLabels: [
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
      suggestedType: undefined,
    })
    renderComponent({
      labelsStatus: 'success',
      suggestedLabels: [
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
    })

    expect(screen.getByText('Bug')).toBeInTheDocument()
    expect(screen.getByText('Feature')).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Accept suggestions'})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Dismiss suggestions'})).toBeInTheDocument()
  })

  it('renders suggested labels and calls onConfirmLabels when confirming them', async () => {
    jest.mocked(useCopilot).mockReturnValue({
      getSuggestions: jest.fn(),
      getStatusForType: jest.fn().mockReturnValue('success'),
      getTypeSuggestion: jest.fn(),
      getLabelSuggestions: jest.fn(),
      typeStatus: 'loading',
      labelsStatus: 'success',
      suggestedLabels: [
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
      suggestedType: undefined,
    })
    renderComponent({
      labelsStatus: 'success',
      suggestedLabels: [
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
    })

    expect(screen.getByText('Bug')).toBeInTheDocument()
    expect(screen.getByText('Feature')).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Dismiss Bug'})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Dismiss Feature'})).toBeInTheDocument()

    expect(screen.getByRole('button', {name: 'Accept suggestions'})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Dismiss suggestions'})).toBeInTheDocument()

    const confirmButton = screen.getByRole('button', {name: 'Accept suggestions'})
    await userEvent.click(confirmButton)

    expect(mockOnConfirmLabels).toHaveBeenCalledTimes(1)
    expect(mockOnConfirmLabels).toHaveBeenCalledWith([
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
    ])
  })

  it('renders suggested labels that can be dismissed individually and applies only non-dismissed ones', async () => {
    jest.mocked(useCopilot).mockReturnValue({
      getSuggestions: jest.fn(),
      getStatusForType: jest.fn().mockReturnValue('success'),
      getTypeSuggestion: jest.fn(),
      getLabelSuggestions: jest.fn(),
      typeStatus: 'loading',
      labelsStatus: 'success',
      suggestedLabels: [
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
      suggestedType: undefined,
    })
    renderComponent({
      labelsStatus: 'success',
      suggestedLabels: [
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
    })

    expect(screen.getByText('Bug')).toBeInTheDocument()
    expect(screen.getByText('Feature')).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Dismiss Bug'})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Dismiss Feature'})).toBeInTheDocument()

    const dismissBugButton = screen.getByRole('button', {name: 'Dismiss Bug'})
    await userEvent.click(dismissBugButton)

    expect(screen.getByRole('button', {name: 'Accept suggestions'})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Dismiss suggestions'})).toBeInTheDocument()

    const confirmButton = screen.getByRole('button', {name: 'Accept suggestions'})
    await userEvent.click(confirmButton)

    expect(mockOnConfirmLabels).toHaveBeenCalledTimes(1)
    expect(mockOnConfirmLabels).toHaveBeenCalledWith([
      {
        id: '2',
        name: 'Feature',
        color: '000000',
        description: 'description',
        nameHTML: 'Feature',
        url: '/test/repo/labels/feature',
        ' $fragmentType': 'LabelPickerLabel',
      },
    ])
  })

  it('calls setShouldShowCopilotComponent to hide the component if all labels are dismissed', async () => {
    jest.mocked(useCopilot).mockReturnValue({
      getSuggestions: jest.fn(),
      getStatusForType: jest.fn().mockReturnValue('success'),
      getTypeSuggestion: jest.fn(),
      getLabelSuggestions: jest.fn(),
      typeStatus: 'loading',
      labelsStatus: 'success',
      suggestedLabels: [
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
      suggestedType: undefined,
    })
    renderComponent({
      labelsStatus: 'success',
      suggestedLabels: [
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
    })

    expect(screen.getByText('Bug')).toBeInTheDocument()
    expect(screen.getByText('Feature')).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Dismiss Bug'})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Dismiss Feature'})).toBeInTheDocument()

    const dismissBugButton = screen.getByRole('button', {name: 'Dismiss Bug'})
    await userEvent.click(dismissBugButton)

    const dismissFeatureButton = screen.getByRole('button', {name: 'Dismiss Feature'})
    await userEvent.click(dismissFeatureButton)

    expect(mockSetShouldShowCopilotComponent).toHaveBeenCalledTimes(1)
    expect(mockSetShouldShowCopilotComponent).toHaveBeenCalledWith(false)
  })

  it('renders error state if failed to fetch suggested labels', () => {
    jest.mocked(useCopilot).mockReturnValue({
      getSuggestions: jest.fn(),
      getStatusForType: jest.fn().mockReturnValue('error'),
      getTypeSuggestion: jest.fn(),
      getLabelSuggestions: jest.fn(),
      typeStatus: 'loading',
      labelsStatus: 'error',
      suggestedLabels: [],
      suggestedType: undefined,
    })
    renderComponent({labelsStatus: 'error'})
    expect(screen.queryByText(/Copilot is thinking.../i)).not.toBeInTheDocument()
    expect(screen.getByText(/Error. Please try again./i)).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Retry'})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Dismiss'})).toBeInTheDocument()
  })

  it('calls onErrorRetry when retry button is clicked', async () => {
    jest.mocked(useCopilot).mockReturnValue({
      getSuggestions: jest.fn(),
      getStatusForType: jest.fn().mockReturnValue('error'),
      getTypeSuggestion: jest.fn(),
      getLabelSuggestions: jest.fn(),
      typeStatus: 'loading',
      labelsStatus: 'error',
      suggestedLabels: [],
      suggestedType: undefined,
    })

    renderComponent({labelsStatus: 'error'})

    const retryButton = screen.getByRole('button', {name: 'Retry'})
    await userEvent.click(retryButton)

    expect(mockOnErrorRetry).toHaveBeenCalledTimes(1)
  })

  it('calls setShouldShowCopilotComponent to hide the component when rejecting suggestions', async () => {
    jest.mocked(useCopilot).mockReturnValue({
      getSuggestions: jest.fn(),
      getStatusForType: jest.fn().mockReturnValue('success'),
      getTypeSuggestion: jest.fn(),
      getLabelSuggestions: jest.fn(),
      typeStatus: 'loading',
      labelsStatus: 'success',
      suggestedLabels: [
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
      suggestedType: undefined,
    })
    renderComponent({
      labelsStatus: 'success',
      suggestedLabels: [
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
    })
    const cancelButton = screen.getByRole('button', {name: 'Dismiss suggestions'})
    await userEvent.click(cancelButton)
    expect(mockSetShouldShowCopilotComponent).toHaveBeenCalledTimes(1)
    expect(mockSetShouldShowCopilotComponent).toHaveBeenCalledWith(false)
  })

  it('calls setShouldShowCopilotComponent to hide the component when copilotLabels is empty', () => {
    mockSetShouldShowCopilotComponent.mockReset()

    jest.mocked(useCopilot).mockReturnValue({
      getSuggestions: jest.fn(),
      getStatusForType: jest.fn().mockReturnValue('success'),
      getTypeSuggestion: jest.fn(),
      getLabelSuggestions: jest.fn(),
      typeStatus: 'loading',
      labelsStatus: 'success',
      suggestedLabels: [],
      suggestedType: undefined,
    })
    renderComponent({labelsStatus: 'success'})
    const cancelButton = screen.queryByRole('button', {name: 'Dismiss suggestions'})
    expect(cancelButton).not.toBeInTheDocument()
    expect(mockSetShouldShowCopilotComponent).toHaveBeenCalledWith(false)
  })
})

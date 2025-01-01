import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'

import {useWorkbenchContext} from '../../contexts/WorkbenchContext'
import Suggestions from '../Suggestions'

jest.mock('../../contexts/WorkbenchContext', () => ({
  useWorkbenchContext: jest.fn(),
}))

const mockUseWorkbenchContext = useWorkbenchContext as jest.Mock

jest.mock('../../contexts/EditorContext', () => ({
  useEditorContext: () => ({
    forceEditorRefresh: jest.fn(),
  }),
}))

jest.mock('../../contexts/WorkbenchUIContext', () => ({
  useWorkbenchUI: () => ({}),
}))

describe('Suggestions Component', () => {
  const mockProps = {
    suggestions: ['Use const instead of let', 'Add return type'],
    errors: [
      {
        source: 'preview-build' as const,
        messageRaw: 'Missing semicolon',
        messagePretty: 'Missing semicolon',
        attached: false,
      },
      {
        source: 'preview-build' as const,
        messageRaw: 'Unused variable',
        messagePretty: 'Unused variable',
        attached: true,
      },
    ],
    onSelectSuggestion: jest.fn(),
    attachAll: jest.fn(),
    attachToggle: jest.fn(),
    fixAll: jest.fn(),
    isFetching: false,
    dismissError: jest.fn(),
    workbenchId: '12345',
    userExpandedSuggestions: true,
    setUserExpandedSuggestions: jest.fn(),
  }

  beforeEach(() => {
    jest.clearAllMocks()

    mockUseWorkbenchContext.mockReturnValue({})
  })

  test('renders correctly with suggestions', () => {
    render(<Suggestions {...mockProps} />)

    // Check header text
    expect(screen.getByText('2 Errors')).toBeInTheDocument()

    // Check if suggestions are not rendered when there are errors
    expect(screen.queryByText('Use const instead of let')).not.toBeInTheDocument()
  })

  test('renders suggestions when no errors are present', () => {
    render(<Suggestions {...mockProps} errors={[]} />)

    expect(screen.getByText('Suggestions')).toBeInTheDocument()
    expect(screen.getByText('Use const instead of let')).toBeInTheDocument()
    expect(screen.getByText('Add return type')).toBeInTheDocument()
  })

  test('calls onSelectSuggestion when suggestion is clicked', async () => {
    const {user} = render(<Suggestions {...mockProps} errors={[]} />)

    const suggestion = screen.getByText('Use const instead of let')
    await user.click(suggestion)

    expect(mockProps.onSelectSuggestion).toHaveBeenCalledWith('Use const instead of let')
  })

  test('handles keyboard navigation on suggestions', async () => {
    const {user} = render(<Suggestions {...mockProps} errors={[]} />)

    const suggestion = screen.getByText('Use const instead of let')
    await user.type(suggestion, '{Enter}')

    expect(mockProps.onSelectSuggestion).toHaveBeenCalledWith('Use const instead of let')
  })

  test('toggles expansion when chevron is clicked', async () => {
    const {user} = render(<Suggestions {...mockProps} />)

    const expandButton = screen.getByLabelText('Hide errors')
    await user.click(expandButton)

    // Button should have changed its aria-label
    expect(screen.getByLabelText('Show errors')).toBeInTheDocument()
  })

  test('calls fixAll when Fix all button is clicked', async () => {
    const {user} = render(<Suggestions {...mockProps} />)

    const fixAllButton = screen.getByText('Fix all')
    await user.click(fixAllButton)

    expect(mockProps.fixAll).toHaveBeenCalled()
  })

  test('calls attachAll when Attach button is clicked', async () => {
    const {user} = render(<Suggestions {...mockProps} />)

    const attachAllButton = screen.getByText('Attach')
    await user.click(attachAllButton)

    expect(mockProps.attachAll).toHaveBeenCalledWith(true)
  })

  test('does not show UI elements when fetching', () => {
    render(<Suggestions {...mockProps} isFetching />)

    // When fetching, errors should not be shown
    expect(screen.queryByText('Errors • 2')).not.toBeInTheDocument()
    expect(screen.getByText('Suggestions')).toBeInTheDocument()
  })
})

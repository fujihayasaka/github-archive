import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'

import {useDiffViewSettings} from '../../contexts/DiffViewSettingsContext'
import {useDismissNotice, useIsNoticeDismissed} from '../../hooks/use-user-notices'
import {DiffCompactLinesPopover} from '../DiffCompactLinesPopover'

// Mock the hooks
jest.mock('../../contexts/DiffViewSettingsContext')
jest.mock('../../hooks/use-user-notices')

describe('DiffCompactLinesPopover', () => {
  const mockUpdateLineSpacing = jest.fn()
  const mockDismissNotice = jest.fn()
  const mockUseDiffViewSettings = useDiffViewSettings as jest.Mock
  const mockUseDismissNotice = useDismissNotice as jest.Mock
  const mockUseIsNoticeDismissed = useIsNoticeDismissed as jest.Mock

  beforeEach(() => {
    mockUseDiffViewSettings.mockReturnValue({updateLineSpacing: mockUpdateLineSpacing})
    mockUseDismissNotice.mockReturnValue({dismissNotice: mockDismissNotice})
    mockUseIsNoticeDismissed.mockReturnValue(false)
  })

  afterEach(() => {
    jest.clearAllMocks()
  })

  it('renders the popover when the notice is not dismissed', () => {
    render(<DiffCompactLinesPopover />)
    expect(screen.getByText('Customizable line height')).toBeInTheDocument()
  })

  it('does not render the popover when the notice is dismissed', () => {
    mockUseIsNoticeDismissed.mockReturnValue(true)
    render(<DiffCompactLinesPopover />)
    expect(screen.queryByText('Customizable line height')).not.toBeInTheDocument()
  })

  it('calls updateLineSpacing and dismissNotice when "Enable compact line height" is clicked', async () => {
    const {user} = render(<DiffCompactLinesPopover />)
    await user.click(screen.getByText('Enable compact line height'))
    expect(mockUpdateLineSpacing).toHaveBeenCalledWith('compact')
    expect(mockDismissNotice).toHaveBeenCalled()
  })

  it('calls dismissNotice when "Dismiss" is clicked', async () => {
    const {user} = render(<DiffCompactLinesPopover />)
    await user.click(screen.getByText('Dismiss'))
    expect(mockDismissNotice).toHaveBeenCalled()
  })
})

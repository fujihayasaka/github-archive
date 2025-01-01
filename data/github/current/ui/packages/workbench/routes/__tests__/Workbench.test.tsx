import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {useState} from 'react'

import {useContentFilter} from '../../contexts/ContentFilterContext'
import type {useTargetedEditsContext} from '../../contexts/TargetedEditsContext'
// Import the component after all mocks are set up
import {Workbench} from '../Workbench'

// Mock the CommandTask enum directly
jest.mock('../../utilities/terminal-reducer', () => ({
  CommandTask: {
    Deploy: 'deploy',
  },
}))

// Mock all dependencies
jest.mock('@github-ui/copilot-auth-token', () => ({
  CopilotAuthTokenProvider: jest.fn().mockImplementation(() => ({})),
}))

jest.mock('@github-ui/react-core/use-route-payload', () => ({
  useRoutePayload: jest.fn().mockReturnValue({
    workbench: {id: 'test-id'},
    copilot: {ssoOrganizations: [], apiURL: 'test-url', currentTopic: 'test-topic'},
    isNewFilePage: false,
  }),
}))

// Mock the filtered content modal component
jest.mock('../../components/FilteredContentModal', () => ({
  FilteredContentModal: jest.fn(({onClose}) => (
    <div data-testid="filtered-content-modal">
      <button onClick={onClose} data-testid="close-filtered-modal">
        Close Modal
      </button>
    </div>
  )),
}))

// Mock all other child components
jest.mock('@github-ui/workspace-editor/components/Banner', () => ({
  Banner: () => <div>Banner Mock</div>,
}))

jest.mock('../../components/MainContent', () => ({
  MainContent: () => <div>Main Content Mock</div>,
}))

jest.mock('../../components/SidePanel/SidePanel', () => ({
  SidePanel: () => <div>Side Panel Mock</div>,
}))

jest.mock('../../components/TargetedEditsInput', () => ({
  TargetedEditsInput: () => <div>Targeted Edits Input Mock</div>,
}))

// Mock context providers
jest.mock('../../contexts/PublishingContext', () => ({
  PublishingProvider: ({children}: {children: React.ReactNode}) => <div>{children}</div>,
  usePublishingContext: () => ({}),
}))

jest.mock('../../contexts/WorkbenchUIContext', () => ({
  useWorkbenchUI: () => ({}),
}))

jest.mock('../../contexts/WorkbenchContext', () => ({
  useWorkbenchContext: () => ({}),
}))

jest.mock('../../contexts/WorkbenchStoreContext', () => ({
  useWorkbenchStore: () => ({}),
}))

jest.mock('../../hooks/use-workbench', () => ({
  useWorkbench: () => ({
    suggestions: ['suggestion1'],
    isFetching: false,
    currentFiles: {}, // This is needed for Object.keys(currentFiles).length
    submitPrompt: jest.fn(),
    cancelPrompt: jest.fn(),
  }),
}))

jest.mock('../../contexts/ErrorsContext', () => ({
  ErrorsProvider: ({children}: {children: React.ReactNode}) => <div>{children}</div>,
}))

jest.mock('../../contexts/IterationHistoryContext', () => ({
  useIterationHistory: jest.fn().mockReturnValue({
    previousRefinements: [],
  }),
}))

jest.mock('../../contexts/ContentFilterContext', () => ({
  useContentFilter: jest.fn().mockReturnValue({
    isFilteredModalOpen: false,
    filterExplanationContent: 'Default explanation content',
    filteredCategories: [],
    setIsFilteredModalOpen: jest.fn(),
  }),
}))

// Fix the TerminalContext mock to use the correct history structure with 'deploy' key
jest.mock('../../contexts/TerminalContext', () => {
  return {
    useTerminalContext: () => {
      const [state, setState] = useState({
        codespaceData: {},
        isCollapsed: false,
        pane: 'output',
        history: {
          // Use the correct key for CommandTask.Deploy
          deploy: {
            output: 'Test output',
            loading: false,
            startTime: null,
            endTime: null,
            exitCode: 0,
            channel: null,
          },
        },
      })
      return {
        state,
        setState,
        executeCommand: jest.fn(),
        openTerminalChannel: jest.fn(),
      }
    },
  }
})

jest.mock('../../contexts/TargetedEditsContext', () => {
  return {
    useTargetedEditsContext: () =>
      ({
        targetedEditsEnabled: false,
        enableTargetedEdits: jest.fn(),
        disableTargetedEdits: jest.fn(),
        toggleTargetedEdits: jest.fn(),
        selectedElement: null,
        deselectElement: jest.fn(),
        modifyJsxClassName: jest.fn(),
        modifyJsxText: jest.fn(),
        modifyGlobalCssVariable: jest.fn(),
        modifyThemeVariables: jest.fn(),
        themeVariables: {
          accent: '#000',
          'accent-foreground': '#000',
          background: '#000',
          border: '#000',
          card: '#000',
          'card-foreground': '#000',
          destructive: '#000',
          'destructive-foreground': '#000',
          foreground: '#000',
          input: '#000',
          muted: '#000',
          'muted-foreground': '#000',
          popover: '#000',
          'popover-foreground': '#000',
          primary: '#000',
          'primary-foreground': '#000',
          ring: '#000',
          secondary: '#000',
          'secondary-foreground': '#000',
          radius: '#000',
          spacing: '#000',
        },
        refetchThemeVariables: jest.fn(),
      }) satisfies ReturnType<typeof useTargetedEditsContext>,
  }
})

describe('Workbench', () => {
  beforeEach(jest.clearAllMocks)

  test('does not render FilteredContentModal when isFilteredModalOpen is false', () => {
    // Setup the mock to return isFilteredModalOpen as false
    ;(useContentFilter as jest.Mock).mockReturnValue({isFilteredModalOpen: false})

    render(<Workbench />)

    // Check that the modal is not rendered
    expect(screen.queryByTestId('filtered-content-modal')).not.toBeInTheDocument()
  })

  test('renders FilteredContentModal when isFilteredModalOpen is true', () => {
    // Setup the mock to return isFilteredModalOpen as true
    ;(useContentFilter as jest.Mock).mockReturnValue({isFilteredModalOpen: true})

    render(<Workbench />)

    // Check that the modal is rendered
    expect(screen.getByTestId('filtered-content-modal')).toBeInTheDocument()
  })

  test('calls setIsFilteredModalOpen when FilteredContentModal is closed', async () => {
    const mockSetIsFilteredModalOpen = jest.fn()
    // Setup the mock to return isFilteredModalOpen as true
    ;(useContentFilter as jest.Mock).mockReturnValue({
      isFilteredModalOpen: true,
      setIsFilteredModalOpen: mockSetIsFilteredModalOpen,
    })

    const {user} = render(<Workbench />)

    // Find and click the close button
    const closeButton = screen.getByTestId('close-filtered-modal')
    await user.click(closeButton)

    // Check that setIsFilteredModalOpen was called with false
    expect(mockSetIsFilteredModalOpen).toHaveBeenCalledWith(false)
  })
})

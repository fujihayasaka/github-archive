import {render} from '@github-ui/react-core/test-utils'
import {screen, waitFor} from '@testing-library/react'
import {useState} from 'react'

import {WorkbenchUIContextProvider} from '../../../contexts/WorkbenchUIContext'
import type {UseWorkbenchReturn} from '../../../hooks/use-workbench'
import type {Panel as PanelType} from '../../../types/workbench-types'
import {SidePanel} from '../SidePanel'

// Mock contexts
jest.mock('../../../contexts/ErrorsContext', () => ({
  useErrors: jest.fn().mockReturnValue({
    iterateErrors: [],
  }),
}))

jest.mock('../../../contexts/WorkbenchContext', () => ({
  useWorkbenchContext: jest.fn(() => ({
    sparkFileUrl: jest.fn(),
  })),
  sparkPathRegex: /.*\.spark$/,
}))

jest.mock('../../../contexts/TargetedEditsContext', () => ({
  useTargetedEditsContext: () => ({
    selectedElement: null,
    targetedEditsEnabled: false,
    disableTargetedEdits: jest.fn(),
    deselectElement: jest.fn(),
  }),
}))

// Mock panel components
jest.mock('../panels/AiPanel', () => ({
  AiPanel: () => <div data-testid="ai-panel">AI Panel</div>,
}))

jest.mock('../panels/AssetsPanel', () => ({
  AssetsPanel: () => <div data-testid="assets-panel">Assets Panel</div>,
}))

jest.mock('../panels/DataPanel', () => ({
  DataPanel: () => <div data-testid="data-panel">Data Panel</div>,
}))

jest.mock('../panels/IteratePanel', () => ({
  __esModule: true,
  default: () => <div data-testid="iterate-panel">Iterate Panel</div>,
}))

jest.mock('../panels/TargetedEditsPanel', () => ({
  TargetedEditsPanel: () => <div data-testid="targeted-edits-panel">Targeted Edits Panel</div>,
}))

jest.mock('../panels/ThemePanel', () => ({
  ThemePanel: () => <div data-testid="theme-panel">Theme Panel</div>,
}))

jest.mock('../PanelBlankslate', () => ({
  PanelBlankslate: ({title}: {title: string}) => <div data-testid="panel-blankslate">{title}</div>,
}))

jest.mock('@github-ui/react-core/use-route-payload', () => ({
  useRoutePayload: jest.fn().mockReturnValue({
    workbench: {id: 'test-id'},
    copilot: {ssoOrganizations: [], apiURL: 'test-url', currentTopic: 'test-topic'},
    isNewFilePage: false,
  }),
}))

describe('SidePanel', () => {
  afterEach(() => {
    jest.clearAllMocks()
  })

  const mockWorkbenchData: UseWorkbenchReturn = {
    id: 'test-id',
    updatedAt: new Date().toString(),
    workbench: {
      id: 'test-id',
      updatedAt: new Date().toString(),
      name: 'Test Workbench',
      friendlyName: 'test-workbench',
      title: 'Test Workbench',
      files: {},
      previousRefinements: [],
      description: 'Test Description',
      suggestions: [],
      shouldGenerateInitialPrompt: false,
      runtimePermanentName: 'test-workbench',
      billableOwner: {
        id: 42,
        login: 'monalisa',
        type: 'User',
      },
      cloudspace_id: 'cloudspace-id',
    },
    isFetching: false,
    persistUserEdit: jest.fn(),
    submitPrompt: jest.fn(),
    suggestions: [],
    name: 'Test Workbench',
    friendlyName: 'test-workbench',
    description: 'Test Description',
    cancelPrompt: jest.fn(),
    updatePartialWorkbench: jest.fn(),
    runtimePermanentName: 'test-workbench',
    isMobileSidebarOpen: false,
    setIsMobileSidebarOpen: jest.fn(),
    repositoryUrl: undefined,
    createRepository: jest.fn(),
    updateRefinementAndFiles: jest.fn(),
  }

  // Helper to render SidePanel with controlled selectedPanel state
  function ControlledSidePanel(props: Partial<React.ComponentProps<typeof SidePanel>>) {
    const [selectedPanel, setSelectedPanel] = useState<PanelType>('iterate')
    return (
      <WorkbenchUIContextProvider>
        <SidePanel
          workbenchData={mockWorkbenchData}
          selectedPanel={selectedPanel}
          setSelectedPanel={setSelectedPanel}
          {...props}
        />
      </WorkbenchUIContextProvider>
    )
  }

  test('renders expanded panel correctly with default iterate panel', () => {
    render(<ControlledSidePanel />)
    expect(screen.getByText('Iterate')).toBeInTheDocument()
    expect(screen.getByTestId('iterate-panel')).toBeInTheDocument()
  })

  test('changes panel when clicking on panel button in expanded mode', async () => {
    const {user} = render(<ControlledSidePanel />)

    // Initial panel is Iterate
    expect(screen.getByTestId('iterate-panel')).toBeInTheDocument()

    // Click on Theme panel button
    await user.click(screen.getByText('Theme'))
    await waitFor(() => {
      expect(screen.getByTestId('theme-panel')).toBeInTheDocument()
    })
  })
})

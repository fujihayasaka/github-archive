import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {render, screen} from '@testing-library/react'

import {useWorkbenchContext, WorkbenchContextProvider} from '../WorkbenchContext'

// Mock dependencies
jest.mock('@github-ui/react-core/use-route-payload', () => ({
  useRoutePayload: jest.fn(),
}))

// Mock navigate function
const mockNavigate = jest.fn()
jest.mock('@github-ui/use-navigate', () => ({
  useNavigate: () => mockNavigate,
}))

jest.mock('../../contexts/WorkbenchUIContext', () => ({
  useWorkbenchUI: () => ({}),
}))

// Default mock values
const defaultWorkbenchData = {
  id: 'test-workbench-id',
  name: 'Test Workbench',
  description: 'Test Description',
  deployUrl: 'https://test-deploy-url',
  repositoryUrl: 'https://github.com/test-repo',
  runtimePermanentName: 'test-runtime',
  friendlyName: 'Test Friendly Name',
}

// Helper component to test the context
function TestComponent({onRender}: {onRender?: (context: ReturnType<typeof useWorkbenchContext>) => void}) {
  const context = useWorkbenchContext()
  onRender?.(context)

  return (
    <div>
      <div data-testid="name">{context.name}</div>
      <div data-testid="description">{context.description}</div>
      <div data-testid="isFetching">{context.isFetching.toString()}</div>
      <div data-testid="isOptimisticLoading">{context.isOptimisticLoading.toString()}</div>
      <div data-testid="isMobileSidebarOpen">{context.isMobileSidebarOpen.toString()}</div>
      <div data-testid="initialPromptSubmitted">{context.initialPromptSubmitted.current.toString()}</div>
      <button onClick={() => context.setName('Updated Name')}>Update Name</button>
    </div>
  )
}

describe('WorkbenchContext', () => {
  beforeEach(() => {
    jest.clearAllMocks()

    // Default mocks setup
    jest.mocked(useRoutePayload).mockReturnValue({
      workbench: defaultWorkbenchData,
    })
  })

  const renderWithProviders = (
    workbenchProps = {},
    onRender?: (context: ReturnType<typeof useWorkbenchContext>) => void,
  ) => {
    // Merge default props with any custom props
    jest.mocked(useRoutePayload).mockReturnValue({
      workbench: {
        ...defaultWorkbenchData,
        ...workbenchProps,
      },
    })

    return render(
      <WorkbenchContextProvider>
        <TestComponent onRender={onRender} />
      </WorkbenchContextProvider>,
    )
  }

  it('initializes with default values from route payload', () => {
    renderWithProviders()

    expect(screen.getByTestId('name').textContent).toBe('Test Workbench')
    expect(screen.getByTestId('description').textContent).toBe('Test Description')
    expect(screen.getByTestId('isFetching').textContent).toBe('false')
    expect(screen.getByTestId('isOptimisticLoading').textContent).toBe('false')
    expect(screen.getByTestId('isMobileSidebarOpen').textContent).toBe('false')
    expect(screen.getByTestId('initialPromptSubmitted').textContent).toBe('false')
  })
})

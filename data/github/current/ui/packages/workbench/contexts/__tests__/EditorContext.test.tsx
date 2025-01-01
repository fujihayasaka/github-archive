import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {useNavigate} from '@github-ui/use-navigate'
import {act, render, screen} from '@testing-library/react'

import type {FileChange} from '../../types/file-syncer-v2-types'
import {type EditorContext, EditorContextProvider, useEditorContext} from '../EditorContext'
import {useFilesContext} from '../FilesContext'
import {useFileSyncerContext} from '../FileSyncerContext'
import {useWorkbenchContext} from '../WorkbenchContext'

jest.mock('@github-ui/use-navigate')
jest.mock('@github-ui/react-core/use-route-payload')
jest.mock('../WorkbenchContext', () => ({
  useWorkbenchContext: jest.fn(),
}))
jest.mock('../FilesContext', () => ({
  useFilesContext: jest.fn(),
}))
jest.mock('../FileSyncerContext', () => ({
  useFileSyncerContext: jest.fn(),
}))

// @ts-expect-error overriding window.location in test
delete window.location
window.location = {} as string & Location
Object.defineProperty(window.location, 'pathname', {value: '/path/to/file.js'})

// Helper component to test the context
function TestComponent({onRender}: {onRender?: (context: ReturnType<typeof useEditorContext>) => void}) {
  const context = useEditorContext()
  onRender?.(context)
  return (
    <div>
      <div data-testid="refreshEditor">{context.refreshEditor.toString()}</div>
      <div data-testid="isAnimating">{context.isAnimating.toString()}</div>
      <div data-testid="previousPath">{context.previousPath || 'null'}</div>
      <div data-testid="isNavigating">{context.isNavigating.toString()}</div>
      <div data-testid="watchingPath">{context.watchingPath || 'null'}</div>
      <button onClick={() => context.forceEditorRefresh()}>Force Refresh</button>
      <button onClick={() => context.setRefreshEditor(true)}>Set Refresh</button>
    </div>
  )
}

describe('EditorContextProvider', () => {
  // Common mocks
  const mockNavigate = jest.fn()
  const mockSetFileChangeStack = jest.fn()
  const mockForceContentRefresh = jest.fn()
  const mockGetFileList = jest.fn()
  const mockFileChangeStack: FileChange[] = []
  const sparkFileUrl = ({sparkId, path}: {sparkId: string; path: string}) => `/copilot/spark/${sparkId}/file/${path}`

  beforeEach(() => {
    jest.clearAllMocks()
    ;(useNavigate as jest.Mock).mockReturnValue(mockNavigate)
    ;(useRoutePayload as jest.Mock).mockReturnValue({
      path: '/path/to/file.js',
      workbench: {id: 'test-id'},
    })
    ;(useWorkbenchContext as jest.Mock).mockReturnValue({
      isFetching: false,
      previousIsFetching: false,
      workbench: {id: 'test-id'},
      sparkFileUrl,
    })
    ;(useFilesContext as jest.Mock).mockReturnValue({
      getFileList: mockGetFileList,
    })
    ;(useFileSyncerContext as jest.Mock).mockReturnValue({
      fileChangeStack: mockFileChangeStack,
      setFileChangeStack: mockSetFileChangeStack,
      forceContentRefresh: mockForceContentRefresh,
    })

    // Default mocks for file change stack to be empty
    mockGetFileList.mockReturnValue([])
    mockFileChangeStack.length = 0

    // Reset timers
    jest.useFakeTimers()
  })

  afterEach(() => {
    jest.useRealTimers()
  })

  const renderWithProviders = (
    isFetching = false,
    fileChangeStack = mockFileChangeStack,
    onRender?: (context: ReturnType<typeof useEditorContext>) => void,
  ) => {
    // Set up mocks with the provided values
    ;(useWorkbenchContext as jest.Mock).mockReturnValue({
      isFetching,
      workbench: {id: 'test-id'},
      sparkFileUrl,
    })
    ;(useFileSyncerContext as jest.Mock).mockReturnValue({
      fileChangeStack,
      setFileChangeStack: mockSetFileChangeStack,
      forceContentRefresh: mockForceContentRefresh,
    })

    return render(
      <EditorContextProvider>
        <TestComponent onRender={onRender} />
      </EditorContextProvider>,
    )
  }

  test('initializes with default values', () => {
    renderWithProviders()

    expect(screen.getByTestId('refreshEditor').textContent).toBe('false')
    expect(screen.getByTestId('isAnimating').textContent).toBe('false')
    expect(screen.getByTestId('previousPath').textContent).toBe('null')
    expect(screen.getByTestId('isNavigating').textContent).toBe('true') // Path is set but previousPath is null
    expect(screen.getByTestId('watchingPath').textContent).toBe('null')
  })

  test('forceEditorRefresh sets refreshEditor to true', () => {
    renderWithProviders()

    act(() => {
      screen.getByText('Force Refresh').click()
    })

    expect(screen.getByTestId('refreshEditor').textContent).toBe('true')
  })

  test('handles file changes when fetching completes', () => {
    // Start with model iterating
    const {rerender} = renderWithProviders(true)

    // Now simulate fetch completion
    ;(useWorkbenchContext as jest.Mock).mockReturnValue({
      isFetching: false,
      workbench: {id: 'test-id'},
    })
    rerender(
      <EditorContextProvider>
        <TestComponent />
      </EditorContextProvider>,
    )

    // Should clear file change stack when fetch completes
    expect(mockSetFileChangeStack).toHaveBeenCalledWith([])
  })

  test('refreshes content when current file needs refresh', () => {
    const fileChanges: FileChange[] = [{type: 'file', path: '/path/to/file.js', changeType: 'modified'}]

    renderWithProviders(false, fileChanges)

    // Should refresh the current file content and clear the stack
    expect(mockForceContentRefresh).toHaveBeenCalled()
    expect(mockSetFileChangeStack).toHaveBeenCalledWith([])
  })

  test('navigates to next file change when fetching and file changes exist', () => {
    const fileList = [{path: 'path/to/newfile.js'}]
    mockGetFileList.mockReturnValue(fileList)

    const fileChanges: FileChange[] = [{type: 'file', path: 'path/to/newfile.js', changeType: 'added'}]

    renderWithProviders(true, fileChanges)

    // Should navigate to the new file
    expect(mockNavigate).toHaveBeenCalledWith('/copilot/spark/test-id/file/path/to/newfile.js')
    // And set watching path
    expect(screen.getByTestId('watchingPath').textContent).toBe('path/to/newfile.js')
  })

  test('handles animation delays when navigating', () => {
    const fileChanges: FileChange[] = [{type: 'file', path: 'path/to/newfile.js', changeType: 'added'}]
    const fileList = [{path: 'path/to/newfile.js'}]
    mockGetFileList.mockReturnValue(fileList)
    let contextRef: EditorContext | null = null

    const {rerender} = renderWithProviders(true, [], context => {
      contextRef = context
    })
    expect(contextRef).not.toBeNull()
    ;(useFileSyncerContext as jest.Mock).mockReturnValue({
      fileChangeStack: fileChanges,
      setFileChangeStack: mockSetFileChangeStack,
      forceContentRefresh: mockForceContentRefresh,
    })
    act(() => {
      contextRef!.setIsAnimating(true)
    })
    rerender(
      <EditorContextProvider>
        <TestComponent />
      </EditorContextProvider>,
    )

    expect(mockSetFileChangeStack).not.toHaveBeenCalled()
    expect(mockNavigate).not.toHaveBeenCalled()

    act(() => {
      contextRef!.setIsAnimating(false)
    })
    // Fast-forward timer
    act(() => {
      jest.advanceTimersByTime(5000)
    })

    // Now it should navigate
    expect(mockNavigate).toHaveBeenCalledWith('/copilot/spark/test-id/file/path/to/newfile.js')
  })

  test('updates navigation timestamp when navigation completes', () => {
    let contextRef: EditorContext | null = null

    ;(useRoutePayload as jest.Mock).mockReturnValue({
      path: '/old/path',
      workbench: {id: 'test-id'},
    })

    const {rerender} = renderWithProviders(false, [], context => {
      contextRef = context
    })
    expect(contextRef).not.toBeNull()
    act(() => {
      contextRef!.setPreviousPath('/old/path')
    })

    expect(screen.getByTestId('isNavigating').textContent).toBe('false')
    expect(screen.getByTestId('previousPath').textContent).toBe('/old/path')
    ;(useRoutePayload as jest.Mock).mockReturnValue({
      path: '/new/path',
      workbench: {id: 'test-id'},
    })

    rerender(
      <EditorContextProvider>
        <TestComponent />
      </EditorContextProvider>,
    )

    expect(screen.getByTestId('isNavigating').textContent).toBe('true')
    expect(screen.getByTestId('previousPath').textContent).toBe('/old/path')

    act(() => {
      contextRef!.setPreviousPath('/new/path')
    })

    expect(screen.getByTestId('previousPath').textContent).toBe('/new/path')
  })
})

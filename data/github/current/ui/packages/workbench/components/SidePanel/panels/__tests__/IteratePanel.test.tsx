import {mockClientEnv} from '@github-ui/client-env/mock'
import {screen} from '@testing-library/react'

import {mockUseWorkbenchDataReturn} from '../../../../__tests__/workbench-mocks'
import {renderWorkbenchStore, type WorkbenchStoreProps} from '../../../../__tests__/WorkbenchStoreWrapper'
import {useCodespaceContext} from '../../../../contexts/CodespaceContext'
import {useContentFilter} from '../../../../contexts/ContentFilterContext'
import {useEditorContext} from '../../../../contexts/EditorContext'
import {useErrors} from '../../../../contexts/ErrorsContext'
import {useFilesContext} from '../../../../contexts/FilesContext'
import {useFileSyncerContext} from '../../../../contexts/FileSyncerContext'
import {useIterationHistory} from '../../../../contexts/IterationHistoryContext'
import {useServerEvents} from '../../../../contexts/ServerEventsContext'
import {useUserPromptContext} from '../../../../contexts/UserPromptContext'
import {useWorkbenchContext} from '../../../../contexts/WorkbenchContext'
import {useWorkbenchEditorAppContext} from '../../../../contexts/WorkbenchEditorAppContext'
import {useWorkbenchUI} from '../../../../contexts/WorkbenchUIContext'
import {useWorkbench, type UseWorkbenchReturn} from '../../../../hooks/use-workbench'
import IteratePanel from '../IteratePanel'

// Mock all the contexts and hooks
jest.mock('../../../../contexts/ContentFilterContext', () => ({
  useContentFilter: jest.fn(),
}))

jest.mock('../../../../contexts/ErrorsContext', () => ({
  useErrors: jest.fn(),
}))

jest.mock('../../../../contexts/IterationHistoryContext', () => ({
  useIterationHistory: jest.fn(),
}))

jest.mock('../../../../contexts/WorkbenchContext', () => ({
  useWorkbenchContext: jest.fn(),
}))

jest.mock('../../../../contexts/WorkbenchUIContext', () => ({
  useWorkbenchUI: jest.fn(),
}))

jest.mock('../../../../contexts/FilesContext', () => ({
  useFilesContext: jest.fn(),
}))

jest.mock('../../../../contexts/FileSyncerContext', () => ({
  useFileSyncerContext: jest.fn(),
}))

jest.mock('../../../../contexts/WorkbenchEditorAppContext', () => ({
  useWorkbenchEditorAppContext: jest.fn(),
}))

jest.mock('../../../../contexts/CodespaceContext', () => ({
  useCodespaceContext: jest.fn(),
}))

jest.mock('../../../../contexts/ServerEventsContext', () => ({
  useServerEvents: jest.fn(),
}))

jest.mock('../../../../hooks/use-workbench', () => ({
  useWorkbench: jest.fn(),
}))

jest.mock('../../../../contexts/EditorContext', () => ({
  useEditorContext: jest.fn(),
}))

// Mock the announce function
jest.mock('@github-ui/aria-live', () => ({
  announce: jest.fn(),
}))

jest.mock('@github-ui/react-core/use-route-payload', () => ({
  useRoutePayload: jest.fn().mockReturnValue({
    workbench: {id: 'test-id'},
    copilot: {ssoOrganizations: [], apiURL: 'test-url', currentTopic: 'test-topic'},
    isNewFilePage: false,
  }),
}))
// Mock the analytics hook
jest.mock('@github-ui/use-analytics', () => ({
  useAnalytics: jest.fn().mockReturnValue({
    sendTrackEvent: jest.fn(),
    sendUIEvent: jest.fn(),
  }),
}))

jest.mock('.../../../../contexts/UserPromptContext', () => ({
  useUserPromptContext: jest.fn(),
}))

// Cast mocked functions
const mockUseContentFilter = useContentFilter as jest.Mock
const mockUseErrors = useErrors as jest.Mock
const mockUseIterationHistory = useIterationHistory as jest.Mock
const mockUseWorkbenchContext = useWorkbenchContext as jest.Mock
const mockUseWorkbenchUI = useWorkbenchUI as jest.Mock
const mockUseFilesContext = useFilesContext as jest.Mock
const mockUseFileSyncerContext = useFileSyncerContext as jest.Mock
const mockUseWorkbenchEditorAppContext = useWorkbenchEditorAppContext as jest.Mock
const mockUseCodespaceContext = useCodespaceContext as jest.Mock
const mockUseServerEventsContext = useServerEvents as jest.Mock
const mockUseWorkbench = useWorkbench as jest.Mock
const mockUseUserPromptContext = useUserPromptContext as jest.Mock
const mockUseEditorContext = useEditorContext as jest.Mock

// Mock functions for workbench data
const mockAttachImage = jest.fn()
const mockCancelPrompt = jest.fn()
const mockSubmitPrompt = jest.fn()
const mockUpdateRefinementAndFiles = jest.fn()
const mockSetDeployErrors = jest.fn()

function setUserPromptContext(overrides: Partial<ReturnType<typeof useUserPromptContext>> = {}) {
  return {
    promptText: '',
    promptImage: null,
    setPromptText: jest.fn(),
    setPromptError: jest.fn(),
    imageUploadError: null,
    setImageUploadError: jest.fn(),
    attachImage: mockAttachImage,
    clearImageAttachment: jest.fn(),
    ...overrides,
  }
}

describe('IteratePanel', () => {
  beforeEach(() => {
    jest.clearAllMocks()

    // Default mocks
    mockUseContentFilter.mockReturnValue({
      filterExplanationContent: null,
    })

    mockUseErrors.mockReturnValue({
      iterateErrors: [],
      setDeployBuildErrors: mockSetDeployErrors,
    })

    mockUseIterationHistory.mockReturnValue({
      previousRefinements: [],
      currentRefinementId: null,
    })

    mockUseWorkbenchContext.mockReturnValue({
      isFetching: false,
      initialPromptSubmitted: {
        current: true,
      },
    })

    mockUseWorkbenchUI.mockReturnValue({
      navigateAndViewFile: jest.fn(),
    })

    mockUseFilesContext.mockReturnValue({
      editFile: jest.fn(),
      deleteFile: jest.fn(),
    })

    mockUseFileSyncerContext.mockReturnValue({
      getFileSyncerV2: jest.fn(),
      fileSyncerStarted: false,
    })

    mockUseWorkbenchEditorAppContext.mockReturnValue({
      setCurrentTopic: jest.fn(),
      setCurrentFile: jest.fn(),
    })

    mockUseCodespaceContext.mockReturnValue({
      codespaceData: {
        codespaceName: 'test-codespace',
        codespaceId: 'test-codespace-id',
        codespaceURL: 'test-codespace-url',
      },
    })

    mockUseServerEventsContext.mockReturnValue({
      serverEvents: {
        isConnected: true,
        isConnecting: false,
        isDisconnected: false,
      },
    })

    mockUseUserPromptContext.mockReturnValue(setUserPromptContext())
  })

  mockUseEditorContext.mockReturnValue({
    forceEditorRefresh: jest.fn(),
  })

  mockUseWorkbench.mockReturnValue({
    updateRefinementAndFiles: mockUpdateRefinementAndFiles,
    updatePartialWorkbench: jest.fn(),
  })
  // Helper function to render with workbenchData prop
  const renderIteratePanel = (customProps: Partial<UseWorkbenchReturn> = {}, storeProps: WorkbenchStoreProps = {}) => {
    const workbenchData = {
      ...mockUseWorkbenchDataReturn,
      cancelPrompt: mockCancelPrompt,
      submitPrompt: mockSubmitPrompt,
      ...customProps,
    } as unknown as UseWorkbenchReturn

    return renderWorkbenchStore({
      children: <IteratePanel workbenchData={workbenchData} />,
      ...storeProps,
    })
  }

  it('renders input field for prompt submission', () => {
    renderIteratePanel()
    expect(screen.getByPlaceholderText('What do you want to change?')).toBeInTheDocument()
    expect(screen.getByLabelText('Send now')).toBeInTheDocument()
  })

  it('submits a prompt when send button is clicked', async () => {
    mockUseUserPromptContext.mockReturnValue(setUserPromptContext({promptText: 'Refactor this code'}))

    const {user} = renderIteratePanel()

    const sendButton = screen.getByLabelText('Send now')
    await user.click(sendButton)

    expect(mockSubmitPrompt).toHaveBeenCalledWith('Refactor this code', 'generate', 'formSubmit', false)
  })

  it('submits a prompt when Enter key is pressed', async () => {
    mockUseUserPromptContext.mockReturnValue(setUserPromptContext({promptText: 'Fix this bug'}))

    const {user} = renderIteratePanel()

    const inputField = screen.getByPlaceholderText('What do you want to change?')
    await user.type(inputField, '{Enter}')

    expect(mockSubmitPrompt).toHaveBeenCalledWith('Fix this bug', 'generate', 'handleKeyDown', false)
  })

  it('shows stop button during prompt fetching', () => {
    renderIteratePanel({isFetching: true})

    expect(screen.getByLabelText('Stop current generation')).toBeInTheDocument()
    expect(screen.queryByLabelText('Send now')).not.toBeInTheDocument()
  })

  it('cancels prompt when stop button is clicked', async () => {
    const {user} = renderIteratePanel({isFetching: true})

    const stopButton = screen.getByLabelText('Stop current generation')
    await user.click(stopButton)

    expect(mockCancelPrompt).toHaveBeenCalled()
  })

  it('shows image attachment when image is provided', () => {
    mockUseUserPromptContext.mockReturnValue(
      setUserPromptContext({
        promptImage: {
          media_type: 'image/png',
          name: 'test-image.png',
          url: 'https://example.com/test-image.png',
        },
      }),
    )

    const mockFile = new File([''], 'test-image.png', {type: 'image/png'})
    renderIteratePanel({
      // eslint-disable-next-line @typescript-eslint/ban-ts-comment
      //@ts-expect-error
      image: {file: mockFile},
    })

    expect(screen.getByText('test-image.png')).toBeInTheDocument()
  })

  it('shows content filter banner when content is filtered', () => {
    mockUseContentFilter.mockReturnValue({
      filterExplanationContent: 'Content was filtered due to policy restrictions',
    })

    // Need to add a refinement for the banner to render inside
    mockUseIterationHistory.mockReturnValue({
      previousRefinements: [
        {
          id: '1',
          prompt: 'Test prompt',
          files: {},
        },
      ],
      updateRefinementAndFiles: mockUpdateRefinementAndFiles,
      currentRefinementId: '1',
    })

    renderIteratePanel()

    expect(screen.getByText('Content was filtered due to policy restrictions')).toBeInTheDocument()
    expect(screen.getByText('Prompt filtered')).toBeInTheDocument()
  })

  it('uses submitPrompt with replace=true when content is filtered', async () => {
    mockUseContentFilter.mockReturnValue({
      filterExplanationContent: 'Content was filtered due to policy restrictions',
    })

    mockUseUserPromptContext.mockReturnValue(
      setUserPromptContext({
        promptText: 'Update this code',
      }),
    )

    const {user} = renderIteratePanel()

    const sendButton = screen.getByLabelText('Send now')
    await user.click(sendButton)

    expect(mockSubmitPrompt).toHaveBeenCalledWith('Update this code', 'generate', 'formSubmit', true)
  })

  it('renders activity log with previous refinements', () => {
    mockUseIterationHistory.mockReturnValue({
      previousRefinements: [
        {
          id: '1',
          iteration_type: 'ai',
          prompt: 'First prompt',
          files: {'file1.js': {fileName: 'file1.js', editType: 'update'}},
        },
        {
          id: '2',
          iteration_type: 'ai',
          parentId: '1',
          prompt: 'Second prompt',
          files: {'file2.js': {fileName: 'file2.js', editType: 'create'}},
        },
      ],
      updateRefinementAndFiles: mockUpdateRefinementAndFiles,
      currentRefinementId: '2',
    })

    renderIteratePanel()

    // Focused on the second prompt
    expect(screen.getByText('First prompt')).toBeInTheDocument()
    expect(screen.getByText('Second prompt')).toBeInTheDocument()
    expect(screen.getByText('Made 1 change')).toBeInTheDocument()
  })

  it('restores a previous version when clicking on a refinement item', async () => {
    let isNavigatingHistory = false
    mockUseIterationHistory.mockReturnValue({
      previousRefinements: [
        {
          id: 1,
          iteration_type: 'ai',
          prompt: 'First prompt',
          files: {'file1.js': {fileName: 'file1.js', editType: 'update'}},
          sha: 'sha1',
        },
        {
          id: 2,
          parentId: 1,
          iteration_type: 'ai',
          prompt: 'Second prompt',
          files: {'file1.js': {fileName: 'file1.js', editType: 'update'}},
          sha: 'sha2',
        },
      ],
      updateRefinementAndFiles: mockUpdateRefinementAndFiles,
      currentRefinementId: 2,
      isNavigatingHistory,
      setIsNavigatingHistory: (value: boolean) => (isNavigatingHistory = value),
    })

    const {user} = renderIteratePanel()

    // Find and click the refinement itself (the component with the prompt text)
    const refinementItem = screen.getByText('First prompt')
    await user.click(refinementItem)

    expect(mockUpdateRefinementAndFiles).toHaveBeenCalledWith(1)
  })

  it('is disabled when generation is in progress', async () => {
    mockUseIterationHistory.mockReturnValue({
      previousRefinements: [
        {
          id: '1',
          iteration_type: 'ai',
          prompt: 'First prompt',
          files: {'file1.js': {fileName: 'file1.js', editType: 'update'}},
        },
        {
          id: '2',
          iteration_type: 'ai',
          parentId: '1',
          prompt: 'Second prompt',
          files: {'file1.js': {fileName: 'file1.js', editType: 'update'}},
        },
      ],
      updateRefinementAndFiles: mockUpdateRefinementAndFiles,
      currentRefinementId: '2',
    })

    mockUseWorkbenchContext.mockReturnValue({
      isFetching: true,
    })

    renderIteratePanel({isFetching: true})

    // Find and click the refinement itself (the component with the prompt text)
    expect(screen.getByRole('button', {name: 'First prompt'})).toBeDisabled()
  })

  it('is disabled when navigation is in progress', async () => {
    let isNavigatingHistory = true
    mockUseIterationHistory.mockReturnValue({
      previousRefinements: [
        {
          id: 1,
          prompt: 'First prompt',
          iteration_type: 'ai',
          files: {'file1.js': {fileName: 'file1.js', editType: 'update'}},
          sha: 'sha1',
        },
        {
          id: 2,
          parentId: 1,
          iteration_type: 'ai',
          prompt: 'Second prompt',
          files: {'file1.js': {fileName: 'file1.js', editType: 'update'}},
          sha: 'sha2',
        },
      ],
      updateRefinementAndFiles: mockUpdateRefinementAndFiles,
      currentRefinementId: 2,
      isNavigatingHistory,
      setIsNavigatingHistory: (value: boolean) => (isNavigatingHistory = value),
    })

    const {user} = renderIteratePanel()

    // Find and click the refinement itself (the component with the prompt text)
    const refinementItem = screen.getByText('First prompt')
    await user.click(refinementItem)

    expect(screen.getByRole('button', {name: 'First prompt'})).toBeDisabled()
  })

  it('is not disabled when the global readOnly flag is set without the FF', async () => {
    renderIteratePanel({}, {readOnly: true})

    expect(screen.getByPlaceholderText('What do you want to change?')).not.toBeDisabled()
    expect(screen.getByLabelText('Send now')).not.toBeDisabled()
  })

  it('is not disabled when the global readOnly flag is set with the FF', async () => {
    mockClientEnv({
      featureFlags: ['workbench_store_readonly'],
    })

    renderIteratePanel({}, {readOnly: true})

    expect(screen.getByPlaceholderText('What do you want to change?')).not.toBeDisabled()
    expect(screen.getByLabelText('Send now')).not.toBeDisabled()
  })

  it('navigates and views file when file is selected in iteration panel', async () => {
    const mockNavigateAndViewFile = jest.fn()
    mockUseWorkbenchContext.mockReturnValue({
      isFetching: false,
    })
    mockUseWorkbenchUI.mockReturnValue({
      navigateAndViewFile: mockNavigateAndViewFile,
    })
    mockUseIterationHistory.mockReturnValue({
      previousRefinements: [
        {
          id: '1',
          prompt: 'Test prompt',
          files: {'file1.js': {fileName: 'file1.js', editType: 'update'}},
        },
      ],
      currentRefinementId: '1',
      isNavigatingHistory: false,
    })

    const {user} = renderIteratePanel()

    const fileItem = await screen.findByText('file1.js')
    await user.click(fileItem)

    expect(mockNavigateAndViewFile).toHaveBeenCalledWith('file1.js')
  })

  // it('attaches errors to prompt when errors are attached', async () => {
  //   mockUseErrors.mockReturnValue({
  //     iterateErrors: [{message: 'Error 1'}, {message: 'Error 2'}],
  //     setDeployBuildErrors: mockSetDeployErrors,
  //   })

  //   const {user} = renderIteratePanel()

  //   // Find and click attach button for errors
  //   // const errorText = screen.getByText('Error 1')
  //   const clickableRow = screen.getByRole('a', {name: /Error 1/})
  //   await user.click(clickableRow)

  //   // Type prompt and submit
  //   const inputField = screen.getByPlaceholderText('What do you want to change?')
  //   await user.type(inputField, 'Fix the code')
  //   await user.click(screen.getByLabelText('Send now'))

  //   // Verify prompt was constructed with error
  //   expect(mockSubmitPrompt).toHaveBeenCalledWith(
  //     'Fix the code; Fix these attached errors: Error 1',
  //     'generate',
  //   )
  //   expect(mockSetDeployErrors).toHaveBeenCalledWith([])
  // })

  // it('provides default "fix" prompt when attaching an error with empty input', async () => {
  //   mockUseErrors.mockReturnValue({
  //     iterateErrors: [{message: 'Error 1'}],
  //     setDeployBuildErrors: mockSetDeployErrors,
  //   })

  //   const {user} = renderIteratePanel()

  //   // Find and click attach button for errors
  //   const attachButton = screen.getByText('Error 1')
  //   await user.click(attachButton)

  //   // Input should have been populated with a default message
  //   const inputField = screen.getByPlaceholderText('What do you want to change?')
  //   expect((inputField as HTMLInputElement).value).toBe('Please fix these build errors.')
  // })
})

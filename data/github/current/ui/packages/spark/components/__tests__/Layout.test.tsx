import '@testing-library/jest-dom'

import {render, setupUserEvent} from '@github-ui/react-core/test-utils'
import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import {useUserPromptContext} from '@github-ui/workbench/contexts/UserPromptContext'
import {useWorkbenchStore} from '@github-ui/workbench/contexts/WorkbenchStoreContext'
import {screen, waitFor} from '@testing-library/react'
import {http, HttpResponse} from 'msw'
import {setupServer} from 'msw/node'

import Layout from '../Layout'

// Mock dependencies
jest.mock('@github-ui/react-core/use-app-payload')
jest.mock('@github-ui/workbench/contexts/UserPromptContext')
jest.mock('@github-ui/workbench/contexts/WorkbenchStoreContext')
jest.mock('react-router-dom', () => ({
  ...jest.requireActual('react-router-dom'),
  useNavigate: jest.fn(),
}))
jest.mock('@github-ui/copilot-chat/utils/copilot-feature-flags', () => {
  const originalModule = jest.requireActual('@github-ui/copilot-chat/utils/copilot-feature-flags')
  return {
    ...originalModule,
    copilotFeatureFlags: {
      ...originalModule.copilotFeatureFlags,
      workbenchUserLimits: false,
    },
  }
})
jest.mock('@github-ui/get-os', () => ({
  isMacOS: jest.fn(() => false),
}))

const mockUseAppPayload = useAppPayload as jest.Mock
const mockUseUserPromptContext = useUserPromptContext as jest.Mock
const mockUseWorkbenchStore = useWorkbenchStore as jest.Mock
const mockUseNavigate = jest.requireMock('react-router-dom').useNavigate as jest.Mock

// MSW server setup
const server = setupServer()
const user = setupUserEvent()

describe('Layout Component', () => {
  let mockReloadQuota: jest.Mock
  let consoleWarnSpy: jest.SpyInstance

  beforeAll(() => server.listen())
  afterEach(() => {
    server.resetHandlers()
    if (consoleWarnSpy) {
      consoleWarnSpy.mockRestore()
    }
  })
  afterAll(() => server.close())

  beforeEach(() => {
    jest.clearAllMocks()

    consoleWarnSpy = jest.spyOn(console, 'warn').mockImplementation(() => {})

    mockReloadQuota = jest.fn()

    mockUseAppPayload.mockReturnValue({icebreakers: []})

    let currentPromptText = ''
    const setPromptTextFn = jest.fn((next: string | ((prev: string) => string)) => {
      if (typeof next === 'function') {
        currentPromptText = next(currentPromptText)
      } else {
        currentPromptText = next
      }
    })

    mockUseUserPromptContext.mockImplementation(() => ({
      promptText: currentPromptText,
      setPromptText: setPromptTextFn,
      attachImage: jest.fn(),
      promptImage: null,
      clearImageAttachment: jest.fn(),
      imageUploadError: null,
      setImageUploadError: jest.fn(),
    }))

    mockUseWorkbenchStore.mockReturnValue({
      reloadQuota: mockReloadQuota,
    })

    mockUseNavigate.mockReturnValue(jest.fn())

    // MSW handlers
    server.use(
      http.post('/copilot/spark', () => {
        return HttpResponse.json({id: 'test-spark-id'}, {status: 200})
      }),
      http.get('/copilot/spark/workbench', () => {
        return HttpResponse.json({workbenches: []}, {status: 200})
      }),
    )
  })

  test('should call reloadQuota on prompt submission', async () => {
    render(<Layout />)

    const promptInput = screen.getByPlaceholderText('Create intelligent prototypes, personal apps, websites and more')
    await user.type(promptInput, 'Test reloadQuota')

    const submitButton = screen.getByTestId('submit-prompt')
    await waitFor(() => expect(submitButton).toBeEnabled())

    await user.click(submitButton)
    expect(mockReloadQuota).toHaveBeenCalled()
  })
})

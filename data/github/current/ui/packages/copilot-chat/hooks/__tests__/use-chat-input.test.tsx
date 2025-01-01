// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {renderHook} from '@github-ui/react-core/test-utils'
import {waitFor} from '@testing-library/react'
import {MemoryRouter, useSearchParams} from 'react-router-dom'

import {getCopilotChatProviderProps} from '../../test-utils/mock-data'
import type {CopilotChatMode} from '../../utils/copilot-chat-types'
import {copilotLocalStorage} from '../../utils/copilot-local-storage'
import {CopilotChatProvider} from '../../utils/CopilotChatContext'
import {useChatInput} from '../use-chat-input'

jest.mock('react-router-dom', () => ({
  ...jest.requireActual('react-router-dom'),
  // useLocation: jest.fn(),
  useSearchParams: jest.fn(() => [new URLSearchParams(''), jest.fn()]),
}))

function mockSearchParams(search: string) {
  const mockedUseSearchParams = jest.mocked(useSearchParams)
  const setter = jest.fn()
  const value: ReturnType<typeof useSearchParams> = [new URLSearchParams(search), setter]
  mockedUseSearchParams.mockReturnValue(value)
  return setter
}

const THREAD_ID = 'thread-id'

function getWrapper(mode: CopilotChatMode, pathname?: string) {
  const wrapper = ({children}: {children: React.ReactNode}) => (
    <MemoryRouter
      // eslint-disable-next-line camelcase
      future={{v7_startTransition: true, v7_relativeSplatPath: true}}
      initialEntries={[pathname ?? `/copilot/c/${THREAD_ID}`]}
    >
      <CopilotChatProvider {...getCopilotChatProviderProps()} threadId={THREAD_ID} mode={mode}>
        {children}
      </CopilotChatProvider>
    </MemoryRouter>
  )
  return wrapper
}

function renderUseChatInput(mode: CopilotChatMode = 'assistive', pathname?: string) {
  return renderHook(() => useChatInput({}), {wrapper: getWrapper(mode, pathname)})
}

describe('initial text', () => {
  test('should be empty', async () => {
    const {result} = renderUseChatInput()
    await waitFor(() => expect(result.current.text).toBe(''))
  })

  it('should use saved text', async () => {
    copilotLocalStorage.setSavedMessageFast(THREAD_ID, 'hello')

    const {result} = renderUseChatInput()
    await waitFor(() => expect(result.current.text).toBe('hello'))
  })

  it('should prefer saved on error text', async () => {
    copilotLocalStorage.setSavedMessageFast(THREAD_ID, 'hello')
    copilotLocalStorage.setSavedUserMessageOnError(THREAD_ID, 'goodbye')

    const {result} = renderUseChatInput()
    await waitFor(() => expect(result.current.text).toBe('goodbye'))
  })

  it('should ignore url text in assistive', async () => {
    copilotLocalStorage.setSavedMessageFast(THREAD_ID, 'hello')
    copilotLocalStorage.setSavedUserMessageOnError(THREAD_ID, 'goodbye')
    mockSearchParams('?prompt=prompt')

    const {result} = renderUseChatInput('assistive')
    await waitFor(() => expect(result.current.text).toBe('goodbye'))
  })

  it('should use url text in immersive', async () => {
    copilotLocalStorage.setSavedMessageFast(THREAD_ID, 'hello')
    copilotLocalStorage.setSavedUserMessageOnError(THREAD_ID, 'goodbye')
    const setSearchParams = mockSearchParams('?prompt=prompt')

    const {result} = renderUseChatInput('immersive', '/copilot')
    await waitFor(() => expect(result.current.text).toBe('prompt'))

    // should also clear the search param
    expect(setSearchParams).toHaveBeenCalledTimes(1)
    const setSearchParamsArg = setSearchParams.mock.calls[0]?.[0] as URLSearchParams | undefined
    expect(setSearchParamsArg).toBeDefined()
    expect(setSearchParamsArg?.get('prompt')).toBeNull()
  })

  it('should ignore url text in immersive in existing thread', async () => {
    copilotLocalStorage.setSavedMessageFast(THREAD_ID, 'hello')
    copilotLocalStorage.setSavedUserMessageOnError(THREAD_ID, 'goodbye')
    mockSearchParams('?prompt=prompt')

    const {result} = renderUseChatInput('immersive')
    await waitFor(() => expect(result.current.text).toBe('goodbye'))
  })
})

describe('auto submit', () => {
  it('should auto submit prompt in immersive mode', async () => {
    const onSubmit = jest.fn()
    const setSearchParams = mockSearchParams('?prompt=test prompt')

    const {result} = renderHook(() => useChatInput({onSubmit}), {wrapper: getWrapper('immersive', '/copilot')})

    // Should clear URL params
    await waitFor(() => {
      expect(setSearchParams).toHaveBeenCalledTimes(1)
    })
    const updatedParams = setSearchParams.mock.calls[0]?.[0] as URLSearchParams
    expect(updatedParams?.get('prompt')).toBeNull()

    // Should call onSubmit with prompt
    await waitFor(() => {
      expect(onSubmit).toHaveBeenCalledWith('test prompt')
    })

    // Should clear input
    await waitFor(() => {
      expect(result.current.text).toBe('')
    })
  })

  it('should not auto submit when autoSubmit is false', async () => {
    const onSubmit = jest.fn()
    const setSearchParams = mockSearchParams('?prompt=test prompt')

    // Override getWrapper to provide modified "autoSubmit: false" props
    const getWrapperWithAutoSubmitFalse = (mode: CopilotChatMode, pathname?: string) => {
      const wrapper = ({children}: {children: React.ReactNode}) => {
        const props = getCopilotChatProviderProps()
        return (
          <MemoryRouter
            // eslint-disable-next-line camelcase
            future={{v7_startTransition: true, v7_relativeSplatPath: true}}
            initialEntries={[pathname ?? `/copilot/c/${THREAD_ID}`]}
          >
            <CopilotChatProvider
              {...props}
              copilotChatPayload={{...props.copilotChatPayload, autoSubmit: false}}
              threadId={THREAD_ID}
              mode={mode}
            >
              {children}
            </CopilotChatProvider>
          </MemoryRouter>
        )
      }
      return wrapper
    }

    const {result} = renderHook(() => useChatInput({onSubmit}), {
      wrapper: getWrapperWithAutoSubmitFalse('immersive', '/copilot'),
    })

    await waitFor(() => {
      expect(setSearchParams).toHaveBeenCalledTimes(1)
    })

    const updatedParams = setSearchParams.mock.calls[0]?.[0] as URLSearchParams
    expect(updatedParams?.get('prompt')).toBeNull()

    // Should NOT call onSubmit
    await waitFor(() => {
      expect(onSubmit).not.toHaveBeenCalled()
    })

    // Should set the text but not clear it
    await waitFor(() => {
      expect(result.current.text).toBe('test prompt')
    })
  })
})

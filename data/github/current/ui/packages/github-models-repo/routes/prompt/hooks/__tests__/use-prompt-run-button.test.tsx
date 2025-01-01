// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {CurrentRepositoryProvider} from '@github-ui/current-repository'
import {createRepository} from '@github-ui/current-repository/test-helpers'
import {AzureModelClient} from '@github-ui/github-models/AzureModelClient'
import {AppPayloadContext} from '@github-ui/react-core/use-app-payload'
import {act, renderHook} from '@testing-library/react'
import {type PropsWithChildren, useMemo, useReducer} from 'react'
import {getPromptAppPayload, mockModel} from '../../../../test-utils/mock-data'
import {ModelsProvider} from '../../contexts/ModelsContext'
import {initialPromptCompareState, PromptCompareStateProvider} from '../../contexts/PromptCompareStateContext'
import {PromptCompareManager, PromptCompareManagerContext, promptCompareReducer} from '../../prompt-compare-manager'
import type {PromptConfig} from '../../prompts'
import usePromptRunButton from '../use-prompt-run-button'

const mockModelClient = new AzureModelClient('https://mock-url.com')
const mockSetShowRunVariablesDialog = jest.fn().mockName('setShowRunVariablesDialog')

describe('usePromptRunButton', () => {
  it('canRun is false when there is no prompt messages', () => {
    const {result} = renderHook(() => usePromptRunButton(mockModelClient, mockSetShowRunVariablesDialog), {
      wrapper: ({children}) => (
        <PromptWrapper mockPrompts={[{name: 'Test Prompt', messages: [], model: 'gpt-4o'}]}>{children}</PromptWrapper>
      ),
    })

    expect(result.current.canRun).toBe(false)
  })

  it('canRun is true when there are prompt messages', () => {
    const {result} = renderHook(() => usePromptRunButton(mockModelClient, mockSetShowRunVariablesDialog), {
      wrapper: ({children}) => (
        <PromptWrapper
          mockPrompts={[
            {
              name: 'Test Prompt',
              messages: [{timestamp: new Date(), role: 'user', message: 'Write a nice story'}],
              model: 'gpt-4o',
            },
          ]}
        >
          {children}
        </PromptWrapper>
      ),
    })

    expect(result.current.canRun).toBe(true)
  })

  it('handleRun does not call modelClient.sendMessage if there is no model selected', () => {
    const mockSendMessage = jest.spyOn(mockModelClient, 'sendMessage')
    const {result} = renderHook(() => usePromptRunButton(mockModelClient, mockSetShowRunVariablesDialog), {
      wrapper: ({children}) => (
        <PromptWrapper
          mockPrompts={[
            {
              name: 'Test Prompt',
              messages: [{timestamp: new Date(), role: 'user', message: 'Write a nice story'}],
            },
          ]}
        >
          {children}
        </PromptWrapper>
      ),
    })
    const vars: Record<string, string> = {}
    act(() => {
      result.current.handleRun(vars)
    })
    expect(mockSendMessage).not.toHaveBeenCalled()
    mockSendMessage.mockRestore()
  })

  it('handleRun calls modelClient.sendMessage when there is a model', () => {
    const mockSendMessage = jest.spyOn(mockModelClient, 'sendMessage')
    const {result} = renderHook(() => usePromptRunButton(mockModelClient, mockSetShowRunVariablesDialog), {
      wrapper: ({children}) => (
        <PromptWrapper
          mockPrompts={[
            {
              name: 'Test Prompt',
              messages: [{timestamp: new Date(), role: 'user', message: 'Write a nice story'}],
              model: 'gpt-4o',
            },
          ]}
        >
          {children}
        </PromptWrapper>
      ),
    })
    const vars: Record<string, string> = {}
    act(() => {
      result.current.handleRun(vars)
    })
    expect(mockSendMessage).toHaveBeenCalled()
    mockSendMessage.mockRestore()
  })

  it('opens variable dialog if there are unset variables in the prompt', () => {
    const {result} = renderHook(() => usePromptRunButton(mockModelClient, mockSetShowRunVariablesDialog), {
      wrapper: ({children}) => (
        <PromptWrapper
          mockPrompts={[
            {
              name: 'Test Prompt',
              messages: [{timestamp: new Date(), role: 'user', message: 'Write a nice story with {{input}}'}],
              model: 'gpt-4o',
            },
          ]}
        >
          {children}
        </PromptWrapper>
      ),
    })
    const vars: Record<string, string> = {}
    result.current.handleRun(vars)
    expect(mockSetShowRunVariablesDialog).toHaveBeenCalled()
  })

  it('handleStop executes modelClient.stopStreamingMessages', () => {
    const mockStopStreamingMessages = jest.spyOn(mockModelClient, 'stopStreamingMessages')
    const {result} = renderHook(() => usePromptRunButton(mockModelClient, mockSetShowRunVariablesDialog), {
      wrapper: ({children}) => (
        <PromptWrapper
          mockPrompts={[
            {
              name: 'Test Prompt',
              messages: [{timestamp: new Date(), role: 'user', message: 'Write a nice story'}],
              model: 'gpt-4o',
            },
          ]}
        >
          {children}
        </PromptWrapper>
      ),
    })
    result.current.handleStop()
    expect(mockStopStreamingMessages).toHaveBeenCalled()
    mockStopStreamingMessages.mockRestore()
  })
})

const PromptWrapper = ({children, mockPrompts}: PropsWithChildren<{mockPrompts?: PromptConfig[]}>) => {
  const repository = createRepository()

  const availableModels = [
    mockModel({id: 'gpt-4o', name: 'gpt-4o', friendly_name: 'gpt-4o', original_name: 'gpt-4o'}),
    mockModel(),
  ]
  const prompts = mockPrompts || [
    {
      name: 'Test Prompt',
      messages: [],
    },
  ]

  const [promptCompareState, promptCompareDispatch] = useReducer(
    promptCompareReducer,
    initialPromptCompareState(prompts, {
      compare: {
        isRunning: false,
        rows: [],
        skippedRowIds: new Set<string>(),
        result: [],
        evaluators: [],
      },
    }),
  )

  const appPayload = getPromptAppPayload({payload: {promptPath: '/test-org/test-repo/prompts/new'}})

  const manager = useMemo(() => new PromptCompareManager(promptCompareDispatch), [promptCompareDispatch])

  return (
    <CurrentRepositoryProvider repository={repository}>
      <ModelsProvider models={availableModels}>
        <PromptCompareStateProvider state={promptCompareState}>
          <PromptCompareManagerContext.Provider value={manager}>
            <AppPayloadContext.Provider value={appPayload}>{children}</AppPayloadContext.Provider>
          </PromptCompareManagerContext.Provider>
        </PromptCompareStateProvider>
      </ModelsProvider>
    </CurrentRepositoryProvider>
  )
}

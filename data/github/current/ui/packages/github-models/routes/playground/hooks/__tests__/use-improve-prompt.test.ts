import type {ModelClientSendMessageResponse, PlaygroundMessage, TokenUsageInfo} from '../../../../types'
import {AzureModelClient} from '../../../../utils/azure-model-client'
import {mockModel} from '../../__tests__/mocks'
import {useImprovePrompt} from '../use-improve-prompt'
import {renderHook, waitFor} from '@testing-library/react'

describe('useImprovePrompt', () => {
  it('returns a generated prompt', async () => {
    const promptSuggestionText = 'update prompt'
    const systemPrompt = 'initial prompt'
    const message = 'updated prompt'
    const modelClient = new AzureModelClient('http://localhost:3000')
    const improvedPromptModel = mockModel
    const playgroundMessage = {
      timestamp: new Date(),
      message,
      role: 'assistant',
    } as PlaygroundMessage

    const response: ModelClientSendMessageResponse = {
      message: playgroundMessage,
    }
    modelClient.sendMessage = jest.fn(async function* (): AsyncGenerator<
      ModelClientSendMessageResponse,
      TokenUsageInfo | undefined,
      unknown
    > {
      yield response
      return
    })

    const {result} = renderHook(() =>
      useImprovePrompt(systemPrompt, promptSuggestionText, modelClient, improvedPromptModel, 'system'),
    )

    expect(result.current.generatedPrompt).toEqual(systemPrompt)
    expect(result.current.isLoading).toEqual(true)

    await waitFor(() => expect(result.current.generatedPrompt).toEqual(playgroundMessage.message))
    await waitFor(() => expect(result.current.isLoading).toEqual(false))
  })

  it('returns the current prompt when error occurs', async () => {
    const promptSuggestionText = 'test'
    const systemPrompt = 'test'
    const modelClient = new AzureModelClient('http://localhost:3000')
    const improvedPromptModel = mockModel
    const error = new Error('error message')

    modelClient.sendMessage = jest.fn(async function* (): AsyncGenerator<
      ModelClientSendMessageResponse,
      TokenUsageInfo | undefined,
      unknown
    > {
      yield Promise.reject(error)
      return
    })

    const {result} = renderHook(() =>
      useImprovePrompt(systemPrompt, promptSuggestionText, modelClient, improvedPromptModel, 'system'),
    )

    expect(result.current.generatedPrompt).toEqual(systemPrompt)
    expect(result.current.isLoading).toEqual(true)

    await waitFor(() => expect(result.current.generatedPrompt).toEqual(systemPrompt))
    await waitFor(() => expect(result.current.isLoading).toEqual(false))
  })
})

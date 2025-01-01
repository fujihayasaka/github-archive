// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {renderHook, waitFor} from '@testing-library/react'
import {useExtractedPrompt} from '../use-extracted-prompt'
import {mockModelState} from '../../../playground/__tests__/mocks'
import type {AzureModelClient} from '../../../../utils/azure-model-client'

describe('useExtractedPrompt', () => {
  test('calls sendMessage with the code snippet', async () => {
    const mockPromptHandler = jest.fn((_prompt: string) => {})

    const mockModelClient = {
      sendMessage: jest.fn(async function* () {
        yield {message: 'asdf'}
      }),
    } as unknown as AzureModelClient

    const {result} = renderHook(() =>
      useExtractedPrompt(mockModelState.catalogData, mockModelClient, mockPromptHandler, 'code-snippet'),
    )
    const {extractingPrompt} = result.current
    expect(extractingPrompt).toBe(true)

    await waitFor(() => {
      expect(mockModelClient.sendMessage).toHaveBeenCalled()
    })

    expect(mockPromptHandler).toHaveBeenCalled()
  })

  test('if maybePrompt is undefined, does not call sendMessage', async () => {
    const mockPromptHandler = jest.fn((_prompt: string) => {})

    const mockModelClient = {
      sendMessage: jest.fn(async function* () {
        yield {message: 'asdf'}
      }),
    } as unknown as AzureModelClient

    const {result} = renderHook(() =>
      useExtractedPrompt(mockModelState.catalogData, mockModelClient, mockPromptHandler, undefined),
    )
    const {extractingPrompt} = result.current
    expect(extractingPrompt).toBe(false)
    await waitFor(() => {
      expect(mockModelClient.sendMessage).not.toHaveBeenCalled()
    })

    expect(mockPromptHandler).not.toHaveBeenCalled()
  })
})

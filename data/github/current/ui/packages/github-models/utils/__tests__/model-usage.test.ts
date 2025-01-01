import {mockModelState} from '../../routes/playground/components/__tests__/mocks'
import {tokenUsageFromChunk, tokenUsageFromResponse, updateTokenUsage} from '../model-usage'

describe('Model-Usage', () => {
  afterEach(() => {
    jest.resetAllMocks()
  })

  describe('updateTokenUsage', () => {
    test('sets all token counters and totals', () => {
      const tokenUsage = {
        inputTokens: 5,
        outputTokens: 10,
      }

      const modelState = mockModelState({
        tokenUsage: {
          lastMessageInputTokens: 0,
          totalInputTokens: 100,
          lastMessageOutputTokens: 0,
          totalOutputTokens: 200,
        },
      })

      const result = updateTokenUsage(modelState.tokenUsage, tokenUsage)

      expect(result.lastMessageOutputTokens).toEqual(10)
      expect(result.totalOutputTokens).toEqual(210)
      expect(result.lastMessageInputTokens).toEqual(5)
      expect(result.totalInputTokens).toEqual(105)
    })
  })

  describe('tokenUsageFromResponse', () => {
    test('returns input/output tokens correctly', () => {
      const usage = tokenUsageFromResponse({
        prompt_tokens: 11,
        completion_tokens: 21,
      })

      expect(usage.inputTokens).toEqual(11)
      expect(usage.outputTokens).toEqual(21)
    })
  })

  describe('tokenUsageFromChunk', () => {
    test('returns input/output tokens correctly', () => {
      const token = tokenUsageFromChunk({
        choices: [],
        usage: {
          prompt_tokens: 1,
          completion_tokens: 2,
        },
      })

      expect(token.inputTokens).toEqual(1)
      expect(token.outputTokens).toEqual(2)
    })
  })
})

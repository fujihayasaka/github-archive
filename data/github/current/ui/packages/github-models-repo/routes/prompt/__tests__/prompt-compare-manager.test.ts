import type {AzureModelClient} from '@github-ui/github-models/AzureModelClient'
import type {Model} from '@github-ui/marketplace-common'
import {mockModel as getMockModel} from '../../../test-utils/mock-data'
import {CoherenceEvaluator} from '../evals-sdk/evaluator/builtin/coherence'
import {PromptCompareManager} from '../prompt-compare-manager'
import type {PromptCompareStateAction} from '../prompt-compare-state'

const createManager = () => {
  const dispatch = jest.fn()
  const manager = new PromptCompareManager(dispatch)
  return {dispatch, manager}
}

describe('PromptCompareManager', () => {
  describe('forkPrompt', () => {
    it('calls dispatch with the correct action', () => {
      const {dispatch, manager} = createManager()

      manager.forkPrompt()

      expect(dispatch).toHaveBeenCalledWith<[PromptCompareStateAction]>({
        type: 'FORK_ORIGINAL_PROMPT',
      })
    })
  })

  describe('addEvaluator', () => {
    it('calls dispatch with the correct action', () => {
      const {dispatch, manager} = createManager()

      manager.evalsAddEvaluator({
        config: CoherenceEvaluator,
        readonly: true,
      })

      expect(dispatch).toHaveBeenCalledWith<[PromptCompareStateAction]>({
        type: 'EVAL_ADD_EVALUATOR',
        evaluator: {
          config: CoherenceEvaluator,
          readonly: true,
        },
      })
    })
  })

  describe('updateEvaluator', () => {
    it('calls dispatch with the correct action', () => {
      const {dispatch, manager} = createManager()

      manager.evalsUpdateEvaluator(1, {
        name: 'new name',
      })

      expect(dispatch).toHaveBeenCalledWith<[PromptCompareStateAction]>({
        type: 'EVAL_UPDATE_EVALUATOR',
        payload: {
          index: 1,
          evaluator: {
            name: 'new name',
          },
        },
      })
    })
  })

  describe('removeEvaluator', () => {
    it('calls dispatch with the correct action', () => {
      const {dispatch, manager} = createManager()

      manager.evalsRemoveEvaluator(1)

      expect(dispatch).toHaveBeenCalledWith<[PromptCompareStateAction]>({
        type: 'EVAL_REMOVE_EVALUATOR',
        index: 1,
      })
    })
  })

  describe('updatePromptPath', () => {
    it('calls dispatch with the correct action', () => {
      const {dispatch, manager} = createManager()
      const path = 'new/path/to/prompt'
      manager.updatePromptPath(path)
      expect(dispatch).toHaveBeenCalledWith<[PromptCompareStateAction]>({
        type: 'UPDATE_PROMPT_PATH',
        payload: {
          path,
        },
      })
    })
  })

  describe('sendMessage', () => {
    it('parameters are passed to client', async () => {
      const {manager} = createManager()

      const mockModel = 'gpt-4o' as unknown as Model
      const mockModelClient = {
        sendMessage: jest.fn(async function* () {
          yield {message: 'some response'}
        }),
      } as unknown as AzureModelClient

      await manager.sendMessage(mockModel, mockModelClient, undefined, 'user prompt', {
        max_tokens: 42,
      })

      expect(mockModelClient.sendMessage).toHaveBeenCalledWith(
        0,
        mockModel,
        expect.any(Array),
        {max_tokens: 42},
        '',
        'text',
        undefined,
      )
    })

    it('removes system prompt is not supported and sent', async () => {
      const {manager} = createManager()

      const mockModel = getMockModel({capabilities: {systemPrompt: false}}) as Model
      const mockModelClient = {
        sendMessage: jest.fn(async function* () {
          yield {message: 'some response'}
        }),
      } as unknown as AzureModelClient

      await manager.sendMessage(mockModel, mockModelClient, 'This is a system prompt!', 'user prompt', {
        max_tokens: 42,
      })

      expect(mockModelClient.sendMessage).toHaveBeenCalledWith(
        0,
        mockModel,
        expect.any(Array),
        {max_tokens: 42},
        '',
        'text',
        undefined,
      )
    })

    it('does not remove system prompt when supported and sent', async () => {
      const {manager} = createManager()

      const mockModel = getMockModel({capabilities: {systemPrompt: true}}) as Model
      const mockModelClient = {
        sendMessage: jest.fn(async function* () {
          yield {message: 'some response'}
        }),
      } as unknown as AzureModelClient

      await manager.sendMessage(mockModel, mockModelClient, 'This is a system prompt!', 'user prompt', {
        max_tokens: 42,
      })

      expect(mockModelClient.sendMessage).toHaveBeenCalledWith(
        0,
        mockModel,
        expect.any(Array),
        {max_tokens: 42},
        'This is a system prompt!',
        'text',
        undefined,
      )
    })
  })
})

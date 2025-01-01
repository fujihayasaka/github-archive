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
})

import {initialPromptCompareState} from '../contexts/PromptCompareStateContext'
import {promptCompareReducer} from '../prompt-compare-manager'
import type {CompareState} from '../prompt-compare-state'
import type {PromptConfig} from '../prompts'

describe('promptCompareReducer', () => {
  describe('FORK_ORIGINAL_PROMPT', () => {
    it('forks original prompt', () => {
      const newState = promptCompareReducer(
        initialPromptCompareState([
          {
            model: 'gpt-4',
            messages: [
              {
                timestamp: new Date(),
                role: 'user',
                message: 'Hello',
              },
            ],
          },
        ] as PromptConfig[]),
        {
          type: 'FORK_ORIGINAL_PROMPT',
        },
      )

      expect(newState.prompts).toHaveLength(2)
      expect(newState.prompts[1]).toEqual(newState.prompts[0])
    })

    it('raises error when no original prompt', () => {
      // This should not happen, but test just to be sure
      expect(() =>
        promptCompareReducer(initialPromptCompareState([]), {
          type: 'FORK_ORIGINAL_PROMPT',
        }),
      ).toThrow()
    })
  })

  describe('ADD_EVALUATOR', () => {
    it('adds new evaluator at the end', () => {
      const newState = promptCompareReducer(
        initialPromptCompareState([], {
          compare: {
            evaluators: [
              {
                config: {
                  name: 'eval 1',
                },
              },
            ],
          } as CompareState,
        }),
        {
          type: 'EVAL_ADD_EVALUATOR',
          evaluator: {
            config: {
              name: 'new eval',
            },
          },
        },
      )

      expect(newState.compare.evaluators).toHaveLength(2)
      expect(newState.compare.evaluators[0]!.config.name).toEqual('eval 1')
      expect(newState.compare.evaluators[1]!.config.name).toEqual('new eval')
    })
  })

  describe('UPDATE_EVALUATOR', () => {
    it('updates evaluator', () => {
      const newState = promptCompareReducer(
        initialPromptCompareState([], {
          compare: {
            evaluators: [
              {
                config: {
                  name: 'eval 1',
                },
              },
            ],
          } as CompareState,
        }),
        {
          type: 'EVAL_UPDATE_EVALUATOR',
          payload: {
            index: 0,
            evaluator: {
              name: 'new name',
            },
          },
        },
      )

      expect(newState.compare.evaluators).toHaveLength(1)
      expect(newState.compare.evaluators[0]!).toEqual({
        config: {
          name: 'new name',
        },
      })
    })
  })

  describe('REMOVE_EVALUATOR', () => {
    it('removes only evaluator', () => {
      const newState = promptCompareReducer(
        initialPromptCompareState([], {
          compare: {
            evaluators: [
              {
                config: {
                  name: 'eval 1',
                },
              },
            ],
          } as CompareState,
        }),
        {
          type: 'EVAL_REMOVE_EVALUATOR',
          index: 0,
        },
      )

      expect(newState.compare.evaluators).toHaveLength(0)
    })

    it('removes evaluator in the middle', () => {
      const newState = promptCompareReducer(
        initialPromptCompareState([], {
          compare: {
            evaluators: [
              {
                config: {
                  name: 'eval 1',
                },
              },
              {
                config: {
                  name: 'eval 2',
                },
              },
              {
                config: {
                  name: 'eval 3',
                },
              },
            ],
          } as CompareState,
        }),
        {
          type: 'EVAL_REMOVE_EVALUATOR',
          index: 1,
        },
      )

      expect(newState.compare.evaluators).toHaveLength(2)
      expect(newState.compare.evaluators[0]!.config.name).toEqual('eval 1')
      expect(newState.compare.evaluators[1]!.config.name).toEqual('eval 3')
    })
  })
})

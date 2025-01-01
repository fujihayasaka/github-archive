import {LLMEvaluator} from '../llm'
import type {EvaluatorLLM} from '../../config'
import type {EvalOptions} from '../../options'
import type {Message} from '../../../types'

describe('LLMEvaluator', () => {
  it('returns pass=true when the model output matches a positive choice', async () => {
    const cfg: EvaluatorLLM = {
      modelId: 'dummy-model',
      modelParameters: {},
      prompt: 'Evaluate: {{prompt}}',
      systemPrompt: 'Answer YES or NO.',
      choices: [
        {choice: 'YES', score: 1},
        {choice: 'NO', score: 0},
      ],
    } as any

    const sendMessages = jest.fn().mockResolvedValue({
      completions: [{message: 'YES'}],
    })

    const options: EvalOptions = {
      api: {sendMessages},
    } as any

    const evaluator = new LLMEvaluator('test-evaluator', cfg, options)

    const prompt: Message[] = [{timestamp: new Date(), role: 'user', message: 'The sky is blue.'}]
    const completion: Message = {
      timestamp: new Date(),
      role: 'assistant',
      message: 'Hmm, let me think... not NO, so YES!', // note that both choices occur in the message
    }

    const result = await evaluator.evaluate(prompt, completion, {id: 1} as any)
    expect(sendMessages).toHaveBeenCalled()
    expect(result).toEqual({pass: true})
  })
})

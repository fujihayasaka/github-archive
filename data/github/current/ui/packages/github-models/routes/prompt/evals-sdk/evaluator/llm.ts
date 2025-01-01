import type {EvalOptions} from '../options'
import type {Message} from '../api'
import type {Choice, DataRow, EvaluatorLLM} from '../config'
import {replaceVars} from '../variables'
import type {EvaluationResult, Evaluator} from './evaluator'

export class LLMEvaluator implements Evaluator {
  readonly name: string
  private cfg: EvaluatorLLM
  private options: EvalOptions

  constructor(name: string, cfg: EvaluatorLLM, options: EvalOptions) {
    this.name = name
    this.cfg = cfg
    this.options = options
  }

  async evaluate(prompt: Message[], completion: Message, row: DataRow, s?: AbortSignal): Promise<EvaluationResult> {
    const firstUserPrompt = prompt.find(x => x.role === 'user')!.message

    // Replace with any variables
    const vars = {
      ...row,
      prompt: firstUserPrompt,
      completion: completion.message,
    }

    const evalPrompt = replaceVars(this.cfg.prompt, vars)

    const messages: Message[] = []

    if (this.cfg.systemPrompt) {
      messages.push({
        timestamp: new Date(),
        role: 'system',
        message: this.cfg.systemPrompt,
      })
    }

    messages.push({
      timestamp: new Date(),
      role: 'user',
      message: evalPrompt,
    })

    const result = await this.options.api.sendMessages(this.cfg.modelId, this.cfg.modelParameters, messages, s)

    if (!result || result.length === 0) {
      throw new Error('Completion for LLM evaluator is empty')
    }

    const msgResult = result[0]!.message

    // Map result to choice
    const choice = this.findChoice(msgResult)
    if (!choice) {
      return {
        error: 'No choice found in completion',
      }
    }

    // Try to map to result
    if (this.cfg.choices.length === 2) {
      // Assume this is pass/fail. We need to revisit this.
      return {
        pass: choice.score > 0,
      }
    }

    return {
      score: choice.score,
    }
  }

  private findChoice(output: string): Choice | undefined {
    return this.cfg.choices.find(x => x.choice === output)
  }
}

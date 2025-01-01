import type {EvalOptions} from '../options'
import type {EvaluationResult, Message} from '../../types'
import type {Choice, DataRow, EvaluatorLLM} from '../config'
import {replaceVars} from '../variables'
import type {Evaluator} from './evaluator'

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
      id: row.id.toString(), // replaceVars expects all values to be string
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

    if (!result || result.completions.length === 0) {
      throw new Error('Completion for LLM evaluator is empty')
    }

    const msgResult = result.completions[0]!.message

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

  // Map the output to a choice by searching for the choice string in the output.
  // To accommodate model chain-of-thought, we search for the last occurrence of the choice string in the output.
  private findChoice(output: string): Choice | undefined {
    const exact = this.cfg.choices.find(c => c.choice === output.trim())
    if (exact) return exact

    const candidates = this.cfg.choices
      .map(c => ({pos: output.lastIndexOf(c.choice), c}))
      .filter(x => x.pos !== -1) // filter out choices that are not in the output
      .sort((a, b) => b.pos - a.pos) // sort by position, so the last occurrence is first

    return candidates[0]?.c
  }
}

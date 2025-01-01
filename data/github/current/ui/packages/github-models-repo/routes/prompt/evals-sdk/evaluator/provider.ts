import type {EvaluatorCfg} from '../config'
import type {EvalOptions} from '../options'
import {BuiltIn} from './builtin/builtin'
import type {Evaluator} from './evaluator'
import {LLMEvaluator} from './llm'
import {StringEvaluator} from './string'

export async function getEvaluator(e: EvaluatorCfg, options: EvalOptions): Promise<Evaluator> {
  if (e.uses) {
    // For now only built-in evaluators referenced in the `github` namespace are supported
    const segments = e.uses.split('/')
    if (segments.length > 1 && segments[0] === 'github') {
      const builtInConfig = BuiltIn[segments[1]!]
      if (builtInConfig) {
        return getEvaluator(builtInConfig, options)
      }
    }
  }

  if (e.string) {
    return new StringEvaluator(e.name, e.string)
  }

  if (e.llm) {
    return new LLMEvaluator(e.name, e.llm, options)
  }

  throw new Error('Not implemented')
}

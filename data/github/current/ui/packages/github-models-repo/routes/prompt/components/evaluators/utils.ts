import type {EvaluatorCfg, EvaluatorLLM, EvaluatorString} from '../../evals-sdk/config'

export function validateLLMEvaluator(e: EvaluatorLLM): string | null {
  if (!e.prompt) {
    return 'Prompt is required'
  }

  if (!e.modelId) {
    return 'Model is required'
  }

  if (e.choices.length === 0) {
    return 'At least one choice is required'
  }

  if (e.choices.some(c => c.choice === '')) {
    return 'All choices must have a value'
  }

  if (e.choices.every(c => c.score === 0)) {
    return 'At least one choice must have a score > 0'
  }

  return null
}

export function validateStringCheck(e: EvaluatorString): string | null {
  if (!e.contains && !e.startsWith && !e.endsWith) {
    return 'Value is required'
  }

  return null
}

export function validate(config: EvaluatorCfg): string | null {
  if (!config.name) {
    return 'Name is required'
  }

  if (config.string) {
    return validateStringCheck(config.string)
  }

  if (config.llm) {
    return validateLLMEvaluator(config.llm)
  }

  return null
}

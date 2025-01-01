import type {Model} from '@github-ui/marketplace-common'
import {o1ModelNames} from './playground-types'
import {isFeatureEnabled} from '@github-ui/feature-flags'

export function supportsStreaming(model: Model) {
  if (model.name === 'o3-mini' && isFeatureEnabled('github_models_o3_mini_streaming')) {
    return true
  }
  return !o1ModelNames.includes(model.name)
}

export function supportsTokenCounting(model: Model) {
  return !o1ModelNames.includes(model.name)
}

export function supportsStructuredOutput(model: Model) {
  // o1 models currently don't support structured output at all
  if (o1ModelNames.includes(model.name)) {
    return false
  }

  // all models 'support' JSON output, but some of them are not trained on enough JSON
  // to be able to actually do it without spinning forever and outputting \n tokens
  const publisher = model.publisher.toLowerCase()
  if (publisher === 'openai' || publisher === 'mistral ai') {
    return true
  }

  return false
}

export function supportsJsonSchemaStructuredOutput(model: Model) {
  // currently only GPT-4o supports JSON Schema Structured Output
  return model.name.toLowerCase() === 'gpt-4o'
}

export function supportsStreamingOptions(model: Model): boolean {
  return model.publisher.toLowerCase() === 'openai'
}

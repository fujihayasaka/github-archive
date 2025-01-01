import {modelsWithJsonSchemaSupport} from './playground-types'

// TODO: This entire file needs to be migrated to a more dynamic way of setting these capabilities
// ref: https://github.com/github/models/issues/1898

export function supportsJsonSchemaStructuredOutput(model: {name: string}) {
  const modelName = model.name.toLowerCase()

  return modelsWithJsonSchemaSupport.includes(modelName)
}

export function supportsStreamingOptions(model: {publisher: string}): boolean {
  return model.publisher.toLowerCase() === 'openai'
}

// Keep in sync with `CustomModelsIndexPayload` in app/controllers/github_models/organization_custom_models_controller.rb
export interface CustomModelsIndexPayload {
  publicKey: [version: number, base64EncodedKey: string]
  orgDisplayLogin: string
  customKeys: CustomKey[]
  customModels: CustomModel[]
}

export type CustomModelsIndexTabs = 'keys' | 'models'

export interface CustomModelsIndexMutationData {
  name: string
}

export type CustomKey = {
  id: number
  name: string
  provider: Provider['key']
  totalModels: number
}

export type Provider = {name: 'OpenAI'; key: 'openai'} | {name: 'Azure AI'; key: 'azureai'}

export type CustomModel = {
  id: number
  slug: string
  name?: string
  customKeyId: CustomKey['id']
  enabled: ModelEnabled
}

// Keep in sync with `CustomModelEnabled` in packages/models_byok/app/public/models_byok/types.rb
export type ModelEnabled = {
  copilot: boolean
  models: boolean
}

export type SelectorCustomModel = {
  slug: string
  name?: string
  deprecated?: boolean
  fresh?: boolean
  createdAt?: number
}

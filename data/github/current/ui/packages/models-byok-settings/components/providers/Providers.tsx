import type {ComponentType} from 'react'
import invariant from 'tiny-invariant'

import type {Provider} from '../../types'
import {AzureAIFields, azureFormSchema} from './AzureAI'
import {OpenAIFields, openaiFormSchema} from './OpenAI'
import type {ProviderFieldProps} from './ProvidersFields'

export const providerList = [
  {
    key: 'openai',
    name: 'OpenAI',
  },
  {
    key: 'azureai',
    name: 'Azure AI',
  },
] as const satisfies Provider[]

export function getProviderFor(key: (typeof providerList)[number]['key']): Provider {
  const provider = providerList.find(p => p.key === key)
  invariant(provider, `Provider with key "${key}" not found`)
  return provider
}

export const providerSchema = [openaiFormSchema, azureFormSchema] as const

export const providerFields = {
  azureai: AzureAIFields,
  openai: OpenAIFields,
} as const satisfies {
  [key in (typeof providerList)[number]['key']]: ComponentType<ProviderFieldProps>
}

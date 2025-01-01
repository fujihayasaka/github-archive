import {newKeyPair} from '@github-ui/encryption/test-helpers'
import {encode} from '@github-ui/encryption/utils'
import {http, HttpResponse} from 'msw'

import {providerList} from '../components/providers/Providers'
import {customModelsIndexRoute} from '../routes/CustomModelsIndex/custom-models-index-route'
import type {
  CustomKey,
  CustomModel,
  CustomModelsIndexMutationData,
  CustomModelsIndexPayload,
  Provider,
  SelectorCustomModel,
} from '../types'

export function mockCustomModelsIndexPayload(overrides: Partial<CustomModelsIndexPayload> = {}) {
  const defaults: CustomModelsIndexPayload = {
    publicKey: [1, getMockPublicKey()],
    orgDisplayLogin: 'someOrg',
    customKeys: mockCustomKeys(),
    customModels: mockCustomModels(),
  }
  return {...defaults, ...overrides}
}

export function getProviders(): Provider[] {
  return providerList
}

export function mockCustomModel(overrides: Partial<CustomModel> = {}): CustomModel {
  const defaults: CustomModel = {slug: 'phi-3.5', customKeyId: 1, id: 1, enabled: {copilot: true, models: true}}
  return Object.assign(defaults, overrides)
}

export function mockCustomModels(): CustomModel[] {
  return [
    {slug: 'phi-3.5', customKeyId: 1, id: 1, enabled: {copilot: true, models: true}},
    {slug: 'phi-3.5-mini', customKeyId: 1, id: 2, enabled: {copilot: false, models: true}},
    {slug: 'phi-3', customKeyId: 1, id: 3, enabled: {copilot: true, models: false}},
    {slug: 'phi-3-mini', customKeyId: 1, id: 4, enabled: {copilot: false, models: false}},
    {slug: 'gpt-4.1', customKeyId: 1, id: 5, enabled: {copilot: true, models: true}},
    {slug: 'o1', customKeyId: 2, id: 6, enabled: {copilot: true, models: false}},
    {slug: 'o1-mini', customKeyId: 2, id: 7, enabled: {copilot: false, models: true}},
    {slug: 'gpt-4', customKeyId: 2, id: 8, enabled: {copilot: false, models: true}},
    {slug: 'o3', customKeyId: 2, id: 9, enabled: {copilot: false, models: false}},
    {slug: 'o3-mini', customKeyId: 2, id: 10, enabled: {copilot: false, models: false}},
  ]
}

export function mockSelectorModel(overrides: Partial<SelectorCustomModel> = {}): SelectorCustomModel {
  return Object.assign(
    {
      slug: overrides?.slug ?? 'NAME',
    } satisfies SelectorCustomModel,
    overrides,
  )
}

export function getMockPublicKey() {
  return encode(newKeyPair().publicKey)
}

export const customModelsIndexRouteHandlers = [
  http.post(customModelsIndexRoute.path, async ({request}) => {
    const body = (await request.json()) as CustomModelsIndexMutationData
    return HttpResponse.json({name: body['name']})
  }),
]

export function mockCustomKey(overrides: Partial<CustomKey> = {}): CustomKey {
  const defaults: CustomKey = {
    id: 1,
    name: 'Example OpenAI Key',
    provider: 'openai',
    totalModels: 0,
  }
  return Object.assign(defaults, overrides)
}

export const mockCustomKeys = (): CustomKey[] => [
  mockCustomKey({id: 1, name: 'Example OpenAI Key', provider: 'openai'}),
  mockCustomKey({id: 2, name: 'Example MSFT Key', provider: 'azureai'}),
]

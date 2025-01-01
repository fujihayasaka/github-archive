import {delay, http, HttpResponse} from 'msw'
import type {AccessPolicyShowPayload, Model, OrganizationAccessPolicy, Publisher} from '../types'

const mockModels: Model[] = [
  mockModel(),
  mockModel({key: 'azureml/bar', name: 'Bar', publisherId: 2}),
  mockModel({key: 'azureml/baz', name: 'Baz', publisherId: 1}),
]

export function mockOrganizationAccessPolicy(overrides: Partial<OrganizationAccessPolicy> = {}) {
  const defaults: OrganizationAccessPolicy = {
    isAllowlist: false,
    isModelsEnabled: true,
    isAccessConfigurable: true,
    allowedModelKeys: mockModels.map(model => model.key),
    allowedCustomModelIds: [],
  }
  return {...defaults, ...overrides}
}

export function mockModel(overrides: Partial<Model> = {}) {
  const defaults: Model = {
    key: 'azureml/foo',
    registry: 'openai',
    name: 'foo',
    friendlyName: 'Foo',
    publisherId: 1,
  }
  return {...defaults, ...overrides}
}

export function mockPublisher(overrides: Partial<Publisher> = {}) {
  const defaults: Publisher = {
    id: 1,
    name: 'OpenAI',
    logoUrl: '/images/modules/marketplace/models/families/openai.svg',
    darkModeIcon: null,
    lightModeIcon: null,
    totalModels: 1,
  }
  return {...defaults, ...overrides}
}

export function mockAccessPolicyShowPayload(overrides: Partial<AccessPolicyShowPayload> = {}) {
  const defaults: AccessPolicyShowPayload = {
    billingEnabled: false,
    policy: mockOrganizationAccessPolicy(),
    orgDisplayLogin: 'someOrg',
    publishers: [
      mockPublisher({id: 1}),
      mockPublisher({id: 2, name: 'Meta', logoUrl: '/images/modules/marketplace/models/families/meta.svg'}),
    ],
    models: mockModels,
    canEnableModelsBilling: true,
  }
  return {...defaults, ...overrides}
}

interface MockHandlersProps {
  pathname: string
  initialPolicy?: OrganizationAccessPolicy
  type?: 'success' | 'loading' | 'error'
}

export function mockHandlers({pathname, initialPolicy, type = 'success'}: MockHandlersProps) {
  if (type === 'success') {
    return [
      http.post(pathname, async ({request}) => {
        const policyOverrides: Partial<OrganizationAccessPolicy> = Object.assign({}, initialPolicy, {
          isModelsEnabled: true,
          isAllowlist: false,
        })
        const body = await request.json()
        if (body && typeof body === 'object') {
          if ('model_slugs' in body) {
            if (!policyOverrides.allowedModelKeys) policyOverrides.allowedModelKeys = []
            policyOverrides.allowedModelKeys = policyOverrides.allowedModelKeys.concat(body.model_slugs)
            policyOverrides.isAllowlist = true
          }
        }
        return HttpResponse.json(mockOrganizationAccessPolicy(policyOverrides), {status: 201})
      }),
      http.delete(pathname, async ({request}) => {
        const policyOverrides: Partial<OrganizationAccessPolicy> = Object.assign({}, initialPolicy, {
          isModelsEnabled: false,
          isAllowlist: true,
        })
        const body = await request.json()
        if (body && typeof body === 'object') {
          if ('model_slugs' in body) {
            if (!policyOverrides.allowedModelKeys) policyOverrides.allowedModelKeys = []
            policyOverrides.allowedModelKeys = policyOverrides.allowedModelKeys.filter(
              key => !body.model_slugs.includes(key),
            )
          }
        }
        return HttpResponse.json(mockOrganizationAccessPolicy(policyOverrides))
      }),
    ]
  }

  if (type === 'error') {
    return [
      http.post(pathname, () =>
        HttpResponse.json(mockOrganizationAccessPolicy({isModelsEnabled: false, isAllowlist: true}), {status: 422}),
      ),
      http.delete(pathname, () =>
        HttpResponse.json(mockOrganizationAccessPolicy({isModelsEnabled: true, isAllowlist: false}), {status: 422}),
      ),
    ]
  }

  return [
    http.post(pathname, async () => {
      await delay('infinite')
      return new HttpResponse('never')
    }),
    http.delete(pathname, async () => {
      await delay('infinite')
      return new HttpResponse('never')
    }),
  ]
}

export function mockBillingHandlers({pathname, type = 'success'}: MockHandlersProps) {
  if (type === 'success') {
    return [
      http.post(pathname, async ({request}) => {
        const override = {billingEnabled: true}
        const body = await request.json()

        if (body && typeof body === 'object') {
          if ('enable' in body) {
            override.billingEnabled = body.enable === '1'
          }
        }

        return HttpResponse.json(mockAccessPolicyShowPayload(override), {status: 201})
      }),
    ]
  }

  if (type === 'error') {
    return [
      http.post(pathname, () => HttpResponse.json(mockAccessPolicyShowPayload({billingEnabled: false}), {status: 422})),
    ]
  }

  return [
    http.post(pathname, async () => {
      await delay('infinite')
      return new HttpResponse('never')
    }),
  ]
}

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
    allowedModelKeys: mockModels.map(model => model.key),
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
    policy: mockOrganizationAccessPolicy(),
    orgDisplayLogin: 'someOrg',
    publishers: [
      mockPublisher({id: 1}),
      mockPublisher({id: 2, name: 'Meta', logoUrl: '/images/modules/marketplace/models/families/meta.svg'}),
    ],
    models: mockModels,
  }
  return {...defaults, ...overrides}
}

export function mockResizeObserver() {
  class MockResizeObserver implements ResizeObserver {
    observe() {}
    unobserve() {}
    disconnect() {}
  }
  Object.defineProperty(window, 'ResizeObserver', {writable: true, configurable: true, value: MockResizeObserver})
}

export function setupMatchMediaMock() {
  /**
   * Required for internal usage of matchMedia in primer/react
   * Duplicated from ui/packages/jest/jest-setup.ts
   * this is not implemented in JSDOM, and until it is we'll need to polyfill
   */
  Object.defineProperty(window, 'matchMedia', {
    writable: true,
    value: jest.fn().mockImplementation(query => {
      return {
        matches: false,
        media: query,
        onchange: null,
        addListener: jest.fn(), // deprecated
        removeListener: jest.fn(), // deprecated
        addEventListener: jest.fn(),
        removeEventListener: jest.fn(),
        dispatchEvent: jest.fn(),
      }
    }),
  })
}

export function mockHandlers({pathname, type = 'success'}: {pathname: string; type?: 'success' | 'loading' | 'error'}) {
  if (type === 'success') {
    return [
      http.post(pathname, () =>
        HttpResponse.json(mockOrganizationAccessPolicy({isModelsEnabled: true, isAllowlist: false}), {status: 201}),
      ),
      http.delete(pathname, () =>
        HttpResponse.json(mockOrganizationAccessPolicy({isModelsEnabled: false, isAllowlist: true})),
      ),
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

import {delay, http, HttpResponse} from 'msw'
import type {RepositoryAccessPolicy, RepositoryAccessPolicyShowPayload} from '../types'

export function mockAccessPolicy(overrides: Partial<RepositoryAccessPolicy> = {}) {
  const defaults: RepositoryAccessPolicy = {
    isRepoModelsEnabled: false,
  }
  return {...defaults, ...overrides}
}

export function mockAccessPolicyShowPayload(overrides: Partial<RepositoryAccessPolicyShowPayload> = {}) {
  const defaults: RepositoryAccessPolicyShowPayload = {
    ownerDisplayLogin: 'theGoogOrg',
    repositoryName: 'theGoodRepo',
    isAccessConfigurable: true,
    repositoryOwnerType: 'organization',
    repositoryAccessPolicy: mockAccessPolicy(),
  }
  return {...defaults, ...overrides}
}

interface MockHandlersProps {
  pathname: string
  initialPolicy?: RepositoryAccessPolicy
  type?: 'success' | 'loading' | 'error'
}

export function mockHandlers({pathname, initialPolicy, type = 'success'}: MockHandlersProps) {
  if (type === 'success') {
    return [
      http.post(pathname, async () => {
        const policyOverrides: Partial<RepositoryAccessPolicy> = Object.assign({}, initialPolicy, {
          isRepoModelsEnabled: true,
        })

        return HttpResponse.json(mockAccessPolicy(policyOverrides), {status: 201})
      }),
      http.delete(pathname, async () => {
        const policyOverrides: Partial<RepositoryAccessPolicy> = Object.assign({}, initialPolicy, {
          isRepoModelsEnabled: false,
        })
        return HttpResponse.json(mockAccessPolicy(policyOverrides))
      }),
    ]
  }

  if (type === 'error') {
    return [
      http.post(pathname, () => HttpResponse.json(mockAccessPolicy({isRepoModelsEnabled: false}), {status: 422})),
      http.delete(pathname, () => HttpResponse.json(mockAccessPolicy({isRepoModelsEnabled: true}), {status: 422})),
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

export function mockResizeObserver() {
  class MockResizeObserver implements ResizeObserver {
    observe() {}
    unobserve() {}
    disconnect() {}
  }
  Object.defineProperty(window, 'ResizeObserver', {writable: true, configurable: true, value: MockResizeObserver})
}

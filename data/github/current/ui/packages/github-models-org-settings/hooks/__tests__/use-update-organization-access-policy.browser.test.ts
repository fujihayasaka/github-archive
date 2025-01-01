import {describe, it, expect, afterEach} from '@github-ui/tests'
import {vi} from 'vitest'
import {renderHook} from '@testing-library/react'
import {withBaseProvidersWrapper} from '@github-ui/react-core/test-utils'
import {
  disableOrgModelsPayload,
  enableOrgModelsPayload,
  allowOrgModelsPayload,
  restrictOrgModelsPayload,
  useUpdateOrganizationAccessPolicy,
} from '../use-update-organization-access-policy'
import type {UpdateOrganizationAccessPolicyPayload} from '../../types'
import {mockOrganizationAccessPolicy} from '../../test-utils/mocks'

const mockVerifiedFetchJSON = vi.fn().mockName('verifiedFetchJSON')
const setPendingUpdateType = vi.fn().mockName('setPendingUpdateType')

vi.mock('@github-ui/verified-fetch', () => {
  return {
    verifiedFetchJSON: (...args: unknown[]) => mockVerifiedFetchJSON(...args),
    reactFetchJSON: (...args: unknown[]) => mockVerifiedFetchJSON(...args),
  }
})

describe('useUpdateOrganizationAccessPolicy', () => {
  afterEach(() => {
    vi.resetAllMocks()
  })

  const orgDisplayLogin = 'some-org'

  it('disables Models access for the org', async () => {
    mockVerifiedFetchJSON.mockResolvedValue({
      ok: true,
      json: () => mockOrganizationAccessPolicy({isModelsEnabled: false, isAllowlist: true}),
    })

    await mutateAsync(orgDisplayLogin, disableOrgModelsPayload())

    expect(mockVerifiedFetchJSON).toHaveBeenCalledTimes(1)
    expect(mockVerifiedFetchJSON).toHaveBeenCalledWith(
      `/organizations/${orgDisplayLogin}/settings/models/access-policy`,
      {method: 'DELETE', body: {disable: '1'}},
    )
    expect(setPendingUpdateType).toHaveBeenCalledTimes(1)
    expect(setPendingUpdateType).toHaveBeenCalledWith('global-toggle')
  })

  it('enables Models access for the org', async () => {
    mockVerifiedFetchJSON.mockResolvedValue({
      ok: true,
      json: () => mockOrganizationAccessPolicy({isModelsEnabled: true, isAllowlist: false}),
    })

    await mutateAsync(orgDisplayLogin, enableOrgModelsPayload())

    expect(mockVerifiedFetchJSON).toHaveBeenCalledTimes(1)
    expect(mockVerifiedFetchJSON).toHaveBeenCalledWith(
      `/organizations/${orgDisplayLogin}/settings/models/access-policy`,
      {method: 'POST', body: {enable: '1'}},
    )
    expect(setPendingUpdateType).toHaveBeenCalledTimes(1)
    expect(setPendingUpdateType).toHaveBeenCalledWith('global-toggle')
  })

  it('restricts Models access for the org', async () => {
    mockVerifiedFetchJSON.mockResolvedValue({
      ok: true,
      json: () => mockOrganizationAccessPolicy({isModelsEnabled: true, isAllowlist: true}),
    })

    await mutateAsync(orgDisplayLogin, restrictOrgModelsPayload())

    expect(mockVerifiedFetchJSON).toHaveBeenCalledTimes(1)
    expect(mockVerifiedFetchJSON).toHaveBeenCalledWith(
      `/organizations/${orgDisplayLogin}/settings/models/access-policy`,
      {method: 'DELETE', body: {}},
    )
    expect(setPendingUpdateType).toHaveBeenCalledTimes(1)
    expect(setPendingUpdateType).toHaveBeenCalledWith('list-type')
  })

  it('switches the org to using a block list instead of an allow list', async () => {
    mockVerifiedFetchJSON.mockResolvedValue({
      ok: true,
      json: () => mockOrganizationAccessPolicy({isModelsEnabled: true, isAllowlist: false}),
    })

    await mutateAsync(orgDisplayLogin, allowOrgModelsPayload())

    expect(mockVerifiedFetchJSON).toHaveBeenCalledTimes(1)
    expect(mockVerifiedFetchJSON).toHaveBeenCalledWith(
      `/organizations/${orgDisplayLogin}/settings/models/access-policy`,
      {method: 'POST', body: {}},
    )
    expect(setPendingUpdateType).toHaveBeenCalledTimes(1)
    expect(setPendingUpdateType).toHaveBeenCalledWith('list-type')
  })

  it('disables a model for the org', async () => {
    mockVerifiedFetchJSON.mockResolvedValue({
      ok: true,
      json: () => mockOrganizationAccessPolicy({isModelsEnabled: true, allowedModelKeys: []}),
    })

    await mutateAsync(orgDisplayLogin, restrictOrgModelsPayload({modelKeys: ['openai/foo']}))

    expect(mockVerifiedFetchJSON).toHaveBeenCalledTimes(1)
    expect(mockVerifiedFetchJSON).toHaveBeenCalledWith(
      `/organizations/${orgDisplayLogin}/settings/models/access-policy`,
      {method: 'DELETE', body: {model_slugs: ['openai/foo']}},
    )
    expect(setPendingUpdateType).toHaveBeenCalledTimes(1)
    expect(setPendingUpdateType).toHaveBeenCalledWith('rules')
  })

  it('enables a model for the org', async () => {
    mockVerifiedFetchJSON.mockResolvedValue({
      ok: true,
      json: () =>
        mockOrganizationAccessPolicy({
          isModelsEnabled: true,
          isAllowlist: true,
          allowedModelKeys: ['msft/bar'],
        }),
    })

    await mutateAsync(orgDisplayLogin, allowOrgModelsPayload({modelKeys: ['msft/bar']}))

    expect(mockVerifiedFetchJSON).toHaveBeenCalledTimes(1)
    expect(mockVerifiedFetchJSON).toHaveBeenCalledWith(
      `/organizations/${orgDisplayLogin}/settings/models/access-policy`,
      {method: 'POST', body: {model_slugs: ['msft/bar']}},
    )
    expect(setPendingUpdateType).toHaveBeenCalledTimes(1)
    expect(setPendingUpdateType).toHaveBeenCalledWith('rules')
  })

  it('disables a publisher for the org', async () => {
    mockVerifiedFetchJSON.mockResolvedValue({
      ok: true,
      json: () => mockOrganizationAccessPolicy({isModelsEnabled: true, allowedModelKeys: ['openai/foo']}),
    })

    await mutateAsync(orgDisplayLogin, restrictOrgModelsPayload({publisherIds: [123]}))

    expect(mockVerifiedFetchJSON).toHaveBeenCalledTimes(1)
    expect(mockVerifiedFetchJSON).toHaveBeenCalledWith(
      `/organizations/${orgDisplayLogin}/settings/models/access-policy`,
      {method: 'DELETE', body: {models_publisher_ids: [123]}},
    )
    expect(setPendingUpdateType).toHaveBeenCalledTimes(1)
    expect(setPendingUpdateType).toHaveBeenCalledWith('rules')
  })

  it('enables a publisher for the org', async () => {
    mockVerifiedFetchJSON.mockResolvedValue({
      ok: true,
      json: () =>
        mockOrganizationAccessPolicy({
          isAllowlist: true,
          isModelsEnabled: true,
          allowedModelKeys: ['openai/foo'],
        }),
    })

    await mutateAsync(orgDisplayLogin, allowOrgModelsPayload({publisherIds: [123]}))

    expect(mockVerifiedFetchJSON).toHaveBeenCalledTimes(1)
    expect(mockVerifiedFetchJSON).toHaveBeenCalledWith(
      `/organizations/${orgDisplayLogin}/settings/models/access-policy`,
      {method: 'POST', body: {models_publisher_ids: [123]}},
    )
    expect(setPendingUpdateType).toHaveBeenCalledTimes(1)
    expect(setPendingUpdateType).toHaveBeenCalledWith('rules')
  })

  it('enables several models and publishers for the org', async () => {
    mockVerifiedFetchJSON.mockResolvedValue({
      ok: true,
      json: () => mockOrganizationAccessPolicy({isModelsEnabled: true, isAllowlist: true}),
    })

    await mutateAsync(
      orgDisplayLogin,
      allowOrgModelsPayload({
        modelKeys: ['openai/foo', 'msft/bar', 'bar/baz'],
        publisherIds: [123, 456],
      }),
    )

    expect(mockVerifiedFetchJSON).toHaveBeenCalledTimes(1)
    expect(mockVerifiedFetchJSON).toHaveBeenCalledWith(
      `/organizations/${orgDisplayLogin}/settings/models/access-policy`,
      {
        method: 'POST',
        body: {model_slugs: ['openai/foo', 'msft/bar', 'bar/baz'], models_publisher_ids: [123, 456]},
      },
    )
    expect(setPendingUpdateType).toHaveBeenCalledTimes(1)
    expect(setPendingUpdateType).toHaveBeenCalledWith('rules')
  })

  it('disables several models and publishers for the org', async () => {
    mockVerifiedFetchJSON.mockResolvedValue({
      ok: true,
      json: () => mockOrganizationAccessPolicy({isModelsEnabled: true, isAllowlist: false}),
    })

    await mutateAsync(
      orgDisplayLogin,
      restrictOrgModelsPayload({
        modelKeys: ['openai/foo', 'msft/bar'],
        publisherIds: [123, 456, 789],
      }),
    )

    expect(mockVerifiedFetchJSON).toHaveBeenCalledTimes(1)
    expect(mockVerifiedFetchJSON).toHaveBeenCalledWith(
      `/organizations/${orgDisplayLogin}/settings/models/access-policy`,
      {
        method: 'DELETE',
        body: {model_slugs: ['openai/foo', 'msft/bar'], models_publisher_ids: [123, 456, 789]},
      },
    )
    expect(setPendingUpdateType).toHaveBeenCalledTimes(1)
    expect(setPendingUpdateType).toHaveBeenCalledWith('rules')
  })
})

async function mutateAsync(orgDisplayLogin: string, payload: UpdateOrganizationAccessPolicyPayload) {
  const {result} = renderHook(() => useUpdateOrganizationAccessPolicy({orgDisplayLogin, setPendingUpdateType}), {
    wrapper: withBaseProvidersWrapper(),
  })
  await result.current.mutateAsync(payload)
}

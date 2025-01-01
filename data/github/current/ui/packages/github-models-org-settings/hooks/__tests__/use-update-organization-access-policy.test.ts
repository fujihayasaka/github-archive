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

const mockVerifiedFetchJSON = jest.fn().mockName('verifiedFetchJSON')

jest.mock('@github-ui/verified-fetch', () => {
  return {
    verifiedFetchJSON: (...args: unknown[]) => mockVerifiedFetchJSON(...args),
  }
})

describe('useUpdateOrganizationAccessPolicy', () => {
  afterEach(() => {
    jest.resetAllMocks()
  })

  const orgDisplayLogin = 'some-org'

  test('disables Models access for the org', async () => {
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
  })

  test('enables Models access for the org', async () => {
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
  })

  test('restricts Models access for the org', async () => {
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
  })

  test('switches the org to using a block list instead of an allow list', async () => {
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
  })

  test('disables a model for the org', async () => {
    mockVerifiedFetchJSON.mockResolvedValue({
      ok: true,
      json: () => mockOrganizationAccessPolicy({isModelsEnabled: true, allowedModelKeys: []}),
    })

    await mutateAsync(orgDisplayLogin, restrictOrgModelsPayload({modelKeys: ['openai/foo']}))

    expect(mockVerifiedFetchJSON).toHaveBeenCalledTimes(1)
    expect(mockVerifiedFetchJSON).toHaveBeenCalledWith(
      `/organizations/${orgDisplayLogin}/settings/models/access-policy`,
      {method: 'DELETE', body: {catalog_item_keys: ['openai/foo']}},
    )
  })

  test('enables a model for the org', async () => {
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
      {method: 'POST', body: {catalog_item_keys: ['msft/bar']}},
    )
  })

  test('disables a publisher for the org', async () => {
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
  })

  test('enables a publisher for the org', async () => {
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
  })

  test('enables several models and publishers for the org', async () => {
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
        body: {catalog_item_keys: ['openai/foo', 'msft/bar', 'bar/baz'], models_publisher_ids: [123, 456]},
      },
    )
  })

  test('disables several models and publishers for the org', async () => {
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
        body: {catalog_item_keys: ['openai/foo', 'msft/bar'], models_publisher_ids: [123, 456, 789]},
      },
    )
  })
})

async function mutateAsync(org: string, payload: UpdateOrganizationAccessPolicyPayload) {
  const {result} = renderHook(() => useUpdateOrganizationAccessPolicy(org), {wrapper: withBaseProvidersWrapper()})
  await result.current.mutateAsync(payload)
}

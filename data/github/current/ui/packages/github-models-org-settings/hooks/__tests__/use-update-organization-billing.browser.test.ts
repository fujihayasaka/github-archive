import {describe, afterEach, it, expect} from '@github-ui/tests'
import {vi} from 'vitest'
import {renderHook} from '@testing-library/react'
import {withBaseProvidersWrapper} from '@github-ui/react-core/test-utils'
import {
  disableModelsBillingPayload,
  enableModelsBillingPayload,
  useUpdateOrganizationBilling,
} from '../use-update-organization-billing'
import type {UpdateModelsBillingPayload} from '../../types'

const mockVerifiedFetchJSON = vi.fn().mockName('verifiedFetchJSON')

vi.mock('@github-ui/verified-fetch', () => {
  return {
    verifiedFetchJSON: (...args: unknown[]) => mockVerifiedFetchJSON(...args),
  }
})

describe('useUpdateOrganizationBilling', () => {
  afterEach(() => {
    vi.resetAllMocks()
  })

  const orgDisplayLogin = 'some-org'

  it('disables Models billing for the org', async () => {
    mockVerifiedFetchJSON.mockResolvedValue({
      ok: true,
      json: () => ({billingEnabled: false}),
    })

    await mutateAsync(orgDisplayLogin, disableModelsBillingPayload())

    expect(mockVerifiedFetchJSON).toHaveBeenCalledTimes(1)
    expect(mockVerifiedFetchJSON).toHaveBeenCalledWith(`/organizations/${orgDisplayLogin}/settings/models/billing`, {
      method: 'POST',
      body: {enable: '0'},
    })
  })

  it('enables Models billing for the org', async () => {
    mockVerifiedFetchJSON.mockResolvedValue({
      ok: true,
      json: () => ({billingEnabled: false}),
    })

    await mutateAsync(orgDisplayLogin, enableModelsBillingPayload())

    expect(mockVerifiedFetchJSON).toHaveBeenCalledTimes(1)
    expect(mockVerifiedFetchJSON).toHaveBeenCalledWith(`/organizations/${orgDisplayLogin}/settings/models/billing`, {
      method: 'POST',
      body: {enable: '1'},
    })
  })
})

async function mutateAsync(orgDisplayLogin: string, payload: UpdateModelsBillingPayload) {
  const {result} = renderHook(() => useUpdateOrganizationBilling({orgDisplayLogin}), {
    wrapper: withBaseProvidersWrapper(),
  })
  await result.current.mutateAsync(payload)
}

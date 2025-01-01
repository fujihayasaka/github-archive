import {renderHook} from '@testing-library/react'
import {withBaseProvidersWrapper} from '@github-ui/react-core/test-utils'
import type {UpdateRepositoryAccessPolicyPayload} from '../../types'
import {
  disableRepoModelsPayload,
  enableRepoModelsPayload,
  useUpdateRepoAccessPolicy,
} from '../use-update-repository-access-policy'
import {mockAccessPolicy} from '../../test-utils/mocks'

const mockVerifiedFetchJSON = jest.fn().mockName('verifiedFetchJSON')

// eslint-disable-next-line no-restricted-syntax
jest.mock('@github-ui/verified-fetch', () => {
  return {
    verifiedFetchJSON: (...args: unknown[]) => mockVerifiedFetchJSON(...args),
  }
})

describe('useUpdateRepositoryAccessPolicy', () => {
  afterEach(() => {
    jest.resetAllMocks()
  })

  const ownerDisplayLogin = 'a-very-good-org'
  const repositoryName = 'a-very-good-repo'

  test('disables Models access for the repo', async () => {
    mockVerifiedFetchJSON.mockResolvedValue({
      ok: true,
      json: () => mockAccessPolicy({isRepoModelsEnabled: false}),
    })

    await mutateAsync(ownerDisplayLogin, repositoryName, disableRepoModelsPayload())

    expect(mockVerifiedFetchJSON).toHaveBeenCalledTimes(1)
    expect(mockVerifiedFetchJSON).toHaveBeenCalledWith(
      `/${ownerDisplayLogin}/${repositoryName}/settings/models/access-policy`,
      {method: 'DELETE'},
    )
  })

  test('enables Models access for the repo', async () => {
    mockVerifiedFetchJSON.mockResolvedValue({
      ok: true,
      json: () => mockAccessPolicy({isRepoModelsEnabled: true}),
    })

    await mutateAsync(ownerDisplayLogin, repositoryName, enableRepoModelsPayload())

    expect(mockVerifiedFetchJSON).toHaveBeenCalledTimes(1)
    expect(mockVerifiedFetchJSON).toHaveBeenCalledWith(
      `/${ownerDisplayLogin}/${repositoryName}/settings/models/access-policy`,
      {method: 'POST'},
    )
  })
})

async function mutateAsync(
  ownerDisplayLogin: string,
  repositoryName: string,
  payload: UpdateRepositoryAccessPolicyPayload,
) {
  const {result} = renderHook(() => useUpdateRepoAccessPolicy(ownerDisplayLogin, repositoryName), {
    wrapper: withBaseProvidersWrapper(),
  })
  await result.current.mutateAsync(payload)
}

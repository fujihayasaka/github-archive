import {renderHook} from '@testing-library/react'
import {withBaseProvidersWrapper} from '@github-ui/react-core/test-utils'
import {useModelsQuery} from '../use-models-query'

const mockVerifiedFetchJSON = jest.fn().mockName('verifiedFetchJSON')

// eslint-disable-next-line no-restricted-syntax
jest.mock('@github-ui/verified-fetch', () => {
  return {
    verifiedFetchJSON: (...args: unknown[]) => mockVerifiedFetchJSON(...args),
  }
})

describe('useModelsQuery', () => {
  it('loads models from endpoint for repo', async () => {
    mockVerifiedFetchJSON.mockResolvedValue({
      ok: true,
      json: () => [
        [
          {
            id: 'azureml://registries/azure-openai/models/gpt-4o/versions/2024-11-20',
            registry: 'azure-openai',
          },
          {
            id: 'azureml://registries/azure-openai/models/gpt-4o-mini/versions/2024-07-18',
            registry: 'azure-openai',
          },
        ],
      ],
    })
    const ownerLogin = 'someOrg'
    const repoName = 'MyFancyProject'

    const {result} = renderHook(() => useModelsQuery(ownerLogin, repoName), {
      wrapper: withBaseProvidersWrapper(),
    })

    expect(result.current.isLoading).toBe(false)
    expect(result.current.error).toBeNull()
    expect(mockVerifiedFetchJSON).toHaveBeenCalledTimes(1)
    expect(mockVerifiedFetchJSON).toHaveBeenCalledWith(`/${ownerLogin}/${repoName}/models`)
  })
})

import {renderHook, waitFor} from '@testing-library/react'
import {withBaseProvidersWrapper} from '@github-ui/react-core/test-utils'
import {usePromptsQuery} from '../use-prompts-query'
import type {ModelRepoPromptsRoutePayload} from '../../types'

const mockVerifiedFetchJSON = jest.fn().mockName('verifiedFetchJSON')

// eslint-disable-next-line no-restricted-syntax
jest.mock('@github-ui/verified-fetch', () => {
  return {
    verifiedFetchJSON: (...args: unknown[]) => mockVerifiedFetchJSON(...args),
  }
})

describe('usePromptsQuery', () => {
  afterEach(() => {
    jest.clearAllMocks()
  })

  it('loads specified page of prompts from the repo', async () => {
    const ownerLogin = 'someOrg'
    const repoName = 'MyFancyProject'
    const page = 3
    const mockPayload: ModelRepoPromptsRoutePayload = {prompts: [], page, totalPages: 5}
    mockVerifiedFetchJSON.mockResolvedValue({
      ok: true,
      json: () => ({payload: mockPayload}),
    })

    const {result} = renderHook(() => usePromptsQuery(ownerLogin, repoName, page), {
      wrapper: withBaseProvidersWrapper(),
    })

    expect(mockVerifiedFetchJSON).toHaveBeenCalledTimes(1)
    expect(mockVerifiedFetchJSON).toHaveBeenCalledWith(`/${ownerLogin}/${repoName}/models/prompts?page=${page}`)
    await waitFor(() => expect(result.current.isSuccess).toBe(true))
    expect(result.current.data).toEqual(mockPayload)
    expect(result.current.error).toBeNull()
  })

  it('does not execute query if owner is blank', () => {
    renderHook(() => usePromptsQuery('', 'MyFancyProject', 1), {
      wrapper: withBaseProvidersWrapper(),
    })

    expect(mockVerifiedFetchJSON).not.toHaveBeenCalled()
  })

  it('does not execute query if repo name is blank', () => {
    renderHook(() => usePromptsQuery('SomeOrg', '', 1), {
      wrapper: withBaseProvidersWrapper(),
    })

    expect(mockVerifiedFetchJSON).not.toHaveBeenCalled()
  })

  it('does not execute query if page is 0', () => {
    renderHook(() => usePromptsQuery('SomeOrg', 'SomeRepo', 0), {
      wrapper: withBaseProvidersWrapper(),
    })

    expect(mockVerifiedFetchJSON).not.toHaveBeenCalled()
  })
})

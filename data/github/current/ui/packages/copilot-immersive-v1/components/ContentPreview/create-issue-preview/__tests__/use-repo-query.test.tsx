// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import type {Repository} from '@github-ui/item-picker/RepositoryPicker'
import {renderHook} from '@github-ui/react-core/test-utils'
import {mockRelayId} from '@github-ui/relay-test-utils/RelayComponents'
import {waitFor} from '@testing-library/react'
import {type OperationDescriptor, RelayEnvironmentProvider} from 'react-relay'
import {createMockEnvironment, MockPayloadGenerator} from 'relay-test-utils'

import {useRepoQuery} from '../use-repo-query'

function setupEnvironment(result: Partial<Repository> | undefined) {
  const environment = createMockEnvironment()

  environment.mock.queueOperationResolver((operation: OperationDescriptor) => {
    expect(operation.request.node.params.name).toBe('RepositoryPickerCurrentRepoQuery')

    return MockPayloadGenerator.generate(operation, {
      Repository() {
        return result
      },
    })
  })

  return environment
}

describe('useRepoQuery', () => {
  it('should return repository', async () => {
    const environment = setupEnvironment({
      id: mockRelayId(),
      nameWithOwner: 'monalisa/smile',
      owner: {
        login: 'monalisa',
      } as Repository['owner'],
      name: 'smile',
    })
    const {result} = renderHook(() => useRepoQuery({owner: 'monalisa', repo: 'smile'}), {
      wrapper: ({children}) => (
        <RelayEnvironmentProvider environment={environment}>{children}</RelayEnvironmentProvider>
      ),
    })

    await waitFor(() => {
      expect(result.current).toEqual(
        expect.objectContaining({
          isLoading: false,
          isError: false,
          data: expect.objectContaining({
            nameWithOwner: 'monalisa/smile',
          }),
        }),
      )
    })
  })

  // Skipped because we can't mock the "repository not found" scenario
  // https://github.com/facebook/relay/issues/3825
  it.skip('should return null when repository is not found', async () => {
    const environment = setupEnvironment(undefined)
    const {result} = renderHook(() => useRepoQuery({owner: 'monalisa', repo: 'smile'}), {
      wrapper: ({children}) => (
        <RelayEnvironmentProvider environment={environment}>{children}</RelayEnvironmentProvider>
      ),
    })

    await waitFor(() => {
      expect(result.current).toEqual(
        expect.objectContaining({
          isLoading: false,
          isError: false,
          data: null,
        }),
      )
    })
  })

  it('should return null when owner or repo is not provided', async () => {
    const environment = setupEnvironment(undefined)
    const {result} = renderHook(() => useRepoQuery({owner: undefined, repo: undefined}), {
      wrapper: ({children}) => (
        <RelayEnvironmentProvider environment={environment}>{children}</RelayEnvironmentProvider>
      ),
    })

    await waitFor(() => {
      expect(result.current).toEqual(
        expect.objectContaining({
          isLoading: false,
          isError: false,
          data: null,
        }),
      )
    })
  })

  it('should return loading state while query is loading', () => {
    const environment = setupEnvironment(undefined)
    const {result} = renderHook(() => useRepoQuery({owner: 'monalisa', repo: 'smile'}), {
      wrapper: ({children}) => (
        <RelayEnvironmentProvider environment={environment}>{children}</RelayEnvironmentProvider>
      ),
    })

    // NOTE we are not using waitFor to finish here, so we stay in a loading state
    expect(result.current).toEqual(
      expect.objectContaining({
        isLoading: true,
        isError: false,
        data: undefined,
      }),
    )
  })

  it('should return error state when query fails', async () => {
    const environment = createMockEnvironment()
    const {result} = renderHook(() => useRepoQuery({owner: 'monalisa', repo: 'smile'}), {
      wrapper: ({children}) => (
        <RelayEnvironmentProvider environment={environment}>{children}</RelayEnvironmentProvider>
      ),
    })
    environment.mock.rejectMostRecentOperation(new Error('Network error'))

    await waitFor(() => {
      expect(result.current).toEqual(
        expect.objectContaining({
          isLoading: false,
          isError: true,
          data: undefined,
        }),
      )
    })
  })
})

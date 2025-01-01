// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {renderHook} from '@github-ui/react-core/test-utils'
import {mockRelayId} from '@github-ui/relay-test-utils/RelayComponents'
import {waitFor} from '@testing-library/react'
import {type OperationDescriptor, RelayEnvironmentProvider} from 'react-relay'
import {createMockEnvironment, MockPayloadGenerator} from 'relay-test-utils'

import {type Label, useLabelsQuery} from '../use-labels-query'

const LABELS: Label[] = ['bug', 'task', 'feature'].map(name => ({
  id: mockRelayId(),
  name,
  color: '',
  description: undefined,
  nameHTML: '',
  url: '',
  ' $fragmentType': 'LabelPickerLabel',
}))

function setupEnvironment(result: Label[] | undefined) {
  const environment = createMockEnvironment()

  environment.mock.queueOperationResolver((operation: OperationDescriptor) => {
    expect(operation.request.node.params.name).toBe('LabelPickerQuery')
    return MockPayloadGenerator.generate(operation, {
      Repository() {
        return {
          labelsByNames: {
            nodes: result ?? [],
          },
        }
      },
    })
  })

  return environment
}

describe('useLabelsQuery', () => {
  it('should return labels', async () => {
    const environment = setupEnvironment(LABELS)
    const {result} = renderHook(() => useLabelsQuery({owner: 'monalisa', repo: 'smile', labels: []}), {
      wrapper: ({children}) => (
        <RelayEnvironmentProvider environment={environment}>{children}</RelayEnvironmentProvider>
      ),
    })

    await waitFor(() => {
      expect(result.current).toEqual(
        expect.objectContaining({
          isLoading: false,
          isError: false,
          data: LABELS.map(node => {
            return expect.objectContaining({
              id: node.id,
              name: node.name,
            })
          }),
        }),
      )
    })
  })

  it('should return empty array when no labels are found', async () => {
    const environment = setupEnvironment([])
    const {result} = renderHook(() => useLabelsQuery({owner: 'monalisa', repo: 'smile', labels: []}), {
      wrapper: ({children}) => (
        <RelayEnvironmentProvider environment={environment}>{children}</RelayEnvironmentProvider>
      ),
    })

    await waitFor(() => {
      expect(result.current).toEqual(
        expect.objectContaining({
          isLoading: false,
          isError: false,
          data: [],
        }),
      )
    })
  })

  it('should return empty array when owner or repo is not provided', async () => {
    const environment = setupEnvironment([])
    const {result} = renderHook(() => useLabelsQuery({owner: undefined, repo: undefined, labels: undefined}), {
      wrapper: ({children}) => (
        <RelayEnvironmentProvider environment={environment}>{children}</RelayEnvironmentProvider>
      ),
    })

    await waitFor(() => {
      expect(result.current).toEqual(
        expect.objectContaining({
          isLoading: false,
          isError: false,
          data: [],
        }),
      )
    })
  })

  it('should return loading state while query is loading', () => {
    const environment = setupEnvironment([])
    const {result} = renderHook(() => useLabelsQuery({owner: 'monalisa', repo: 'smile', labels: []}), {
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
    const {result} = renderHook(() => useLabelsQuery({owner: 'monalisa', repo: 'smile', labels: []}), {
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

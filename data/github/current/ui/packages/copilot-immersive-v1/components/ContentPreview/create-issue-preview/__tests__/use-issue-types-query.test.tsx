// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import type {IssueType} from '@github-ui/item-picker/IssueTypePicker'
import {renderHook} from '@github-ui/react-core/test-utils'
import {mockRelayId} from '@github-ui/relay-test-utils/RelayComponents'
import {waitFor} from '@testing-library/react'
import {type OperationDescriptor, RelayEnvironmentProvider} from 'react-relay'
import {createMockEnvironment, MockPayloadGenerator} from 'relay-test-utils'

import {useIssueTypesQuery} from '../use-issue-types-query'

const ISSUE_TYPES: IssueType[] = [
  {
    color: 'GREEN',
    description: '',
    id: mockRelayId(),
    isEnabled: true,
    name: 'Feature',
    ' $fragmentType': 'IssueTypePickerIssueType',
  },
  {
    color: 'BLUE',
    description: '',
    id: mockRelayId(),
    isEnabled: true,
    name: 'Task',
    ' $fragmentType': 'IssueTypePickerIssueType',
  },
  {
    color: 'RED',
    description: '',
    id: mockRelayId(),
    isEnabled: true,
    name: 'Bug',
    ' $fragmentType': 'IssueTypePickerIssueType',
  },
]

function setupEnvironment(result: IssueType[] | undefined) {
  const environment = createMockEnvironment()

  environment.mock.queueOperationResolver((operation: OperationDescriptor) => {
    expect(operation.request.node.params.name).toBe('IssueTypePickerQuery')
    return MockPayloadGenerator.generate(operation, {
      Repository() {
        return {
          issueTypes: {
            edges: result?.map(node => ({node})) ?? [],
          },
        }
      },
    })
  })

  return environment
}

describe('useIssueTypesQuery', () => {
  it('should return issue types', async () => {
    const environment = setupEnvironment(ISSUE_TYPES)
    const {result} = renderHook(() => useIssueTypesQuery({owner: 'monalisa', repo: 'smile'}), {
      wrapper: ({children}) => (
        <RelayEnvironmentProvider environment={environment}>{children}</RelayEnvironmentProvider>
      ),
    })

    await waitFor(() => {
      expect(result.current).toEqual(
        expect.objectContaining({
          isLoading: false,
          isError: false,
          data: ISSUE_TYPES.map(type => {
            return expect.objectContaining({
              id: type.id,
              name: type.name,
              color: type.color,
            })
          }),
        }),
      )
    })
  })

  it('should return empty array when no issue types are found', async () => {
    const environment = setupEnvironment([])
    const {result} = renderHook(() => useIssueTypesQuery({owner: 'monalisa', repo: 'smile'}), {
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
    const {result} = renderHook(() => useIssueTypesQuery({owner: undefined, repo: undefined}), {
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
    const {result} = renderHook(() => useIssueTypesQuery({owner: 'monalisa', repo: 'smile'}), {
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
    const {result} = renderHook(() => useIssueTypesQuery({owner: 'monalisa', repo: 'smile'}), {
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

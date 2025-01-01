// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {copilotBotLogin} from '@github-ui/assignees/copilot-user'
import type {Assignee} from '@github-ui/item-picker/AssigneePicker'
import {renderHook} from '@github-ui/react-core/test-utils'
import {mockRelayId} from '@github-ui/relay-test-utils/RelayComponents'
import {waitFor} from '@testing-library/react'
import {type OperationDescriptor, RelayEnvironmentProvider} from 'react-relay'
import {createMockEnvironment, MockPayloadGenerator} from 'relay-test-utils'

import {useAssigneesQuery} from '../use-assignees-query'

const USERS: Assignee[] = [
  {
    __typename: '',
    id: mockRelayId(),
    login: 'monalisa',
    name: '',
    avatarUrl: '',
    profileResourcePath: '',
  },
  {
    __typename: '',
    id: mockRelayId(),
    login: copilotBotLogin,
    name: '',
    avatarUrl: '',
    profileResourcePath: '',
  },
  {
    __typename: '',
    id: mockRelayId(),
    login: 'hubot',
    name: '',
    avatarUrl: '',
    profileResourcePath: '',
  },
]

function setupEnvironment(result: Assignee[] | undefined) {
  const environment = createMockEnvironment()

  environment.mock.queueOperationResolver((operation: OperationDescriptor) => {
    expect(operation.request.node.params.name).toBe('AssigneePickerSearchAssignableRepositoryUsersQuery')
    return MockPayloadGenerator.generate(operation, {
      Repository() {
        return {
          suggestedActors: {
            nodes: result ?? [],
          },
        }
      },
    })
  })

  return environment
}

describe('useAssigneesQuery', () => {
  it('should return assignees', async () => {
    const environment = setupEnvironment(USERS)
    const {result} = renderHook(() => useAssigneesQuery({owner: 'monalisa', repo: 'smile', assignees: []}), {
      wrapper: ({children}) => (
        <RelayEnvironmentProvider environment={environment}>{children}</RelayEnvironmentProvider>
      ),
    })

    await waitFor(() => {
      expect(result.current).toEqual(
        expect.objectContaining({
          isLoading: false,
          isError: false,
          data: USERS.map(node => {
            return expect.objectContaining({
              id: node.id,
              login: node.login,
            })
          }),
        }),
      )
    })
  })

  it('should return empty array when no assignees are found', async () => {
    const environment = setupEnvironment([])
    const {result} = renderHook(() => useAssigneesQuery({owner: 'monalisa', repo: 'smile', assignees: []}), {
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
    const {result} = renderHook(() => useAssigneesQuery({owner: undefined, repo: undefined, assignees: undefined}), {
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
    const {result} = renderHook(() => useAssigneesQuery({owner: 'monalisa', repo: 'smile', assignees: []}), {
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
    const {result} = renderHook(() => useAssigneesQuery({owner: 'monalisa', repo: 'smile', assignees: []}), {
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

import {createMockEnvironment} from 'relay-test-utils'
import {commitCreateRepositoryLabelMutation} from '../create-repository-label-mutation'
import {ConnectionHandler, type Environment} from 'relay-runtime'

describe('createRepositoryLabelMutation', () => {
  let environment: ReturnType<typeof createMockEnvironment>
  let connectionId: string
  const mockInput = {
    repositoryId: 'repository:123',
    name: 'bug',
    color: 'ff0000',
    description: 'Something is not working correctly',
  }

  beforeEach(() => {
    environment = createMockEnvironment()
    connectionId = primeLabelsConnection(environment)
  })

  it('should call the mutation with correct variables', () => {
    const onCompleted = jest.fn()
    const onError = jest.fn()

    commitCreateRepositoryLabelMutation({
      environment: environment as unknown as Environment,
      input: mockInput,
      connectionId,
      onCompleted,
      onError,
    })

    expect(environment.mock.getMostRecentOperation().request.variables).toEqual({
      input: mockInput,
      connection: connectionId,
    })

    const mockResponse = {
      createLabel: {
        label: {
          id: 'label:456',
          name: 'bug',
          nameHTML: 'bug',
          color: 'ff0000',
          description: 'Something is not working correctly',
          repository: {
            id: 'repository:123',
          },
        },
        errors: [],
      },
    }

    environment.mock.resolveMostRecentOperation({
      data: mockResponse,
    })

    expect(onCompleted).toHaveBeenCalled()
    expect(onError).not.toHaveBeenCalled()
  })

  it('inserts the new edge in the store', () => {
    commitCreateRepositoryLabelMutation({
      environment: environment as unknown as Environment,
      input: mockInput,
      connectionId,
      onCompleted: jest.fn(),
      onError: jest.fn(),
    })
    environment.mock.resolveMostRecentOperation({
      data: {
        createLabel: {
          label: {
            id: 'label:456',
            __typename: 'Label',
            name: 'bug',
            nameHTML: 'bug',
            color: 'ff0000',
            description: 'Something is not working correctly',
            repository: {id: 'repository:123'},
          },
          errors: [],
        },
      },
    })
    const connectionRecord = environment.getStore().getSource().get(connectionId) as unknown as {
      edges: {__refs: unknown[]}
    }
    const refs = connectionRecord?.edges?.['__refs']
    expect(refs).toBeInstanceOf(Array)
    expect(refs).toHaveLength(1)
  })

  it('increments totalCount', () => {
    expect((environment.getStore().getSource().get(connectionId) as unknown as {totalCount: number}).totalCount).toBe(0)

    commitCreateRepositoryLabelMutation({
      environment: environment as unknown as Environment,
      input: mockInput,
      connectionId,
      onCompleted: jest.fn(),
      onError: jest.fn(),
    })

    environment.mock.resolveMostRecentOperation({
      data: {
        createLabel: {
          label: {
            id: 'label:1',
            __typename: 'Label',
            name: 'bug',
            nameHTML: 'bug',
            color: 'ff0000',
            description: 'Something is not working correctly',
            repository: {id: 'repository:123'},
          },
          errors: [],
        },
      },
    })

    expect((environment.getStore().getSource().get(connectionId) as unknown as {totalCount: number}).totalCount).toBe(1)
  })

  it('should call onError when mutation fails', () => {
    const onCompleted = jest.fn()
    const onError = jest.fn()
    const testError = new Error('Network error')

    commitCreateRepositoryLabelMutation({
      environment: environment as unknown as Environment,
      input: mockInput,
      connectionId,
      onCompleted,
      onError,
    })

    environment.mock.rejectMostRecentOperation(testError)

    expect(onError).toHaveBeenCalledWith(testError)
    expect(onCompleted).not.toHaveBeenCalled()
  })

  it('should handle mutation response with errors', () => {
    const onCompleted = jest.fn()
    const onError = jest.fn()

    commitCreateRepositoryLabelMutation({
      environment: environment as unknown as Environment,
      input: mockInput,
      connectionId: 'client:repo-123:__LabelList_labels_connection(...)',
      onCompleted,
      onError,
    })

    // When there are GraphQL errors in the response,
    // the operation should still resolve successfully
    expect(environment.mock.getMostRecentOperation().request.variables).toEqual({
      input: mockInput,
      connection: 'client:repo-123:__LabelList_labels_connection(...)',
    })

    // Verify that the mutation was committed without throwing
    expect(() => {
      environment.mock.resolveMostRecentOperation({
        data: {
          createLabel: {
            label: null,
            errors: [
              {
                message: 'Label name already exists',
              },
            ],
          },
        },
      })
    }).not.toThrow()
  })

  it('should handle minimal required input', () => {
    const onCompleted = jest.fn()
    const onError = jest.fn()
    const minimalInput = {
      repositoryId: 'repository:123',
      name: 'enhancement',
      color: '84b6eb',
    }

    commitCreateRepositoryLabelMutation({
      environment: environment as unknown as Environment,
      input: minimalInput,
      connectionId,
      onCompleted,
      onError,
    })

    expect(environment.mock.getMostRecentOperation().request.variables).toEqual({
      input: minimalInput,
      connection: connectionId,
    })

    const mockResponse = {
      createLabel: {
        label: {
          id: 'label:789',
          name: 'enhancement',
          nameHTML: 'enhancement',
          color: '84b6eb',
          description: null,
          repository: {
            id: 'repository:123',
          },
        },
        errors: [],
      },
    }

    environment.mock.resolveMostRecentOperation({
      data: mockResponse,
    })

    expect(onCompleted).toHaveBeenCalled()
    expect(onError).not.toHaveBeenCalled()
  })
})

function primeLabelsConnection(env: ReturnType<typeof createMockEnvironment>, repoId = 'repository:123') {
  let connectionId = ''
  env.commitUpdate(store => {
    if (!store.get(repoId)) {
      store.create(repoId, 'Repository')
    }
    connectionId = ConnectionHandler.getConnectionID(repoId, 'LabelList_labels', {
      orderBy: {direction: 'ASC', field: 'NAME'},
      skip: 0,
    })
    if (!store.get(connectionId)) {
      const connection = store.create(connectionId, 'LabelConnection')
      connection.setLinkedRecords([], 'edges')
      connection.setValue(0, 'totalCount')
    }
  })
  return connectionId
}

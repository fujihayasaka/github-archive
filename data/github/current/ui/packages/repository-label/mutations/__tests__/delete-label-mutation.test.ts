import {createMockEnvironment} from 'relay-test-utils'
import {commitDeleteLabelMutation} from '../delete-label-mutation'
import type {Environment} from 'relay-runtime'

describe('deleteLabelMutation', () => {
  let environment: ReturnType<typeof createMockEnvironment>
  const labelId = 'label:123'

  beforeEach(() => {
    environment = createMockEnvironment()
  })

  it('should call the mutation with correct variables', () => {
    const onCompleted = jest.fn()
    const onError = jest.fn()

    commitDeleteLabelMutation({
      environment: environment as unknown as Environment,
      input: {id: labelId},
      onCompleted,
      onError,
    })

    expect(environment.mock.getMostRecentOperation().request.variables).toEqual({
      input: {id: labelId},
    })

    environment.mock.resolveMostRecentOperation({
      data: {
        deleteLabel: {
          clientMutationId: 'test-id',
        },
      },
    })

    expect(onCompleted).toHaveBeenCalled()
    expect(onError).not.toHaveBeenCalled()
  })

  it('should call onError when mutation fails', () => {
    const onCompleted = jest.fn()
    const onError = jest.fn()
    const testError = new Error('Mutation failed')

    commitDeleteLabelMutation({
      environment: environment as unknown as Environment,
      input: {id: labelId},
      onCompleted,
      onError,
    })

    environment.mock.rejectMostRecentOperation(testError)

    expect(onError).toHaveBeenCalledWith(testError)
    expect(onCompleted).not.toHaveBeenCalled()
  })
})

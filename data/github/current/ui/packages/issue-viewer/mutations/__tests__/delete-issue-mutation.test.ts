import {commitDeleteIssueMutation} from '../delete-issue-mutation'
import {createMockEnvironment} from 'relay-test-utils'
import type RelayModernEnvironment from 'relay-runtime/lib/store/RelayModernEnvironment'

describe('commitDeleteIssueMutation', () => {
  // eslint-disable-next-line jest/no-done-callback
  it('should not remove the issue from the relay store', done => {
    const environment = createMockEnvironment()
    const input = {issueId: 'issue-id-1'}
    const onCompleted = jest.fn()
    const onError = jest.fn()

    commitDeleteIssueMutation({
      environment: environment as unknown as RelayModernEnvironment,
      input,
      onCompleted,
      onError,
    })

    environment.mock.resolveMostRecentOperation({
      data: {
        deleteIssue: {
          issue: {
            id: 'issue-id-1',
          },
        },
      },
    })

    setTimeout(() => {
      const store = environment.getStore()
      const recordSource = store.getSource()
      const issueRecord = recordSource.get('issue-id-1')

      expect(issueRecord).not.toBeNull()
      expect(onCompleted).toHaveBeenCalled()
      expect(onError).not.toHaveBeenCalled()
      done()
    }, 0)
  })
})

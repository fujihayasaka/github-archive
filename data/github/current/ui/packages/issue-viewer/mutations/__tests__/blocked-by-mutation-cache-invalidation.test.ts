import {createMockEnvironment} from 'relay-test-utils'
import type RelayModernEnvironment from 'relay-runtime/lib/store/RelayModernEnvironment'

import {addBlockedByMutation} from '../add-blocked-by-mutation'
import {createOperationDescriptor, getRequest} from 'relay-runtime'
import {LazyRelationshipsBlockedByListViewQueryGraphQL} from '../../components/sections/relations-section/LazyRelationshipsBlockedByListView'
import {LazyRelationshipsBlockingListViewQueryGraphQL} from '../../components/sections/relations-section/LazyRelationshipsBlockingListView'
import {removeBlockedByMutation} from '../remove-blocked-by-mutation'
import {act} from '@testing-library/react'

describe('blocked by mutation', () => {
  it('invalidates the lazy queries cache when adding an item', () => {
    const environment = createMockEnvironment()

    const input = {
      issueId: 'issue-id-1',
      blockingIssueId: 'issue-id-2',
    }

    // Adding Blocked by - list all query to the store
    const blockedByListAllRequest = getRequest(LazyRelationshipsBlockedByListViewQueryGraphQL)
    const blockedByListAllOperation = createOperationDescriptor(blockedByListAllRequest, {
      id: input.issueId,
      pageSize: 10,
    })
    const blockedByViewAllResultPayload = {
      issue: {
        __typename: 'Issue',
        id: input.issueId,
        repository: {
          id: 'repo-id-1',
          nameWithOwner: 'unicorns-r-us/dependencies-test',
        },
        blockedBy: {
          edges: [],
          pageInfo: {hasNextPage: false, endCursor: 'NA'},
        },
      },
    }
    environment.commitPayload(blockedByListAllOperation, blockedByViewAllResultPayload)

    expect(environment.check(blockedByListAllOperation).status).toStrictEqual('available')

    // Adding Is blocking - list all query to the store
    const blockingListAllRequest = getRequest(LazyRelationshipsBlockingListViewQueryGraphQL)
    const blockingListAllOperation = createOperationDescriptor(blockingListAllRequest, {
      id: input.blockingIssueId,
      pageSize: 10,
    })
    const blockingViewAllResultPayload = {
      issue: {
        __typename: 'Issue',
        id: input.blockingIssueId,
        repository: {
          id: 'repo-id-1',
          nameWithOwner: 'unicorns-r-us/dependencies-test',
        },
        blocking: {
          edges: [],
          pageInfo: {hasNextPage: false, endCursor: 'NA'},
        },
      },
    }
    environment.commitPayload(blockingListAllOperation, blockingViewAllResultPayload)

    expect(environment.check(blockingListAllOperation).status).toStrictEqual('available')

    // Executing the mutation
    const onCompleted = jest.fn()
    const onError = jest.fn()
    addBlockedByMutation({
      environment: environment as unknown as RelayModernEnvironment,
      input,
      onCompleted,
      onError,
    })

    const repositoryFragmentData = {
      id: 'repo-id-1',
      nameWithOwner: 'user/repo',
      owner: {
        __typename: 'User',
        id: 'user-id-1',
        login: 'user',
      },
      isArchived: false,
    }
    const mutationData = {
      data: {
        addBlockedBy: {
          issue: {
            id: input.issueId,
            repository: repositoryFragmentData,
            parent: null,
            topBlockedBy: {
              nodes: [],
              pageInfo: {hasNextPage: true},
            },
            topBlocking: {
              nodes: [],
              pageInfo: {hasNextPage: true},
            },
            issueDependenciesSummary: {
              blockedBy: 1,
              blocking: 1,
            },
            viewerCanUpdateMetadata: true,
          },
          blockingIssue: {
            id: input.blockingIssueId,
            number: 2,
            title: 'Issue 2',
            repository: repositoryFragmentData,
            parent: null,
            topBlockedBy: {
              nodes: [],
              pageInfo: {hasNextPage: false},
            },
            topBlocking: {
              nodes: [],
              pageInfo: {hasNextPage: false},
            },
            issueDependenciesSummary: {
              blockedBy: 0,
              blocking: 1,
            },
            viewerCanUpdateMetadata: true,
          },
        },
      },
    }

    act(() => environment.mock.resolveMostRecentOperation(mutationData))

    // assertions
    const store = environment.getStore()
    const recordSource = store.getSource()
    const issueRecord = recordSource.get(input.issueId)

    expect(issueRecord).not.toBeNull()
    expect(onCompleted).toHaveBeenCalled()
    expect(onError).not.toHaveBeenCalled()

    expect(environment.check(blockedByListAllOperation).status).toStrictEqual('stale')
    expect(environment.check(blockingListAllOperation).status).toStrictEqual('stale')
  })

  it('invalidates the lazy queries cache when removing an item', () => {
    const environment = createMockEnvironment()

    const input = {
      issueId: 'issue-id-1',
      blockingIssueId: 'issue-id-2',
    }

    // Adding Blocked by - list all query to the store
    const blockedByListAllRequest = getRequest(LazyRelationshipsBlockedByListViewQueryGraphQL)
    const blockedByListAllOperation = createOperationDescriptor(blockedByListAllRequest, {
      id: input.issueId,
      pageSize: 10,
    })
    const blockedByViewAllResultPayload = {
      issue: {
        __typename: 'Issue',
        id: input.issueId,
        repository: {
          id: 'repo-id-1',
          nameWithOwner: 'unicorns-r-us/dependencies-test',
        },
        blockedBy: {
          edges: [],
          pageInfo: {hasNextPage: false, endCursor: 'NA'},
        },
      },
    }
    environment.commitPayload(blockedByListAllOperation, blockedByViewAllResultPayload)

    expect(environment.check(blockedByListAllOperation).status).toStrictEqual('available')

    // Adding Is blocking - list all query to the store
    const blockingListAllRequest = getRequest(LazyRelationshipsBlockingListViewQueryGraphQL)
    const blockingListAllOperation = createOperationDescriptor(blockingListAllRequest, {
      id: input.blockingIssueId,
      pageSize: 10,
    })
    const blockingViewAllResultPayload = {
      issue: {
        __typename: 'Issue',
        id: input.blockingIssueId,
        repository: {
          id: 'repo-id-1',
          nameWithOwner: 'unicorns-r-us/dependencies-test',
        },
        blocking: {
          edges: [],
          pageInfo: {hasNextPage: false, endCursor: 'NA'},
        },
      },
    }
    environment.commitPayload(blockingListAllOperation, blockingViewAllResultPayload)

    expect(environment.check(blockingListAllOperation).status).toStrictEqual('available')

    // Executing the mutation
    const onCompleted = jest.fn()
    const onError = jest.fn()
    removeBlockedByMutation({
      environment: environment as unknown as RelayModernEnvironment,
      input,
      onCompleted,
      onError,
    })

    const repositoryFragmentData = {
      id: 'repo-id-1',
      nameWithOwner: 'user/repo',
      owner: {
        __typename: 'User',
        id: 'user-id-1',
        login: 'user',
      },
      isArchived: false,
    }
    const mutationData = {
      data: {
        removeBlockedBy: {
          issue: {
            id: input.issueId,
            repository: repositoryFragmentData,
            parent: null,
            topBlockedBy: {
              nodes: [],
              pageInfo: {hasNextPage: true},
            },
            topBlocking: {
              nodes: [],
              pageInfo: {hasNextPage: true},
            },
            issueDependenciesSummary: {
              blockedBy: 1,
              blocking: 1,
            },
            viewerCanUpdateMetadata: true,
          },
          blockingIssue: {
            id: input.blockingIssueId,
            number: 2,
            title: 'Issue 2',
            repository: repositoryFragmentData,
            parent: null,
            topBlockedBy: {
              nodes: [],
              pageInfo: {hasNextPage: false},
            },
            topBlocking: {
              nodes: [],
              pageInfo: {hasNextPage: false},
            },
            issueDependenciesSummary: {
              blockedBy: 0,
              blocking: 1,
            },
            viewerCanUpdateMetadata: true,
          },
        },
      },
    }

    act(() => environment.mock.resolveMostRecentOperation(mutationData))

    // assertions
    const store = environment.getStore()
    const recordSource = store.getSource()
    const issueRecord = recordSource.get(input.issueId)

    expect(issueRecord).not.toBeNull()
    expect(onCompleted).toHaveBeenCalled()
    expect(onError).not.toHaveBeenCalled()

    expect(environment.check(blockedByListAllOperation).status).toStrictEqual('stale')
    expect(environment.check(blockingListAllOperation).status).toStrictEqual('stale')
  })
})

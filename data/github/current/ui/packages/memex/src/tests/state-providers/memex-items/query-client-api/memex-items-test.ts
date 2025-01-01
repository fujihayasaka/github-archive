import {type QueryClient, QueryObserver} from '@tanstack/react-query'

import type {IColumnWithItems} from '../../../../client/api/columns/contracts/column-with-items'
import type {EnrichedText} from '../../../../client/api/columns/contracts/text'
import {ItemType} from '../../../../client/api/memex-items/item-type'
import {createMemexItemModel, type MemexItemModel} from '../../../../client/models/memex-item-model'
import {useGetSidePanelItemNotOnClient} from '../../../../client/queries/side-panel'
import {mergeItemData} from '../../../../client/state-providers/memex-items/memex-item-helpers'
import {
  buildMemexGroupedItemsQueryKey,
  buildMemexGroupsQueryKey,
  buildMemexSecondaryGroupsQueryKey,
  buildMemexUngroupedItemsQueryKey,
  createGroupedItemsId,
  type MemexUngroupedItemsQueryKey,
  type PaginatedMemexItemsQueryKey,
} from '../../../../client/state-providers/memex-items/queries/query-keys'
import {
  type MemexGroupsPageQueryData,
  type MemexItemsPageQueryData,
  pageParamForInitialPage,
  type PaginatedMemexItemsQueryVariables,
} from '../../../../client/state-providers/memex-items/queries/types'
import {
  useMemexItemsQuery,
  type UseMemexItemsQueryData,
} from '../../../../client/state-providers/memex-items/queries/use-memex-items-query'
import {setQueryDataForMemexGroupsPage} from '../../../../client/state-providers/memex-items/query-client-api/memex-groups'
import {
  addMemexItemForGroupToQueryClient,
  addMemexItemToQueryClient,
  findMemexItemByIdInQueryClient,
  findMemexItemGlobalIndexByIdInQueryClient,
  getMemexItemModelsFromQueryClient,
  getMemexItemsQueryDataFromQueryClient,
  getQueryDataForGroupedItemsPage,
  getQueryDataForMemexItemsPage,
  getQueryDataForSidePanelItemNotOnClientFromQueryClient,
  hasMemexItemsQueryData,
  isMemexItemInGroup,
  type OptimisticUpdateRollbackData,
  removeMemexItemsFromQueryClient,
  rollbackMemexItemData,
  setMemexItemsQueryDataInQueryClient,
  setMemexItemsToForceRerenderInQueryClient,
  setQueryDataForGroupedItemsPage,
  setQueryDataForMemexItemsPage,
  setQueryDataForSidePanelItemNotOnClientInQueryClient,
  updateGroupForMemexItems,
  updateMemexItemInQueryClient,
  updateMemexItemPositionInQueryClient,
  updateMemexItemsForColumnInQueryClient,
  updateMemexItemsInQueryClient,
  updateMemexItemWitNewRowPositionInQueryClient,
} from '../../../../client/state-providers/memex-items/query-client-api/memex-items'
import {
  getQueryDataForMemexItemsTotalCounts,
  mergeQueryDataForMemexItemsTotalCounts,
} from '../../../../client/state-providers/memex-items/query-client-api/memex-totals'
import {setPageParamsQueryDataForVariables} from '../../../../client/state-providers/memex-items/query-client-api/page-params'
import {seedJSONIsland} from '../../../../mocks/server/mock-server'
import {columnValueFactory} from '../../../factories/column-values/column-value-factory'
import {draftIssueFactory} from '../../../factories/memex-items/draft-issue-factory'
import {issueFactory} from '../../../factories/memex-items/issue-factory'
import {pullRequestFactory} from '../../../factories/memex-items/pull-request-factory'
import {
  activateQueryByQueryKey,
  initQueryClient,
  setAndActivateInitialQueriesByPage,
  setAndActivateInitialQueriesByPageForGroup,
  setMemexItemsForPage,
} from './helpers'

function getQueryData(queryClient: QueryClient) {
  return queryClient.getQueryData<UseMemexItemsQueryData>(useMemexItemsQuery.getKey())
}

function getMemexItemModelsForQueryKeys(
  queryClient: QueryClient,
  queryKeys: Array<PaginatedMemexItemsQueryKey>,
): Array<MemexItemModel> {
  const newPages = queryKeys.map(queryKey => queryClient.getQueryData<MemexItemsPageQueryData>(queryKey))
  return newPages.flatMap(page => page?.nodes || [])
}

function getQueryClientItems(queryClient: QueryClient): Array<MemexItemModel> {
  const queryData = getQueryData(queryClient)

  if (queryData?.pages.length === 1) {
    return queryData.pages[0]?.nodes || []
  }
  return queryData?.pages.flatMap(page => page.nodes) || []
}

function setQueryData(queryClient: QueryClient, queryData: UseMemexItemsQueryData) {
  return queryClient.setQueryData<UseMemexItemsQueryData>(useMemexItemsQuery.getKey(), queryData)
}

function setInitialQueryDataPageNodes(queryClient: QueryClient, itemsByPage: Array<Array<MemexItemModel>>) {
  setQueryData(queryClient, {
    pages: itemsByPage.map(items => {
      return {
        nodes: items,
        pageInfo: {endCursor: '', startCursor: '', hasNextPage: false, hasPreviousPage: false},
        totalCount: {value: items.length, isApproximate: false},
      }
    }),
    pageParams: [],
  })
}

function setInitialQueryClientItems(queryClient: QueryClient, items: Array<MemexItemModel>) {
  setInitialQueryDataPageNodes(queryClient, [items])
}

function setInitialQueriesByPage(
  queryClient: QueryClient,
  variables: PaginatedMemexItemsQueryVariables,
  itemsByPage: Array<Array<MemexItemModel>>,
) {
  const queryKeys: Array<MemexUngroupedItemsQueryKey> = []
  for (const [index, items] of itemsByPage.entries()) {
    const pageParam = index === 0 ? pageParamForInitialPage : {after: index.toString()}
    setMemexItemsForPage(queryClient, variables, pageParam, items)
    queryKeys.push(buildMemexUngroupedItemsQueryKey(variables, pageParam))
  }
  return queryKeys
}

function setAndActivateInitialSidePanelQuery(queryClient: QueryClient, sidePanelItem: MemexItemModel) {
  setQueryDataForSidePanelItemNotOnClientInQueryClient(queryClient, sidePanelItem)
  const queryKey = useGetSidePanelItemNotOnClient.getKey({itemId: sidePanelItem.id.toString()})
  queryClient.getQueryCache().find({queryKey})?.addObserver(new QueryObserver(queryClient, {queryKey}))
}

describe('query-client-api Memex items', () => {
  describe('getQueryDataForMemexItemsPage', () => {
    it('returns ungrouped data from query client', () => {
      const queryClient = initQueryClient()

      const variables: PaginatedMemexItemsQueryVariables = {}
      const firstPageItems = [issueFactory.build(), issueFactory.build()].map(item => createMemexItemModel(item))
      const expectedPageData: MemexItemsPageQueryData = {
        nodes: firstPageItems,
        pageInfo: {hasNextPage: false, hasPreviousPage: false},
      }

      setQueryDataForMemexItemsPage(queryClient, variables, pageParamForInitialPage, expectedPageData)

      const returnedPageData = getQueryDataForMemexItemsPage(queryClient, variables, pageParamForInitialPage)

      expect(returnedPageData).toEqual(expectedPageData)
    })
  })

  describe('getQueryDataForGroupedItemsPage', () => {
    it('returns data for a specific group from query client', () => {
      const queryClient = initQueryClient()

      const variables: PaginatedMemexItemsQueryVariables = {}
      const firstPageItems = [issueFactory.build(), issueFactory.build()].map(item => createMemexItemModel(item))
      const expectedPageData: MemexItemsPageQueryData = {
        nodes: firstPageItems,
        pageInfo: {hasNextPage: false, hasPreviousPage: false},
      }

      setQueryDataForGroupedItemsPage(
        queryClient,
        variables,
        {groupId: 'Todo'},
        pageParamForInitialPage,
        expectedPageData,
      )

      const returnedPageData = getQueryDataForGroupedItemsPage(
        queryClient,
        variables,
        {groupId: 'Todo'},
        pageParamForInitialPage,
      )

      expect(returnedPageData).toEqual(expectedPageData)
    })
  })

  describe('setQueryDataForMemexItemsPage', () => {
    it('updates ungrouped data in query client', () => {
      const queryClient = initQueryClient()

      const variables: PaginatedMemexItemsQueryVariables = {}
      const firstPageItems = [issueFactory.build(), issueFactory.build()].map(item => createMemexItemModel(item))
      const expectedPageData: MemexItemsPageQueryData = {
        nodes: firstPageItems,
        pageInfo: {hasNextPage: false, hasPreviousPage: false},
      }

      setQueryDataForMemexItemsPage(queryClient, variables, pageParamForInitialPage, expectedPageData)

      const returnedPageData = queryClient.getQueryData(
        buildMemexUngroupedItemsQueryKey(variables, pageParamForInitialPage),
      )
      expect(returnedPageData).toEqual(expectedPageData)
    })
  })

  describe('setQueryDataForGroupedItemsPage', () => {
    it('updates data for a single group in query client', () => {
      const queryClient = initQueryClient()

      const variables: PaginatedMemexItemsQueryVariables = {}
      const firstPageItems = [issueFactory.build(), issueFactory.build()].map(item => createMemexItemModel(item))
      const expectedPageData: MemexItemsPageQueryData = {
        nodes: firstPageItems,
        pageInfo: {hasNextPage: false, hasPreviousPage: false},
      }

      setQueryDataForGroupedItemsPage(
        queryClient,
        variables,
        {groupId: 'Todo'},
        pageParamForInitialPage,
        expectedPageData,
      )

      const returnedPageData = queryClient.getQueryData(
        buildMemexGroupedItemsQueryKey(variables, {groupId: 'Todo'}, pageParamForInitialPage),
      )
      expect(returnedPageData).toEqual(expectedPageData)
    })
  })

  describe('getMemexItemModelsFromQueryClient', () => {
    it('returns array of memex item models', () => {
      const queryClient = initQueryClient()
      const memexItemModels = [issueFactory.build()].map(item => createMemexItemModel(item))
      setInitialQueryClientItems(queryClient, memexItemModels)

      const returnedMemexItemModels = getMemexItemModelsFromQueryClient(queryClient)

      expect(returnedMemexItemModels).toBe(memexItemModels)
    })

    it(`'memex_table_without_limits' enabled: returns array of memex item models across pages`, () => {
      seedJSONIsland('memex-enabled-features', ['memex_table_without_limits'])

      const queryClient = initQueryClient()

      const memexItemModelsForFirstPage = [issueFactory.build()].map(item => createMemexItemModel(item))
      const memexItemModelsForSecondPage = [issueFactory.build()].map(item => createMemexItemModel(item))
      setAndActivateInitialQueriesByPage(queryClient, {}, [memexItemModelsForFirstPage, memexItemModelsForSecondPage])

      const returnedMemexItemModels = getMemexItemModelsFromQueryClient(queryClient)

      expect(returnedMemexItemModels).toEqual(memexItemModelsForFirstPage.concat(memexItemModelsForSecondPage))
    })
  })

  describe('getMemexItemsQueryDataFromQueryClient', () => {
    it('returns query data', () => {
      const queryClient = initQueryClient()
      const memexItemModels = [issueFactory.build()].map(item => createMemexItemModel(item))
      const initialQueryData = setQueryData(queryClient, {
        pages: [
          {
            nodes: memexItemModels,
            pageInfo: {endCursor: '', startCursor: '', hasNextPage: false, hasPreviousPage: false},
            totalCount: {value: memexItemModels.length, isApproximate: false},
          },
        ],
        pageParams: [],
      })

      const returnedQueryData = getMemexItemsQueryDataFromQueryClient(queryClient)

      expect(returnedQueryData).toBe(initialQueryData)
    })
  })

  describe('setMemexItemsQueryDataInQueryClient', () => {
    it('updates query data, but with new object identity', () => {
      const queryClient = initQueryClient()
      const memexItemModels = [issueFactory.build(), pullRequestFactory.build()].map(item => createMemexItemModel(item))
      const initialQueryData = {
        pages: [
          {
            nodes: memexItemModels,
            pageInfo: {endCursor: '', startCursor: '', hasNextPage: false, hasPreviousPage: false},
            totalCount: {value: memexItemModels.length, isApproximate: false},
          },
        ],
        pageParams: [],
      }

      setQueryData(queryClient, initialQueryData)

      setMemexItemsQueryDataInQueryClient(queryClient, initialQueryData)

      const retrievedQueryData = queryClient.getQueryData<UseMemexItemsQueryData>(useMemexItemsQuery.getKey())

      expect(retrievedQueryData === initialQueryData).toBeFalsy()
      expect(retrievedQueryData).toEqual(initialQueryData)
    })
  })

  describe('setMemexItemsToForceRerenderInQueryClient', () => {
    it('re-uses existing memex items, but with new array identity', () => {
      const queryClient = initQueryClient()
      const originalMemexItemModels = [issueFactory.build()].map(item => createMemexItemModel(item))
      setInitialQueryClientItems(queryClient, originalMemexItemModels)

      setMemexItemsToForceRerenderInQueryClient(queryClient)

      const newMemexItemModels = getQueryClientItems(queryClient)

      expect(newMemexItemModels === originalMemexItemModels).toBeFalsy()
      expect(newMemexItemModels).toEqual(originalMemexItemModels)
    })

    it(`'memex_table_without_limits' enabled: re-uses existing memex items, but with new array identity across multiple pages`, () => {
      seedJSONIsland('memex-enabled-features', ['memex_table_without_limits'])

      const queryClient = initQueryClient()
      const originalMemexItemModels = [issueFactory.build(), issueFactory.build()].map(item =>
        createMemexItemModel(item),
      )
      const queryKeys = setAndActivateInitialQueriesByPage(queryClient, {}, [
        [originalMemexItemModels[0]],
        [originalMemexItemModels[1]],
      ])

      setMemexItemsToForceRerenderInQueryClient(queryClient)

      const newMemexItemModels = getMemexItemModelsForQueryKeys(queryClient, queryKeys)

      expect(newMemexItemModels === originalMemexItemModels).toBeFalsy()
      expect(newMemexItemModels).toEqual(originalMemexItemModels)
    })
  })

  describe('hasMemexItemsQueryData', () => {
    it('returns true if data has been initialized', () => {
      const queryClient = initQueryClient()
      const memexItemModels = [issueFactory.build()].map(item => createMemexItemModel(item))
      setMemexItemsForPage(queryClient, {}, pageParamForInitialPage, memexItemModels)

      const hasQueryData = hasMemexItemsQueryData(queryClient)
      expect(hasQueryData).toBeTruthy()
    })

    it('returns true if data has been initialized with an empty array', () => {
      const queryClient = initQueryClient()
      setMemexItemsForPage(queryClient, {}, pageParamForInitialPage, [])

      const hasQueryData = hasMemexItemsQueryData(queryClient)

      expect(hasQueryData).toBeTruthy()
    })

    it('returns true if data has been initialized with variables', () => {
      const queryClient = initQueryClient()
      const memexItemModels = [issueFactory.build()].map(item => createMemexItemModel(item))
      setMemexItemsForPage(queryClient, {q: 'is:draft'}, pageParamForInitialPage, memexItemModels)

      const hasQueryData = hasMemexItemsQueryData(queryClient)
      expect(hasQueryData).toBeTruthy()
    })

    it('returns false if data has not been initialized', () => {
      const queryClient = initQueryClient()

      const hasQueryData = hasMemexItemsQueryData(queryClient)

      expect(hasQueryData).toBeFalsy()
    })
  })

  describe('findMemexItemByIdInQueryClient', () => {
    it('returns undefined for id not existing in QueryClient', () => {
      const queryClient = initQueryClient()
      const idForItemInQueryClient = 100
      const idForNonExistantItem = idForItemInQueryClient + 1
      setInitialQueryClientItems(
        queryClient,
        [issueFactory.build({id: idForItemInQueryClient})].map(item => createMemexItemModel(item)),
      )

      const memexItemModelFound = findMemexItemByIdInQueryClient(queryClient, idForNonExistantItem)

      expect(memexItemModelFound).toBeUndefined()
    })

    it('returns item found in QueryClient', () => {
      const queryClient = initQueryClient()
      const idForItemInQueryClient = 100
      const itemModel = createMemexItemModel(issueFactory.build({id: idForItemInQueryClient}))
      setInitialQueryClientItems(queryClient, [itemModel])

      const memexItemModelFound = findMemexItemByIdInQueryClient(queryClient, idForItemInQueryClient)

      expect(memexItemModelFound).toBe(itemModel)
    })

    it(`'memex_table_without_limits' enabled: returns item found in QueryClient in second page of data`, () => {
      seedJSONIsland('memex-enabled-features', ['memex_table_without_limits'])

      const queryClient = initQueryClient()
      const idForItemInSecondPage = 100
      const itemModel = createMemexItemModel(issueFactory.build({id: idForItemInSecondPage}))
      const otherItemModel = createMemexItemModel(issueFactory.build())
      // Initial query data with two pages, each with a single item
      setInitialQueriesByPage(queryClient, {}, [[otherItemModel], [itemModel]])

      const memexItemModelFound = findMemexItemByIdInQueryClient(queryClient, idForItemInSecondPage)

      // Verify we can find an item even if it is in the second page of data.
      expect(memexItemModelFound).toBe(itemModel)
    })
  })

  describe('isMemexItemByIdPartOfGroupByIdInQueryClient', () => {
    it('returns false if item model by id is not existent as part of group by id in QueryClient', () => {
      seedJSONIsland('memex-enabled-features', ['memex_table_without_limits'])
      const queryClient = initQueryClient()

      const groupId = 'Todo'
      const idForItemInQueryClient = 100
      const idForNonExistantItem = idForItemInQueryClient + 1
      const variables: PaginatedMemexItemsQueryVariables = {q: ''}
      const firstPageItems = [issueFactory.build({id: idForItemInQueryClient})].map(item => createMemexItemModel(item))

      setAndActivateInitialQueriesByPageForGroup(
        queryClient,
        variables,
        {groupId},
        [firstPageItems],
        100, // total items on server
      )
      setPageParamsQueryDataForVariables(queryClient, variables, {
        groupedItems: {
          group1: [pageParamForInitialPage],
        },
        pageParams: [pageParamForInitialPage],
      })

      const memexItemModelFound = isMemexItemInGroup(queryClient, idForNonExistantItem, groupId)

      expect(memexItemModelFound).toBeFalsy()
    })

    it('returns true if item model by id is part of group by id in QueryClient', () => {
      seedJSONIsland('memex-enabled-features', ['memex_table_without_limits'])
      const queryClient = initQueryClient()

      const groupId = 'Todo'
      const idForItemInQueryClient = 100
      const variables: PaginatedMemexItemsQueryVariables = {q: ''}
      const firstPageItems = [issueFactory.build({id: idForItemInQueryClient}), pullRequestFactory.build()].map(item =>
        createMemexItemModel(item),
      )

      setAndActivateInitialQueriesByPageForGroup(
        queryClient,
        variables,
        {groupId},
        [
          [firstPageItems[1]], // page 1,
          [firstPageItems[0]], // page 2,
        ],
        100, // total items on server
      )
      setPageParamsQueryDataForVariables(queryClient, variables, {
        groupedItems: {
          group1: [pageParamForInitialPage],
        },
        pageParams: [pageParamForInitialPage],
      })

      const memexItemModelFound = isMemexItemInGroup(queryClient, idForItemInQueryClient, groupId)

      // Verify we can find an item even if it is in the second page of data.
      expect(memexItemModelFound).toBeTruthy()
    })
  })

  describe('findMemexItemGlobalIndexByIdInQueryClient', () => {
    it('returns -1 for id not existing in QueryClient', () => {
      const queryClient = initQueryClient()
      const idForItemInQueryClient = 100
      const idForNonExistantItem = idForItemInQueryClient + 1
      setInitialQueryClientItems(
        queryClient,
        [issueFactory.build({id: idForItemInQueryClient})].map(item => createMemexItemModel(item)),
      )

      const index = findMemexItemGlobalIndexByIdInQueryClient(queryClient, idForNonExistantItem)
      expect(index).toBe(-1)
    })

    it('returns index for item found in QueryClient', () => {
      const queryClient = initQueryClient()
      const idForItemInQueryClient = 100
      const itemModel = createMemexItemModel(issueFactory.build({id: idForItemInQueryClient}))
      setInitialQueryClientItems(queryClient, [itemModel])

      const index = findMemexItemGlobalIndexByIdInQueryClient(queryClient, idForItemInQueryClient)
      expect(index).toBe(0)
    })

    it(`'memex_table_without_limits' enabled: returns index for item found in QueryClient in second page of data`, () => {
      seedJSONIsland('memex-enabled-features', ['memex_table_without_limits'])

      const queryClient = initQueryClient()
      const idForItemInSecondPage = 100
      const itemModel = createMemexItemModel(issueFactory.build({id: idForItemInSecondPage}))
      const firstPageItemModel = createMemexItemModel(issueFactory.build())
      const otherSecondPageItemModel = createMemexItemModel(issueFactory.build())
      // Initial query data with two pages, and the second page has two items
      setInitialQueriesByPage(queryClient, {}, [[firstPageItemModel], [otherSecondPageItemModel, itemModel]])

      const index = findMemexItemGlobalIndexByIdInQueryClient(queryClient, idForItemInSecondPage)

      // Verify we can find an item's index even if it is in the second page of data.
      expect(index).toBe(2)
    })
  })

  describe('addMemexItemToQueryClient', () => {
    it('updates item if it is already in array', () => {
      const queryClient = initQueryClient()
      const originalMemexItemModels = [issueFactory.build()].map(item => createMemexItemModel(item))
      setInitialQueryClientItems(queryClient, originalMemexItemModels)

      originalMemexItemModels[0].memexProjectColumnValues = [
        columnValueFactory.title('A Brand New Title', ItemType.Issue).build(),
      ]

      addMemexItemToQueryClient(queryClient, originalMemexItemModels[0])
      const newMemexItemModels = getQueryClientItems(queryClient)

      expect(originalMemexItemModels).toStrictEqual(newMemexItemModels)
    })

    it('pushes item to end of array if no index is provided', () => {
      const queryClient = initQueryClient()
      const originalMemexItemModels = [issueFactory.build()].map(item => createMemexItemModel(item))
      setInitialQueryClientItems(queryClient, originalMemexItemModels)
      const newMemexItemModel = createMemexItemModel(pullRequestFactory.build())

      addMemexItemToQueryClient(queryClient, newMemexItemModel)
      const newMemexItemModels = getQueryClientItems(queryClient)

      expect(newMemexItemModels === originalMemexItemModels).toBeFalsy()
      expect(newMemexItemModels).toHaveLength(2)
      expect(newMemexItemModels[0]).toBe(originalMemexItemModels[0])
      expect(newMemexItemModels[1]).toBe(newMemexItemModel)
      expect(newMemexItemModels[0].prioritizedIndex).toEqual(0)
      expect(newMemexItemModels[1].prioritizedIndex).toEqual(1)
    })

    it('inserts item at index provided', () => {
      const queryClient = initQueryClient()
      const originalMemexItemModels = [issueFactory.build()].map(item => createMemexItemModel(item))
      setInitialQueryClientItems(queryClient, originalMemexItemModels)
      const newMemexItemModel = createMemexItemModel(pullRequestFactory.build())

      addMemexItemToQueryClient(queryClient, newMemexItemModel, 0)
      const newMemexItemModels = getQueryClientItems(queryClient)

      expect(newMemexItemModels === originalMemexItemModels).toBeFalsy()
      expect(newMemexItemModels).toHaveLength(2)
      expect(newMemexItemModels[0]).toBe(newMemexItemModel)
      expect(newMemexItemModels[1]).toBe(originalMemexItemModels[0])
      expect(newMemexItemModels[0].prioritizedIndex).toEqual(0)
      expect(newMemexItemModels[1].prioritizedIndex).toEqual(1)
    })

    it(`memex_table_without_limits enabled: pushes item to end of array if no index is provided across multiple pages`, () => {
      seedJSONIsland('memex-enabled-features', ['memex_table_without_limits'])

      const variables: PaginatedMemexItemsQueryVariables = {q: ''}

      const queryClient = initQueryClient()
      const originalMemexItemModels = [issueFactory.build(), issueFactory.build()].map(item =>
        createMemexItemModel(item),
      )

      const queryKeys = setAndActivateInitialQueriesByPage(queryClient, variables, [
        [originalMemexItemModels[0]],
        [originalMemexItemModels[1]],
      ])

      const newMemexItemModel = createMemexItemModel(pullRequestFactory.build())

      addMemexItemToQueryClient(queryClient, newMemexItemModel)
      const newMemexItemModels = getMemexItemModelsForQueryKeys(queryClient, queryKeys)

      expect(newMemexItemModels === originalMemexItemModels).toBeFalsy()
      expect(newMemexItemModels).toHaveLength(3)
      expect(newMemexItemModels[0]).toBe(originalMemexItemModels[0])
      expect(newMemexItemModels[1]).toBe(originalMemexItemModels[1])
      expect(newMemexItemModels[2]).toBe(newMemexItemModel)
    })
    it(`'memex_table_without_limits' enabled: pushes item to end of array if no index is provided across multiple pages and groups`, () => {
      seedJSONIsland('memex-enabled-features', ['memex_table_without_limits'])

      const queryClient = initQueryClient()
      const variables: PaginatedMemexItemsQueryVariables = {q: ''}
      const originalMemexItemModels = [issueFactory.build(), issueFactory.build()].map(item =>
        createMemexItemModel(item),
      )

      // Include a query of groups in the query cache so that we can test the state where there are active
      // queries for both groups and items.
      // This should help prevent https://github.com/github/projects-platform/issues/1202 from regressing

      setQueryDataForMemexGroupsPage(queryClient, variables, pageParamForInitialPage, {
        groups: [{groupId: 'group1', groupValue: 'Group Name'}],
        pageInfo: {hasNextPage: false, hasPreviousPage: false},
      })
      activateQueryByQueryKey(queryClient, buildMemexGroupsQueryKey(variables, pageParamForInitialPage))

      const queryKeys = setAndActivateInitialQueriesByPageForGroup(queryClient, variables, {groupId: 'group1'}, [
        [originalMemexItemModels[0]],
        [originalMemexItemModels[1]],
      ])

      const newMemexItemModel = createMemexItemModel(pullRequestFactory.build())

      addMemexItemToQueryClient(queryClient, newMemexItemModel)
      const newMemexItemModels = getMemexItemModelsForQueryKeys(queryClient, queryKeys)

      expect(newMemexItemModels === originalMemexItemModels).toBeFalsy()
      expect(newMemexItemModels).toHaveLength(3)
      expect(newMemexItemModels[0]).toBe(originalMemexItemModels[0])
      expect(newMemexItemModels[1]).toBe(originalMemexItemModels[1])
      expect(newMemexItemModels[2]).toBe(newMemexItemModel)
    })

    it(`'memex_table_without_limits' enabled: inserts item at index provided across multiple pages`, () => {
      seedJSONIsland('memex-enabled-features', ['memex_table_without_limits'])
      const variables: PaginatedMemexItemsQueryVariables = {q: ''}

      const queryClient = initQueryClient()
      const originalMemexItemModels = [issueFactory.build(), issueFactory.build(), issueFactory.build()].map(item =>
        createMemexItemModel(item),
      )
      const queryKeys = setAndActivateInitialQueriesByPage(queryClient, variables, [
        [originalMemexItemModels[0]], // page 1
        [originalMemexItemModels[1], originalMemexItemModels[2]], // page 2
      ])

      const initialMemexItemModels = getMemexItemModelsForQueryKeys(queryClient, queryKeys)
      expect(initialMemexItemModels).toHaveLength(3)

      const newMemexItemModel = createMemexItemModel(pullRequestFactory.build())

      addMemexItemToQueryClient(queryClient, newMemexItemModel, 2)
      const newMemexItemModels = getMemexItemModelsForQueryKeys(queryClient, queryKeys)

      expect(newMemexItemModels === originalMemexItemModels).toBeFalsy()
      expect(newMemexItemModels).toHaveLength(4)
      expect(newMemexItemModels[0]).toBe(originalMemexItemModels[0])
      expect(newMemexItemModels[1]).toBe(originalMemexItemModels[1])
      expect(newMemexItemModels[2]).toBe(newMemexItemModel)
      expect(newMemexItemModels[3]).toBe(originalMemexItemModels[2])

      const newTotalCounts = getQueryDataForMemexItemsTotalCounts(queryClient, variables)
      expect(newTotalCounts.totalCount.value).toEqual(4)
    })

    it(`'memex_table_without_limits' enabled: does not add item if last page has "hasNextPage: true"`, () => {
      seedJSONIsland('memex-enabled-features', ['memex_table_without_limits'])
      const variables: PaginatedMemexItemsQueryVariables = {q: ''}

      const queryClient = initQueryClient()
      const originalMemexItemModels = [issueFactory.build()].map(item => createMemexItemModel(item))
      const queryKeys = setAndActivateInitialQueriesByPage(
        queryClient,
        variables,
        [
          [originalMemexItemModels[0]], // page 1
        ],
        100, // total items on server
      )
      // We want to set `hasNextPage` to true so that we can test the case where we are inserting an item
      // when we aren't at our last page of data.
      // Get the query data for the page so that we can modify it to `hasNextPage: true`
      const initialPageData = getQueryDataForMemexItemsPage(queryClient, variables, pageParamForInitialPage)!
      setQueryDataForMemexItemsPage(queryClient, variables, pageParamForInitialPage, {
        ...initialPageData,
        pageInfo: {hasNextPage: true, hasPreviousPage: false},
      })

      const initialMemexItemModels = getMemexItemModelsForQueryKeys(queryClient, queryKeys)
      expect(initialMemexItemModels).toHaveLength(1)

      const newMemexItemModel = createMemexItemModel(pullRequestFactory.build())

      addMemexItemToQueryClient(queryClient, newMemexItemModel)
      const newMemexItemModels = getMemexItemModelsForQueryKeys(queryClient, queryKeys)

      expect(newMemexItemModels === originalMemexItemModels).toBeFalsy()
      expect(newMemexItemModels).toHaveLength(1)
      expect(newMemexItemModels[0]).toBe(originalMemexItemModels[0])

      const newTotalCounts = getQueryDataForMemexItemsTotalCounts(queryClient, variables)
      // Should still update the total count even if we don't add the item on the client
      expect(newTotalCounts.totalCount.value).toEqual(101)
    })
  })

  describe('addMemexItemForGroupToQueryClient', () => {
    it(`adds item to end of last page for group when only one page`, () => {
      const queryClient = initQueryClient()
      const variables: PaginatedMemexItemsQueryVariables = {q: ''}
      const originalMemexItemModels = [issueFactory.build()].map(item => createMemexItemModel(item))
      const queryKeys = setAndActivateInitialQueriesByPageForGroup(queryClient, variables, {groupId: 'group1'}, [
        [originalMemexItemModels[0]], // page 1
      ])
      setPageParamsQueryDataForVariables(queryClient, variables, {
        groupedItems: {
          group1: [pageParamForInitialPage],
        },
        pageParams: [pageParamForInitialPage],
      })
      const originalTotalCounts = getQueryDataForMemexItemsTotalCounts(queryClient, variables)
      expect(originalTotalCounts.groups['group1']?.value).toEqual(1)
      expect(originalTotalCounts.totalCount.value).toEqual(1)

      const newMemexItemModel = createMemexItemModel(pullRequestFactory.build())

      addMemexItemForGroupToQueryClient(queryClient, newMemexItemModel, {groupId: 'group1'})
      const newMemexItemModels = getMemexItemModelsForQueryKeys(queryClient, queryKeys)

      expect(newMemexItemModels).toHaveLength(2)
      expect(newMemexItemModels[0]).toBe(originalMemexItemModels[0])
      expect(newMemexItemModels[1]).toBe(newMemexItemModel)

      const newTotalCounts = getQueryDataForMemexItemsTotalCounts(queryClient, variables)
      expect(newTotalCounts.groups['group1']?.value).toEqual(2)
      expect(newTotalCounts.totalCount.value).toEqual(2)
    })

    it(`adds item to end of last page for group if multiple pages`, () => {
      const queryClient = initQueryClient()
      const variables: PaginatedMemexItemsQueryVariables = {q: ''}
      const originalMemexItemModels = [issueFactory.build(), issueFactory.build()].map(item =>
        createMemexItemModel(item),
      )
      const queryKeys = setAndActivateInitialQueriesByPageForGroup(
        queryClient,
        variables,
        {groupId: 'group1'},
        [
          [originalMemexItemModels[0]], // page 1
          [originalMemexItemModels[1]], // page 2
        ],
        100, // total items on server
      )
      setPageParamsQueryDataForVariables(queryClient, variables, {
        groupedItems: {
          group1: [pageParamForInitialPage, {after: '1'}],
        },
        pageParams: [pageParamForInitialPage],
      })

      const newMemexItemModel = createMemexItemModel(pullRequestFactory.build())

      addMemexItemForGroupToQueryClient(queryClient, newMemexItemModel, {groupId: 'group1'})
      const newMemexItemModels = getMemexItemModelsForQueryKeys(queryClient, queryKeys)

      expect(newMemexItemModels).toHaveLength(3)
      expect(newMemexItemModels[0]).toBe(originalMemexItemModels[0])
      expect(newMemexItemModels[1]).toBe(originalMemexItemModels[1])
      expect(newMemexItemModels[2]).toBe(newMemexItemModel)

      const newTotalCounts = getQueryDataForMemexItemsTotalCounts(queryClient, variables)
      expect(newTotalCounts.groups['group1']?.value).toEqual(3)
      expect(newTotalCounts.totalCount.value).toEqual(101)
    })

    it(`adds item to end of last page for group with sparse groupedItems`, () => {
      const queryClient = initQueryClient()
      const variables: PaginatedMemexItemsQueryVariables = {q: ''}

      const groupsPageData: MemexGroupsPageQueryData = {
        groups: [
          {
            groupId: 'serverGroup1Id',
            groupValue: 'Group 1',
            groupMetadata: {
              id: 'group1',
              color: 'RED',
              name: 'Group 1',
              nameHtml: 'Group 1',
              description: '',
              descriptionHtml: '',
            },
          },
          {
            groupId: 'serverGroup2Id',
            groupValue: 'Group 2',
            groupMetadata: {
              id: 'group2',
              color: 'RED',
              name: 'Group 2',
              nameHtml: 'Group 2',
              description: '',
              descriptionHtml: '',
            },
          },
        ],
        pageInfo: {hasNextPage: false, hasPreviousPage: false},
      }
      const groupsQueryKey = buildMemexGroupsQueryKey(variables, pageParamForInitialPage)
      queryClient.setQueryData(groupsQueryKey, groupsPageData)
      activateQueryByQueryKey(queryClient, groupsQueryKey)

      const originalMemexItemModels = [issueFactory.build()].map(item => createMemexItemModel(item))
      const queryKeys = setAndActivateInitialQueriesByPageForGroup(
        queryClient,
        variables,
        {groupId: 'serverGroup1Id'},
        [[originalMemexItemModels[0]]],
        // explicitly _not_ including query data for serverGroup2Id
        100, // total items on server
      )
      setPageParamsQueryDataForVariables(queryClient, variables, {
        groupedItems: {
          serverGroup1Id: [pageParamForInitialPage],
          // explicitly _not_ including page params for serverGroup2Id
        },
        pageParams: [pageParamForInitialPage],
      })

      const newMemexItemModel = createMemexItemModel(pullRequestFactory.build())

      // Add an item to the empty group
      addMemexItemForGroupToQueryClient(queryClient, newMemexItemModel, {groupId: 'serverGroup2Id'})

      // We now have a query key for the second group
      const newQueryKeys = [
        ...queryKeys,
        buildMemexGroupedItemsQueryKey(variables, {groupId: 'serverGroup2Id'}, pageParamForInitialPage),
      ]
      const newMemexItemModels = getMemexItemModelsForQueryKeys(queryClient, newQueryKeys)

      expect(newMemexItemModels).toHaveLength(2)
      expect(newMemexItemModels[0]).toBe(originalMemexItemModels[0])
      expect(newMemexItemModels[1]).toBe(newMemexItemModel)

      const newTotalCounts = getQueryDataForMemexItemsTotalCounts(queryClient, variables)
      expect(newTotalCounts.groups['serverGroup1Id']?.value).toEqual(1)
      expect(newTotalCounts.groups['serverGroup2Id']?.value).toEqual(1)
      expect(newTotalCounts.totalCount.value).toEqual(101)
    })

    it(`does not add item to page that has more data`, () => {
      const queryClient = initQueryClient()
      const variables: PaginatedMemexItemsQueryVariables = {q: ''}
      const originalMemexItemModels = [issueFactory.build(), issueFactory.build()].map(item =>
        createMemexItemModel(item),
      )
      const queryKeys = setAndActivateInitialQueriesByPageForGroup(
        queryClient,
        variables,
        {groupId: 'group1'},
        [
          [originalMemexItemModels[0]], // page 1
        ],
        100, // total items on server
      )
      setPageParamsQueryDataForVariables(queryClient, variables, {
        groupedItems: {
          group1: [pageParamForInitialPage],
        },
        pageParams: [pageParamForInitialPage],
      })

      // We want to set `hasNextPage` to true so that we can test the case where we are inserting an item
      // when we aren't at our last page of data.
      // Get the query data for the page so that we can modify it to `hasNextPage: true`
      const initialPageData = getQueryDataForGroupedItemsPage(
        queryClient,
        variables,
        {groupId: 'group1'},
        pageParamForInitialPage,
      )!
      setQueryDataForGroupedItemsPage(queryClient, variables, {groupId: 'group1'}, pageParamForInitialPage, {
        ...initialPageData,
        pageInfo: {hasNextPage: true, hasPreviousPage: false},
      })

      const newMemexItemModel = createMemexItemModel(pullRequestFactory.build())

      addMemexItemForGroupToQueryClient(queryClient, newMemexItemModel, {groupId: 'group1'})
      const newMemexItemModels = getMemexItemModelsForQueryKeys(queryClient, queryKeys)

      expect(newMemexItemModels).toHaveLength(1)
      expect(newMemexItemModels[0]).toBe(originalMemexItemModels[0])

      const newTotalCounts = getQueryDataForMemexItemsTotalCounts(queryClient, variables)
      // Should update totals even when item isn't added to pages on client
      expect(newTotalCounts.groups['group1']?.value).toEqual(2)
      expect(newTotalCounts.totalCount.value).toEqual(101)
    })

    it(`deduplicates items if the item to add already exists`, () => {
      seedJSONIsland('memex-enabled-features', ['memex_table_without_limits'])
      const queryClient = initQueryClient()
      const variables: PaginatedMemexItemsQueryVariables = {q: ''}

      const groupsPageData: MemexGroupsPageQueryData = {
        groups: [
          {
            groupId: 'serverGroup1Id',
            groupValue: 'Group 1',
            groupMetadata: {
              id: 'group1',
              color: 'RED',
              name: 'Group 1',
              nameHtml: 'Group 1',
              description: '',
              descriptionHtml: '',
            },
          },
          {
            groupId: 'serverGroup2Id',
            groupValue: 'Group 2',
            groupMetadata: {
              id: 'group2',
              color: 'RED',
              name: 'Group 2',
              nameHtml: 'Group 2',
              description: '',
              descriptionHtml: '',
            },
          },
        ],
        pageInfo: {hasNextPage: false, hasPreviousPage: false},
      }
      const groupsQueryKey = buildMemexGroupsQueryKey(variables, pageParamForInitialPage)
      queryClient.setQueryData(groupsQueryKey, groupsPageData)
      activateQueryByQueryKey(queryClient, groupsQueryKey)

      const originalMemexItemModels = [issueFactory.build()].map(item => createMemexItemModel(item))
      const queryKeys = setAndActivateInitialQueriesByPageForGroup(
        queryClient,
        variables,
        {groupId: 'serverGroup1Id'},
        [[originalMemexItemModels[0]]],
        // explicitly _not_ including query data for serverGroup2Id
        100, // total items on server
      )
      setPageParamsQueryDataForVariables(queryClient, variables, {
        groupedItems: {
          serverGroup1Id: [pageParamForInitialPage],
          // explicitly _not_ including page params for serverGroup2Id
        },
        pageParams: [pageParamForInitialPage],
      })

      // Add an existing item to the empty group
      addMemexItemForGroupToQueryClient(queryClient, originalMemexItemModels[0], {groupId: 'serverGroup2Id'})

      // We now have a query key for the second group
      const newQueryKeys = [
        ...queryKeys,
        buildMemexGroupedItemsQueryKey(variables, {groupId: 'serverGroup2Id'}, pageParamForInitialPage),
      ]

      const newMemexItemModels = getMemexItemModelsForQueryKeys(queryClient, newQueryKeys)
      expect(newMemexItemModels).toHaveLength(1)
      expect(newMemexItemModels[0]).toBe(originalMemexItemModels[0])

      // now verify the item only exist in group 2, and total count remains unchanged!
      const newTotalCounts = getQueryDataForMemexItemsTotalCounts(queryClient, variables)
      expect(newTotalCounts.groups['serverGroup1Id']?.value).toEqual(0)
      expect(newTotalCounts.groups['serverGroup2Id']?.value).toEqual(1)
      expect(newTotalCounts.totalCount.value).toEqual(100)
    })

    it(`when secondary grouping is present, adds item to end of page when only one page`, () => {
      seedJSONIsland('memex-enabled-features', ['memex_table_without_limits'])
      const queryClient = initQueryClient()
      const variables: PaginatedMemexItemsQueryVariables = {
        verticalGroupedByColumnId: 'Status',
        horizontalGroupedByColumnId: 'Status',
      }
      const originalMemexItemModels = [issueFactory.build()].map(item => createMemexItemModel(item))

      const groupsPageData: MemexGroupsPageQueryData = {
        groups: [
          {
            groupId: 'serverGroup1Id',
            groupValue: 'Group 1',
            groupMetadata: {
              id: 'group1',
              color: 'RED',
              name: 'Group 1',
              nameHtml: 'Group 1',
              description: '',
              descriptionHtml: '',
            },
          },
        ],
        pageInfo: {hasNextPage: false, hasPreviousPage: false},
      }
      const groupsQueryKey = buildMemexGroupsQueryKey(variables, pageParamForInitialPage)
      queryClient.setQueryData(groupsQueryKey, groupsPageData)
      activateQueryByQueryKey(queryClient, groupsQueryKey)

      const secondaryGroupsPageData: MemexGroupsPageQueryData = {
        groups: [
          {
            groupId: 'serverSecondaryGroup1Id',
            groupValue: 'Secondary Group 1',
            groupMetadata: {
              id: 'secondaryGroup1',
              name: 'Secondary Group 1',
              nameHtml: 'Secondary Group 1',
              color: 'RED',
              description: '',
              descriptionHtml: '',
            },
          },
        ],
        pageInfo: {hasNextPage: false, hasPreviousPage: false},
      }
      const secondaryGroupsQueryKey = buildMemexSecondaryGroupsQueryKey(variables, pageParamForInitialPage)
      queryClient.setQueryData(secondaryGroupsQueryKey, secondaryGroupsPageData)
      activateQueryByQueryKey(queryClient, secondaryGroupsQueryKey)

      const queryKeys = setAndActivateInitialQueriesByPageForGroup(
        queryClient,
        variables,
        {groupId: 'serverGroup1Id', secondaryGroupId: 'serverSecondaryGroup1Id'},
        [
          originalMemexItemModels, // page 1
        ],
      )
      setPageParamsQueryDataForVariables(queryClient, variables, {
        groupedItems: {
          [createGroupedItemsId({groupId: 'serverGroup1Id', secondaryGroupId: 'serverSecondaryGroup1Id'})]: [
            pageParamForInitialPage,
          ],
        },
        pageParams: [pageParamForInitialPage],
        secondaryGroups: [pageParamForInitialPage],
      })

      const originalTotalCounts = getQueryDataForMemexItemsTotalCounts(queryClient, variables)
      expect(originalTotalCounts.groups['serverGroup1Id']?.value).toEqual(1)
      expect(originalTotalCounts.groups['serverSecondaryGroup1Id']?.value).toEqual(1)
      expect(originalTotalCounts.totalCount.value).toEqual(1)

      const newMemexItemModel = createMemexItemModel(pullRequestFactory.build())

      addMemexItemForGroupToQueryClient(queryClient, newMemexItemModel, {
        groupId: 'serverGroup1Id',
        secondaryGroupId: 'serverSecondaryGroup1Id',
      })
      const newMemexItemModels = getMemexItemModelsForQueryKeys(queryClient, queryKeys)

      expect(newMemexItemModels).toHaveLength(2)
      expect(newMemexItemModels[0]).toBe(originalMemexItemModels[0])
      expect(newMemexItemModels[1]).toBe(newMemexItemModel)

      const newTotalCounts = getQueryDataForMemexItemsTotalCounts(queryClient, variables)
      expect(newTotalCounts.groups['serverGroup1Id']?.value).toEqual(2)
      expect(newTotalCounts.groups['serverSecondaryGroup1Id']?.value).toEqual(2)
      expect(newTotalCounts.totalCount.value).toEqual(2)
    })

    it(`when secondary grouping is present, adds item to empty cell`, () => {
      seedJSONIsland('memex-enabled-features', ['memex_table_without_limits'])
      const queryClient = initQueryClient()
      const variables: PaginatedMemexItemsQueryVariables = {q: ''}

      const groupsPageData: MemexGroupsPageQueryData = {
        groups: [
          {
            groupId: 'serverGroup1Id',
            groupValue: 'Group 1',
            groupMetadata: {
              id: 'group1',
              color: 'RED',
              name: 'Group 1',
              nameHtml: 'Group 1',
              description: '',
              descriptionHtml: '',
            },
          },
        ],
        pageInfo: {hasNextPage: false, hasPreviousPage: false},
      }
      const groupsQueryKey = buildMemexGroupsQueryKey(variables, pageParamForInitialPage)
      queryClient.setQueryData(groupsQueryKey, groupsPageData)
      activateQueryByQueryKey(queryClient, groupsQueryKey)

      const secondaryGroupsPageData: MemexGroupsPageQueryData = {
        groups: [
          {
            groupId: 'serverSecondaryGroup1Id',
            groupValue: 'Secondary group 1',
            groupMetadata: {
              id: 'secondaryGroup1',
              color: 'BLUE',
              name: 'Secondary group 1',
              nameHtml: 'Secondary group 1',
              description: '',
              descriptionHtml: '',
            },
          },
        ],
        pageInfo: {hasNextPage: false, hasPreviousPage: false},
      }
      const secondaryGroupsQueryKey = buildMemexGroupsQueryKey(variables, pageParamForInitialPage)
      queryClient.setQueryData(secondaryGroupsQueryKey, secondaryGroupsPageData)
      activateQueryByQueryKey(queryClient, secondaryGroupsQueryKey)

      setPageParamsQueryDataForVariables(queryClient, variables, {
        groupedItems: {
          // explicitly _not_ including page params for any grouped items
        },
        pageParams: [pageParamForInitialPage],
      })

      const originalTotalCounts = {
        groups: {
          serverGroup1Id: {value: 0, isApproximate: false},
          serverSecondaryGroup1Id: {value: 0, isApproximate: false},
        },
        totalCount: {
          value: 0,
          isApproximate: false,
        },
      }
      mergeQueryDataForMemexItemsTotalCounts(queryClient, variables, originalTotalCounts)

      const newMemexItemModel = createMemexItemModel(pullRequestFactory.build())

      // Add item to the empty cell
      addMemexItemForGroupToQueryClient(queryClient, newMemexItemModel, {
        groupId: 'serverGroup1Id',
        secondaryGroupId: 'serverSecondaryGroup1Id',
      })

      // We should now have a query key for the grouped items cell
      const newQueryKeys = [
        buildMemexGroupedItemsQueryKey(
          variables,
          {groupId: 'serverGroup1Id', secondaryGroupId: 'serverSecondaryGroup1Id'},
          pageParamForInitialPage,
        ),
      ]
      const newMemexItemModels = getMemexItemModelsForQueryKeys(queryClient, newQueryKeys)

      expect(newMemexItemModels).toHaveLength(1)
      expect(newMemexItemModels[0]).toBe(newMemexItemModel)

      // We optimistically updated the counts
      const newTotalCounts = getQueryDataForMemexItemsTotalCounts(queryClient, variables)
      expect(newTotalCounts.groups['serverGroup1Id']?.value).toEqual(1)
      expect(newTotalCounts.groups['serverSecondaryGroup1Id']?.value).toEqual(1)
      expect(newTotalCounts.totalCount.value).toEqual(1)
    })

    it(`when secondary grouping is present, does not add item to page that has more data`, () => {
      seedJSONIsland('memex-enabled-features', ['memex_table_without_limits'])
      const queryClient = initQueryClient()
      const variables: PaginatedMemexItemsQueryVariables = {
        verticalGroupedByColumnId: 'Status',
        horizontalGroupedByColumnId: 'Status',
      }
      const originalMemexItemModels = [issueFactory.build()].map(item => createMemexItemModel(item))

      const groupsPageData: MemexGroupsPageQueryData = {
        groups: [
          {
            groupId: 'serverGroup1Id',
            groupValue: 'Group 1',
            groupMetadata: {
              id: 'group1',
              color: 'RED',
              name: 'Group 1',
              nameHtml: 'Group 1',
              description: '',
              descriptionHtml: '',
            },
          },
        ],
        pageInfo: {hasNextPage: false, hasPreviousPage: false},
      }
      const groupsQueryKey = buildMemexGroupsQueryKey(variables, pageParamForInitialPage)
      queryClient.setQueryData(groupsQueryKey, groupsPageData)
      activateQueryByQueryKey(queryClient, groupsQueryKey)

      const secondaryGroupsPageData: MemexGroupsPageQueryData = {
        groups: [
          {
            groupId: 'serverSecondaryGroup1Id',
            groupValue: 'Secondary Group 1',
            groupMetadata: {
              id: 'secondaryGroup1',
              name: 'Secondary Group 1',
              nameHtml: 'Secondary Group 1',
              color: 'RED',
              description: '',
              descriptionHtml: '',
            },
          },
        ],
        pageInfo: {hasNextPage: false, hasPreviousPage: false},
      }
      const secondaryGroupsQueryKey = buildMemexSecondaryGroupsQueryKey(variables, pageParamForInitialPage)
      queryClient.setQueryData(secondaryGroupsQueryKey, secondaryGroupsPageData)
      activateQueryByQueryKey(queryClient, secondaryGroupsQueryKey)

      const queryKeys = setAndActivateInitialQueriesByPageForGroup(
        queryClient,
        variables,
        {groupId: 'serverGroup1Id', secondaryGroupId: 'serverSecondaryGroup1Id'},
        [
          originalMemexItemModels, // page 1
        ],
        100, // total items on server
      )
      setPageParamsQueryDataForVariables(queryClient, variables, {
        groupedItems: {
          [createGroupedItemsId({groupId: 'serverGroup1Id', secondaryGroupId: 'serverSecondaryGroup1Id'})]: [
            pageParamForInitialPage,
          ],
        },
        pageParams: [pageParamForInitialPage],
        secondaryGroups: [pageParamForInitialPage],
      })

      // We want to set `hasNextPage` to true so that we can test the case where we are inserting an item
      // when we aren't at our last page of data.
      // Get the query data for the page so that we can modify it to `hasNextPage: true`
      const initialPageData = getQueryDataForGroupedItemsPage(
        queryClient,
        variables,
        {groupId: 'serverGroup1Id', secondaryGroupId: 'serverSecondaryGroup1Id'},
        pageParamForInitialPage,
      )!
      setQueryDataForGroupedItemsPage(
        queryClient,
        variables,
        {groupId: 'serverGroup1Id', secondaryGroupId: 'serverSecondaryGroup1Id'},
        pageParamForInitialPage,
        {
          ...initialPageData,
          pageInfo: {hasNextPage: true, hasPreviousPage: false},
        },
      )

      const newMemexItemModel = createMemexItemModel(pullRequestFactory.build())

      addMemexItemForGroupToQueryClient(queryClient, newMemexItemModel, {
        groupId: 'serverGroup1Id',
        secondaryGroupId: 'serverSecondaryGroup1Id',
      })
      const newMemexItemModels = getMemexItemModelsForQueryKeys(queryClient, queryKeys)

      expect(newMemexItemModels).toHaveLength(1)
      expect(newMemexItemModels[0]).toBe(originalMemexItemModels[0])

      const newTotalCounts = getQueryDataForMemexItemsTotalCounts(queryClient, variables)
      // Should update totals even when item isn't added to pages on client
      expect(newTotalCounts.groups['serverGroup1Id']?.value).toEqual(2)
      expect(newTotalCounts.groups['serverSecondaryGroup1Id']?.value).toEqual(2)
      expect(newTotalCounts.totalCount.value).toEqual(101)
    })
  })

  describe('removeMemexItemsFromQueryClient', () => {
    it('removes matching items and returns array with new identity', () => {
      const queryClient = initQueryClient()
      const originalMemexItemModels = [issueFactory.build(), pullRequestFactory.build(), draftIssueFactory.build()].map(
        item => createMemexItemModel(item),
      )
      setInitialQueryClientItems(queryClient, originalMemexItemModels)

      removeMemexItemsFromQueryClient(queryClient, [originalMemexItemModels[0].id, originalMemexItemModels[2].id])

      const newMemexItemModels = getQueryClientItems(queryClient)

      expect(newMemexItemModels === originalMemexItemModels).toBeFalsy()
      expect(newMemexItemModels).toHaveLength(1)
      expect(newMemexItemModels[0]).toBe(originalMemexItemModels[1])
    })

    it(`'memex_table_without_limits' enabled: removes matching items and returns array with new identity across multiple pages`, () => {
      seedJSONIsland('memex-enabled-features', ['memex_table_without_limits'])
      const variables: PaginatedMemexItemsQueryVariables = {q: ''}
      const queryClient = initQueryClient()
      const originalMemexItemModels = [
        issueFactory.build(),
        pullRequestFactory.build(),
        pullRequestFactory.build(),
        pullRequestFactory.build(),
        draftIssueFactory.build(),
      ].map(item => createMemexItemModel(item))

      const queryKeys = setAndActivateInitialQueriesByPage(queryClient, variables, [
        [originalMemexItemModels[0]], // page 1
        [originalMemexItemModels[1], originalMemexItemModels[2], originalMemexItemModels[3]], // page 2
        [originalMemexItemModels[4]], // page 3
      ])

      removeMemexItemsFromQueryClient(queryClient, [
        originalMemexItemModels[0].id, // delete item on page 1
        originalMemexItemModels[1].id, // delete first two items on page 2
        originalMemexItemModels[2].id,
        originalMemexItemModels[4].id, // delete item on page 3
      ])

      const newMemexItemModels = getMemexItemModelsForQueryKeys(queryClient, queryKeys)

      expect(newMemexItemModels === originalMemexItemModels).toBeFalsy()
      expect(newMemexItemModels).toHaveLength(1)
      expect(newMemexItemModels[0]).toBe(originalMemexItemModels[3]) // only the third item on page 2 should be remaining

      const newTotals = getQueryDataForMemexItemsTotalCounts(queryClient, variables)
      expect(newTotals.totalCount.value).toEqual(originalMemexItemModels.length - 4)
    })

    it(`'memex_table_without_limits' enabled: removes matching items and returns array with new identity across multiple pages and groups`, () => {
      seedJSONIsland('memex-enabled-features', ['memex_table_without_limits'])
      const variables: PaginatedMemexItemsQueryVariables = {q: ''}
      const queryClient = initQueryClient()
      const originalMemexItemModels = [
        issueFactory.build(),
        pullRequestFactory.build(),
        pullRequestFactory.build(),
        pullRequestFactory.build(),
        draftIssueFactory.build(),
        pullRequestFactory.build(),
        issueFactory.build(),
      ].map(item => createMemexItemModel(item))

      // Include a query of groups in the query cache so that we can test the state where there are active
      // queries for both groups and items.
      // This should help prevent https://github.com/github/projects-platform/issues/1202 from regressing
      setQueryDataForMemexGroupsPage(queryClient, variables, pageParamForInitialPage, {
        groups: [
          {groupId: 'group1', groupValue: 'Group 1'},
          {groupId: 'group2', groupValue: 'Group 2'},
        ],
        pageInfo: {hasNextPage: false, hasPreviousPage: false},
      })
      activateQueryByQueryKey(queryClient, buildMemexGroupsQueryKey(variables, pageParamForInitialPage))
      const queryKeys = setAndActivateInitialQueriesByPageForGroup(queryClient, variables, {groupId: 'group1'}, [
        [originalMemexItemModels[0]], // group1 page 1
        [originalMemexItemModels[1], originalMemexItemModels[2], originalMemexItemModels[3]], // group1 page 2
        [originalMemexItemModels[4]], // group1 page 3
        [originalMemexItemModels[5]], // group1 page 4
      ]).concat(
        setAndActivateInitialQueriesByPageForGroup(
          queryClient,
          variables,
          {groupId: 'group2'},
          [
            [originalMemexItemModels[6]], // group2 page 1
          ],
          originalMemexItemModels.length, // total items on server
        ),
      )

      const originalTotals = getQueryDataForMemexItemsTotalCounts(queryClient, variables)
      expect(originalTotals.totalCount.value).toEqual(originalMemexItemModels.length)
      expect(originalTotals.groups['group1'].value).toEqual(6)
      expect(originalTotals.groups['group2'].value).toEqual(1)

      const rollbackData = removeMemexItemsFromQueryClient(queryClient, [
        originalMemexItemModels[0].id, // delete item on page 1 of group1
        originalMemexItemModels[1].id, // delete first two items on page 2 of group1
        originalMemexItemModels[2].id,
        originalMemexItemModels[4].id, // delete item on page 3 of group1
        originalMemexItemModels[6].id, // delete item on page 1 of group2
      ])
      const newMemexItemModels = getMemexItemModelsForQueryKeys(queryClient, queryKeys)

      expect(newMemexItemModels === originalMemexItemModels).toBeFalsy()
      expect(newMemexItemModels).toHaveLength(2)
      expect(newMemexItemModels[0]).toBe(originalMemexItemModels[3]) // the third item on page 2 should be remaining
      expect(newMemexItemModels[1]).toBe(originalMemexItemModels[5]) // the one item on page 4 should be remaining

      const newTotals = getQueryDataForMemexItemsTotalCounts(queryClient, variables)
      expect(newTotals.totalCount.value).toEqual(2)
      expect(newTotals.groups['group1']?.value).toEqual(2)
      expect(newTotals.groups['group2']?.value).toEqual(0)

      expect(rollbackData).toBeDefined()
      if (rollbackData) {
        expect(rollbackData.queryData).toHaveLength(4) // We removed items from 4 different pages
        //page 1 is in rollback data with its original item
        expect(rollbackData.queryData[0].queryKey).toEqual(queryKeys[0])
        expect(rollbackData.queryData[0].queryData.nodes).toEqual([originalMemexItemModels[0]])

        //page 2 is in rollback data with its original items
        expect(rollbackData.queryData[1].queryKey).toEqual(queryKeys[1])
        expect(rollbackData.queryData[1].queryData.nodes).toEqual([
          originalMemexItemModels[1],
          originalMemexItemModels[2],
          originalMemexItemModels[3],
        ])

        //page 3 is in rollback data with its original item
        expect(rollbackData.queryData[2].queryKey).toEqual(queryKeys[2])
        expect(rollbackData.queryData[2].queryData.nodes).toEqual([originalMemexItemModels[4]])

        //page 1 of group 2 is in rollback data with its original item
        expect(rollbackData.queryData[3].queryKey).toEqual(queryKeys[4])
        expect(rollbackData.queryData[3].queryData.nodes).toEqual([originalMemexItemModels[6]])

        // original totalCounts are also preserved
        expect(rollbackData.totalCounts).toMatchObject(originalTotals)
      }
    })
  })

  describe('updateGroupForMemexItems', () => {
    it('single page of items for source group and target group', () => {
      const queryClient = initQueryClient()
      const variables: PaginatedMemexItemsQueryVariables = {}
      const originalMemexItemModels = [issueFactory.build(), issueFactory.build(), issueFactory.build()].map(item =>
        createMemexItemModel(item),
      )

      const queryKeys = [
        ...setAndActivateInitialQueriesByPageForGroup(queryClient, variables, {groupId: 'group1'}, [
          [originalMemexItemModels[0], originalMemexItemModels[1]], // 1 page with two items
        ]),
        ...setAndActivateInitialQueriesByPageForGroup(queryClient, variables, {groupId: 'group2'}, [
          [originalMemexItemModels[2]], // 1 page with one item
        ]),
      ]

      setPageParamsQueryDataForVariables(queryClient, variables, {
        groupedItems: {
          [createGroupedItemsId({groupId: 'group1'})]: [pageParamForInitialPage],
          [createGroupedItemsId({groupId: 'group2'})]: [pageParamForInitialPage],
        },
        pageParams: [pageParamForInitialPage],
      })

      const initialTotalCounts = getQueryDataForMemexItemsTotalCounts(queryClient, variables)
      expect(initialTotalCounts.groups['group1']?.value).toEqual(2)
      expect(initialTotalCounts.groups['group2']?.value).toEqual(1)

      const rollbackData = updateGroupForMemexItems(
        queryClient,
        [originalMemexItemModels[0], originalMemexItemModels[1]],
        'group2',
      )

      const newPages = queryKeys.map(queryKey => queryClient.getQueryData<MemexItemsPageQueryData>(queryKey))

      const pageForGroup1 = newPages[0]
      expect(pageForGroup1?.nodes).toHaveLength(0)

      const pageForGroup2 = newPages[1]
      expect(pageForGroup2?.nodes).toHaveLength(3)
      expect(pageForGroup2?.nodes[0]).toBe(originalMemexItemModels[0])
      expect(pageForGroup2?.nodes[1]).toBe(originalMemexItemModels[1])
      expect(pageForGroup2?.nodes[2]).toBe(originalMemexItemModels[2])

      const updatedTotalCounts = getQueryDataForMemexItemsTotalCounts(queryClient, variables)
      expect(updatedTotalCounts.groups['group1']?.value).toEqual(0)
      expect(updatedTotalCounts.groups['group2']?.value).toEqual(3)

      rollbackMemexItemData(queryClient, rollbackData)

      const rollbackPages = queryKeys.map(queryKey => queryClient.getQueryData<MemexItemsPageQueryData>(queryKey))

      const pageForGroup1AfterRollback = rollbackPages[0]
      expect(pageForGroup1AfterRollback?.nodes).toHaveLength(2)
      expect(pageForGroup1AfterRollback?.nodes[0]).toBe(originalMemexItemModels[0])
      expect(pageForGroup1AfterRollback?.nodes[1]).toBe(originalMemexItemModels[1])

      const pageForGroup2AfterRollback = rollbackPages[1]
      expect(pageForGroup2AfterRollback?.nodes).toHaveLength(1)
      expect(pageForGroup2AfterRollback?.nodes[0]).toBe(originalMemexItemModels[2])

      const totalCountsAfterRollback = getQueryDataForMemexItemsTotalCounts(queryClient, variables)
      expect(totalCountsAfterRollback.groups['group1']?.value).toEqual(2)
      expect(totalCountsAfterRollback.groups['group2']?.value).toEqual(1)
    })

    it('multiple pages of items for source group and single page for target group', () => {
      const queryClient = initQueryClient()
      const variables: PaginatedMemexItemsQueryVariables = {}
      const originalMemexItemModels = [issueFactory.build(), issueFactory.build(), issueFactory.build()].map(item =>
        createMemexItemModel(item),
      )

      const queryKeys = [
        ...setAndActivateInitialQueriesByPageForGroup(queryClient, variables, {groupId: 'group1'}, [
          [originalMemexItemModels[0]], // 1 page with one item
          [originalMemexItemModels[1]], // 1 page with one item
        ]),
        ...setAndActivateInitialQueriesByPageForGroup(queryClient, variables, {groupId: 'group2'}, [
          [originalMemexItemModels[2]], // 1 page with one item
        ]),
      ]

      setPageParamsQueryDataForVariables(queryClient, variables, {
        groupedItems: {
          [createGroupedItemsId({groupId: 'group1'})]: [pageParamForInitialPage, {after: 'group1page2'}],
          [createGroupedItemsId({groupId: 'group2'})]: [pageParamForInitialPage],
        },
        pageParams: [pageParamForInitialPage],
      })

      const rollbackData = updateGroupForMemexItems(
        queryClient,
        [originalMemexItemModels[0], originalMemexItemModels[1]],
        'group2',
      )

      const newPages = queryKeys.map(queryKey => queryClient.getQueryData<MemexItemsPageQueryData>(queryKey))

      const page1ForGroup1 = newPages[0]
      expect(page1ForGroup1?.nodes).toHaveLength(0)

      const page2ForGroup1 = newPages[1]
      expect(page2ForGroup1?.nodes).toHaveLength(0)
      const pageForGroup2 = newPages[2]
      expect(pageForGroup2?.nodes).toHaveLength(3)
      expect(pageForGroup2?.nodes).toHaveLength(3)
      expect(pageForGroup2?.nodes[0]).toBe(originalMemexItemModels[0])
      expect(pageForGroup2?.nodes[1]).toBe(originalMemexItemModels[1])
      expect(pageForGroup2?.nodes[2]).toBe(originalMemexItemModels[2])

      rollbackMemexItemData(queryClient, rollbackData)

      const rollbackPages = queryKeys.map(queryKey => queryClient.getQueryData<MemexItemsPageQueryData>(queryKey))

      const page1ForGroup1AfterRollback = rollbackPages[0]
      expect(page1ForGroup1AfterRollback?.nodes).toHaveLength(1)
      expect(page1ForGroup1AfterRollback?.nodes[0]).toBe(originalMemexItemModels[0])

      const page2ForGroup1AfterRollback = rollbackPages[1]
      expect(page2ForGroup1AfterRollback?.nodes).toHaveLength(1)
      expect(page2ForGroup1AfterRollback?.nodes[0]).toBe(originalMemexItemModels[1])

      const pageForGroup2AfterRollback = rollbackPages[2]
      expect(pageForGroup2AfterRollback?.nodes).toHaveLength(1)
      expect(pageForGroup2AfterRollback?.nodes[0]).toBe(originalMemexItemModels[2])
    })

    it('multiple pages of items for source group and multiple pages for target group', () => {
      const queryClient = initQueryClient()
      const variables: PaginatedMemexItemsQueryVariables = {}
      const originalMemexItemModels = [
        issueFactory.build(),
        issueFactory.build(),
        issueFactory.build(),
        issueFactory.build(),
      ].map(item => createMemexItemModel(item))

      const queryKeys = [
        ...setAndActivateInitialQueriesByPageForGroup(queryClient, variables, {groupId: 'group1'}, [
          [originalMemexItemModels[0]], // 1 page with one item
          [originalMemexItemModels[1]], // 1 page with one item
        ]),
        ...setAndActivateInitialQueriesByPageForGroup(queryClient, variables, {groupId: 'group2'}, [
          [originalMemexItemModels[2]], // 1 page with one item
          [originalMemexItemModels[3]], // 1 page with one item
        ]),
      ]

      setPageParamsQueryDataForVariables(queryClient, variables, {
        groupedItems: {
          [createGroupedItemsId({groupId: 'group1'})]: [pageParamForInitialPage, {after: 'group1page2'}],
          [createGroupedItemsId({groupId: 'group2'})]: [pageParamForInitialPage, {after: 'group2page2'}],
        },
        pageParams: [pageParamForInitialPage],
      })

      const rollbackData = updateGroupForMemexItems(
        queryClient,
        [originalMemexItemModels[0], originalMemexItemModels[1]],
        'group2',
      )

      const newPages = queryKeys.map(queryKey => queryClient.getQueryData<MemexItemsPageQueryData>(queryKey))

      const page1ForGroup1 = newPages[0]
      expect(page1ForGroup1?.nodes).toHaveLength(0)

      const page2ForGroup1 = newPages[1]
      expect(page2ForGroup1?.nodes).toHaveLength(0)
      const page1ForGroup2 = newPages[2]
      expect(page1ForGroup2?.nodes).toHaveLength(3)
      expect(page1ForGroup2?.nodes).toHaveLength(3)
      expect(page1ForGroup2?.nodes[0]).toBe(originalMemexItemModels[0])
      expect(page1ForGroup2?.nodes[1]).toBe(originalMemexItemModels[1])
      expect(page1ForGroup2?.nodes[2]).toBe(originalMemexItemModels[2])

      const page2ForGroup2 = newPages[3]
      expect(page2ForGroup2?.nodes).toHaveLength(1)

      rollbackMemexItemData(queryClient, rollbackData)

      const rollbackPages = queryKeys.map(queryKey => queryClient.getQueryData<MemexItemsPageQueryData>(queryKey))

      const page1ForGroup1AfterRollback = rollbackPages[0]
      expect(page1ForGroup1AfterRollback?.nodes).toHaveLength(1)
      expect(page1ForGroup1AfterRollback?.nodes[0]).toBe(originalMemexItemModels[0])

      const page2ForGroup1AfterRollback = rollbackPages[1]
      expect(page2ForGroup1AfterRollback?.nodes).toHaveLength(1)
      expect(page2ForGroup1AfterRollback?.nodes[0]).toBe(originalMemexItemModels[1])

      const page1ForGroup2AfterRollback = rollbackPages[2]
      expect(page1ForGroup2AfterRollback?.nodes).toHaveLength(1)
      expect(page1ForGroup2AfterRollback?.nodes[0]).toBe(originalMemexItemModels[2])

      const page2ForGroup2AfterRollback = rollbackPages[3]
      expect(page2ForGroup2AfterRollback?.nodes).toHaveLength(1)
      expect(page2ForGroup2AfterRollback?.nodes[0]).toBe(originalMemexItemModels[3])
    })

    it('with secondary groups', () => {
      const queryClient = initQueryClient()
      const variables: PaginatedMemexItemsQueryVariables = {
        verticalGroupedByColumnId: 'Status',
        horizontalGroupedByColumnId: 'Status',
      }

      const originalMemexItemModels = [issueFactory.build(), issueFactory.build(), issueFactory.build()].map(item =>
        createMemexItemModel(item),
      )

      const groupsPageData: MemexGroupsPageQueryData = {
        groups: [
          {
            groupId: 'serverGroup1Id',
            groupValue: 'Group 1',
            groupMetadata: {
              id: 'group1',
              color: 'RED',
              name: 'Group 1',
              nameHtml: 'Group 1',
              description: '',
              descriptionHtml: '',
            },
          },
          {
            groupId: 'serverGroup2Id',
            groupValue: 'Group 2',
            groupMetadata: {
              id: 'group2',
              color: 'BLUE',
              name: 'Group 2',
              nameHtml: 'Group 2',
              description: '',
              descriptionHtml: '',
            },
          },
        ],
        pageInfo: {hasNextPage: false, hasPreviousPage: false},
      }
      const groupsQueryKey = buildMemexGroupsQueryKey(variables, pageParamForInitialPage)
      queryClient.setQueryData(groupsQueryKey, groupsPageData)
      activateQueryByQueryKey(queryClient, groupsQueryKey)

      const secondaryGroupsPageData: MemexGroupsPageQueryData = {
        groups: [
          {
            groupId: 'serverSecondaryGroup1Id',
            groupValue: 'Secondary Group 1',
            groupMetadata: {
              id: 'secondaryGroup1',
              name: 'Secondary Group 1',
              nameHtml: 'Secondary Group 1',
              color: 'RED',
              description: '',
              descriptionHtml: '',
            },
          },
          {
            groupId: 'serverSecondaryGroup2Id',
            groupValue: 'Secondary Group 2',
            groupMetadata: {
              id: 'secondaryGroup2',
              name: 'Secondary Group 2',
              nameHtml: 'Secondary Group 2',
              color: 'RED',
              description: '',
              descriptionHtml: '',
            },
          },
        ],
        pageInfo: {hasNextPage: false, hasPreviousPage: false},
      }
      const secondaryGroupsQueryKey = buildMemexSecondaryGroupsQueryKey(variables, pageParamForInitialPage)
      queryClient.setQueryData(secondaryGroupsQueryKey, secondaryGroupsPageData)
      activateQueryByQueryKey(queryClient, secondaryGroupsQueryKey)

      const queryKeys = [
        ...setAndActivateInitialQueriesByPageForGroup(
          queryClient,
          variables,
          {groupId: 'serverGroup1Id', secondaryGroupId: 'serverSecondaryGroup1Id'},
          [[originalMemexItemModels[0], originalMemexItemModels[1]]],
        ),
        ...setAndActivateInitialQueriesByPageForGroup(
          queryClient,
          variables,
          {groupId: 'serverGroup1Id', secondaryGroupId: 'serverSecondaryGroup2Id'},
          [[originalMemexItemModels[2]]],
        ),
      ]

      setPageParamsQueryDataForVariables(queryClient, variables, {
        groupedItems: {
          [createGroupedItemsId({groupId: 'serverGroup1Id', secondaryGroupId: 'serverSecondaryGroup1Id'})]: [
            pageParamForInitialPage,
          ],
          [createGroupedItemsId({groupId: 'serverGroup1Id', secondaryGroupId: 'serverSecondaryGroup2Id'})]: [
            pageParamForInitialPage,
          ],
        },
        pageParams: [pageParamForInitialPage],
        secondaryGroups: [pageParamForInitialPage],
      })

      const initialTotalCounts = getQueryDataForMemexItemsTotalCounts(queryClient, variables)
      expect(initialTotalCounts.groups['serverSecondaryGroup1Id']?.value).toEqual(2)
      expect(initialTotalCounts.groups['serverSecondaryGroup2Id']?.value).toEqual(1)

      const rollbackData = updateGroupForMemexItems(
        queryClient,
        [originalMemexItemModels[0], originalMemexItemModels[1]],
        'serverGroup1Id',
        'serverSecondaryGroup2Id',
      )

      const newPages = queryKeys.map(queryKey => queryClient.getQueryData<MemexItemsPageQueryData>(queryKey))

      const cell1 = newPages[0]
      expect(cell1?.nodes).toHaveLength(0)

      const cell2 = newPages[1]
      expect(cell2?.nodes).toHaveLength(3)
      expect(cell2?.nodes[0]).toBe(originalMemexItemModels[0])
      expect(cell2?.nodes[1]).toBe(originalMemexItemModels[1])
      expect(cell2?.nodes[2]).toBe(originalMemexItemModels[2])

      const updatedTotalCounts = getQueryDataForMemexItemsTotalCounts(queryClient, variables)
      expect(updatedTotalCounts.groups['serverSecondaryGroup1Id']?.value).toEqual(0)
      expect(updatedTotalCounts.groups['serverSecondaryGroup2Id']?.value).toEqual(3)

      rollbackMemexItemData(queryClient, rollbackData)

      const rollbackPages = queryKeys.map(queryKey => queryClient.getQueryData<MemexItemsPageQueryData>(queryKey))

      const cell1AfterRollback = rollbackPages[0]
      expect(cell1AfterRollback?.nodes).toHaveLength(2)
      expect(cell1AfterRollback?.nodes[0]).toBe(originalMemexItemModels[0])
      expect(cell1AfterRollback?.nodes[1]).toBe(originalMemexItemModels[1])

      const cell2AfterRollback = rollbackPages[1]
      expect(cell2AfterRollback?.nodes).toHaveLength(1)
      expect(cell2AfterRollback?.nodes[0]).toBe(originalMemexItemModels[2])

      const totalCountsAfterRollback = getQueryDataForMemexItemsTotalCounts(queryClient, variables)
      expect(totalCountsAfterRollback.groups['serverSecondaryGroup1Id']?.value).toEqual(2)
      expect(totalCountsAfterRollback.groups['serverSecondaryGroup2Id']?.value).toEqual(1)
    })

    it('with secondary groups into an empty cell', () => {
      const queryClient = initQueryClient()
      const variables: PaginatedMemexItemsQueryVariables = {
        verticalGroupedByColumnId: 'Status',
        horizontalGroupedByColumnId: 'Status',
      }

      const originalMemexItemModels = [issueFactory.build(), issueFactory.build(), issueFactory.build()].map(item =>
        createMemexItemModel(item),
      )

      const groupsPageData: MemexGroupsPageQueryData = {
        groups: [
          {
            groupId: 'serverGroup1Id',
            groupValue: 'Group 1',
            groupMetadata: {
              id: 'group1',
              color: 'RED',
              name: 'Group 1',
              nameHtml: 'Group 1',
              description: '',
              descriptionHtml: '',
            },
          },
          {
            groupId: 'serverGroup2Id',
            groupValue: 'Group 2',
            groupMetadata: {
              id: 'group2',
              color: 'BLUE',
              name: 'Group 2',
              nameHtml: 'Group 2',
              description: '',
              descriptionHtml: '',
            },
          },
        ],
        pageInfo: {hasNextPage: false, hasPreviousPage: false},
      }
      const groupsQueryKey = buildMemexGroupsQueryKey(variables, pageParamForInitialPage)
      queryClient.setQueryData(groupsQueryKey, groupsPageData)
      activateQueryByQueryKey(queryClient, groupsQueryKey)

      const secondaryGroupsPageData: MemexGroupsPageQueryData = {
        groups: [
          {
            groupId: 'serverSecondaryGroup1Id',
            groupValue: 'Secondary Group 1',
            groupMetadata: {
              id: 'secondaryGroup1',
              name: 'Secondary Group 1',
              nameHtml: 'Secondary Group 1',
              color: 'RED',
              description: '',
              descriptionHtml: '',
            },
          },
          {
            groupId: 'serverSecondaryGroup2Id',
            groupValue: 'Secondary Group 2',
            groupMetadata: {
              id: 'secondaryGroup2',
              name: 'Secondary Group 2',
              nameHtml: 'Secondary Group 2',
              color: 'RED',
              description: '',
              descriptionHtml: '',
            },
          },
        ],
        pageInfo: {hasNextPage: false, hasPreviousPage: false},
      }
      const secondaryGroupsQueryKey = buildMemexSecondaryGroupsQueryKey(variables, pageParamForInitialPage)
      queryClient.setQueryData(secondaryGroupsQueryKey, secondaryGroupsPageData)
      activateQueryByQueryKey(queryClient, secondaryGroupsQueryKey)

      const queryKeys = [
        ...setAndActivateInitialQueriesByPageForGroup(
          queryClient,
          variables,
          {groupId: 'serverGroup1Id', secondaryGroupId: 'serverSecondaryGroup1Id'},
          [[originalMemexItemModels[0], originalMemexItemModels[1]]],
        ),
        // second cell is intentionally left blank
      ]

      setPageParamsQueryDataForVariables(queryClient, variables, {
        groupedItems: {
          [createGroupedItemsId({groupId: 'serverGroup1Id', secondaryGroupId: 'serverSecondaryGroup1Id'})]: [
            pageParamForInitialPage,
          ],
          // second cell is intentionally left blank
        },
        pageParams: [pageParamForInitialPage],
        secondaryGroups: [pageParamForInitialPage],
      })

      const initialTotalCounts = getQueryDataForMemexItemsTotalCounts(queryClient, variables)
      expect(initialTotalCounts.groups['serverGroup1Id']?.value).toEqual(2)
      expect(initialTotalCounts.groups['serverGroup2Id']?.value).toBeUndefined()
      expect(initialTotalCounts.groups['serverSecondaryGroup1Id']?.value).toEqual(2)
      expect(initialTotalCounts.groups['serverSecondaryGroup2Id']?.value).toBeUndefined()

      const rollbackData = updateGroupForMemexItems(
        queryClient,
        [originalMemexItemModels[0], originalMemexItemModels[1]],
        'serverGroup1Id',
        'serverSecondaryGroup2Id',
      )

      // make sure we now account for the new cell that previously didn't have any data.
      const newQueryKeys = [
        ...queryKeys,
        buildMemexGroupedItemsQueryKey(
          variables,
          {groupId: 'serverGroup1Id', secondaryGroupId: 'serverSecondaryGroup2Id'},
          pageParamForInitialPage,
        ),
      ]

      const newPages = newQueryKeys.map(queryKey => queryClient.getQueryData<MemexItemsPageQueryData>(queryKey))

      const cell1 = newPages[0]
      expect(cell1?.nodes).toHaveLength(0)

      const cell2 = newPages[1]
      expect(cell2?.nodes).toHaveLength(2)
      expect(cell2?.nodes[0]).toBe(originalMemexItemModels[0])
      expect(cell2?.nodes[1]).toBe(originalMemexItemModels[1])

      const updatedTotalCounts = getQueryDataForMemexItemsTotalCounts(queryClient, variables)
      expect(updatedTotalCounts.groups['serverGroup1Id']?.value).toEqual(2)
      expect(updatedTotalCounts.groups['serverGroup2Id']?.value).toBeUndefined()
      expect(updatedTotalCounts.groups['serverSecondaryGroup1Id']?.value).toEqual(0)
      expect(updatedTotalCounts.groups['serverSecondaryGroup2Id']?.value).toEqual(2)

      rollbackMemexItemData(queryClient, rollbackData)

      const rollbackPages = newQueryKeys.map(queryKey => queryClient.getQueryData<MemexItemsPageQueryData>(queryKey))

      const cell1AfterRollback = rollbackPages[0]
      expect(cell1AfterRollback?.nodes).toHaveLength(2)
      expect(cell1AfterRollback?.nodes[0]).toBe(originalMemexItemModels[0])
      expect(cell1AfterRollback?.nodes[1]).toBe(originalMemexItemModels[1])

      const cell2AfterRollback = rollbackPages[1]
      expect(cell2AfterRollback?.nodes).toHaveLength(0)

      const totalCountsAfterRollback = getQueryDataForMemexItemsTotalCounts(queryClient, variables)
      expect(totalCountsAfterRollback.groups['serverGroup1Id']?.value).toEqual(2)
      expect(totalCountsAfterRollback.groups['serverGroup2Id']?.value).toBeUndefined()
      expect(totalCountsAfterRollback.groups['serverSecondaryGroup1Id']?.value).toEqual(2)
      expect(totalCountsAfterRollback.groups['serverSecondaryGroup2Id']?.value).toBeUndefined()
    })
  })

  describe('updateMemexItemPositionInQueryClient', () => {
    it('movingItemId does not exist', () => {
      const queryClient = initQueryClient()
      const idForItemInQueryClient = 100
      const idForNonExistantItem = idForItemInQueryClient + 1
      const originalMemexItemModels = [issueFactory.build({id: idForItemInQueryClient})].map(item =>
        createMemexItemModel(item),
      )

      const queryKeys = setAndActivateInitialQueriesByPage(queryClient, {}, [
        [originalMemexItemModels[0]], // 1 page with one item
      ])

      const result = updateMemexItemPositionInQueryClient(queryClient, idForNonExistantItem, {
        overItemId: idForItemInQueryClient,
        side: 'after',
      })

      const newMemexItemModels = getMemexItemModelsForQueryKeys(queryClient, queryKeys)

      expect(newMemexItemModels).toHaveLength(1)
      expect(result).toBeUndefined()
    })

    it('reorderData.overItemId does not exist', () => {
      const queryClient = initQueryClient()
      const idForItemInQueryClient = 100
      const idForNonExistantItem = idForItemInQueryClient + 1
      const originalMemexItemModels = [issueFactory.build({id: idForItemInQueryClient})].map(item =>
        createMemexItemModel(item),
      )

      const queryKeys = setAndActivateInitialQueriesByPage(queryClient, {}, [
        [originalMemexItemModels[0]], // 1 page with one item
      ])

      const result = updateMemexItemPositionInQueryClient(queryClient, idForItemInQueryClient, {
        overItemId: idForNonExistantItem,
        side: 'after',
      })

      const newMemexItemModels = getMemexItemModelsForQueryKeys(queryClient, queryKeys)

      expect(newMemexItemModels).toHaveLength(1)
      expect(result).toBeUndefined()
    })

    it('moving after item within same query', () => {
      const queryClient = initQueryClient()
      const idForItemInQueryClient = 100
      const idForSecondItemInQueryClient = idForItemInQueryClient + 1
      const originalMemexItemModels = [
        issueFactory.build({id: idForItemInQueryClient}),
        issueFactory.build({id: idForSecondItemInQueryClient}),
      ].map(item => createMemexItemModel(item))

      const queryKeys = setAndActivateInitialQueriesByPage(queryClient, {}, [
        [originalMemexItemModels[0], originalMemexItemModels[1]], // 1 page with two items
      ])
      //move first item after second item
      const result = updateMemexItemPositionInQueryClient(queryClient, idForItemInQueryClient, {
        overItemId: idForSecondItemInQueryClient,
        side: 'after',
      })

      const newMemexItemModels = getMemexItemModelsForQueryKeys(queryClient, queryKeys)

      expect(newMemexItemModels).toHaveLength(2)
      expect(newMemexItemModels[0].id).toBe(idForSecondItemInQueryClient)
      expect(newMemexItemModels[1].id).toBe(idForItemInQueryClient)
      expect(result?.previousItemId).toBe(idForSecondItemInQueryClient)

      // Does not change total count
      const newTotalCount = getQueryDataForMemexItemsTotalCounts(queryClient, {}).totalCount.value
      expect(newTotalCount).toEqual(2)

      expect(result?.rollbackData.queryData).toHaveLength(1) // moving within same page
      expect(result?.rollbackData.queryData[0].queryKey).toEqual(queryKeys[0])
      expect(result?.rollbackData.queryData[0].queryData.nodes).toEqual([
        originalMemexItemModels[0],
        originalMemexItemModels[1],
      ])
    })

    it('moving before within same query', () => {
      const queryClient = initQueryClient()
      const idForItemInQueryClient = 100
      const idForSecondItemInQueryClient = idForItemInQueryClient + 1
      const originalMemexItemModels = [
        issueFactory.build({id: idForItemInQueryClient}),
        issueFactory.build({id: idForSecondItemInQueryClient}),
      ].map(item => createMemexItemModel(item))

      const queryKeys = setAndActivateInitialQueriesByPage(queryClient, {}, [
        [originalMemexItemModels[0], originalMemexItemModels[1]], // 1 page with two items
      ])
      //move second item before first item
      const result = updateMemexItemPositionInQueryClient(queryClient, idForSecondItemInQueryClient, {
        overItemId: idForItemInQueryClient,
        side: 'before',
      })

      const newMemexItemModels = getMemexItemModelsForQueryKeys(queryClient, queryKeys)

      expect(newMemexItemModels).toHaveLength(2)
      expect(newMemexItemModels[0].id).toBe(idForSecondItemInQueryClient)
      expect(newMemexItemModels[1].id).toBe(idForItemInQueryClient)
      expect(result?.previousItemId).toBe('')

      // Does not change total count
      const newTotalCount = getQueryDataForMemexItemsTotalCounts(queryClient, {}).totalCount.value
      expect(newTotalCount).toEqual(2)
    })

    it('moving after item of different query', () => {
      const queryClient = initQueryClient()
      const idForItemInFirstPage = 100
      const idForItemInSecondPage = idForItemInFirstPage + 1
      const originalMemexItemModels = [
        issueFactory.build({id: idForItemInFirstPage}),
        issueFactory.build({id: idForItemInSecondPage}),
      ].map(item => createMemexItemModel(item))

      const queryKeys = setAndActivateInitialQueriesByPage(queryClient, {}, [
        [originalMemexItemModels[0]], // one item in page
        [originalMemexItemModels[1]], // one item in page
      ])
      //move item in first page after item in second page
      const result = updateMemexItemPositionInQueryClient(queryClient, idForItemInFirstPage, {
        overItemId: idForItemInSecondPage,
        side: 'after',
      })

      const newPages = queryKeys.map(queryKey => queryClient.getQueryData<MemexItemsPageQueryData>(queryKey))

      // moved item is no longer in first page
      expect(newPages[0]?.nodes).toHaveLength(0)
      // second page now has two items
      expect(newPages[1]?.nodes).toHaveLength(2)
      expect(newPages[1]?.nodes[0].id).toBe(idForItemInSecondPage)
      expect(newPages[1]?.nodes[1].id).toBe(idForItemInFirstPage)
      expect(result?.previousItemId).toBe(idForItemInSecondPage)

      // Does not change total count
      const newTotalCount = getQueryDataForMemexItemsTotalCounts(queryClient, {}).totalCount.value
      expect(newTotalCount).toEqual(2)
    })

    it('moving before item of different query', () => {
      const queryClient = initQueryClient()
      const idForItemInFirstPage = 100
      const idForItemInSecondPage = idForItemInFirstPage + 1
      const originalMemexItemModels = [
        issueFactory.build({id: idForItemInFirstPage}),
        issueFactory.build({id: idForItemInSecondPage}),
      ].map(item => createMemexItemModel(item))

      const queryKeys = setAndActivateInitialQueriesByPage(queryClient, {}, [
        [originalMemexItemModels[0]], // one item in page
        [originalMemexItemModels[1]], // one item in page
      ])
      //move item in first page before item in second page
      const result = updateMemexItemPositionInQueryClient(queryClient, idForItemInFirstPage, {
        overItemId: idForItemInSecondPage,
        side: 'before',
      })

      const newPages = queryKeys.map(queryKey => queryClient.getQueryData<MemexItemsPageQueryData>(queryKey))
      const newTotals = getQueryDataForMemexItemsTotalCounts(queryClient, {})
      // Overall total hasn't changed
      expect(newTotals.totalCount.value).toEqual(originalMemexItemModels.length)
      // moved item is no longer in first page
      expect(newPages[0]?.nodes).toHaveLength(0)
      // second page now has two items
      expect(newPages[1]?.nodes).toHaveLength(2)
      expect(newPages[1]?.nodes[0].id).toBe(idForItemInFirstPage)
      expect(newPages[1]?.nodes[1].id).toBe(idForItemInSecondPage)
      expect(result?.previousItemId).toBe('')
    })

    it('moving to empty group based on groupId', () => {
      const queryClient = initQueryClient()
      const idForItemInFirstPage = 100
      const idForItemInSecondPage = idForItemInFirstPage + 1
      const originalMemexItemModels = [
        issueFactory.build({id: idForItemInFirstPage}),
        issueFactory.build({id: idForItemInSecondPage}),
      ].map(item => createMemexItemModel(item))

      const queryKeys = setAndActivateInitialQueriesByPageForGroup(queryClient, {}, {groupId: 'group1'}, [
        [originalMemexItemModels[0]], // one item for group
      ])
        .concat(
          setAndActivateInitialQueriesByPageForGroup(queryClient, {}, {groupId: 'group2'}, [
            [originalMemexItemModels[1]], // one item for group
          ]),
        )
        .concat(
          setAndActivateInitialQueriesByPageForGroup(queryClient, {}, {groupId: 'group3'}, [
            [], // no items for group
          ]),
        )
      const originalTotalCounts = {
        groups: {
          group1: {value: 1, isApproximate: false},
          group2: {value: 1, isApproximate: false},
          group3: {value: 0, isApproximate: false},
        },
        totalCount: {
          value: originalMemexItemModels.length, // total items for all three groups,
          isApproximate: false,
        },
      }
      mergeQueryDataForMemexItemsTotalCounts(queryClient, {}, originalTotalCounts)

      //move item in first page to empty group
      const result = updateMemexItemPositionInQueryClient(queryClient, idForItemInFirstPage, {
        overGroupId: 'group3',
      })

      const newPages = queryKeys.map(queryKey => queryClient.getQueryData<MemexItemsPageQueryData>(queryKey))
      const newTotals = getQueryDataForMemexItemsTotalCounts(queryClient, {})
      // Overall total hasn't changed
      expect(newTotals.totalCount?.value).toEqual(originalMemexItemModels.length)
      // moved item is no longer in first group
      expect(newPages[0]?.nodes).toHaveLength(0)
      // expect(newTotals.groups['group1']?.value).toBe(0) // TODO: fix and enable

      // second group is unchanged
      expect(newPages[1]?.nodes).toHaveLength(1)
      expect(newTotals.groups['group2']?.value).toBe(1)
      expect(newPages[1]?.nodes[0].id).toBe(idForItemInSecondPage)

      // third group now has one item
      expect(newPages[2]?.nodes).toHaveLength(1)
      expect(newPages[2]?.nodes[0].id).toBe(idForItemInFirstPage)
      // expect(newTotals.groups['group3']?.value).toBe(1) // TODO: fix and enable

      expect(result?.previousItemId).toBeUndefined()
      expect(result?.rollbackData.queryData).toHaveLength(2) // moving between two pages
      expect(result?.rollbackData.queryData[0].queryKey).toEqual(queryKeys[0])
      expect(result?.rollbackData.queryData[0].queryData.nodes).toEqual([originalMemexItemModels[0]])
      expect(result?.rollbackData.queryData[1].queryKey).toEqual(queryKeys[2]) // third page is where we're moving to
      expect(result?.rollbackData.queryData[1].queryData.nodes).toEqual([]) // initially no data in the third page

      // original totalCounts are also preserved
      expect(result?.rollbackData.totalCounts).toMatchObject(originalTotalCounts)
    })

    it('moving to empty group with sparse grouped items', () => {
      const queryClient = initQueryClient()
      const variables: PaginatedMemexItemsQueryVariables = {
        verticalGroupedByColumnId: 'Status',
        horizontalGroupedByColumnId: 'Status',
      }
      const originalMemexItemModels = [issueFactory.build()].map(item => createMemexItemModel(item))

      const groupsPageData: MemexGroupsPageQueryData = {
        groups: [
          {
            groupId: 'serverGroup1Id',
            groupValue: 'Group 1',
            groupMetadata: {
              id: 'group1',
              color: 'RED',
              name: 'Group 1',
              nameHtml: 'Group 1',
              description: '',
              descriptionHtml: '',
            },
          },
          {
            groupId: 'serverGroup2Id',
            groupValue: 'Group 2',
            groupMetadata: {
              id: 'group2',
              color: 'BLUE',
              name: 'Group 2',
              nameHtml: 'Group 2',
              description: '',
              descriptionHtml: '',
            },
          },
        ],
        pageInfo: {hasNextPage: false, hasPreviousPage: false},
      }
      const groupsQueryKey = buildMemexGroupsQueryKey(variables, pageParamForInitialPage)
      queryClient.setQueryData(groupsQueryKey, groupsPageData)
      activateQueryByQueryKey(queryClient, groupsQueryKey)

      const queryKeys = setAndActivateInitialQueriesByPageForGroup(
        queryClient,
        variables,
        {groupId: 'serverGroup1Id'},
        [
          originalMemexItemModels, // page 1
        ],
      )
      // Intentionally not adding a query key for serverGroup2Id

      setPageParamsQueryDataForVariables(queryClient, variables, {
        groupedItems: {
          [createGroupedItemsId({groupId: 'serverGroup1Id'})]: [pageParamForInitialPage],
          // Intentionally not adding page params for serverGroup2Id
        },
        pageParams: [pageParamForInitialPage],
        secondaryGroups: [pageParamForInitialPage],
      })

      const originalTotalCounts = {
        groups: {
          serverGroup1Id: {value: 1, isApproximate: false},
          serverGroup2Id: {value: 0, isApproximate: false},
        },
        totalCount: {
          value: originalMemexItemModels.length,
          isApproximate: false,
        },
      }
      mergeQueryDataForMemexItemsTotalCounts(queryClient, variables, originalTotalCounts)

      const result = updateMemexItemPositionInQueryClient(queryClient, originalMemexItemModels[0].id, {
        overGroupId: 'serverGroup2Id',
      })

      const newTotals = getQueryDataForMemexItemsTotalCounts(queryClient, variables)
      // Overall total is unchanged
      expect(newTotals.totalCount?.value).toEqual(1)
      // Old group count is now 0
      expect(newTotals.groups['serverGroup1Id']?.value).toEqual(0)
      // New group count is now 1
      expect(newTotals.groups['serverGroup2Id']?.value).toEqual(1)

      const newQueryKeys = [
        ...queryKeys,
        buildMemexGroupedItemsQueryKey(variables, {groupId: 'serverGroup2Id'}, pageParamForInitialPage),
      ]
      const newPages = newQueryKeys.map(queryKey => queryClient.getQueryData<MemexItemsPageQueryData>(queryKey))

      // moved item is no longer in first cell
      expect(newPages[0]?.nodes).toHaveLength(0)

      // moved item is now in a different cell
      expect(newPages[1]?.nodes).toHaveLength(1)
      expect(newPages[1]?.nodes[0].id).toBe(originalMemexItemModels[0].id)
      expect(result?.previousItemId).toBeUndefined()

      expect(result?.previousItemId).toBeUndefined()
      expect(result?.rollbackData.queryData).toHaveLength(2) // moving between two pages
      expect(result?.rollbackData.queryData[0].queryKey).toEqual(newQueryKeys[0])
      expect(result?.rollbackData.queryData[0].queryData.nodes).toEqual([originalMemexItemModels[0]])
      expect(result?.rollbackData.queryData[1].queryKey).toEqual(newQueryKeys[1]) // second page is where we're moving to
      expect(result?.rollbackData.queryData[1].queryData.nodes).toEqual([]) // initially no data in the second page

      // original totalCounts are also preserved
      expect(result?.rollbackData.totalCounts).toMatchObject(originalTotalCounts)
    })

    it('moving to empty cell based on groupId and secondaryGroupId', () => {
      seedJSONIsland('memex-enabled-features', ['memex_table_without_limits'])
      const queryClient = initQueryClient()
      const variables: PaginatedMemexItemsQueryVariables = {
        verticalGroupedByColumnId: 'Status',
        horizontalGroupedByColumnId: 'Status',
      }
      const originalMemexItemModels = [issueFactory.build()].map(item => createMemexItemModel(item))

      const groupsPageData: MemexGroupsPageQueryData = {
        groups: [
          {
            groupId: 'serverGroup1Id',
            groupValue: 'Group 1',
            groupMetadata: {
              id: 'group1',
              color: 'RED',
              name: 'Group 1',
              nameHtml: 'Group 1',
              description: '',
              descriptionHtml: '',
            },
          },
          {
            groupId: 'serverGroup2Id',
            groupValue: 'Group 2',
            groupMetadata: {
              id: 'group2',
              color: 'BLUE',
              name: 'Group 2',
              nameHtml: 'Group 2',
              description: '',
              descriptionHtml: '',
            },
          },
        ],
        pageInfo: {hasNextPage: false, hasPreviousPage: false},
      }
      const groupsQueryKey = buildMemexGroupsQueryKey(variables, pageParamForInitialPage)
      queryClient.setQueryData(groupsQueryKey, groupsPageData)
      activateQueryByQueryKey(queryClient, groupsQueryKey)

      const secondaryGroupsPageData: MemexGroupsPageQueryData = {
        groups: [
          {
            groupId: 'serverSecondaryGroup1Id',
            groupValue: 'Secondary Group 1',
            groupMetadata: {
              id: 'secondaryGroup1',
              name: 'Secondary Group 1',
              nameHtml: 'Secondary Group 1',
              color: 'RED',
              description: '',
              descriptionHtml: '',
            },
          },
          {
            groupId: 'serverSecondaryGroup2Id',
            groupValue: 'Secondary Group 2',
            groupMetadata: {
              id: 'secondaryGroup2',
              name: 'Secondary Group 2',
              nameHtml: 'Secondary Group 2',
              color: 'RED',
              description: '',
              descriptionHtml: '',
            },
          },
        ],
        pageInfo: {hasNextPage: false, hasPreviousPage: false},
      }
      const secondaryGroupsQueryKey = buildMemexSecondaryGroupsQueryKey(variables, pageParamForInitialPage)
      queryClient.setQueryData(secondaryGroupsQueryKey, secondaryGroupsPageData)
      activateQueryByQueryKey(queryClient, secondaryGroupsQueryKey)

      const queryKeys = setAndActivateInitialQueriesByPageForGroup(
        queryClient,
        variables,
        {groupId: 'serverGroup1Id', secondaryGroupId: 'serverSecondaryGroup1Id'},
        [
          originalMemexItemModels, // page 1
        ],
        // intentionally not adding query data for empty cells
      )

      setPageParamsQueryDataForVariables(queryClient, variables, {
        groupedItems: {
          [createGroupedItemsId({groupId: 'serverGroup1Id', secondaryGroupId: 'serverSecondaryGroup1Id'})]: [
            pageParamForInitialPage,
          ],
          // intentionally not adding page params data for empty cells
        },
        pageParams: [pageParamForInitialPage],
        secondaryGroups: [pageParamForInitialPage],
      })

      const originalTotalCounts = {
        groups: {
          serverGroup1Id: {value: 1, isApproximate: false},
          serverGroup2Id: {value: 0, isApproximate: false},
          serverSecondaryGroup1Id: {value: 1, isApproximate: false},
          serverSecondaryGroup2Id: {value: 0, isApproximate: false},
        },
        totalCount: {
          value: originalMemexItemModels.length,
          isApproximate: false,
        },
      }
      mergeQueryDataForMemexItemsTotalCounts(queryClient, variables, originalTotalCounts)

      const result = updateMemexItemPositionInQueryClient(queryClient, originalMemexItemModels[0].id, {
        overGroupId: 'serverGroup2Id',
        overSecondaryGroupId: 'serverSecondaryGroup2Id',
      })

      const newTotals = getQueryDataForMemexItemsTotalCounts(queryClient, variables)
      // Overall total is unchanged
      expect(newTotals.totalCount?.value).toEqual(1)
      // Old primary group count is now 0
      expect(newTotals.groups['serverGroup1Id']?.value).toEqual(0)
      // New primary group count is now 1
      expect(newTotals.groups['serverGroup2Id']?.value).toEqual(1)
      // Old secondary group count is now 0
      expect(newTotals.groups['serverSecondaryGroup1Id']?.value).toEqual(0)
      // New secondary group count is now 1
      expect(newTotals.groups['serverSecondaryGroup2Id']?.value).toEqual(1)

      const newQueryKeys = [
        ...queryKeys,
        buildMemexGroupedItemsQueryKey(
          variables,
          {groupId: 'serverGroup2Id', secondaryGroupId: 'serverSecondaryGroup2Id'},
          pageParamForInitialPage,
        ),
      ]
      const newPages = newQueryKeys.map(queryKey => queryClient.getQueryData<MemexItemsPageQueryData>(queryKey))

      // moved item is no longer in first cell
      expect(newPages[0]?.nodes).toHaveLength(0)

      // moved item is now in a different cell
      expect(newPages[1]?.nodes).toHaveLength(1)
      expect(newPages[1]?.nodes[0].id).toBe(originalMemexItemModels[0].id)
      expect(result?.previousItemId).toBeUndefined()

      expect(result?.previousItemId).toBeUndefined()
      expect(result?.rollbackData.queryData).toHaveLength(2) // moving between two pages
      expect(result?.rollbackData.queryData[0].queryKey).toEqual(newQueryKeys[0])
      expect(result?.rollbackData.queryData[0].queryData.nodes).toEqual([originalMemexItemModels[0]])
      expect(result?.rollbackData.queryData[1].queryKey).toEqual(newQueryKeys[1]) // second page is where we're moving to
      expect(result?.rollbackData.queryData[1].queryData.nodes).toEqual([]) // initially no data in the second page

      // original totalCounts are also preserved
      expect(result?.rollbackData.totalCounts).toMatchObject(originalTotalCounts)
    })
  })

  describe('updateMemexItemWitNewRowPositionInQueryClient', () => {
    it('does nothing if the item cannot be found', () => {
      const queryClient = initQueryClient()
      const idForItemInQueryClient = 100
      const idForNonExistantItem = idForItemInQueryClient + 1
      const originalMemexItemModels = [issueFactory.build({id: idForItemInQueryClient})].map(item =>
        createMemexItemModel(item),
      )
      setInitialQueryClientItems(queryClient, originalMemexItemModels)

      const result = updateMemexItemWitNewRowPositionInQueryClient(queryClient, idForNonExistantItem, 0)

      const newMemexItemModels = getQueryClientItems(queryClient)

      expect(newMemexItemModels === originalMemexItemModels).toBeTruthy()
      expect(newMemexItemModels).toHaveLength(1)
      expect(result.previousItemId).toBe(-1)
      expect(result.previousMovingItemIndex).toBeUndefined()
    })

    it('moves an item down in the array', () => {
      const queryClient = initQueryClient()
      const originalMemexItemModels = [issueFactory.build(), pullRequestFactory.build()].map(item =>
        createMemexItemModel(item),
      )
      setInitialQueryClientItems(queryClient, originalMemexItemModels)

      const result = updateMemexItemWitNewRowPositionInQueryClient(queryClient, originalMemexItemModels[0].id, 1)

      const newMemexItemModels = getQueryClientItems(queryClient)

      expect(newMemexItemModels === originalMemexItemModels).toBeFalsy()
      expect(newMemexItemModels).toHaveLength(2)
      expect(newMemexItemModels[0]).toBe(originalMemexItemModels[1])
      expect(newMemexItemModels[1]).toBe(originalMemexItemModels[0])
      expect(result.previousItemId).toBe(originalMemexItemModels[1].id)
      expect(result.previousMovingItemIndex).toBe(0)
      // Reassigns prioritizedIndex to match new relative index
      expect(newMemexItemModels[0].prioritizedIndex).toEqual(0)
      expect(newMemexItemModels[1].prioritizedIndex).toEqual(1)
    })

    it('moves an item to be first in the array', () => {
      const queryClient = initQueryClient()
      const originalMemexItemModels = [issueFactory.build(), pullRequestFactory.build()].map(item =>
        createMemexItemModel(item),
      )
      setInitialQueryClientItems(queryClient, originalMemexItemModels)

      const result = updateMemexItemWitNewRowPositionInQueryClient(queryClient, originalMemexItemModels[1].id, 0)

      const newMemexItemModels = getQueryClientItems(queryClient)

      expect(newMemexItemModels === originalMemexItemModels).toBeFalsy()
      expect(newMemexItemModels).toHaveLength(2)
      expect(newMemexItemModels[1]).toBe(originalMemexItemModels[0])
      expect(newMemexItemModels[0]).toBe(originalMemexItemModels[1])
      expect(result.previousItemId).toBe('')
      expect(result.previousMovingItemIndex).toBe(1)
      // Reassigns prioritizedIndex to match new relative index
      expect(newMemexItemModels[0].prioritizedIndex).toEqual(0)
      expect(newMemexItemModels[1].prioritizedIndex).toEqual(1)
    })

    it('moves an item up in the array', () => {
      const queryClient = initQueryClient()
      const originalMemexItemModels = [issueFactory.build(), draftIssueFactory.build(), pullRequestFactory.build()].map(
        item => createMemexItemModel(item),
      )
      setInitialQueryClientItems(queryClient, originalMemexItemModels)

      const result = updateMemexItemWitNewRowPositionInQueryClient(queryClient, originalMemexItemModels[2].id, 1)

      const newMemexItemModels = getQueryClientItems(queryClient)

      expect(newMemexItemModels === originalMemexItemModels).toBeFalsy()
      expect(newMemexItemModels).toHaveLength(3)
      expect(newMemexItemModels[1]).toBe(originalMemexItemModels[2])
      expect(newMemexItemModels[2]).toBe(originalMemexItemModels[1])
      expect(result.previousItemId).toBe(originalMemexItemModels[0].id)
      expect(result.previousMovingItemIndex).toBe(2)
      // Reassigns prioritizedIndex to match new relative index
      expect(newMemexItemModels[0].prioritizedIndex).toEqual(0)
      expect(newMemexItemModels[1].prioritizedIndex).toEqual(1)
    })

    it('moves an item down where target index is within same page as item moving', () => {
      seedJSONIsland('memex-enabled-features', ['memex_table_without_limits'])

      const queryClient = initQueryClient()
      const originalMemexItemModels = [issueFactory.build(), pullRequestFactory.build()].map(item =>
        createMemexItemModel(item),
      )

      const queryKeys = setAndActivateInitialQueriesByPage(queryClient, {}, [
        [originalMemexItemModels[0], originalMemexItemModels[1]],
      ])

      const result = updateMemexItemWitNewRowPositionInQueryClient(queryClient, originalMemexItemModels[0].id, 1)
      const newMemexItemModels = getMemexItemModelsForQueryKeys(queryClient, queryKeys)

      expect(newMemexItemModels === originalMemexItemModels).toBeFalsy()
      expect(newMemexItemModels).toHaveLength(2)
      expect(newMemexItemModels[0]).toBe(originalMemexItemModels[1])
      expect(newMemexItemModels[1]).toBe(originalMemexItemModels[0])
      expect(result.previousItemId).toBe(originalMemexItemModels[1].id)
      expect(result.previousMovingItemIndex).toBe(0)
    })

    it('moves an item to be first where target index is within same page as item moving', () => {
      seedJSONIsland('memex-enabled-features', ['memex_table_without_limits'])

      const queryClient = initQueryClient()
      const originalMemexItemModels = [issueFactory.build(), pullRequestFactory.build()].map(item =>
        createMemexItemModel(item),
      )

      const queryKeys = setAndActivateInitialQueriesByPage(queryClient, {}, [
        [originalMemexItemModels[0], originalMemexItemModels[1]],
      ])

      const result = updateMemexItemWitNewRowPositionInQueryClient(queryClient, originalMemexItemModels[1].id, 0)
      const newMemexItemModels = getMemexItemModelsForQueryKeys(queryClient, queryKeys)

      expect(newMemexItemModels === originalMemexItemModels).toBeFalsy()
      expect(newMemexItemModels).toHaveLength(2)
      expect(newMemexItemModels[1]).toBe(originalMemexItemModels[0])
      expect(newMemexItemModels[0]).toBe(originalMemexItemModels[1])
      expect(result.previousItemId).toBe('')
      expect(result.previousMovingItemIndex).toBe(1)
    })

    it('moves an item up where target index is within same page as item moving', () => {
      seedJSONIsland('memex-enabled-features', ['memex_table_without_limits'])

      const queryClient = initQueryClient()
      const originalMemexItemModels = [issueFactory.build(), draftIssueFactory.build(), pullRequestFactory.build()].map(
        item => createMemexItemModel(item),
      )

      const queryKeys = setAndActivateInitialQueriesByPage(queryClient, {}, [
        [originalMemexItemModels[0], originalMemexItemModels[1], originalMemexItemModels[2]],
      ])

      const result = updateMemexItemWitNewRowPositionInQueryClient(queryClient, originalMemexItemModels[2].id, 1)
      const newMemexItemModels = getMemexItemModelsForQueryKeys(queryClient, queryKeys)

      expect(newMemexItemModels === originalMemexItemModels).toBeFalsy()
      expect(newMemexItemModels).toHaveLength(3)
      expect(newMemexItemModels[1]).toBe(originalMemexItemModels[2])
      expect(newMemexItemModels[2]).toBe(originalMemexItemModels[1])
      expect(result.previousItemId).toBe(originalMemexItemModels[0].id)
      expect(result.previousMovingItemIndex).toBe(2)
    })

    it(`'memex_table_without_limits' enabled: moves an item down in the array across multiple pages`, () => {
      seedJSONIsland('memex-enabled-features', ['memex_table_without_limits'])

      const queryClient = initQueryClient()
      const originalMemexItemModels = [
        issueFactory.build(),
        pullRequestFactory.build(),
        issueFactory.build(),
        pullRequestFactory.build(),
      ].map(item => createMemexItemModel(item))

      const queryKeys = setAndActivateInitialQueriesByPage(queryClient, {}, [
        [originalMemexItemModels[0], originalMemexItemModels[1]], // page 1
        [originalMemexItemModels[2], originalMemexItemModels[3]], // page 2
      ])

      const result = updateMemexItemWitNewRowPositionInQueryClient(queryClient, originalMemexItemModels[0].id, 2)

      const newMemexItemModels = getMemexItemModelsForQueryKeys(queryClient, queryKeys)

      expect(newMemexItemModels === originalMemexItemModels).toBeFalsy()
      expect(newMemexItemModels).toHaveLength(4)
      expect(newMemexItemModels[0]).toBe(originalMemexItemModels[1])
      expect(newMemexItemModels[1]).toBe(originalMemexItemModels[2])
      expect(newMemexItemModels[2]).toBe(originalMemexItemModels[0])
      expect(newMemexItemModels[3]).toBe(originalMemexItemModels[3])

      expect(result.previousItemId).toBe(originalMemexItemModels[2].id)
      expect(result.previousMovingItemIndex).toBe(0)
    })

    it(`'memex_table_without_limits' enabled: moves an item down in the array across multiple grouped pages`, () => {
      seedJSONIsland('memex-enabled-features', ['memex_table_without_limits'])

      const queryClient = initQueryClient()
      const originalMemexItemModels = [
        issueFactory.build(),
        pullRequestFactory.build(),
        issueFactory.build(),
        pullRequestFactory.build(),
      ].map(item => createMemexItemModel(item))

      // Include a query of groups in the query cache so that we can test the state where there are active
      // queries for both groups and items.
      // This should help prevent https://github.com/github/projects-platform/issues/1202 from regressing

      setQueryDataForMemexGroupsPage(queryClient, {}, pageParamForInitialPage, {
        groups: [{groupId: 'group1', groupValue: 'Group Name'}],
        pageInfo: {hasNextPage: false, hasPreviousPage: false},
      })
      activateQueryByQueryKey(queryClient, buildMemexGroupsQueryKey({}, pageParamForInitialPage))

      const queryKeys = setAndActivateInitialQueriesByPageForGroup(queryClient, {}, {groupId: 'group1'}, [
        [originalMemexItemModels[0], originalMemexItemModels[1]], // page 1
        [originalMemexItemModels[2], originalMemexItemModels[3]], // page 2
      ])

      const result = updateMemexItemWitNewRowPositionInQueryClient(queryClient, originalMemexItemModels[0].id, 2)

      const newMemexItemModels = getMemexItemModelsForQueryKeys(queryClient, queryKeys)

      expect(newMemexItemModels === originalMemexItemModels).toBeFalsy()
      expect(newMemexItemModels).toHaveLength(4)
      expect(newMemexItemModels[0]).toBe(originalMemexItemModels[1])
      expect(newMemexItemModels[1]).toBe(originalMemexItemModels[2])
      expect(newMemexItemModels[2]).toBe(originalMemexItemModels[0])
      expect(newMemexItemModels[3]).toBe(originalMemexItemModels[3])

      expect(result.previousItemId).toBe(originalMemexItemModels[2].id)
      expect(result.previousMovingItemIndex).toBe(0)
    })

    it(`'memex_table_without_limits' enabled: moves an item up in the array across multiple pages`, () => {
      seedJSONIsland('memex-enabled-features', ['memex_table_without_limits'])

      const queryClient = initQueryClient()
      const originalMemexItemModels = [
        issueFactory.build(),
        pullRequestFactory.build(),
        issueFactory.build(),
        pullRequestFactory.build(),
      ].map(item => createMemexItemModel(item))

      const queryKeys = setAndActivateInitialQueriesByPage(queryClient, {}, [
        [originalMemexItemModels[0], originalMemexItemModels[1]], // page 1
        [originalMemexItemModels[2], originalMemexItemModels[3]], // page 2
      ])

      const result = updateMemexItemWitNewRowPositionInQueryClient(queryClient, originalMemexItemModels[2].id, 1)

      const newMemexItemModels = getMemexItemModelsForQueryKeys(queryClient, queryKeys)

      expect(newMemexItemModels === originalMemexItemModels).toBeFalsy()
      expect(newMemexItemModels).toHaveLength(4)
      expect(newMemexItemModels[0]).toBe(originalMemexItemModels[0])
      expect(newMemexItemModels[1]).toBe(originalMemexItemModels[2])
      expect(newMemexItemModels[2]).toBe(originalMemexItemModels[1])
      expect(newMemexItemModels[3]).toBe(originalMemexItemModels[3])

      expect(result.previousItemId).toBe(newMemexItemModels[0].id)
      expect(result.previousMovingItemIndex).toBe(2)
    })

    it(`'memex_table_without_limits' enabled: moves an item to the first position in the array across multiple pages`, () => {
      seedJSONIsland('memex-enabled-features', ['memex_table_without_limits'])

      const queryClient = initQueryClient()
      const originalMemexItemModels = [
        issueFactory.build(),
        pullRequestFactory.build(),
        issueFactory.build(),
        pullRequestFactory.build(),
      ].map(item => createMemexItemModel(item))

      const queryKeys = setAndActivateInitialQueriesByPage(queryClient, {}, [
        [originalMemexItemModels[0], originalMemexItemModels[1]], // page 1
        [originalMemexItemModels[2], originalMemexItemModels[3]], // page 2
      ])

      const result = updateMemexItemWitNewRowPositionInQueryClient(queryClient, originalMemexItemModels[2].id, 0)

      const newMemexItemModels = getMemexItemModelsForQueryKeys(queryClient, queryKeys)

      expect(newMemexItemModels === originalMemexItemModels).toBeFalsy()
      expect(newMemexItemModels).toHaveLength(4)
      expect(newMemexItemModels[0]).toBe(originalMemexItemModels[2])
      expect(newMemexItemModels[1]).toBe(originalMemexItemModels[0])
      expect(newMemexItemModels[2]).toBe(originalMemexItemModels[1])
      expect(newMemexItemModels[3]).toBe(originalMemexItemModels[3])

      expect(result.previousItemId).toBe('') // empty string indicates this was moved into the first position with no previous item
      expect(result.previousMovingItemIndex).toBe(2)
    })
  })

  describe('updateMemexItemInQueryClient', () => {
    it('does nothing if item with id cannot be found', () => {
      const queryClient = initQueryClient()
      const originalMemexItemModels = [issueFactory.build()].map(item => createMemexItemModel(item))
      const newMemexItemWithDifferentId = issueFactory.build()
      setInitialQueryClientItems(queryClient, originalMemexItemModels)

      updateMemexItemInQueryClient(queryClient, newMemexItemWithDifferentId)

      const newMemexItemModels = getQueryClientItems(queryClient)

      expect(newMemexItemModels).toBe(originalMemexItemModels)
    })

    it('creates new array with merged values on a new MemexItemModel', () => {
      const queryClient = initQueryClient()
      const id = 10000
      const originalMemexItemModels = [
        issueFactory.build({
          id,
          memexProjectColumnValues: [columnValueFactory.title('Original title', ItemType.Issue).build()],
        }),
      ].map(item => createMemexItemModel(item))
      const newMemexItemWithSameId = issueFactory.build({
        id,
        memexProjectColumnValues: [columnValueFactory.title('New title', ItemType.Issue).build()],
      })

      setInitialQueryClientItems(queryClient, originalMemexItemModels)

      updateMemexItemInQueryClient(queryClient, newMemexItemWithSameId)

      const newMemexItemModels = getQueryClientItems(queryClient)

      expect(newMemexItemModels === originalMemexItemModels).toBeFalsy()
      expect(newMemexItemModels[0] === originalMemexItemModels[0]).toBeFalsy()
      expect(newMemexItemModels).toHaveLength(1)
      expect((newMemexItemModels[0].columns.Title?.value.title as EnrichedText).raw).toEqual('New title')
    })

    it(`'memex_table_without_limits' enabled: finds the item to update across multiple pages`, () => {
      seedJSONIsland('memex-enabled-features', ['memex_table_without_limits'])
      const queryClient = initQueryClient()
      const itemInSecondPageId = 10000
      const itemToUpdate = issueFactory.build({
        id: itemInSecondPageId,
        memexProjectColumnValues: [columnValueFactory.title('Original Title', ItemType.Issue).build()],
      })

      const firstPageItems = [issueFactory.build(), issueFactory.build()].map(item => createMemexItemModel(item))
      const secondPageItems = [issueFactory.build(), itemToUpdate].map(item => createMemexItemModel(item))

      // Initial query data with two pages
      const queryKeys = setAndActivateInitialQueriesByPage(queryClient, {}, [firstPageItems, secondPageItems])

      const initialMemexItems = getMemexItemModelsForQueryKeys(queryClient, queryKeys)

      // Verify that we do not initially have a Label column value for the first item in the second page
      // i.e. the 4th item in our flattened list
      expect(initialMemexItems[3].id).toBe(itemInSecondPageId)
      expect((initialMemexItems[3].columns.Title?.value.title as EnrichedText).raw).toEqual('Original Title')
      expect(initialMemexItems[3].columns.Labels).toBeUndefined()
      // Attempt to update the query data with a new data for the item in the second page
      // update itemInSecondPage with a label
      const labelColumnValue = columnValueFactory.labels(['foo']).build()
      const newMemexFactoryWithSameId = issueFactory.build({
        id: itemInSecondPageId,
        memexProjectColumnValues: [columnValueFactory.title('New Title', ItemType.Issue).build(), labelColumnValue],
      })
      const newMemexItemModel = createMemexItemModel(newMemexFactoryWithSameId)

      updateMemexItemInQueryClient(queryClient, newMemexItemModel)

      const newMemexItemModels = getMemexItemModelsForQueryKeys(queryClient, queryKeys)

      // Ensure the second item in the second page is the same item, but with a updated title and label value
      expect(newMemexItemModels[3].id).toBe(itemInSecondPageId)
      expect((newMemexItemModels[3].columns.Title?.value.title as EnrichedText).raw).toEqual('New Title')
      expect(newMemexItemModels[3].columns.Labels).toBe(labelColumnValue.value)
    })

    it(`'memex_table_without_limits' enabled: finds the item to update across multiple pages and groups`, () => {
      seedJSONIsland('memex-enabled-features', ['memex_table_without_limits'])
      const queryClient = initQueryClient()
      const itemInSecondPageId = 10000
      const itemToUpdate = issueFactory.build({
        id: itemInSecondPageId,
        memexProjectColumnValues: [columnValueFactory.title('Original Title', ItemType.Issue).build()],
      })

      const firstPageItems = [issueFactory.build(), issueFactory.build()].map(item => createMemexItemModel(item))
      const secondPageItems = [issueFactory.build(), itemToUpdate].map(item => createMemexItemModel(item))

      // Include a query of groups in the query cache so that we can test the state where there are active
      // queries for both groups and items.
      // This should help prevent https://github.com/github/projects-platform/issues/1202 from regressing

      setQueryDataForMemexGroupsPage(queryClient, {}, pageParamForInitialPage, {
        groups: [{groupId: 'group1', groupValue: 'Group Name'}],
        pageInfo: {hasNextPage: false, hasPreviousPage: false},
      })

      activateQueryByQueryKey(queryClient, buildMemexGroupsQueryKey({}, pageParamForInitialPage))

      // Initial query data with two pages
      const queryKeys = setAndActivateInitialQueriesByPageForGroup(queryClient, {}, {groupId: 'group1'}, [
        firstPageItems,
        secondPageItems,
      ])

      const initialMemexItems = getMemexItemModelsForQueryKeys(queryClient, queryKeys)

      // Verify that we do not initially have a Label column value for the first item in the second page
      // i.e. the 4th item in our flattened list
      expect(initialMemexItems[3].id).toBe(itemInSecondPageId)
      expect((initialMemexItems[3].columns.Title?.value.title as EnrichedText).raw).toEqual('Original Title')
      expect(initialMemexItems[3].columns.Labels).toBeUndefined()
      // Attempt to update the query data with a new data for the item in the second page
      // update itemInSecondPage with a label
      const labelColumnValue = columnValueFactory.labels(['foo']).build()
      const newMemexFactoryWithSameId = issueFactory.build({
        id: itemInSecondPageId,
        memexProjectColumnValues: [columnValueFactory.title('New Title', ItemType.Issue).build(), labelColumnValue],
      })
      const newMemexItemModel = createMemexItemModel(newMemexFactoryWithSameId)

      updateMemexItemInQueryClient(queryClient, newMemexItemModel)

      const newMemexItemModels = getMemexItemModelsForQueryKeys(queryClient, queryKeys)

      // Ensure the second item in the second page is the same item, but with a updated title and label value
      expect(newMemexItemModels[3].id).toBe(itemInSecondPageId)
      expect((newMemexItemModels[3].columns.Title?.value.title as EnrichedText).raw).toEqual('New Title')
      expect(newMemexItemModels[3].columns.Labels).toBe(labelColumnValue.value)
    })

    it(`'memex_table_without_limits' enabled: finds the item to update in the side panel`, () => {
      seedJSONIsland('memex-enabled-features', ['memex_table_without_limits'])
      const queryClient = initQueryClient()
      const sidePanelItemId = 10000
      const sidePanelItem = issueFactory.build({
        id: sidePanelItemId,
        memexProjectColumnValues: [columnValueFactory.title('Original Title', ItemType.Issue).build()],
      })

      const firstPageItems = [issueFactory.build(), issueFactory.build()].map(item => createMemexItemModel(item))
      const sidePanelItemModel = createMemexItemModel(sidePanelItem)

      // Initial query data with one page and one side panel item
      setAndActivateInitialQueriesByPage(queryClient, {}, [firstPageItems])
      setAndActivateInitialSidePanelQuery(queryClient, sidePanelItemModel)
      const sidePanelItemFromCache = getQueryDataForSidePanelItemNotOnClientFromQueryClient(
        queryClient,
        sidePanelItemId.toString(),
      )

      // Verify that we do not initially have a Label column value for the side panel item
      expect(sidePanelItemFromCache?.id).toBe(sidePanelItemId)
      expect((sidePanelItemFromCache?.columns.Title?.value.title as EnrichedText).raw).toEqual('Original Title')
      expect(sidePanelItemFromCache?.columns.Labels).toBeUndefined()
      // Attempt to update the query data with a new data for the side panel item
      const labelColumnValue = columnValueFactory.labels(['foo']).build()
      const newMemexFactoryWithSameId = issueFactory.build({
        id: sidePanelItemId,
        memexProjectColumnValues: [columnValueFactory.title('New Title', ItemType.Issue).build(), labelColumnValue],
      })
      const newMemexItemModel = createMemexItemModel(newMemexFactoryWithSameId)

      updateMemexItemInQueryClient(queryClient, newMemexItemModel)

      const newSidePanelItemModel = getQueryDataForSidePanelItemNotOnClientFromQueryClient(
        queryClient,
        sidePanelItemId.toString(),
      )

      // Ensure the side panel item is the same item, but with a updated title and label value
      expect(newSidePanelItemModel?.id).toBe(sidePanelItemId)
      expect((newSidePanelItemModel?.columns.Title?.value.title as EnrichedText).raw).toEqual('New Title')
      expect(newSidePanelItemModel?.columns.Labels).toBe(labelColumnValue.value)
    })
  })

  describe('updateMemexItemsInQueryClient', () => {
    it('creates new model for new items', () => {
      const queryClient = initQueryClient()
      const originalMemexItemModels: Array<MemexItemModel> = []
      const newMemexItem = issueFactory.build()
      setInitialQueryClientItems(queryClient, originalMemexItemModels)

      updateMemexItemsInQueryClient(queryClient, [newMemexItem], undefined)

      const newMemexItemModels = getQueryClientItems(queryClient)

      expect(newMemexItemModels === originalMemexItemModels).toBeFalsy()
      expect(newMemexItemModels).toHaveLength(1)
      expect(newMemexItemModels[0].id).toEqual(newMemexItem.id)
    })

    it('merges values for existing items', () => {
      const queryClient = initQueryClient()
      const id = 10000
      const originalMemexItemModels = [
        issueFactory.build({
          id,
          memexProjectColumnValues: [columnValueFactory.title('Original title', ItemType.Issue).build()],
        }),
      ].map(item => createMemexItemModel(item))
      const newMemexItemWithSameId = issueFactory.build({
        id,
        memexProjectColumnValues: [columnValueFactory.title('New title', ItemType.Issue).build()],
      })

      setInitialQueryClientItems(queryClient, originalMemexItemModels)

      updateMemexItemsInQueryClient(queryClient, [newMemexItemWithSameId], undefined)

      const newMemexItemModels = getQueryClientItems(queryClient)

      expect(newMemexItemModels === originalMemexItemModels).toBeFalsy()
      expect(newMemexItemModels[0] === originalMemexItemModels[0]).toBeFalsy()
      expect(newMemexItemModels).toHaveLength(1)
      expect((newMemexItemModels[0].columns.Title?.value.title as EnrichedText).raw).toEqual('New title')
    })

    it('skips updates for items with skippingLiveUpdates:true', () => {
      const queryClient = initQueryClient()
      const id = 10000
      const originalMemexItemModels = [
        issueFactory.build({
          id,
          memexProjectColumnValues: [columnValueFactory.title('Original title', ItemType.Issue).build()],
        }),
      ].map(item => createMemexItemModel(item))
      originalMemexItemModels[0].skippingLiveUpdates = true
      const newMemexItemWithSameId = issueFactory.build({
        id,
        memexProjectColumnValues: [columnValueFactory.title('New title', ItemType.Issue).build()],
      })

      setInitialQueryClientItems(queryClient, originalMemexItemModels)

      updateMemexItemsInQueryClient(queryClient, [newMemexItemWithSameId], undefined)

      const newMemexItemModels = getQueryClientItems(queryClient)

      expect(newMemexItemModels === originalMemexItemModels).toBeFalsy()
      expect(newMemexItemModels[0] === originalMemexItemModels[0]).toBeTruthy()
      expect(newMemexItemModels).toHaveLength(1)
      expect((newMemexItemModels[0].columns.Title?.value.title as EnrichedText).raw).toEqual('Original title')
    })

    it('skips updates for item id passed as sidePanelStateItemId', () => {
      const queryClient = initQueryClient()
      const id = 10000
      const originalColumnValue = columnValueFactory.labels(['original']).build()
      const originalMemexItemModels = [
        issueFactory.build({
          id,
          memexProjectColumnValues: [originalColumnValue],
        }),
      ].map(item => createMemexItemModel(item))
      const newMemexItemWithSameId = issueFactory.build({
        id,
        memexProjectColumnValues: [columnValueFactory.labels(['new']).build()],
      })

      setInitialQueryClientItems(queryClient, originalMemexItemModels)

      updateMemexItemsInQueryClient(queryClient, [newMemexItemWithSameId], id)

      const newMemexItemModels = getQueryClientItems(queryClient)

      expect(newMemexItemModels === originalMemexItemModels).toBeFalsy()
      expect(newMemexItemModels[0] === originalMemexItemModels[0]).toBeTruthy()
      expect(newMemexItemModels).toHaveLength(1)
      expect(newMemexItemModels[0].columns.Labels).toBe(originalColumnValue.value)
    })

    it('applies updates for item id passed as sidePanelStateItemId with title changes', () => {
      const queryClient = initQueryClient()
      const id = 10000
      const originalMemexItemModels = [
        issueFactory.build({
          id,
          memexProjectColumnValues: [columnValueFactory.title('Original title', ItemType.Issue).build()],
        }),
      ].map(item => createMemexItemModel(item))
      const newMemexItemWithSameId = issueFactory.build({
        id,
        memexProjectColumnValues: [columnValueFactory.title('New title', ItemType.Issue).build()],
      })

      setInitialQueryClientItems(queryClient, originalMemexItemModels)

      updateMemexItemsInQueryClient(queryClient, [newMemexItemWithSameId], id)

      const newMemexItemModels = getQueryClientItems(queryClient)

      expect(newMemexItemModels === originalMemexItemModels).toBeFalsy()
      expect(newMemexItemModels[0] === originalMemexItemModels[0]).toBeFalsy()
      expect(newMemexItemModels).toHaveLength(1)
      expect((newMemexItemModels[0].columns.Title?.value.title as EnrichedText).raw).toEqual('New title')
    })

    it(`merges values for existing items across multiple pages when 'memex_table_without_limits' flag is enabled`, () => {
      seedJSONIsland('memex-enabled-features', ['memex_table_without_limits'])

      const queryClient = initQueryClient()
      const id = 10000
      const originalMemexItemModels = [
        issueFactory.build(),
        issueFactory.build({
          id,
          memexProjectColumnValues: [columnValueFactory.title('Original title', ItemType.Issue).build()],
        }),
      ].map(item => createMemexItemModel(item))
      const newMemexItemWithSameId = issueFactory.build({
        id,
        memexProjectColumnValues: [columnValueFactory.title('New title', ItemType.Issue).build()],
      })

      const queryKeys = setAndActivateInitialQueriesByPage(queryClient, {}, [
        [originalMemexItemModels[0]],
        [originalMemexItemModels[1]],
      ])

      updateMemexItemsInQueryClient(queryClient, [newMemexItemWithSameId], undefined)

      const newMemexItemModels = getMemexItemModelsForQueryKeys(queryClient, queryKeys)

      expect(newMemexItemModels === originalMemexItemModels).toBeFalsy()
      expect(newMemexItemModels[1] === originalMemexItemModels[1]).toBeFalsy()
      expect(newMemexItemModels).toHaveLength(2)
      expect((newMemexItemModels[1].columns.Title?.value.title as EnrichedText).raw).toEqual('New title')
    })

    it(`merges values for existing items across multiple pages and groups when 'memex_table_without_limits' flag is enabled`, () => {
      seedJSONIsland('memex-enabled-features', ['memex_table_without_limits'])

      const queryClient = initQueryClient()
      const id = 10000
      const originalMemexItemModels = [
        issueFactory.build(),
        issueFactory.build({
          id,
          memexProjectColumnValues: [columnValueFactory.title('Original title', ItemType.Issue).build()],
        }),
      ].map(item => createMemexItemModel(item))
      const newMemexItemWithSameId = issueFactory.build({
        id,
        memexProjectColumnValues: [columnValueFactory.title('New title', ItemType.Issue).build()],
      })

      // Include a query of groups in the query cache so that we can test the state where there are active
      // queries for both groups and items.
      // This should help prevent https://github.com/github/projects-platform/issues/1202 from regressing

      setQueryDataForMemexGroupsPage(queryClient, {}, pageParamForInitialPage, {
        groups: [{groupId: 'group1', groupValue: 'Group Name'}],
        pageInfo: {hasNextPage: false, hasPreviousPage: false},
      })
      activateQueryByQueryKey(queryClient, buildMemexGroupsQueryKey({}, pageParamForInitialPage))

      const queryKeys = setAndActivateInitialQueriesByPageForGroup(queryClient, {}, {groupId: 'group1'}, [
        [originalMemexItemModels[0]],
        [originalMemexItemModels[1]],
      ])

      updateMemexItemsInQueryClient(queryClient, [newMemexItemWithSameId], undefined)

      const newMemexItemModels = getMemexItemModelsForQueryKeys(queryClient, queryKeys)

      expect(newMemexItemModels === originalMemexItemModels).toBeFalsy()
      expect(newMemexItemModels[1] === originalMemexItemModels[1]).toBeFalsy()
      expect(newMemexItemModels).toHaveLength(2)
      expect((newMemexItemModels[1].columns.Title?.value.title as EnrichedText).raw).toEqual('New title')
    })

    it(`'memex_table_without_limits' enabled: adds items that dont exist yet`, () => {
      seedJSONIsland('memex-enabled-features', ['memex_table_without_limits'])

      const queryClient = initQueryClient()
      const id = 10000
      const originalMemexItemModels = [issueFactory.build(), issueFactory.build()].map(item =>
        createMemexItemModel(item),
      )
      const newMemexItemWithId = issueFactory.build({
        id,
        memexProjectColumnValues: [columnValueFactory.title('New title', ItemType.Issue).build()],
      })

      const queryKeys = setAndActivateInitialQueriesByPage(queryClient, {}, [
        [originalMemexItemModels[0]],
        [originalMemexItemModels[1]],
      ])

      updateMemexItemsInQueryClient(queryClient, [newMemexItemWithId], undefined)

      const newMemexItemModels = getMemexItemModelsForQueryKeys(queryClient, queryKeys)

      expect(newMemexItemModels === originalMemexItemModels).toBeFalsy()
      expect(newMemexItemModels).toHaveLength(3)
      expect((newMemexItemModels[2].columns.Title?.value.title as EnrichedText).raw).toEqual('New title')
    })

    it(`'memex_table_without_limits' enabled: skips updates for items with skippingLiveUpdates:true with flags enabled`, () => {
      seedJSONIsland('memex-enabled-features', ['memex_table_without_limits'])

      const queryClient = initQueryClient()
      const id = 10000
      const originalMemexItemModels = [
        issueFactory.build(),
        issueFactory.build({
          id,
          memexProjectColumnValues: [columnValueFactory.title('Original title', ItemType.Issue).build()],
        }),
      ].map(item => createMemexItemModel(item))
      originalMemexItemModels[1].skippingLiveUpdates = true
      const newMemexItemWithSameId = issueFactory.build({
        id,
        memexProjectColumnValues: [columnValueFactory.title('New title', ItemType.Issue).build()],
      })

      const queryKeys = setAndActivateInitialQueriesByPage(queryClient, {}, [
        [originalMemexItemModels[0]],
        [originalMemexItemModels[1]],
      ])

      updateMemexItemsInQueryClient(queryClient, [newMemexItemWithSameId], undefined)

      const newMemexItemModels = getMemexItemModelsForQueryKeys(queryClient, queryKeys)

      expect(newMemexItemModels === originalMemexItemModels).toBeFalsy()
      expect(newMemexItemModels[1] === originalMemexItemModels[1]).toBeTruthy()
      expect(newMemexItemModels).toHaveLength(2)
      expect((newMemexItemModels[1].columns.Title?.value.title as EnrichedText).raw).toEqual('Original title')
    })

    it(`'memex_table_without_limits' enabled: skips updates for item id passed as sidePanelStateItemId with flags enabled`, () => {
      seedJSONIsland('memex-enabled-features', ['memex_table_without_limits'])

      const queryClient = initQueryClient()
      const id = 10000
      const originalMemexItemModels = [
        issueFactory.build(),
        issueFactory.build({
          id,
          memexProjectColumnValues: [columnValueFactory.title('Original title', ItemType.Issue).build()],
        }),
      ].map(item => createMemexItemModel(item))
      const newMemexItemWithSameId = issueFactory.build({
        id,
        memexProjectColumnValues: [columnValueFactory.title('New title', ItemType.Issue).build()],
      })

      const queryKeys = setAndActivateInitialQueriesByPage(queryClient, {}, [
        [originalMemexItemModels[0]],
        [originalMemexItemModels[1]],
      ])

      updateMemexItemsInQueryClient(queryClient, [newMemexItemWithSameId], id)

      const newMemexItemModels = getMemexItemModelsForQueryKeys(queryClient, queryKeys)

      expect(newMemexItemModels === originalMemexItemModels).toBeFalsy()
      expect(newMemexItemModels[1] === originalMemexItemModels[1]).toBeTruthy()
      expect(newMemexItemModels).toHaveLength(2)
      expect((newMemexItemModels[1].columns.Title?.value.title as EnrichedText).raw).toEqual('Original title')
    })
  })

  describe('updateMemexItemsForColumnInQueryClient', () => {
    it('updates column values for items', () => {
      const queryClient = initQueryClient()
      const itemId = 10000
      const originalMemexItemModels = [issueFactory.build({id: itemId})].map(i => createMemexItemModel(i))
      setInitialQueryClientItems(queryClient, originalMemexItemModels)

      const labelColumnValue = columnValueFactory.labels(['foo']).build()
      const columnWithItems = {
        id: labelColumnValue.memexProjectColumnId,
        memexProjectColumnValues: [{memexProjectItemId: itemId, value: labelColumnValue.value}],
      } as IColumnWithItems
      updateMemexItemsForColumnInQueryClient(queryClient, columnWithItems)

      const newMemexItemModels = getQueryClientItems(queryClient)
      expect(newMemexItemModels[0].columns.Labels).toBe(labelColumnValue.value)
    })

    it('does not update memexProjectColumnValues if memex_side_panel_query is disabled', () => {
      const queryClient = initQueryClient()
      const itemId = 10000
      const originalMemexItemModels = [issueFactory.build({id: itemId})].map(i => createMemexItemModel(i))
      setInitialQueryClientItems(queryClient, originalMemexItemModels)

      const labelColumnValue = columnValueFactory.labels(['foo']).build()
      const columnWithItems = {
        id: labelColumnValue.memexProjectColumnId,
        memexProjectColumnValues: [{memexProjectItemId: itemId, value: labelColumnValue.value}],
      } as IColumnWithItems
      updateMemexItemsForColumnInQueryClient(queryClient, columnWithItems)

      const newMemexItemModels = getQueryClientItems(queryClient)
      expect(newMemexItemModels[0].columns.Labels).toBe(labelColumnValue.value)

      // We want to check the `memexProjectColumnValues` to see if the new column data was added;
      // however, we can't directly access this field. So, we instead perform a merge with the same
      // item, which internally iterates over this array, and will tell us whether or not
      // it was actually updated.
      const mergedItem = createMemexItemModel(mergeItemData(newMemexItemModels[0], newMemexItemModels[0])!)

      // An undefined value here means that `memexProjectColumnValues` was not updated.
      expect(mergedItem?.columns.Labels).toBeUndefined()
    })

    it('updates memexProjectColumnValues if memex_side_panel_query is enabled', () => {
      seedJSONIsland('memex-enabled-features', ['memex_side_panel_query'])
      const queryClient = initQueryClient()
      const itemId = 10000
      const originalMemexItemModels = [issueFactory.build({id: itemId})].map(i => createMemexItemModel(i))
      setInitialQueryClientItems(queryClient, originalMemexItemModels)

      const labelColumnValue = columnValueFactory.labels(['foo']).build()
      const columnWithItems = {
        id: labelColumnValue.memexProjectColumnId,
        memexProjectColumnValues: [{memexProjectItemId: itemId, value: labelColumnValue.value}],
      } as IColumnWithItems
      updateMemexItemsForColumnInQueryClient(queryClient, columnWithItems)

      const newMemexItemModels = getQueryClientItems(queryClient)
      expect(newMemexItemModels[0].columns.Labels).toBe(labelColumnValue.value)

      // We want to check the `memexProjectColumnValues` to see if the new column data was added;
      // however, we can't directly access this field. So, we instead perform a merge with the same
      // item, which internally iterates over this array, and will tell us whether or not
      // it was actually updated.
      const mergedItem = createMemexItemModel(mergeItemData(newMemexItemModels[0], newMemexItemModels[0])!)

      // A value here means that `memexProjectColumnValues` was properly updated.
      expect(mergedItem?.columns.Labels).toBe(labelColumnValue.value)
    })

    it('sets column value to undefined if data is not present for item', () => {
      const queryClient = initQueryClient()
      const originalMemexItemModels = [issueFactory.build({id: 100})].map(i => createMemexItemModel(i))
      setInitialQueryClientItems(queryClient, originalMemexItemModels)

      const labelColumnValue = columnValueFactory.labels(['foo']).build()
      const columnWithItems = {
        id: labelColumnValue.memexProjectColumnId,
        // Different item id
        memexProjectColumnValues: [{memexProjectItemId: 200, value: labelColumnValue.value}],
      } as IColumnWithItems
      updateMemexItemsForColumnInQueryClient(queryClient, columnWithItems)

      const newMemexItemModels = getQueryClientItems(queryClient)
      expect(newMemexItemModels[0].columns).toStrictEqual({Labels: undefined})
    })

    it(`'memex_table_without_limits' enabled: updates column values for items across multiple pages`, () => {
      seedJSONIsland('memex-enabled-features', ['memex_table_without_limits'])
      const queryClient = initQueryClient()
      const itemInSecondPageId = 10000
      const originalMemexItemModels = [issueFactory.build(), issueFactory.build({id: itemInSecondPageId})].map(i =>
        createMemexItemModel(i),
      )
      // Initial query data with two pages, each with a single item
      const queryKeys = setAndActivateInitialQueriesByPage(queryClient, {}, [
        [originalMemexItemModels[0]],
        [originalMemexItemModels[1]],
      ])

      const initialMemexItems = getMemexItemModelsForQueryKeys(queryClient, queryKeys)

      // Verify that we do not initially have a Label column value for the first item in the second page
      expect(initialMemexItems[1].id).toBe(itemInSecondPageId)
      expect(initialMemexItems[1].columns.Labels).toBeUndefined()

      const labelColumnValue = columnValueFactory.labels(['foo']).build()
      const columnWithItems = {
        id: labelColumnValue.memexProjectColumnId,
        memexProjectColumnValues: [{memexProjectItemId: itemInSecondPageId, value: labelColumnValue.value}],
      } as IColumnWithItems
      // Attempt to update the query data with a new data for the item in the second page
      updateMemexItemsForColumnInQueryClient(queryClient, columnWithItems)

      const newMemexItemModels = getMemexItemModelsForQueryKeys(queryClient, queryKeys)

      // Ensure the first item in the second page is the same item, but with a new label value
      expect(newMemexItemModels[1].id).toBe(itemInSecondPageId)
      expect(newMemexItemModels[1].columns.Labels).toBe(labelColumnValue.value)
    })

    it(`'memex_table_without_limits' enabled: updates column values for items across multiple pages and groups`, () => {
      seedJSONIsland('memex-enabled-features', ['memex_table_without_limits'])
      const queryClient = initQueryClient()
      const itemInSecondPageId = 10000
      const originalMemexItemModels = [issueFactory.build(), issueFactory.build({id: itemInSecondPageId})].map(i =>
        createMemexItemModel(i),
      )

      // Include a query of groups in the query cache so that we can test the state where there are active
      // queries for both groups and items.
      // This should help prevent https://github.com/github/projects-platform/issues/1202 from regressing

      setQueryDataForMemexGroupsPage(queryClient, {}, pageParamForInitialPage, {
        groups: [{groupId: 'group1', groupValue: 'Group Name'}],
        pageInfo: {hasNextPage: false, hasPreviousPage: false},
      })
      activateQueryByQueryKey(queryClient, buildMemexGroupsQueryKey({}, pageParamForInitialPage))

      // Initial query data with two pages, each with a single item
      const queryKeys = setAndActivateInitialQueriesByPageForGroup(queryClient, {}, {groupId: 'group1'}, [
        [originalMemexItemModels[0]],
        [originalMemexItemModels[1]],
      ])

      const initialMemexItems = getMemexItemModelsForQueryKeys(queryClient, queryKeys)

      // Verify that we do not initially have a Label column value for the first item in the second page
      expect(initialMemexItems[1].id).toBe(itemInSecondPageId)
      expect(initialMemexItems[1].columns.Labels).toBeUndefined()

      const labelColumnValue = columnValueFactory.labels(['foo']).build()
      const columnWithItems = {
        id: labelColumnValue.memexProjectColumnId,
        memexProjectColumnValues: [{memexProjectItemId: itemInSecondPageId, value: labelColumnValue.value}],
      } as IColumnWithItems
      // Attempt to update the query data with a new data for the item in the second page
      updateMemexItemsForColumnInQueryClient(queryClient, columnWithItems)

      const newMemexItemModels = getMemexItemModelsForQueryKeys(queryClient, queryKeys)

      // Ensure the first item in the second page is the same item, but with a new label value
      expect(newMemexItemModels[1].id).toBe(itemInSecondPageId)
      expect(newMemexItemModels[1].columns.Labels).toBe(labelColumnValue.value)
    })
  })

  describe('getQueryDataForSidePanelItemNotOnClientFromQueryClient', () => {
    it('returns undefined if itemId is null', () => {
      const queryClient = initQueryClient()
      const result = getQueryDataForSidePanelItemNotOnClientFromQueryClient(queryClient, null)
      expect(result).toBeUndefined()
    })

    it('returns undefined if itemId is not in queryClient', () => {
      const queryClient = initQueryClient()
      const memexItemModel = createMemexItemModel(issueFactory.build())
      setQueryDataForSidePanelItemNotOnClientInQueryClient(queryClient, memexItemModel)
      const idNotInQueryData = '100000'
      const result = getQueryDataForSidePanelItemNotOnClientFromQueryClient(queryClient, idNotInQueryData)
      expect(result).toBeUndefined()
    })

    it('returns memexItemModel for itemId in queryClient', () => {
      const queryClient = initQueryClient()
      const memexItemModel = createMemexItemModel(issueFactory.build())
      setQueryDataForSidePanelItemNotOnClientInQueryClient(queryClient, memexItemModel)
      const result = getQueryDataForSidePanelItemNotOnClientFromQueryClient(queryClient, memexItemModel.id.toString())
      expect(result).toBe(memexItemModel)
    })
  })

  describe('setQueryDataForSidePanelItemNotOnClientInQueryClient', () => {
    it('returns early if item exists in main query cache', () => {
      const queryClient = initQueryClient()
      const memexItemModel = createMemexItemModel(issueFactory.build())
      setInitialQueryClientItems(queryClient, [memexItemModel])
      const found = findMemexItemByIdInQueryClient(queryClient, memexItemModel.id)
      expect(found).toEqual(memexItemModel)
      setQueryDataForSidePanelItemNotOnClientInQueryClient(queryClient, memexItemModel)
      const result = getQueryDataForSidePanelItemNotOnClientFromQueryClient(queryClient, memexItemModel.id.toString())
      expect(result).toBeUndefined()
    })

    it('removes the item from the side panel cache if it already exists in main query cache', () => {
      const queryClient = initQueryClient()
      const memexItemModel = createMemexItemModel(issueFactory.build())
      setQueryDataForSidePanelItemNotOnClientInQueryClient(queryClient, memexItemModel)
      const sidePanelCache = getQueryDataForSidePanelItemNotOnClientFromQueryClient(
        queryClient,
        memexItemModel.id.toString(),
      )
      // Succeeds when item not in main cache
      expect(sidePanelCache).toEqual(memexItemModel)

      setInitialQueryClientItems(queryClient, [memexItemModel])
      const mainCache = findMemexItemByIdInQueryClient(queryClient, memexItemModel.id)
      expect(mainCache).toEqual(memexItemModel)
      setQueryDataForSidePanelItemNotOnClientInQueryClient(queryClient, memexItemModel)
      const result = getQueryDataForSidePanelItemNotOnClientFromQueryClient(queryClient, memexItemModel.id.toString())
      // Removes item when already in main cache
      expect(result).toBeUndefined()
    })
  })

  describe('rollbackMemexItemData', () => {
    it('iterates over rollback data and updates query data', () => {
      const queryClient = initQueryClient()
      const variables: PaginatedMemexItemsQueryVariables = {}

      const queryKeys = setAndActivateInitialQueriesByPage(queryClient, variables, [
        [issueFactory.build()].map(item => createMemexItemModel(item)),
        [issueFactory.build()].map(item => createMemexItemModel(item)),
        [issueFactory.build()].map(item => createMemexItemModel(item)),
      ])
      const page1QueryKey = queryKeys[0]
      const page3QueryKey = queryKeys[2]

      const page1RollbackQueryData: MemexItemsPageQueryData = {
        nodes: [issueFactory.build()].map(item => createMemexItemModel(item)),
        pageInfo: {endCursor: '', startCursor: '', hasNextPage: true, hasPreviousPage: false},
      }
      const page3RollbackQueryData: MemexItemsPageQueryData = {
        nodes: [issueFactory.build()].map(item => createMemexItemModel(item)),
        pageInfo: {endCursor: '', startCursor: '2', hasNextPage: true, hasPreviousPage: false},
      }

      const page2ExistingQueryData = queryClient.getQueryData(queryKeys[1])

      const rollbackData: OptimisticUpdateRollbackData = {
        queryData: [
          {queryKey: page1QueryKey, queryData: page1RollbackQueryData},
          {queryKey: page3QueryKey, queryData: page3RollbackQueryData},
        ],
        totalCounts: {totalCount: {value: 2, isApproximate: false}, groups: {}},
      }

      rollbackMemexItemData(queryClient, rollbackData)

      // Pages 1 and 3 were in the rollback data, so they are changed to the value passed in
      expect(getQueryDataForMemexItemsPage(queryClient, variables, pageParamForInitialPage)).toBe(
        page1RollbackQueryData,
      )

      expect(getQueryDataForMemexItemsPage(queryClient, variables, {after: '2'})).toBe(page3RollbackQueryData)

      // Page 2 is not in the rollback data, so it is unchanged.
      expect(getQueryDataForMemexItemsPage(queryClient, variables, {after: '1'})).toBe(page2ExistingQueryData)

      // Total counts are rolled back to the value passed in
      expect(getQueryDataForMemexItemsTotalCounts(queryClient, variables)).toEqual(rollbackData.totalCounts)
    })
  })
})

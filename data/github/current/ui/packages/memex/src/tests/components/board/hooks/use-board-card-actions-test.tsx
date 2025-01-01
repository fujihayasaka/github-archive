import {
  isEveryItemInColumn,
  isEveryItemInColumnPWL,
} from '../../../../client/components/board/hooks/use-board-card-actions'
import {
  buildNoValueVerticalGroup,
  buildVerticalGroupForOption,
  type VerticalGroup,
} from '../../../../client/models/vertical-group'
import {createGroupedItemsId} from '../../../../client/state-providers/memex-items/queries/query-keys'
import {
  pageParamForInitialPage,
  type PaginatedMemexItemsQueryVariables,
} from '../../../../client/state-providers/memex-items/queries/types'
import {setPageParamsQueryDataForVariables} from '../../../../client/state-providers/memex-items/query-client-api/page-params'
import {statusOptions} from '../../../../mocks/data/single-select'
import {DefaultClosedIssue, DefaultDraftIssue, DefaultOpenIssue} from '../../../../mocks/memex-items'
import {issueFactory} from '../../../factories/memex-items/issue-factory'
import {createMemexItemModel} from '../../../mocks/models/memex-item-model'
import {
  initQueryClient,
  setAndActivateInitialQueriesByPageForGroup,
} from '../../../state-providers/memex-items/query-client-api/helpers'

describe('isEveryItemInColumn', () => {
  it('should return true when the columnValue is undefined and the target column is the no-option column', () => {
    expect(
      isEveryItemInColumn(
        // items with no status
        [createMemexItemModel(DefaultDraftIssue), createMemexItemModel(DefaultDraftIssue)],
        buildNoValueVerticalGroup('Status'),
        'Status',
      ),
    ).toBe(true)
  })

  it('should return false when a columnValue is undefined and the target column is not the no-option column', () => {
    expect(
      isEveryItemInColumn(
        // items with labels
        [createMemexItemModel(DefaultDraftIssue), createMemexItemModel(DefaultDraftIssue)],
        buildVerticalGroupForOption(statusOptions.find(o => o.name === 'Backlog')!),
        'Status',
      ),
    ).toBe(false)
  })

  it('should return true when selected columnValues are already in the target column', () => {
    expect(
      isEveryItemInColumn(
        // backlog items
        [createMemexItemModel(DefaultOpenIssue), createMemexItemModel(DefaultOpenIssue)],
        buildVerticalGroupForOption(statusOptions.find(o => o.name === 'Backlog')!),
        'Status',
      ),
    ).toBe(true)
  })

  it('should return false when selected columnValues are not in the target column', () => {
    expect(
      isEveryItemInColumn(
        // closed items
        [createMemexItemModel(DefaultClosedIssue), createMemexItemModel(DefaultClosedIssue)],
        buildVerticalGroupForOption(statusOptions.find(o => o.name === 'Backlog')!),
        'Status',
      ),
    ).toBe(false)
  })
})

describe('isEveryItemInColumnPWL', () => {
  it('should return true when all items are in a single query for group', () => {
    const queryClient = initQueryClient()
    const variables: PaginatedMemexItemsQueryVariables = {}
    const originalMemexItemModels = [issueFactory.build(), issueFactory.build(), issueFactory.build()].map(item =>
      createMemexItemModel(item),
    )

    setAndActivateInitialQueriesByPageForGroup(queryClient, variables, {groupId: 'group1'}, [
      [originalMemexItemModels[0], originalMemexItemModels[1]], // 1 page with two items
    ])
    setAndActivateInitialQueriesByPageForGroup(queryClient, variables, {groupId: 'group2'}, [
      [originalMemexItemModels[2]], // 1 page with one item
    ])

    setPageParamsQueryDataForVariables(queryClient, variables, {
      groupedItems: {
        [createGroupedItemsId({groupId: 'group1'})]: [pageParamForInitialPage],
        [createGroupedItemsId({groupId: 'group2'})]: [pageParamForInitialPage],
      },
      pageParams: [pageParamForInitialPage],
    })

    const group1: VerticalGroup = {id: 'group1', groupMetadata: undefined, name: 'Group 1', nameHtml: 'Group 1'}
    const group2: VerticalGroup = {id: 'group2', groupMetadata: undefined, name: 'Group 2', nameHtml: 'Group 2'}

    // 2 items from group 1
    expect(
      isEveryItemInColumnPWL(queryClient, [originalMemexItemModels[0], originalMemexItemModels[1]], group1),
    ).toBeTruthy()

    // 1 item from group 2
    expect(isEveryItemInColumnPWL(queryClient, [originalMemexItemModels[2]], group2)).toBeTruthy()

    // All 3 items across 2 groups
    expect(
      isEveryItemInColumnPWL(
        queryClient,
        [originalMemexItemModels[0], originalMemexItemModels[1], originalMemexItemModels[2]],
        group1,
      ),
    ).toBeFalsy()

    // All 3 items across 2 groups
    expect(
      isEveryItemInColumnPWL(
        queryClient,
        [originalMemexItemModels[0], originalMemexItemModels[1], originalMemexItemModels[2]],
        group2,
      ),
    ).toBeFalsy()
  })

  it('should return true when all items are in multiple queries for a group', () => {
    const queryClient = initQueryClient()
    const variables: PaginatedMemexItemsQueryVariables = {}
    const originalMemexItemModels = [issueFactory.build(), issueFactory.build()].map(item => createMemexItemModel(item))

    setAndActivateInitialQueriesByPageForGroup(queryClient, variables, {groupId: 'group1'}, [
      [originalMemexItemModels[0]], // First page with one item
      [originalMemexItemModels[1]], // Second page with one item
    ])

    setPageParamsQueryDataForVariables(queryClient, variables, {
      groupedItems: {
        [createGroupedItemsId({groupId: 'group1'})]: [pageParamForInitialPage, {after: 'cursor1'}],
      },
      pageParams: [pageParamForInitialPage],
    })

    const group1: VerticalGroup = {id: 'group1', groupMetadata: undefined, name: 'Group 1', nameHtml: 'Group 1'}

    // 2 items from group 1
    expect(
      isEveryItemInColumnPWL(queryClient, [originalMemexItemModels[0], originalMemexItemModels[1]], group1),
    ).toBeTruthy()
  })
})

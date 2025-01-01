import {ItemType} from '../../../client/api/memex-items/item-type'
import {useIsColumnLoadedForItem} from '../../../client/hooks/common/use-is-column-loaded'
import {DefaultColumns} from '../../../mocks/data/columns'
import {createMockEnvironment} from '../../create-mock-environment'
import {columnValueFactory} from '../../factories/column-values/column-value-factory'
import {issueFactory} from '../../factories/memex-items/issue-factory'
import {createMemexItemModel} from '../../mocks/models/memex-item-model'

const mockUseHasColumnData = jest.fn()
jest.mock('../../../client/state-providers/columns/use-has-column-data', () => ({
  useHasColumnData: () => ({
    hasColumnData: mockUseHasColumnData,
  }),
}))

describe('useIsColumnLoadedForItem', () => {
  describe('memex_table_without_limits disabled', () => {
    it('uses useHasColumnData to determine if field is loaded', () => {
      const item = createMemexItemModel(issueFactory.build())
      // Item has no columns
      expect(Object.keys(item.columns).length).toEqual(0)

      // But columns are still considered loaded based on useHasColumnData
      mockUseHasColumnData.mockReturnValue(true)
      expect(useIsColumnLoadedForItem(item, 10)).toBeTruthy()
      expect(useIsColumnLoadedForItem(item, 20)).toBeTruthy()
    })
  })

  describe('memex_table_without_limits enabled', () => {
    it('uses item.columns to determine if field is loaded', () => {
      createMockEnvironment({
        jsonIslandData: {
          'memex-columns-data': DefaultColumns,
          'memex-enabled-features': ['memex_table_without_limits'],
        },
      })
      const item = createMemexItemModel(issueFactory.build())
      // Item has no columns
      expect(Object.keys(item.columns).length).toEqual(0)

      const titleColumn = DefaultColumns.find(c => c.name === 'Title')
      const statusColumn = DefaultColumns.find(c => c.name === 'Status')

      // Does not use result of useHasColumnData
      mockUseHasColumnData.mockReturnValue(true)
      expect(useIsColumnLoadedForItem(item, titleColumn!.id)).toBeFalsy()
      expect(useIsColumnLoadedForItem(item, statusColumn!.id)).toBeFalsy()

      const itemWithColumns = createMemexItemModel(
        issueFactory
          .withColumnValues([
            columnValueFactory.title('A title', ItemType.Issue).build(),
            columnValueFactory.status('Backlog', DefaultColumns).build(),
          ])
          .build(),
      )

      // Does not use result of useHasColumnData
      mockUseHasColumnData.mockReturnValue(false)
      expect(Object.keys(itemWithColumns.columns).length).toEqual(2)
      expect(useIsColumnLoadedForItem(itemWithColumns, titleColumn!.id)).toBeTruthy()
      expect(useIsColumnLoadedForItem(itemWithColumns, statusColumn!.id)).toBeTruthy()
    })
  })
})

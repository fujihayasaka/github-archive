import {test} from '../../fixtures/test-extended'
import {waitForSuggestions} from '../../helpers/dom/interactions'

const rowSelector = 'div[data-testid^=TableRow]'

test.describe('Filtering by issue type field values', () => {
  test.beforeEach(async ({memex}) => {
    await memex.navigateToStory('integrationTestsWithItems', {
      viewType: 'table',
      serverFeatures: {memex_table_without_limits: true},
    })
  })

  test('shows correct number of items when filtering on issue type', async ({memex}) => {
    await memex.sharedInteractions.filterToExpectedCount('type:Batch', rowSelector, 1)
    await memex.sharedInteractions.filterToExpectedCount('type:Bug', rowSelector, 1)
    await memex.sharedInteractions.filterToExpectedCount('no:type', rowSelector, 5)
    await memex.sharedInteractions.filterToExpectedCount('-no:type', rowSelector, 2)
  })

  test('search suggestions shows issue type field', async ({page, memex}) => {
    await memex.filter.toggleFilter()
    await waitForSuggestions(page, 'ty')
    await memex.filter.expectToBeFocused()
    await memex.filter.expectToHaveValue('type:')
  })
})

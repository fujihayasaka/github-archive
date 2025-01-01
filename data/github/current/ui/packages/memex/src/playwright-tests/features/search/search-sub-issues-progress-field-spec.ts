import {test} from '../../fixtures/test-extended'
import {waitForSuggestions} from '../../helpers/dom/interactions'

const rowSelector = 'div[data-testid^=TableRow]'

test.describe('Filtering by sub-issues progress field values', () => {
  test.beforeEach(async ({memex}) => {
    await memex.navigateToStory('integrationTestsWithSubIssues', {
      viewType: 'table',
      serverFeatures: {memex_table_without_limits: true},
    })
  })

  test('shows correct number of items when filtering on sub-issues progress', async ({memex}) => {
    await memex.sharedInteractions.filterToExpectedCount('no:sub-issues-progress', rowSelector, 28)
    await memex.sharedInteractions.filterToExpectedCount('-no:sub-issues-progress', rowSelector, 2)
    await memex.sharedInteractions.filterToExpectedCount('has:sub-issues-progress', rowSelector, 2)
    await memex.sharedInteractions.filterToExpectedCount('-has:sub-issues-progress', rowSelector, 28)
  })

  test('search suggestions show sub-issues progress field', async ({page, memex}) => {
    await memex.filter.toggleFilter()
    await waitForSuggestions(page, 'su')
    await memex.filter.expectSuggestionsResultCount(3)
    await memex.filter.expectToHaveSuggestions([
      'No sub-issues progress',
      'Has sub-issues progress',
      'Exclude sub-issues-progress',
    ])
    await memex.filter.expectToBeFocused()
    await memex.filter.expectToHaveValue('sub-issues-progress:')
  })
})

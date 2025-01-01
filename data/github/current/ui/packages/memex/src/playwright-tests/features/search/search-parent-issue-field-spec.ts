import {test} from '../../fixtures/test-extended'
import {waitForSuggestions} from '../../helpers/dom/interactions'

const rowSelector = 'div[data-testid^=TableRow]'

test.describe('Filtering by parent issue field values', () => {
  test.beforeEach(async ({memex}) => {
    await memex.navigateToStory('integrationTestsWithSubIssues', {
      viewType: 'table',
      serverFeatures: {memex_table_without_limits: true},
    })
  })

  test('shows correct number of items when filtering on parent issue', async ({memex}) => {
    await memex.sharedInteractions.filterToExpectedCount('no:parent-issue', rowSelector, 26)
    await memex.sharedInteractions.filterToExpectedCount('-no:parent-issue', rowSelector, 4)
    await memex.sharedInteractions.filterToExpectedCount('has:parent-issue', rowSelector, 4)
    await memex.sharedInteractions.filterToExpectedCount('-has:parent-issue', rowSelector, 26)
  })

  test('search suggestions show parent issue field', async ({page, memex}) => {
    await memex.filter.toggleFilter()
    await waitForSuggestions(page, 'pa')
    await memex.filter.expectToBeFocused()
    await memex.filter.expectToHaveValue('parent-issue:')
  })
})

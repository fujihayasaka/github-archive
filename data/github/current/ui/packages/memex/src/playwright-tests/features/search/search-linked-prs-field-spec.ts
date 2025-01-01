import {test} from '../../fixtures/test-extended'
import {waitForSuggestions} from '../../helpers/dom/interactions'

const rowSelector = 'div[data-testid^=TableRow]'

test.describe('Filtering by linked pull request field values', () => {
  test.beforeEach(async ({memex}) => {
    await memex.navigateToStory('integrationTestsWithItems', {
      viewType: 'table',
      serverFeatures: {memex_table_without_limits: true},
    })
  })

  test('shows correct number of items when filtering is done based on pull request numbers', async ({memex}) => {
    await memex.sharedInteractions.filterToExpectedCount('linked-pull-requests:123', rowSelector, 1)
    await memex.sharedInteractions.filterToExpectedCount('linked-pull-requests:1234', rowSelector, 1)
    await memex.sharedInteractions.filterToExpectedCount('linked-pull-requests:111111', rowSelector, 0)
  })

  test('search suggestions shows linked pull request field', async ({page, memex}) => {
    await memex.filter.toggleFilter()
    await waitForSuggestions(page, 'linked')
    await memex.filter.expectSuggestionsResultCount(3)
    await memex.filter.expectToHaveSuggestions([
      'No linked pull requests',
      'Has linked pull requests',
      'Exclude linked-pull-requests',
    ])
    await memex.filter.expectToBeFocused()
    await memex.filter.expectToHaveValue('linked-pull-requests:')
  })
})

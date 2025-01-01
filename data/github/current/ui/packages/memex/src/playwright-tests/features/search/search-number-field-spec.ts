import {test} from '../../fixtures/test-extended'
import {waitForSuggestions} from '../../helpers/dom/interactions'

const rowSelector = 'div[data-testid^=TableRow]'

test.describe('Filtering by number field values', () => {
  test.beforeEach(async ({memex}) => {
    await memex.navigateToStory('integrationTestsWithItems', {
      viewType: 'table',
      serverFeatures: {memex_table_without_limits: true},
    })
  })

  test('search suggestions shows number field title', async ({page, memex}) => {
    await memex.filter.toggleFilter()

    await waitForSuggestions(page, 'Est')

    await memex.filter.expectToBeFocused()
    await memex.filter.expectToHaveValue('estimate:')
  })

  test('search suggestions shows number field values', async ({page, memex}) => {
    await memex.filter.toggleFilter()

    await waitForSuggestions(page, 'Estimate:', {withSelection: false})

    await memex.filter.expectSuggestionsResultCount(3)
    await memex.filter.expectToHaveSuggestions(['No estimate', 'Has estimate', 'Exclude estimate'])
  })

  test('shows correct number of items when filtering is done based on number values', async ({memex}) => {
    await memex.sharedInteractions.filterToExpectedCount('Estimate:10', rowSelector, 2)
    await memex.sharedInteractions.filterToExpectedCount('Estimate:3', rowSelector, 1)
  })
})

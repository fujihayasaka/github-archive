import {test} from '../../fixtures/test-extended'
import {waitForSuggestions} from '../../helpers/dom/interactions'

const rowSelector = 'div[data-testid^=TableRow]'

test.describe('Filtering by iteration field values', () => {
  test.beforeEach(async ({memex}) => {
    await memex.navigateToStory('appWithIterationsField', {
      viewType: 'table',
      serverFeatures: {memex_table_without_limits: true},
    })
  })

  test('shows correct number of items when filtering is done based on iteration values', async ({memex}) => {
    await memex.sharedInteractions.filterToExpectedCount('Iteration:"Iteration 4"', rowSelector, 3)
    await memex.sharedInteractions.filterToExpectedCount('Iteration:"Iteration 5"', rowSelector, 1)
  })

  test('shows correct number of items when filtering is done using iteration @current filter', async ({memex}) => {
    await memex.sharedInteractions.filterToExpectedCount('Iteration:@current', rowSelector, 3)
  })

  test('shows correct number of items when filtering on multiple iteration values', async ({memex}) => {
    await memex.sharedInteractions.filterToExpectedCount('Iteration:"Iteration 4",@next', rowSelector, 4)
  })

  test('search suggestions shows iteration fields title', async ({page, memex}) => {
    await memex.filter.toggleFilter()
    await waitForSuggestions(page, 'ite')
    await memex.filter.expectToBeFocused()
    await memex.filter.expectToHaveValue('iteration:')
  })

  test('search suggestions only shows iterations values that are currently in use', async ({page, memex}) => {
    await memex.filter.toggleFilter()
    await waitForSuggestions(page, 'ite')

    await page.waitForTimeout(1000)

    // 3 custom values, 2 of the items are pregenerated i.e No and Exclude, and then the two actual iterations
    await memex.filter.expectSuggestionsResultCount(13)
    await memex.filter.expectToHaveSuggestions([
      'No iteration',
      'Has iteration',
      'Exclude iteration',
      'Current iteration',
      'Next iteration',
      'Previous iteration',
      'Iteration 4',
      'Iteration 5',
      'Iteration 6',
      'Iteration 0',
      'Iteration 1',
      'Iteration 2',
      'Iteration 3',
    ])
  })
})

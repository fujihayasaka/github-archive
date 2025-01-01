import {test} from '../../fixtures/test-extended'
import {waitForSuggestions} from '../../helpers/dom/interactions'

const rowSelector = 'div[data-testid^=TableRow]'

test.describe('Filtering by iteration field values', () => {
  test.beforeEach(async ({memex}) => {
    await memex.navigateToStory('appWithReasonField', {
      viewType: 'table',
      serverFeatures: {memex_table_without_limits: true},
    })
  })

  test('shows correct number of items when filtering by reason as field or quantifier', async ({memex}) => {
    await memex.sharedInteractions.filterToExpectedCount('reason:customer-request', rowSelector, 2)
    await memex.sharedInteractions.filterToExpectedCount('reason:completed', rowSelector, 2)
  })

  test('shows correct number of items when filtering by reason with different values', async ({memex}) => {
    await memex.sharedInteractions.filterToExpectedCount('reason:customer-request,completed', rowSelector, 2)
    await memex.sharedInteractions.filterToExpectedCount('reason:"not planned","customer-request"', rowSelector, 3)
  })

  test('search suggestions shows reason field title once', async ({page, memex}) => {
    await memex.filter.toggleFilter()
    await waitForSuggestions(page, 'rea')
    await memex.filter.expectToBeFocused()
    await memex.filter.expectToHaveValue('reason:')
  })
})

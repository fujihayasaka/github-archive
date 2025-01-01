import {Resources} from '../../../client/strings'
import {test} from '../../fixtures/test-extended'
import {waitForSuggestions} from '../../helpers/dom/interactions'
import {getColumnHeaderMenuOption, getColumnMenuTrigger} from '../../helpers/table/interactions'

test.describe('SearchSuggestionsForTableOnly', () => {
  test.beforeEach(async ({memex}) => {
    await memex.navigateToStory('integrationTestsWithItems', {
      viewType: 'table',
      serverFeatures: {memex_table_without_limits: true},
    })

    // Show search input
    await memex.filter.toggleFilter()
  })

  test('Creating a filter from column header shows the suggestions correctly', async ({page, memex}) => {
    test.fixme(
      false,
      'PWL - Unexpected behavior, See https://github.com/github/projects-platform/issues/3092 for details',
    )
    const menuTrigger = await getColumnMenuTrigger(page, 'Assignees')

    // Open the menu.
    await menuTrigger.click()

    // Select the Filter by values option from Assignees
    const filterOption = getColumnHeaderMenuOption(page, 'Assignees', Resources.tableHeaderContextMenu.filterValues)
    await filterOption.click()

    // Suggestions should be displayed for the assignee column
    await memex.filter.toggleFilter() // should be refactored when annotation is fixed
    await waitForSuggestions(page, 'dma', {withSelection: false})
  })

  test('shows suggestions for filters on fields that contain dashes', async ({page, memex}) => {
    // Add a new single select field that contains a dash in its name
    await memex.tableView.addField.show()
    await memex.tableView.addField.clickNewField()
    await memex.tableView.addField.setFieldName('test-field')
    await memex.tableView.addField.setFieldType('text')
    await memex.tableView.addField.clickSaveButton()

    await page.waitForTimeout(1000) // wait a short time while the field is created

    // Try to filter on the new field
    await memex.filter.toggleFilter()
    await waitForSuggestions(page, 'test-field:', {withSelection: false})

    // We should see suggestions for the new field, with its
    // possible options populating the suggestions box
    await memex.filter.expectToHaveSuggestions([
      'No test-field',
      'Has test-field',
      'Exclude test-field',
      'test-field starts with...',
      'test-field ends with...',
      'test-field contains...',
    ])
  })

  // https://github.com/github/memex/issues/9285
  test.fixme('should be able to filter on fields that have hyphens and those that do not', async ({memex}) => {
    // Add a new single select field that contains a dash in its name
    await memex.tableView.addField.show()
    await memex.tableView.addField.clickNewField()
    await memex.tableView.addField.setFieldName('test-field')
    await memex.tableView.addField.setFieldType('text')
    await memex.tableView.addField.clickSaveButton()

    await memex.filter.INPUT.focus()

    // Should get suggestions for a field that had hyphens replacing spaces
    await memex.filter.expectToHaveSuggestionsForQuery('due-', ['due date:'])

    // Should get suggestions for a field that had hyphens originally in its name
    await memex.filter.expectToHaveSuggestionsForQuery('test-', ['test field:'])

    // Must also work with negated filters
    await memex.filter.expectToHaveSuggestionsForQuery('-due-', ['due date:'])
    await memex.filter.expectToHaveSuggestionsForQuery('-test-', ['test field:'])
  })
})

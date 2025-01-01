import {expect} from '@playwright/test'

import {test} from '../../fixtures/test-extended'
import {mustFind, mustNotFind} from '../../helpers/dom/assertions'
import {waitForSuggestions} from '../../helpers/dom/interactions'
import {_} from '../../helpers/dom/selectors'
import {eventually} from '../../helpers/utils'
import type {ViewType} from '../../types/view-type'

const EXTENDED_TIMEOUT = 6000
test.describe('SearchSuggestions', () => {
  const testCases: Array<{view: ViewType; itemSelector: string}> = [
    {
      view: 'table',
      itemSelector: 'div[data-testid^=TableRow]',
    },
    {
      view: 'board',
      itemSelector: 'div[data-testid=board-view-column-card]',
    },
  ]

  for (const testCase of testCases) {
    test(`does not display suggestions upon load in ${testCase.view}`, async ({memex}) => {
      await memex.navigateToStory('integrationTestsWithItems', {
        filterQuery: '-label:changelog',
        serverFeatures: {memex_table_without_limits: true},
      })

      await memex.filter.expectSuggestionsNotToBeVisible()
    })

    test.describe(`in ${testCase.view}`, () => {
      test.beforeEach(async ({memex}) => {
        await memex.navigateToStory('integrationTestsWithItems', {
          viewType: testCase.view,
          serverFeatures: {memex_table_without_limits: true},
        })

        // Show search input
        await memex.filter.toggleFilter()
      })

      test(`it shows the columns suggestion when clicking the input container`, async ({page, memex}) => {
        await memex.filter.toggleFilter()

        // suggestions are shown on focus
        await waitForSuggestions(page, 'as')
        await page.waitForTimeout(1000)

        await memex.filter.expectSuggestionsResultCount(9)
      })

      test(`it shows the column and keyword suggestions for negative search queries`, async ({page, memex}) => {
        await memex.filter.toggleFilter()

        // suggestions are shown on focus
        await waitForSuggestions(page, '-i', {withSelection: false})

        await memex.filter.expectSuggestionsResultCount(2)
        await memex.filter.expectToHaveSuggestions(['Impact', 'Is'])
        await page.waitForTimeout(1000)

        await page.keyboard.press('Backspace')
        await expect(page.getByTestId('suggestions-heading').getByText('Exclude')).toBeVisible()
        await page.waitForTimeout(1000)

        await page.keyboard.insertText('n')
        await page.waitForTimeout(1000)
        await page.keyboard.press('ArrowDown')
        await page.keyboard.press('ArrowDown')
        await page.waitForTimeout(1000)
        await memex.filter.expectTextForSelectedSuggestedItem(/No/)
      })

      // https://github.com/github/memex/issues/9288
      test.fixme(`mixing negative queries with other queries updates search field correctly`, async ({page, memex}) => {
        await memex.filter.INPUT.click()
        await memex.filter.expectToBeFocused()

        // suggestions are not shown on focus
        await mustNotFind(page, _('search-suggestions-box'))

        await page.keyboard.insertText('-as')

        await page.waitForSelector(_('search-suggestions-box'), {timeout: EXTENDED_TIMEOUT})
        await page.waitForSelector(_('search-suggestions-item-Assignees'), {timeout: EXTENDED_TIMEOUT})

        await page.keyboard.press('Enter')
        await page.waitForTimeout(500)
        await memex.filter.expectToBeFocused()
        await memex.filter.expectToHaveValue('-assignee:')

        await page.keyboard.press('Enter')
        await page.waitForTimeout(500)
        await memex.filter.expectToBeFocused()
        await memex.filter.expectToHaveValue('-no:assignee')

        await page.keyboard.insertText(' l')
        await page.waitForTimeout(500)

        await page.keyboard.press('Enter')
        await page.waitForTimeout(500)
        await memex.filter.expectToBeFocused()
        await memex.filter.expectToHaveValue('-no:assignee label:')

        await page.keyboard.press('ArrowDown')
        await page.keyboard.press('ArrowDown')
        await page.keyboard.press('ArrowDown')
        await page.keyboard.press('Enter')

        await page.waitForTimeout(500)
        await memex.filter.expectToBeFocused()
        await memex.filter.expectToHaveValue('-no:assignee label:"tech debt"')

        await page.keyboard.insertText(' -is')
        await page.waitForTimeout(500)
        await page.keyboard.press('Backspace')
        await page.keyboard.press('Backspace')
        await page.keyboard.press('Backspace')
        await page.keyboard.insertText('is')
        await page.waitForTimeout(500)

        await page.keyboard.press('Enter')
        await page.waitForTimeout(500)
        await memex.filter.expectToBeFocused()
        await memex.filter.expectToHaveValue('-no:assignee label:"tech debt" is:')
      })

      test(`supports keyboard navigation for selecting items`, async ({page, memex}) => {
        await memex.filter.toggleFilter()
        await waitForSuggestions(page, 'st', {withSelection: false})

        await page.waitForTimeout(500)
        await memex.filter.expectSuggestionsResultCount(3)
        await memex.filter.expectToHaveSuggestions(['Stage', 'Status', 'State'])

        await page.keyboard.press('ArrowDown')
        await memex.filter.expectTextForSelectedSuggestedItem('Stage')
      })

      test(`hides the suggestions with escape key`, async ({page, memex}) => {
        await memex.filter.toggleFilter()
        await waitForSuggestions(page, 'st', {withSelection: false})

        await page.keyboard.press('Escape')
        await page.waitForTimeout(500) // allow DOM to remove the element
        await expect(page.locator('[aria-label=Suggestions]')).not.toBeVisible()
      })

      test(`does not show any suggestions for text not matching existing filters`, async ({page, memex}) => {
        await memex.filter.toggleFilter()
        await page.waitForTimeout(500)

        await mustFind(page, '[aria-label=Suggestions]') // suggestions appear by defualt in PWL

        await page.keyboard.insertText('fixes')
        await memex.filter.expectToBeFocused()
        await memex.filter.expectToHaveValue('fixes')

        await page.waitForTimeout(500)
        await expect(page.locator('[aria-label=Suggestions]')).not.toBeVisible()
      })

      test(`shows present column values filter`, async ({page, memex}) => {
        await memex.filter.toggleFilter()

        await waitForSuggestions(page, 'labe', {withSelection: false})
        await page.keyboard.press('ArrowDown')
        await memex.filter.expectTextForSelectedSuggestedItem('Label')
        await page.keyboard.press('Enter')
        await page.waitForTimeout(1000)

        await memex.filter.expectToBeFocused()
        await memex.filter.expectToHaveValue('label:')
        await page.waitForTimeout(1000)

        // look for `has:` option, which is two options down in PWL:
        await page.keyboard.press('ArrowDown')
        await page.keyboard.press('ArrowDown')
        await page.waitForTimeout(1000)
        await page.keyboard.press('Enter')
        await memex.filter.expectToBeFocused()
        await memex.filter.expectToHaveValue('has:label')

        await page.waitForTimeout(1000)
        const resultsCountElement = await page.waitForSelector(_('filter-results-count'), {timeout: EXTENDED_TIMEOUT})
        await page.waitForTimeout(1000)
        expect(await resultsCountElement.textContent()).toBe('3')
        const rowsOnPageAfterFilter = page.locator(testCase.itemSelector)
        await expect(rowsOnPageAfterFilter).toHaveCount(3)
      })

      test(`shows suggestions for has filter`, async ({page, memex}) => {
        await memex.filter.toggleFilter()
        await page.waitForTimeout(1000)

        await waitForSuggestions(page, 'has', {withSelection: false})
        await page.keyboard.press('ArrowDown')
        await memex.filter.expectTextForSelectedSuggestedItem('Has')
        await page.keyboard.press('Enter')
        await memex.filter.expectToBeFocused()
        await memex.filter.expectToHaveValue('has:')

        // look for `Assignee` option, which is two options down in PWL:
        await page.keyboard.press('ArrowDown')
        await page.keyboard.press('ArrowDown')
        await page.keyboard.press('Enter')
        await page.waitForTimeout(1000)
        await memex.filter.expectToBeFocused()
        await memex.filter.expectToHaveValue('has:assignee')

        const resultsCountElement = await page.waitForSelector(_('filter-results-count'), {timeout: EXTENDED_TIMEOUT})
        await page.waitForTimeout(1000)
        expect(await resultsCountElement.textContent()).toBe('4')
        const rowsOnPageAfterFilter = page.locator(testCase.itemSelector)
        await expect(rowsOnPageAfterFilter).toHaveCount(4)
      })

      test(`shows empty column values filter`, async ({page, memex}) => {
        await memex.filter.toggleFilter()
        await page.waitForTimeout(500)

        await waitForSuggestions(page, 'labe', {withSelection: false})
        await page.keyboard.press('ArrowDown')
        await memex.filter.expectTextForSelectedSuggestedItem('Label')

        await page.keyboard.press('Enter')
        await page.waitForTimeout(500)
        await memex.filter.expectToBeFocused()
        await memex.filter.expectToHaveValue('label:')

        await page.keyboard.press('ArrowDown')
        await page.keyboard.press('Enter')
        await page.waitForTimeout(1000)
        await memex.filter.expectToBeFocused()
        await memex.filter.expectToHaveValue('no:label')
        await page.waitForTimeout(1000)
        const resultsCountElement = await page.waitForSelector(_('filter-results-count'), {timeout: EXTENDED_TIMEOUT})
        await page.waitForTimeout(1000) // wait a short time for the count to update
        expect(await resultsCountElement.textContent()).toBe('4')
        const rowsOnPageAfterFilter = page.locator(testCase.itemSelector)
        await expect(rowsOnPageAfterFilter).toHaveCount(4)
      })

      test(`shows suggestions for no filter`, async ({page, memex}) => {
        await memex.filter.toggleFilter()
        await page.waitForTimeout(500)

        await waitForSuggestions(page, 'no', {withSelection: false})
        await page.keyboard.press('ArrowDown')
        await memex.filter.expectTextForSelectedSuggestedItem('No')

        await page.keyboard.press('Enter')
        await page.waitForTimeout(500)
        await memex.filter.expectToBeFocused()
        await memex.filter.expectToHaveValue('no:')

        // look for `Assignee` option, which is two options down in PWL:
        await page.keyboard.press('ArrowDown')
        await page.keyboard.press('ArrowDown')
        await page.keyboard.press('Enter')
        await page.waitForTimeout(500)
        await memex.filter.expectToBeFocused()
        await memex.filter.expectToHaveValue('no:assignee')
        await page.waitForTimeout(1000) // wait for filter bar to populate
        const resultsCountElement = await page.waitForSelector(_('filter-results-count'), {timeout: EXTENDED_TIMEOUT})
        await page.waitForTimeout(500) // wait for counter to update
        expect(await resultsCountElement.textContent()).toBe('3')
        const rowsOnPageAfterFilter = page.locator(testCase.itemSelector)
        await expect(rowsOnPageAfterFilter).toHaveCount(3)
      })

      test(`shows negative filter option`, async ({page, memex}) => {
        await memex.filter.toggleFilter()
        await page.waitForTimeout(500)

        await waitForSuggestions(page, 'stat', {withSelection: false})
        await page.keyboard.press('ArrowDown')
        await memex.filter.expectTextForSelectedSuggestedItem('Status')

        await page.keyboard.press('Enter')
        await page.waitForTimeout(500)
        await memex.filter.expectToBeFocused()
        await memex.filter.expectToHaveValue('status:')

        // look for `exclusion` option, which is three options down in PWL:
        await page.keyboard.press('ArrowDown')
        await page.keyboard.press('ArrowDown')
        await page.keyboard.press('ArrowDown')
        await page.keyboard.press('Enter')
        await page.waitForTimeout(500)

        await memex.filter.expectToBeFocused()
        await memex.filter.expectToHaveValue('-status:')

        await page.keyboard.press('ArrowDown')
        await memex.filter.expectTextForSelectedSuggestedItem(/Backlog/)
        await page.keyboard.press('Enter')
        await page.waitForTimeout(500)
        await memex.filter.expectToBeFocused()
        await memex.filter.expectToHaveValue('-status:Backlog')
        await page.waitForTimeout(500)
        const resultsCountElement = await page.waitForSelector(_('filter-results-count'), {timeout: EXTENDED_TIMEOUT})
        await page.waitForTimeout(500)
        expect(await resultsCountElement.textContent()).toBe('5')
        const rowsOnPageAfterFilter = page.locator(testCase.itemSelector)
        await expect(rowsOnPageAfterFilter).toHaveCount(5)
      })

      test(`shows suggestions for text matching existing filters`, async ({page, memex}) => {
        await memex.filter.toggleFilter()
        await page.waitForTimeout(1000)

        await waitForSuggestions(page, 'labe', {withSelection: false})
        await page.waitForTimeout(1000)
        await page.keyboard.press('ArrowDown')
        await memex.filter.expectTextForSelectedSuggestedItem('Label')
        await page.keyboard.press('Enter')

        await memex.filter.expectToHaveValue('label:')
        await page.keyboard.insertText('"tech debt"')
        await page.waitForTimeout(1000)
        await memex.filter.expectToBeFocused()
        await memex.filter.expectToHaveValue('label:"tech debt"')
        await page.waitForTimeout(1000)
        const resultsCountElement = await page.waitForSelector(_('filter-results-count'), {timeout: EXTENDED_TIMEOUT})
        await page.waitForTimeout(1000)
        expect(await resultsCountElement.textContent()).toBe('1')
        const rowsOnPageAfterFilter = page.locator(testCase.itemSelector)
        await expect(rowsOnPageAfterFilter).toHaveCount(1)
      })

      test(`shows suggestions for text matching existing filters with emojis`, async ({page, memex}) => {
        await memex.filter.toggleFilter()
        await page.waitForTimeout(500)

        await waitForSuggestions(page, 'labe', {withSelection: false})
        await page.keyboard.press('ArrowDown')
        await memex.filter.expectTextForSelectedSuggestedItem('Label')

        await page.keyboard.press('Enter')
        await page.waitForTimeout(500)

        await page.keyboard.insertText('"enhancement ✨"')
        await page.waitForTimeout(500)
        await memex.filter.expectToBeFocused()
        await memex.filter.expectToHaveValue('label:"enhancement ✨"')

        await page.waitForTimeout(500)
        const resultsCountElement = await page.waitForSelector(_('filter-results-count'), {timeout: EXTENDED_TIMEOUT})
        await page.waitForTimeout(500)
        expect(await resultsCountElement.textContent()).toBe('3')
        const rowsOnPageAfterFilter = page.locator(testCase.itemSelector)
        await expect(rowsOnPageAfterFilter).toHaveCount(3)
      })

      test(`shows up the suggestion again after cleaning up the text`, async ({page, memex}) => {
        await memex.filter.toggleFilter()
        await page.waitForTimeout(1000)

        await waitForSuggestions(page, 'stat', {withSelection: false})
        await page.keyboard.press('ArrowDown')
        await page.waitForTimeout(1000)
        await memex.filter.expectTextForSelectedSuggestedItem('Status')
        await page.keyboard.press('Enter')

        await page.waitForTimeout(1000)
        await page.keyboard.insertText('Done')
        await memex.filter.expectToBeFocused()
        await page.waitForTimeout(1000)
        await memex.filter.expectToHaveValue('status:Done')
        await page.keyboard.press('Enter')
        await page.waitForTimeout(2000)
        let resultsCountElement = await mustFind(page, _('filter-results-count'))
        await page.waitForTimeout(1000)
        expect(await resultsCountElement.textContent()).toBe('3')
        let rowsOnPageAfterFilter = page.locator(testCase.itemSelector)
        await expect(rowsOnPageAfterFilter).toHaveCount(3)

        for (let i = 0; i < 4; i++) {
          await page.keyboard.press('Backspace')
        }

        await page.waitForTimeout(1000)
        await page.keyboard.insertText('Backlog')
        await memex.filter.expectToBeFocused()
        await memex.filter.expectToHaveValue('status:Backlog')
        await page.waitForTimeout(1000)
        await page.waitForSelector(_('search-suggestions-box'), {state: 'detached'})
        await page.keyboard.press('Enter')
        await page.waitForTimeout(1000)

        resultsCountElement = await mustFind(page, _('filter-results-count'))
        await page.waitForTimeout(1000)
        expect(await resultsCountElement.textContent()).toBe('2')
        rowsOnPageAfterFilter = page.locator(testCase.itemSelector)
        await expect(rowsOnPageAfterFilter).toHaveCount(2)
      })

      test(`allows multiple filters`, async ({page, memex}) => {
        await memex.filter.toggleFilter()
        await page.waitForTimeout(500)

        await waitForSuggestions(page, 'labe', {withSelection: false})
        await page.keyboard.press('ArrowDown')
        await memex.filter.expectTextForSelectedSuggestedItem('Label')
        await page.keyboard.press('Enter')

        await page.waitForTimeout(500)
        await page.keyboard.insertText('"tech debt"')
        await memex.filter.expectToBeFocused()
        await memex.filter.expectToHaveValue('label:"tech debt"')
        await page.keyboard.press('Enter')

        await page.waitForTimeout(500)
        let resultsCountElement = await mustFind(page, _('filter-results-count'))
        await page.waitForTimeout(500)
        expect(await resultsCountElement.textContent()).toBe('1')
        const rowsOnPageAfterFilter = page.locator(testCase.itemSelector)
        await expect(rowsOnPageAfterFilter).toHaveCount(1)

        // Extra whitespace char needed for this test to execute in Safari browser.
        // Otherwise Safari's smart substitution replaces `" ` with a `“`.
        await page.keyboard.insertText('  ')
        await page.waitForTimeout(500)

        await page.keyboard.insertText('stat')
        await page.waitForTimeout(500)
        await page.keyboard.insertText('us')
        await page.keyboard.press('ArrowDown')
        await memex.filter.expectTextForSelectedSuggestedItem('Status')
        await memex.filter.expectToBeFocused()
        await memex.filter.expectToHaveValue('label:"tech debt"  status')

        await page.waitForTimeout(500)
        await memex.filter.expectTextForSelectedSuggestedItem('Status')
        await page.keyboard.press('Enter')
        await page.waitForTimeout(500)
        await page.keyboard.insertText('Don')

        await page.waitForTimeout(500)
        await page.keyboard.press('ArrowDown')
        await memex.filter.expectTextForSelectedSuggestedItem(/Done/)
        await page.keyboard.press('Enter')

        await page.waitForTimeout(1000)
        resultsCountElement = await mustFind(page, _('filter-results-count'))
        await page.waitForTimeout(500)
        expect(await resultsCountElement.textContent()).toBe('1')
        await expect(rowsOnPageAfterFilter).toHaveCount(1)
      })

      test(`allows filter with text column value that contains an emoji`, async ({page, memex}) => {
        await memex.filter.toggleFilter()

        await waitForSuggestions(page, 'custom', {withSelection: false})
        await page.keyboard.press('ArrowDown')
        await memex.filter.expectTextForSelectedSuggestedItem('Custom Text')
        await page.keyboard.press('Enter') // select "custom text" from the dropdown

        await page.waitForTimeout(1000)
        await memex.filter.expectToHaveSuggestions([
          'No custom text',
          'Has custom text',
          'Exclude custom-text',
          'custom text starts with...',
          'custom text ends with...',
          'custom text contains...',
        ])

        await page.waitForTimeout(1000)
        // Enter a search prefix prefix
        await page.keyboard.insertText('🎉*') //
        await page.waitForTimeout(1000)
        const resultsCountElement = await page.waitForSelector(_('filter-results-count'), {
          timeout: EXTENDED_TIMEOUT,
        })
        await page.waitForTimeout(1000)
        await eventually(async () => {
          expect(await resultsCountElement.textContent()).toEqual('1')
        })
        const rowsOnPageAfterFilter = page.locator(testCase.itemSelector)
        await expect(rowsOnPageAfterFilter).toHaveCount(1)
      })

      test(`same filter can be applied multiple times`, async ({page, memex}) => {
        await memex.filter.toggleFilter()

        await waitForSuggestions(page, 'labe', {withSelection: false})
        await page.keyboard.press('ArrowDown')
        await memex.filter.expectTextForSelectedSuggestedItem('Label')
        await page.keyboard.press('Enter')

        await page.waitForTimeout(1000)
        await page.keyboard.insertText('blocker')
        await memex.filter.expectToBeFocused()
        await memex.filter.expectToHaveValue('label:blocker')
        await page.waitForTimeout(1000)

        await page.keyboard.insertText(' ')
        await page.waitForTimeout(1000)

        await waitForSuggestions(page, 'labe')
        await page.waitForTimeout(1000)
        await memex.filter.expectToBeFocused()
        await memex.filter.expectToHaveValue('label:blocker label:')

        await waitForSuggestions(page, 'enhanc')

        await page.waitForTimeout(1000)
        await memex.filter.expectToHaveValue('label:blocker label:"enhancement ✨"')
      })

      test(`shows suggestions for negative filters`, async ({page, memex}) => {
        await memex.filter.toggleFilter()

        await waitForSuggestions(page, '-label:', {withSelection: false})
        await page.waitForTimeout(1000)

        // tech-debt is the second option in the suggestions list
        await page.keyboard.press('ArrowDown')
        await page.keyboard.press('ArrowDown')
        await page.waitForTimeout(1000)
        await page.keyboard.press('Enter')

        await page.waitForTimeout(1000)
        await memex.filter.expectToBeFocused()
        await memex.filter.expectToHaveValue('-label:"tech debt"')
        await page.waitForTimeout(1000)

        const resultsCountElement = await page.waitForSelector(_('filter-results-count'), {timeout: EXTENDED_TIMEOUT})
        await page.waitForTimeout(1000)
        expect(await resultsCountElement.textContent()).toEqual('6')
        const rowsOnPageAfterFilter = page.locator(testCase.itemSelector)
        await expect(rowsOnPageAfterFilter).toHaveCount(6)
      })
    })
  }

  for (const testCase of testCases) {
    test.describe(`in ${testCase.view}`, () => {
      test.beforeEach(async ({memex}) => {
        await memex.navigateToStory('integrationTestsWithItems', {
          viewType: testCase.view,
          filterQuery: `label:"tech debt" assignee:lerebear`,
          serverFeatures: {memex_table_without_limits: true},
        })
      })

      test(`Search suggestions are parsed correctly from the URL search params`, async ({page, memex}) => {
        await memex.filter.INPUT.click({position: {x: 10, y: 10}})

        await memex.filter.expectToBeFocused()
        await memex.filter.expectToHaveValue('label:"tech debt" assignee:lerebear')
        await page.keyboard.press('End')
        await page.keyboard.down('Meta')
        await page.keyboard.down('ArrowRight')
        await page.keyboard.up('Meta')
        await page.keyboard.type(' ')
        await page.waitForTimeout(500)

        // Suggestions are render by default in PWL after a space
        await expect(page.locator('[aria-label=Suggestions]')).toBeVisible()

        await page.keyboard.type('stat')
        await page.waitForTimeout(1000)

        // status should be suggested as it is not in the search input
        await page.keyboard.press('ArrowDown')
        await memex.filter.expectTextForSelectedSuggestedItem('Status')
      })
    })
  }

  for (const testCase of testCases) {
    test.describe(`in ${testCase.view}`, () => {
      test.beforeEach(async ({memex}) => {
        await memex.navigateToStory('integrationTestsWithItems', {
          viewType: testCase.view,
          filterQuery: 'status:',
          serverFeatures: {memex_table_without_limits: true},
        })
      })

      test('Search suggestions after a double quote', async ({page, memex}) => {
        await memex.filter.toggleFilter()
        await memex.filter.expectToBeFocused()
        await page.keyboard.press('End')
        await page.keyboard.insertText('"')
        await page.waitForTimeout(500)
        await memex.filter.expectToHaveSuggestions(['Exclude status', 'Backlog', 'In Progress', 'Ready', 'Done'])

        await page.keyboard.press('ArrowDown')
        await page.keyboard.press('ArrowDown')
        await page.keyboard.press('Enter')
        await page.waitForTimeout(500)

        await memex.filter.expectToBeFocused()
        await memex.filter.expectToHaveValue('status:Backlog')

        await page.waitForTimeout(500)
        const resultsCountElement = await page.waitForSelector(_('filter-results-count'), {
          timeout: EXTENDED_TIMEOUT,
        })
        await page.waitForTimeout(500)
        expect(await resultsCountElement.textContent()).toEqual('2')
      })

      test('Search suggestions with colon', async ({page, memex}) => {
        await memex.filter.toggleFilter()
        await memex.filter.expectToBeFocused()
        await page.keyboard.press('End')
        await page.keyboard.insertText('"in:review",')

        await memex.filter.expectToHaveSuggestions(['Exclude status', 'Backlog', 'In Progress', 'Ready', 'Done'])

        await page.keyboard.press('ArrowDown')
        await page.keyboard.press('ArrowDown')
        await page.keyboard.press('Enter')
        await page.waitForTimeout(500)

        await memex.filter.expectToBeFocused()
        await memex.filter.expectToHaveValue('status:"in:review",Backlog')

        await page.waitForTimeout(500)
        const resultsCountElement = await page.waitForSelector(_('filter-results-count'), {
          timeout: EXTENDED_TIMEOUT,
        })
        await page.waitForTimeout(500)
        expect(await resultsCountElement.textContent()).toEqual('2')
      })
    })
  }
})

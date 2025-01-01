import {expect} from '@playwright/test'

import {test} from '../../fixtures/test-extended'
import {dragTo} from '../../helpers/dom/interactions'
import {_} from '../../helpers/dom/selectors'
import {PWL_SKIP_REASON} from '../../helpers/pwl-spec-migration'

const memex_table_without_limits = true

test.describe('Change board field from view context menu', () => {
  test('user can change vertical group field', async ({page, memex}) => {
    await memex.navigateToStory('integrationTestsWithCustomItems', {
      viewType: 'board',
      serverFeatures: {memex_small_viewport_a11y: true, memex_touch_to_drag: true, memex_table_without_limits},
    })

    await memex.boardView.getColumn('No Status').expectCardCount(3)

    await memex.viewOptionsMenu.open()
    await expect(memex.viewOptionsMenu.VIEW_OPTIONS_MENU_COLUMN_BY).toContainText('Status')

    // Switch the board field to Aardvarks
    await memex.viewOptionsMenu.VIEW_OPTIONS_MENU_COLUMN_BY.click()
    await page.waitForSelector(_('group-by-menu'))
    const groupByAardvarks = await page.waitForSelector(_('group-by-Aardvarks'))
    await groupByAardvarks.click()

    // Ensure values from the new field are visible on the board
    await memex.boardView.getColumn('No Aardvarks').expectVisible()
    await memex.boardView.getColumn('Aric').expectVisible()
  })

  test('Empty default group will be hidden from user after last card removed', async ({page, memex}) => {
    test.skip(true, PWL_SKIP_REASON)
    await memex.navigateToStory('integrationTestsWithCustomItems', {
      viewType: 'board',
      verticalGroupedBy: {columnId: 19}, // Start with the board column field set to custom single select `Aardvarks` field
      serverFeatures: {memex_small_viewport_a11y: true, memex_touch_to_drag: true, memex_table_without_limits},
    })

    const firstCard = memex.boardView.getCard('No Aardvarks', 0).cardLocator

    const dropBox = await memex.boardView.getColumn('Brendan').COLUMN_DROP_ZONE.boundingBox()
    await dragTo(page, firstCard, {x: dropBox.x + dropBox.width / 2, y: dropBox.y})

    await memex.boardView.getColumn('No Aardvarks').expectHidden()

    await memex.viewOptionsMenu.open()
    await expect(memex.viewOptionsMenu.VIEW_OPTIONS_MENU_COLUMN_BY).toContainText('Aardvarks')

    // Switch the board field to status
    await memex.viewOptionsMenu.VIEW_OPTIONS_MENU_COLUMN_BY.click()
    await page.waitForSelector(_('group-by-menu'))
    const groupByStatus = await page.waitForSelector(_('group-by-Status'))
    await groupByStatus.click()

    // The no-status column should now appear
    await memex.boardView.getColumn('No Status').expectVisible()
  })
})

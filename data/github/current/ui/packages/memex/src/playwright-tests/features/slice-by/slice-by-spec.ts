import {expect} from '@playwright/test'

import {
  SliceByApplied,
  SliceItemDeselected,
  SliceItemSelected,
  SlicerDeselect,
  SlicerHideEmpty,
  SlicerPanelUI,
  SlicerShowEmpty,
  ViewOptionsMenuUI,
} from '../../../client/api/stats/contracts'
import {
  SLICER_PANEL_DEFAULT_WIDTH,
  SLICER_PANEL_MAX_WIDTH,
  SLICER_PANEL_MIN_WIDTH,
} from '../../../client/components/slicer-panel/constants'
import {assigneesColumn, issueTypeColumn, stageColumn, StageColumnId} from '../../../mocks/data/columns'
import {test} from '../../fixtures/test-extended'
import {todayString} from '../../helpers/dates'
import {dragTo} from '../../helpers/dom/interactions'
import {expectSliceByColumnIdUrlParam, expectSliceValueUrlParam} from '../../helpers/table/assertions'
import {addDraftItem} from '../../helpers/table/interactions'
import {getRowCountInTable} from '../../helpers/table/selectors'
import {eventually} from '../../helpers/utils'
import type {ViewType} from '../../types/view-type'

const views: Array<ViewType> = ['table', 'roadmap', 'board']
const memex_table_without_limits = true

const EXTENDED_TIMEOUT = 35_000

for (const viewType of views) {
  test.describe(`${viewType} slice by`, () => {
    // Common Tests
    test('Renders a list of slicer items for single select columns', async ({memex}) => {
      await memex.navigateToStory('integrationTestsWithItems', {
        viewType,
        serverFeatures: {memex_table_without_limits},
      })

      await memex.viewOptionsMenu.open()
      await memex.viewOptionsMenu.VIEW_OPTIONS_MENU_SLICE_BY.click()
      await memex.viewOptionsMenu.SLICE_BY_MENU.getByTestId('slice-Stage').click()

      await memex.slicerPanel.expectTitle('Stage')
      await memex.slicerPanel.expectListItemCount(3)
      await memex.slicerPanel.expectListItemToContainText(0, 'Up Next')
      await memex.slicerPanel.expectListItemToHaveCount(0, 1)

      // Expect some relevant stats to have been sent
      await memex.stats.expectStatsToContain({
        name: SliceByApplied,
        memexProjectColumnId: StageColumnId,
        memexProjectViewNumber: 1,
        context: JSON.stringify({layout: viewType}),
        ui: ViewOptionsMenuUI,
      })
    })

    test('Toggles empty slicer items for single select columns', async ({memex}) => {
      await memex.navigateToStory('integrationTestsWithItems', {
        viewType,
        serverFeatures: {memex_table_without_limits},
      })

      await memex.viewOptionsMenu.open()
      await memex.viewOptionsMenu.VIEW_OPTIONS_MENU_SLICE_BY.click()
      await memex.viewOptionsMenu.SLICE_BY_MENU.getByTestId('slice-Stage').click()
      await memex.viewOptionsMenu.close()

      await memex.slicerPanel.expectTitle('Stage')

      const lastItem = memex.slicerPanel.LIST_ITEMS.last()
      await expect(lastItem).toContainText('No Stage')

      // this view contains redacted items which are no longer rendered in PWL
      await memex.slicerPanel.expectListItemCount(3)
      await expect(lastItem.getByTestId('slicer-item-count')).toContainText('5')

      await memex.slicerPanel.TOGGLE_EMPTY_ITEMS_BUTTON.click()
      await memex.slicerPanel.expectListItemCount(5)
      await expect(memex.slicerPanel.TOGGLE_EMPTY_ITEMS_BUTTON).toHaveText('Hide empty values')
      await expect(lastItem.getByTestId('slicer-item-count')).toContainText('0')

      await memex.slicerPanel.TOGGLE_EMPTY_ITEMS_BUTTON.click()
      await memex.slicerPanel.expectListItemCount(3)
      await expect(memex.slicerPanel.TOGGLE_EMPTY_ITEMS_BUTTON).toHaveText('Show empty values')

      // Expect some relevant stats to have been sent
      await memex.stats.expectStatsToContain({
        name: SlicerHideEmpty,
        memexProjectColumnId: StageColumnId,
        memexProjectViewNumber: 1,
        context: JSON.stringify({layout: viewType}),
        ui: SlicerPanelUI,
      })
      await memex.stats.expectStatsToContain({
        name: SlicerShowEmpty,
        memexProjectColumnId: StageColumnId,
        memexProjectViewNumber: 1,
        context: JSON.stringify({layout: viewType}),
        ui: SlicerPanelUI,
      })
    })

    test('Renders a list of slicer items for iteration columns', async ({memex}) => {
      await memex.navigateToStory('appWithIterationsField', {
        viewType,
        serverFeatures: {memex_table_without_limits},
      })

      await memex.viewOptionsMenu.open()
      await memex.viewOptionsMenu.VIEW_OPTIONS_MENU_SLICE_BY.click()
      await memex.viewOptionsMenu.SLICE_BY_MENU.getByTestId('slice-Iteration').click()

      await memex.slicerPanel.expectTitle('Iteration')
      await memex.slicerPanel.expectListItemCount(4)
      await memex.slicerPanel.expectListItemToContainText(0, 'Iteration 4')
      await memex.slicerPanel.expectListItemToHaveCount(0, 3)

      // Completed
      await expect(memex.slicerPanel.SLICER_PANEL.getByTestId('completed-iteration-header')).toBeVisible()
      await memex.slicerPanel.expectListItemToContainText(3, 'Iteration 0')
      await memex.slicerPanel.expectListItemToHaveCount(3, 1)
    })

    test('Toggles empty slicer items for iteration columns', async ({memex}) => {
      await memex.navigateToStory('appWithIterationsField', {
        viewType,
        serverFeatures: {memex_table_without_limits},
      })

      await memex.viewOptionsMenu.open()
      await memex.viewOptionsMenu.VIEW_OPTIONS_MENU_SLICE_BY.click()
      await memex.viewOptionsMenu.SLICE_BY_MENU.getByTestId('slice-Iteration').click()
      await memex.viewOptionsMenu.close()

      await memex.slicerPanel.expectTitle('Iteration')

      await memex.slicerPanel.expectListItemCount(4)
      await memex.slicerPanel.expectListItemToContainText(3, 'Iteration 0')
      await memex.slicerPanel.expectListItemToHaveCount(3, 1)

      await memex.slicerPanel.TOGGLE_EMPTY_ITEMS_BUTTON.click()
      await memex.slicerPanel.expectListItemCount(8)
      await expect(memex.slicerPanel.TOGGLE_EMPTY_ITEMS_BUTTON).toHaveText('Hide empty values')

      await memex.slicerPanel.expectListItemToContainText(4, 'Iteration 3')
      await memex.slicerPanel.expectListItemToHaveCount(4, 0)

      await memex.slicerPanel.TOGGLE_EMPTY_ITEMS_BUTTON.click()
      await memex.slicerPanel.expectListItemCount(4)
      await expect(memex.slicerPanel.TOGGLE_EMPTY_ITEMS_BUTTON).toHaveText('Show empty values')
    })

    test('Renders a list of slicer items for label columns', async ({memex}) => {
      await memex.navigateToStory('integrationTestsWithItems', {
        viewType,
        serverFeatures: {memex_table_without_limits},
      })

      await memex.viewOptionsMenu.open()
      await memex.viewOptionsMenu.VIEW_OPTIONS_MENU_SLICE_BY.click()
      await memex.viewOptionsMenu.SLICE_BY_MENU.getByTestId('slice-Labels').click()

      await memex.slicerPanel.expectTitle('Labels')
      await memex.slicerPanel.expectListItemCount(3)
      await memex.slicerPanel.expectListItemToContainText(0, 'enhancement ✨')
      await memex.slicerPanel.expectListItemToHaveCount(0, 3)
    })

    test('Toggles empty slicer items for labels columns', async ({memex}) => {
      await memex.navigateToStory('integrationTestsWithItems', {
        viewType,
        serverFeatures: {memex_table_without_limits},
      })

      await memex.viewOptionsMenu.open()
      await memex.viewOptionsMenu.VIEW_OPTIONS_MENU_SLICE_BY.click()
      await memex.viewOptionsMenu.SLICE_BY_MENU.getByTestId('slice-Labels').click()
      await memex.viewOptionsMenu.close()

      await memex.slicerPanel.expectTitle('Labels')

      const lastItem = memex.slicerPanel.LIST_ITEMS.last()
      await expect(lastItem).toContainText('No Labels')

      // For Item counts we need to take into account that PWL excludes redacted items
      // `integrationTestsWithItems includes` redacted items as part of the mock
      await memex.slicerPanel.expectListItemCount(3)
      await expect(memex.slicerPanel.TOGGLE_EMPTY_ITEMS_BUTTON).toBeHidden()
      await expect(lastItem.getByTestId('slicer-item-count')).toContainText('4')

      await memex.filter.INPUT.fill('lere')

      await eventually(() => memex.slicerPanel.expectListItemCount(1))
      await expect(memex.slicerPanel.TOGGLE_EMPTY_ITEMS_BUTTON).toHaveText('Show empty values')
      await expect(lastItem).not.toContainText('No Labels')

      await memex.slicerPanel.TOGGLE_EMPTY_ITEMS_BUTTON.click()
      await memex.slicerPanel.expectListItemCount(2)
      await expect(memex.slicerPanel.TOGGLE_EMPTY_ITEMS_BUTTON).toHaveText('Hide empty values')
      await expect(lastItem.getByTestId('slicer-item-count')).toContainText('0')

      await memex.slicerPanel.TOGGLE_EMPTY_ITEMS_BUTTON.click()
      await memex.slicerPanel.expectListItemCount(1)
      await expect(memex.slicerPanel.TOGGLE_EMPTY_ITEMS_BUTTON).toHaveText('Show empty values')
    })

    test('Renders a list of slicer items for milestone columns', async ({memex}) => {
      await memex.navigateToStory('integrationTestsWithItems', {
        viewType,
        serverFeatures: {memex_table_without_limits},
      })

      await memex.viewOptionsMenu.open()
      await memex.viewOptionsMenu.VIEW_OPTIONS_MENU_SLICE_BY.click()
      await memex.viewOptionsMenu.SLICE_BY_MENU.getByTestId('slice-Milestone').click()

      await memex.slicerPanel.expectTitle('Milestone')
      await memex.slicerPanel.expectListItemCount(3)
      await memex.slicerPanel.expectListItemToContainText(0, 'Sprint 9')
      await memex.slicerPanel.expectListItemToHaveCount(0, 1)
    })

    test('Toggles empty slicer items for milestone columns', async ({memex}) => {
      await memex.navigateToStory('integrationTestsWithItems', {
        viewType,
        serverFeatures: {memex_table_without_limits},
      })

      await memex.viewOptionsMenu.open()
      await memex.viewOptionsMenu.VIEW_OPTIONS_MENU_SLICE_BY.click()
      await memex.viewOptionsMenu.SLICE_BY_MENU.getByTestId('slice-Milestone').click()
      await memex.viewOptionsMenu.close()

      await memex.slicerPanel.expectTitle('Milestone')

      const lastItem = memex.slicerPanel.LIST_ITEMS.last()
      await expect(lastItem).toContainText('No Milestone')

      await memex.slicerPanel.expectListItemCount(3)
      await expect(memex.slicerPanel.TOGGLE_EMPTY_ITEMS_BUTTON).toBeHidden()
      await expect(lastItem.getByTestId('slicer-item-count')).toContainText('3')

      await memex.filter.INPUT.fill('lere')

      await eventually(() => memex.slicerPanel.expectListItemCount(1))
      await expect(memex.slicerPanel.TOGGLE_EMPTY_ITEMS_BUTTON).toHaveText('Show empty values')
      await expect(lastItem).not.toContainText('No Milestone')

      await memex.slicerPanel.TOGGLE_EMPTY_ITEMS_BUTTON.click()
      await memex.slicerPanel.expectListItemCount(2)
      await expect(memex.slicerPanel.TOGGLE_EMPTY_ITEMS_BUTTON).toHaveText('Hide empty values')
      await expect(lastItem.getByTestId('slicer-item-count')).toContainText('0')

      await memex.slicerPanel.TOGGLE_EMPTY_ITEMS_BUTTON.click()
      await memex.slicerPanel.expectListItemCount(1)
      await expect(memex.slicerPanel.TOGGLE_EMPTY_ITEMS_BUTTON).toHaveText('Show empty values')
    })

    test('Renders a list of slicer items for parent issue columns', async ({memex}) => {
      await memex.navigateToStory('integrationTestsWithSubIssues', {
        viewType,
        serverFeatures: {memex_table_without_limits},
      })

      await memex.viewOptionsMenu.open()
      await memex.viewOptionsMenu.VIEW_OPTIONS_MENU_SLICE_BY.click()
      await memex.viewOptionsMenu.SLICE_BY_MENU.getByTestId('slice-Parent issue').click()

      await memex.slicerPanel.expectTitle('Parent issue')
      await memex.slicerPanel.expectListItemCount(4)
      await memex.slicerPanel.expectListItemToContainText(0, 'Parent One')
    })

    test('Toggles empty slicer items for parent issue columns', async ({memex}) => {
      await memex.navigateToStory('integrationTestsWithSubIssues', {
        viewType,
        serverFeatures: {memex_table_without_limits},
      })

      await memex.viewOptionsMenu.open()
      await memex.viewOptionsMenu.VIEW_OPTIONS_MENU_SLICE_BY.click()
      await memex.viewOptionsMenu.SLICE_BY_MENU.getByTestId('slice-Parent issue').click()
      await memex.viewOptionsMenu.close()

      await memex.slicerPanel.expectTitle('Parent issue')

      const lastItem = memex.slicerPanel.LIST_ITEMS.last()
      await expect(lastItem).toContainText('No Parent issue')

      await memex.slicerPanel.expectListItemCount(4)
      await expect(memex.slicerPanel.TOGGLE_EMPTY_ITEMS_BUTTON).toBeHidden()
      await expect(lastItem.getByTestId('slicer-item-count')).toContainText('26')

      await memex.filter.INPUT.fill('focused')

      await eventually(() => memex.slicerPanel.expectListItemCount(1))
      await expect(memex.slicerPanel.TOGGLE_EMPTY_ITEMS_BUTTON).toHaveText('Show empty values')
      await expect(lastItem).not.toContainText('No Parent issue')

      await memex.slicerPanel.TOGGLE_EMPTY_ITEMS_BUTTON.click()
      await memex.slicerPanel.expectListItemCount(2)
      await expect(memex.slicerPanel.TOGGLE_EMPTY_ITEMS_BUTTON).toHaveText('Hide empty values')
      await expect(lastItem.getByTestId('slicer-item-count')).toContainText('0')

      await memex.slicerPanel.TOGGLE_EMPTY_ITEMS_BUTTON.click()
      await memex.slicerPanel.expectListItemCount(1)
      await expect(memex.slicerPanel.TOGGLE_EMPTY_ITEMS_BUTTON).toHaveText('Show empty values')
    })

    test('Opens parent issue in side panel with click', async ({memex}) => {
      await memex.navigateToStory('integrationTestsWithSubIssues', {
        viewType,
        serverFeatures: {memex_table_without_limits},
      })

      await memex.viewOptionsMenu.open()
      await memex.viewOptionsMenu.VIEW_OPTIONS_MENU_SLICE_BY.click()
      await memex.viewOptionsMenu.SLICE_BY_MENU.getByTestId('slice-Parent issue').click()
      await memex.viewOptionsMenu.close()

      await memex.slicerPanel.SLICER_PANEL.getByText('Parent One').click()
      await expect(memex.sidePanel.NEW_ISSUE_VIEWER_DEVELOPMENT_WARNING).toBeVisible()
    })

    test('Renders a list of slicer items for issue type columns', async ({memex}) => {
      await memex.navigateToStory('integrationTestsWithItems', {
        viewType,
        serverFeatures: {memex_table_without_limits},
      })

      await memex.viewOptionsMenu.open()
      await memex.viewOptionsMenu.VIEW_OPTIONS_MENU_SLICE_BY.click()
      await memex.viewOptionsMenu.SLICE_BY_MENU.getByTestId('slice-Type').click()

      await memex.slicerPanel.expectTitle('Type')
      await memex.slicerPanel.expectListItemCount(3)
      await memex.slicerPanel.expectListItemToContainText(0, 'Batch')
      await memex.slicerPanel.expectListItemToHaveCount(0, 1)
    })

    test('Toggles empty slicer items for issue type columns', async ({memex}) => {
      await memex.navigateToStory('integrationTestsWithItems', {
        viewType,
        serverFeatures: {memex_table_without_limits},
      })

      await memex.viewOptionsMenu.open()
      await memex.viewOptionsMenu.VIEW_OPTIONS_MENU_SLICE_BY.click()
      await memex.viewOptionsMenu.SLICE_BY_MENU.getByTestId('slice-Type').click()
      await memex.viewOptionsMenu.close()

      await memex.slicerPanel.expectTitle('Type')

      const lastItem = memex.slicerPanel.LIST_ITEMS.last()
      await expect(lastItem).toContainText('No Type')

      // this view contains redacted items which are no longer rendered in PWL
      await memex.slicerPanel.expectListItemCount(3)
      await expect(memex.slicerPanel.TOGGLE_EMPTY_ITEMS_BUTTON).toBeHidden()
      await expect(lastItem.getByTestId('slicer-item-count')).toContainText('5')

      await memex.filter.INPUT.fill('lere')

      await eventually(() => memex.slicerPanel.expectListItemCount(1))
      await expect(memex.slicerPanel.TOGGLE_EMPTY_ITEMS_BUTTON).toHaveText('Show empty values')
      await expect(lastItem).not.toContainText('No Type')

      await memex.slicerPanel.TOGGLE_EMPTY_ITEMS_BUTTON.click()
      await memex.slicerPanel.expectListItemCount(2)
      await expect(memex.slicerPanel.TOGGLE_EMPTY_ITEMS_BUTTON).toHaveText('Hide empty values')
      await expect(lastItem.getByTestId('slicer-item-count')).toContainText('0')

      await memex.slicerPanel.TOGGLE_EMPTY_ITEMS_BUTTON.click()
      await memex.slicerPanel.expectListItemCount(1)
      await expect(memex.slicerPanel.TOGGLE_EMPTY_ITEMS_BUTTON).toHaveText('Show empty values')
    })

    test('Renders a list of slicer items for repository columns', async ({memex}) => {
      test.setTimeout(EXTENDED_TIMEOUT)
      await memex.navigateToStory('reactTableWithItems', {
        viewType,
        serverFeatures: {memex_table_without_limits},
      })

      await memex.viewOptionsMenu.open()
      await memex.viewOptionsMenu.VIEW_OPTIONS_MENU_SLICE_BY.click()
      await expect(memex.viewOptionsMenu.SLICE_BY_MENU).toBeVisible()
      await memex.viewOptionsMenu.SLICE_BY_MENU.getByTestId('slice-Repository').click()

      await memex.slicerPanel.expectTitle('Repository')
      await memex.slicerPanel.expectListItemCount(4)
      await memex.slicerPanel.expectListItemToContainText(0, 'github/github')
      await memex.slicerPanel.expectListItemToHaveCount(0, 4)
    })

    test('Toggles empty slicer items for repository columns', async ({memex}) => {
      test.skip(
        true,
        'PWL: slow test takes over 30,000ms to run and is tracked under https://github.com/github/projects-platform/issues/3103',
      )
      await memex.navigateToStory('reactTableWithItems', {
        viewType,
        serverFeatures: {memex_table_without_limits},
      })

      await memex.viewOptionsMenu.open()
      await memex.viewOptionsMenu.VIEW_OPTIONS_MENU_SLICE_BY.click()
      await expect(memex.viewOptionsMenu.SLICE_BY_MENU).toBeVisible()
      await memex.viewOptionsMenu.SLICE_BY_MENU.getByTestId('slice-Repository').click()
      await memex.viewOptionsMenu.close()

      await eventually(() => memex.slicerPanel.expectTitle('Repository'))

      const lastItem = memex.slicerPanel.LIST_ITEMS.last()
      await expect(lastItem).toContainText('No Repository')

      await memex.slicerPanel.expectListItemCount(4)
      await expect(memex.slicerPanel.TOGGLE_EMPTY_ITEMS_BUTTON).toBeHidden()
      await eventually(() => expect(lastItem.getByTestId('slicer-item-count')).toContainText('1'))

      await memex.filter.INPUT.fill('lere')
      await expect(memex.slicerPanel.TOGGLE_EMPTY_ITEMS_BUTTON).toHaveText('Show empty values')
      await expect(lastItem).not.toContainText('No Repository')

      await memex.slicerPanel.TOGGLE_EMPTY_ITEMS_BUTTON.click()
      await memex.slicerPanel.expectListItemCount(3)
      await expect(memex.slicerPanel.TOGGLE_EMPTY_ITEMS_BUTTON).toHaveText('Hide empty values')
      await expect(lastItem.getByTestId('slicer-item-count')).toContainText('0')

      await memex.slicerPanel.TOGGLE_EMPTY_ITEMS_BUTTON.click()
      await memex.slicerPanel.expectListItemCount(2)
      await expect(memex.slicerPanel.TOGGLE_EMPTY_ITEMS_BUTTON).toHaveText('Show empty values')
    })

    test('Renders a list of slicer items for text columns', async ({memex}) => {
      await memex.navigateToStory('integrationTestsWithItems', {
        viewType,
        serverFeatures: {memex_table_without_limits},
      })

      await memex.viewOptionsMenu.open()
      await memex.viewOptionsMenu.VIEW_OPTIONS_MENU_SLICE_BY.click()
      await memex.viewOptionsMenu.SLICE_BY_MENU.getByTestId('slice-Team').click()

      await memex.slicerPanel.expectTitle('Team')
      await memex.slicerPanel.expectListItemCount(3)
      await memex.slicerPanel.expectListItemToContainText(0, 'Design Systems')
      await memex.slicerPanel.expectListItemToHaveCount(0, 1)
    })

    test('Toggles empty slicer items for text columns', async ({memex}) => {
      await memex.navigateToStory('integrationTestsWithItems', {
        viewType,
        serverFeatures: {memex_table_without_limits},
      })

      await memex.viewOptionsMenu.open()
      await memex.viewOptionsMenu.VIEW_OPTIONS_MENU_SLICE_BY.click()
      await memex.viewOptionsMenu.SLICE_BY_MENU.getByTestId('slice-Team').click()
      await memex.viewOptionsMenu.close()

      await memex.slicerPanel.expectTitle('Team')

      const lastItem = memex.slicerPanel.LIST_ITEMS.last()
      await expect(lastItem).toContainText('No Team')

      await memex.slicerPanel.expectListItemCount(3)
      await expect(memex.slicerPanel.TOGGLE_EMPTY_ITEMS_BUTTON).toBeHidden()
      await expect(lastItem.getByTestId('slicer-item-count')).toContainText('4')

      await memex.filter.INPUT.fill('lere')

      await eventually(() => memex.slicerPanel.expectListItemCount(1))
      await expect(memex.slicerPanel.TOGGLE_EMPTY_ITEMS_BUTTON).toHaveText('Show empty values')
      await expect(lastItem).not.toContainText('No Team')

      await memex.slicerPanel.TOGGLE_EMPTY_ITEMS_BUTTON.click()
      await memex.slicerPanel.expectListItemCount(2)
      await expect(memex.slicerPanel.TOGGLE_EMPTY_ITEMS_BUTTON).toHaveText('Hide empty values')
      await expect(lastItem.getByTestId('slicer-item-count')).toContainText('0')

      await memex.slicerPanel.TOGGLE_EMPTY_ITEMS_BUTTON.click()
      await memex.slicerPanel.expectListItemCount(1)
      await expect(memex.slicerPanel.TOGGLE_EMPTY_ITEMS_BUTTON).toHaveText('Show empty values')
    })

    test('Renders a list of slicer items for number columns', async ({memex}) => {
      await memex.navigateToStory('integrationTestsWithItems', {
        viewType,
        serverFeatures: {memex_table_without_limits},
      })

      await memex.viewOptionsMenu.open()
      await memex.viewOptionsMenu.VIEW_OPTIONS_MENU_SLICE_BY.click()
      await memex.viewOptionsMenu.SLICE_BY_MENU.getByTestId('slice-Estimate').click()

      await memex.slicerPanel.expectTitle('Estimate')
      await memex.slicerPanel.expectListItemCount(4)
      await memex.slicerPanel.expectListItemToContainText(0, '1')
      await memex.slicerPanel.expectListItemToHaveCount(0, 1)
    })

    test('Toggles empty slicer items for number columns', async ({memex}) => {
      await memex.navigateToStory('integrationTestsWithItems', {
        viewType,
        serverFeatures: {memex_table_without_limits},
      })

      await memex.viewOptionsMenu.open()
      await memex.viewOptionsMenu.VIEW_OPTIONS_MENU_SLICE_BY.click()
      await memex.viewOptionsMenu.SLICE_BY_MENU.getByTestId('slice-Estimate').click()
      await memex.viewOptionsMenu.close()

      await memex.slicerPanel.expectTitle('Estimate')

      const lastItem = memex.slicerPanel.LIST_ITEMS.last()
      await expect(lastItem).toContainText('No Estimate')

      await memex.slicerPanel.expectListItemCount(4)
      await expect(memex.slicerPanel.TOGGLE_EMPTY_ITEMS_BUTTON).toBeHidden()
      await expect(lastItem.getByTestId('slicer-item-count')).toContainText('3')

      await memex.filter.INPUT.fill('lere')

      await eventually(() => memex.slicerPanel.expectListItemCount(1))
      await expect(memex.slicerPanel.TOGGLE_EMPTY_ITEMS_BUTTON).toHaveText('Show empty values')
      await expect(lastItem).not.toContainText('No Estimate')

      await memex.slicerPanel.TOGGLE_EMPTY_ITEMS_BUTTON.click()
      await memex.slicerPanel.expectListItemCount(2)
      await expect(memex.slicerPanel.TOGGLE_EMPTY_ITEMS_BUTTON).toHaveText('Hide empty values')
      await expect(lastItem.getByTestId('slicer-item-count')).toContainText('0')

      await memex.slicerPanel.TOGGLE_EMPTY_ITEMS_BUTTON.click()
      await memex.slicerPanel.expectListItemCount(1)
      await expect(memex.slicerPanel.TOGGLE_EMPTY_ITEMS_BUTTON).toHaveText('Show empty values')
    })

    test('Renders a list of slicer items for date columns', async ({memex}) => {
      test.skip(
        true,
        'PWL: slicer-items throws an exception when the date value is null ' +
          'in getSlicerItem this test has been skipped under https://github.com/github/projects-platform/issues/3103',
      )
      await memex.navigateToStory('integrationTestsWithItems', {
        viewType,
        serverFeatures: {memex_table_without_limits},
      })

      await memex.viewOptionsMenu.open()
      await memex.viewOptionsMenu.VIEW_OPTIONS_MENU_SLICE_BY.click()
      await memex.viewOptionsMenu.SLICE_BY_MENU.getByTestId('slice-Due Date').click()

      await memex.slicerPanel.expectTitle('Due Date')
      await memex.slicerPanel.expectListItemCount(3)
      await memex.slicerPanel.expectListItemToContainText(0, 'Today')
      await memex.slicerPanel.expectListItemToHaveCount(0, 2)
    })

    test('Toggles empty slicer items for date columns', async ({memex}) => {
      test.skip(
        true,
        'PWL: slicer-items throws an exception when the date value is null ' +
          'in getSlicerItem this test has been skipped under https://github.com/github/projects-platform/issues/3103',
      )
      await memex.navigateToStory('integrationTestsWithItems', {
        viewType,
        serverFeatures: {memex_table_without_limits},
      })

      await memex.viewOptionsMenu.open()
      await memex.viewOptionsMenu.VIEW_OPTIONS_MENU_SLICE_BY.click()
      await memex.viewOptionsMenu.SLICE_BY_MENU.getByTestId('slice-Due Date').click()
      await memex.viewOptionsMenu.close()

      await memex.slicerPanel.expectTitle('Due Date')

      const lastItem = memex.slicerPanel.LIST_ITEMS.last()
      await expect(lastItem).toContainText('No Due Date')

      await memex.slicerPanel.expectListItemCount(3)
      await expect(memex.slicerPanel.TOGGLE_EMPTY_ITEMS_BUTTON).toBeHidden()
      await expect(lastItem.getByTestId('slicer-item-count')).toContainText('5')

      await memex.filter.INPUT.fill('lere')

      await eventually(() => memex.slicerPanel.expectListItemCount(1))
      await expect(memex.slicerPanel.TOGGLE_EMPTY_ITEMS_BUTTON).toHaveText('Show empty values')
      await expect(lastItem).not.toContainText('No Due Date')

      await memex.slicerPanel.TOGGLE_EMPTY_ITEMS_BUTTON.click()
      await memex.slicerPanel.expectListItemCount(2)
      await expect(memex.slicerPanel.TOGGLE_EMPTY_ITEMS_BUTTON).toHaveText('Hide empty values')
      await expect(lastItem.getByTestId('slicer-item-count')).toContainText('0')

      await memex.slicerPanel.TOGGLE_EMPTY_ITEMS_BUTTON.click()
      await memex.slicerPanel.expectListItemCount(1)
      await expect(memex.slicerPanel.TOGGLE_EMPTY_ITEMS_BUTTON).toHaveText('Show empty values')
    })

    test('Renders a list of slicer items for assignee columns', async ({memex}) => {
      await memex.navigateToStory('integrationTestsWithItems', {
        viewType,
        serverFeatures: {memex_table_without_limits},
      })

      await memex.viewOptionsMenu.open()
      await memex.viewOptionsMenu.VIEW_OPTIONS_MENU_SLICE_BY.click()
      await memex.viewOptionsMenu.SLICE_BY_MENU.getByTestId('slice-Assignees').click()

      await memex.slicerPanel.expectTitle('Assignees')
      // Assignees can vary, but we can rely on count for "No Assignees"
      const noAssigneesIndex = (await memex.slicerPanel.LIST_ITEMS.count()) - 1
      await memex.slicerPanel.expectListItemToContainText(noAssigneesIndex, 'No Assignees')
      await memex.slicerPanel.expectListItemToHaveCount(noAssigneesIndex, 3)
    })

    test('Toggles empty slicer items for assignee columns', async ({memex}) => {
      await memex.navigateToStory('integrationTestsWithItems', {
        viewType,
        serverFeatures: {memex_table_without_limits},
      })

      await memex.viewOptionsMenu.open()
      await memex.viewOptionsMenu.VIEW_OPTIONS_MENU_SLICE_BY.click()
      await memex.viewOptionsMenu.SLICE_BY_MENU.getByTestId('slice-Assignees').click()
      await memex.viewOptionsMenu.close()

      await memex.slicerPanel.expectTitle('Assignees')

      const lastItem = memex.slicerPanel.LIST_ITEMS.last()
      await expect(lastItem).toContainText('No Assignees')

      await memex.slicerPanel.expectListItemCount(6)
      await expect(memex.slicerPanel.TOGGLE_EMPTY_ITEMS_BUTTON).toBeHidden()
      await expect(lastItem.getByTestId('slicer-item-count')).toContainText('3')

      await memex.filter.INPUT.fill('status:Done')

      await eventually(() => memex.slicerPanel.expectListItemCount(4))
      await expect(memex.slicerPanel.TOGGLE_EMPTY_ITEMS_BUTTON).toHaveText('Show empty values')
      await expect(lastItem).not.toContainText('No Assignees')

      await memex.slicerPanel.TOGGLE_EMPTY_ITEMS_BUTTON.click()
      await memex.slicerPanel.expectListItemCount(5)
      await expect(memex.slicerPanel.TOGGLE_EMPTY_ITEMS_BUTTON).toHaveText('Hide empty values')
      await expect(lastItem.getByTestId('slicer-item-count')).toContainText('0')

      await memex.slicerPanel.TOGGLE_EMPTY_ITEMS_BUTTON.click()
      await memex.slicerPanel.expectListItemCount(4)
      await expect(memex.slicerPanel.TOGGLE_EMPTY_ITEMS_BUTTON).toHaveText('Show empty values')
    })

    test('Updates the slice field from slicer panel menu', async ({memex}) => {
      test.setTimeout(EXTENDED_TIMEOUT)
      await memex.navigateToStory('integrationTestsWithItems', {
        viewType,
        sliceBy: {columnId: issueTypeColumn.name},
        serverFeatures: {memex_table_without_limits},
      })

      await memex.slicerPanel.SLICER_PANEL_TITLE.click()
      await memex.viewOptionsMenu.SLICE_BY_MENU.getByTestId('slice-Stage').click()

      await memex.slicerPanel.expectTitle('Stage')
      await memex.slicerPanel.expectListItemCount(3)
      await memex.slicerPanel.expectListItemToContainText(0, 'Up Next')
      await memex.slicerPanel.expectListItemToHaveCount(0, 1)
    })

    test('Does not include filtered out items', async ({memex}) => {
      await memex.navigateToStory('integrationTestsWithItems', {
        viewType,
        serverFeatures: {memex_table_without_limits},
      })

      await memex.viewOptionsMenu.open()
      await memex.viewOptionsMenu.VIEW_OPTIONS_MENU_SLICE_BY.click()
      await memex.viewOptionsMenu.SLICE_BY_MENU.getByTestId('slice-Stage').click()
      await memex.viewOptionsMenu.close()

      await memex.slicerPanel.expectListItemCount(3)
      await memex.filter.filterBy('stage:"Closed"')
      await memex.slicerPanel.expectListItemCount(1)
      await memex.slicerPanel.expectListItemToContainText(0, 'Closed')
    })

    test('Updates the search params in the url on slice by selection', async ({page, memex}) => {
      await memex.navigateToStory('appWithIterationsField', {
        viewType,
        serverFeatures: {memex_table_without_limits},
      })

      await memex.viewOptionsMenu.open()
      await memex.viewOptionsMenu.VIEW_OPTIONS_MENU_SLICE_BY.click()
      await expect(memex.viewOptionsMenu.SLICE_BY_MENU).toBeVisible()
      await memex.viewOptionsMenu.SLICE_BY_MENU.getByTestId('slice-Iteration').click()
      await eventually(() => memex.slicerPanel.expectTitle('Iteration'))

      expectSliceByColumnIdUrlParam(page, '20')
    })

    test('Resets the search params in the url on slice by selection', async ({page, memex}) => {
      await memex.navigateToStory('appWithIterationsField', {
        viewType,
        serverFeatures: {memex_table_without_limits},
      })

      await memex.viewOptionsMenu.open()
      await memex.viewOptionsMenu.VIEW_OPTIONS_MENU_SLICE_BY.click()
      await memex.viewOptionsMenu.SLICE_BY_MENU.getByTestId('slice-Iteration').click()

      await memex.viewOptionsMenu.open()
      await memex.viewOptionsMenu.VIEW_OPTIONS_MENU_SLICE_BY.click()
      await memex.viewOptionsMenu.SLICE_BY_MENU.getByTestId('slice-none').click()

      expectSliceByColumnIdUrlParam(page, null)
    })

    test('Updates the search params in the url on slice value selection', async ({page, memex}) => {
      test.setTimeout(EXTENDED_TIMEOUT)
      await memex.navigateToStory('reactTableWithItems', {
        viewType,
        serverFeatures: {memex_table_without_limits},
      })

      await memex.viewOptionsMenu.open()
      await memex.viewOptionsMenu.VIEW_OPTIONS_MENU_SLICE_BY.click()
      await expect(memex.viewOptionsMenu.SLICE_BY_MENU).toBeVisible()
      await memex.viewOptionsMenu.SLICE_BY_MENU.getByTestId('slice-Stage').click()
      await memex.slicerPanel.expectTitle('Stage')
      await memex.slicerPanel.LIST_ITEMS.getByText('Up Next').click()

      await eventually(() => expectSliceValueUrlParam(page, 'Up Next'))
    })

    test('Resets the search params in the url on slice value deselection', async ({page, memex}) => {
      test.skip(
        true,
        'PWL: slow test takes over 30,000ms to run and is tracked under https://github.com/github/projects-platform/issues/3103',
      )
      await memex.navigateToStory('reactTableWithItems', {
        viewType,
        serverFeatures: {memex_table_without_limits},
      })

      await memex.viewOptionsMenu.open()
      await memex.viewOptionsMenu.VIEW_OPTIONS_MENU_SLICE_BY.click()
      await expect(memex.viewOptionsMenu.SLICE_BY_MENU).toBeVisible()
      await memex.viewOptionsMenu.SLICE_BY_MENU.getByTestId('slice-Stage').click()
      await eventually(() => memex.slicerPanel.expectTitle('Stage'))
      await memex.slicerPanel.SLICER_PANEL.getByText('Up Next').click()
      await memex.slicerPanel.SLICER_PANEL.getByText('Up Next').click()

      expectSliceValueUrlParam(page, null)
    })

    test('Maintains the selected slice value on save', async ({page, memex}) => {
      test.skip(
        true,
        'PWL: slow test takes over 30,000ms to run and is tracked under https://github.com/github/projects-platform/issues/3103',
      )
      await memex.navigateToStory('reactTableWithItems', {
        viewType,
        serverFeatures: {memex_table_without_limits},
      })

      await memex.viewOptionsMenu.open()
      await memex.viewOptionsMenu.VIEW_OPTIONS_MENU_SLICE_BY.click()
      await expect(memex.viewOptionsMenu.SLICE_BY_MENU).toBeVisible()
      await memex.viewOptionsMenu.SLICE_BY_MENU.getByTestId('slice-Stage').click()
      await eventually(() => memex.slicerPanel.expectTitle('Stage'))
      await memex.slicerPanel.SLICER_PANEL.getByText('Up Next').click()

      await memex.viewOptionsMenu.expectViewStateIsDirty()
      expectSliceByColumnIdUrlParam(page, StageColumnId.toString())
      expectSliceValueUrlParam(page, 'Up Next')

      // Save changes leaves the slice value in the URL (and state)
      await memex.viewOptionsMenu.saveChanges()
      await memex.viewOptionsMenu.expectViewStateNotDirty()
      expectSliceValueUrlParam(page, 'Up Next')
      // Fixes flake in CI due to asynchronous nature of URL update
      await page.waitForFunction(() => new URL(window.location.href).searchParams.get('sliceByColumnId') === null)
      expectSliceByColumnIdUrlParam(page, null)
    })

    test('Discards the selected slice value on discarding slice changes', async ({page, memex}) => {
      test.skip(
        true,
        'PWL: slow test takes over 30,000ms to run and is tracked under https://github.com/github/projects-platform/issues/3103',
      )
      await memex.navigateToStory('reactTableWithItems', {
        viewType,
        serverFeatures: {memex_table_without_limits},
      })

      await memex.viewOptionsMenu.open()
      await memex.viewOptionsMenu.VIEW_OPTIONS_MENU_SLICE_BY.click()
      await expect(memex.viewOptionsMenu.SLICE_BY_MENU).toBeVisible()
      await memex.viewOptionsMenu.SLICE_BY_MENU.getByTestId('slice-Stage').click()
      await eventually(() => memex.slicerPanel.expectTitle('Stage'))
      await memex.slicerPanel.SLICER_PANEL.getByText('Up Next').click()

      await memex.viewOptionsMenu.expectViewStateIsDirty()
      expectSliceByColumnIdUrlParam(page, StageColumnId.toString())
      expectSliceValueUrlParam(page, 'Up Next')

      // Discard slice-by changes removes the slice value in the URL (and state)
      await memex.viewOptionsMenu.discardChanges()
      await memex.viewOptionsMenu.expectViewStateNotDirty()
      expectSliceValueUrlParam(page, null)
      expectSliceByColumnIdUrlParam(page, null)
    })

    test('Maintains the selected slice value on discarding unrelated changes', async ({page, memex}) => {
      test.skip(
        true,
        'PWL: slow test takes over 30,000ms to run and is tracked under https://github.com/github/projects-platform/issues/3103',
      )
      await memex.navigateToStory('reactTableWithItems', {
        viewType,
        serverFeatures: {memex_table_without_limits},
      })

      await memex.viewOptionsMenu.open()
      await memex.viewOptionsMenu.VIEW_OPTIONS_MENU_SLICE_BY.click()
      await expect(memex.viewOptionsMenu.SLICE_BY_MENU).toBeVisible()
      await memex.viewOptionsMenu.SLICE_BY_MENU.getByTestId('slice-Stage').click()
      await eventually(() => memex.slicerPanel.expectTitle('Stage'))
      await memex.slicerPanel.SLICER_PANEL.getByText('Up Next').click()

      await memex.viewOptionsMenu.expectViewStateIsDirty()
      expectSliceByColumnIdUrlParam(page, StageColumnId.toString())
      expectSliceValueUrlParam(page, 'Up Next')

      // Save changes leaves the slice value in the URL (and state)
      await memex.viewOptionsMenu.saveChanges()
      await memex.viewOptionsMenu.expectViewStateNotDirty()
      expectSliceValueUrlParam(page, 'Up Next')

      await memex.filter.filterBy('xxx')
      await memex.viewOptionsMenu.expectViewStateIsDirty()

      // Discard unrelated changes leaves the slice value in the URL (and state)
      await memex.viewOptionsMenu.discardChanges()
      await memex.viewOptionsMenu.expectViewStateNotDirty()
      expectSliceValueUrlParam(page, 'Up Next')
    })

    test('Shows a Deselect button when a slice value is selected', async ({memex}) => {
      test.skip(
        viewType === 'table', // the table flavor of this spec is the only one experiencing issues
        'PWL: slow test takes over 30,000ms to run and is tracked under https://github.com/github/projects-platform/issues/3103',
      )
      await memex.navigateToStory('reactTableWithItems', {
        viewType,
        serverFeatures: {memex_table_without_limits},
      })

      await memex.viewOptionsMenu.open()
      await memex.viewOptionsMenu.VIEW_OPTIONS_MENU_SLICE_BY.click()
      await expect(memex.viewOptionsMenu.SLICE_BY_MENU).toBeVisible()
      await memex.viewOptionsMenu.SLICE_BY_MENU.getByTestId('slice-Stage').click()
      await eventually(() => memex.slicerPanel.expectTitle('Stage'))

      await memex.slicerPanel.LIST_ITEMS.getByText('Up Next').click()

      await expect(memex.slicerPanel.DESELECT).toBeVisible()
    })

    test('Does not show a Deselect button when a slice value is not selected', async ({page, memex}) => {
      test.skip(
        viewType === 'table', // the table flavor of this spec is the only one experiencing issues
        'PWL: Flaky test tracked under https://github.com/github/projects-platform/issues/3103',
      )
      await memex.navigateToStory('reactTableWithItems', {
        viewType,
        serverFeatures: {memex_table_without_limits},
      })

      await memex.viewOptionsMenu.open()
      await memex.viewOptionsMenu.VIEW_OPTIONS_MENU_SLICE_BY.click()
      await expect(memex.viewOptionsMenu.SLICE_BY_MENU).toBeVisible()
      await memex.viewOptionsMenu.SLICE_BY_MENU.getByTestId('slice-Stage').click()
      await expect(page.locator('[data-testid=slicer-panel] ul')).toBeVisible()

      await expect(memex.slicerPanel.DESELECT).toBeHidden()
    })

    test('Does not filter slicer items when an iteration slicer item is selected', async ({memex}) => {
      await memex.navigateToStory('appWithIterationsField', {
        viewType,
        serverFeatures: {memex_table_without_limits},
      })

      await memex.viewOptionsMenu.open()
      await memex.viewOptionsMenu.VIEW_OPTIONS_MENU_SLICE_BY.click()
      await expect(memex.viewOptionsMenu.SLICE_BY_MENU).toBeVisible()
      await memex.viewOptionsMenu.SLICE_BY_MENU.getByTestId('slice-Iteration').click()

      await memex.slicerPanel.expectListItemCount(4)
      await memex.slicerPanel.expectListItemToHaveCount(0, 3)
      await memex.slicerPanel.expectListItemToHaveCount(1, 1)
      await memex.slicerPanel.expectListItemToHaveCount(2, 3)
      await memex.slicerPanel.expectListItemToHaveCount(3, 1)

      await memex.slicerPanel.LIST_ITEMS.getByText('Iteration 4').click()

      await memex.slicerPanel.expectListItemCount(4)
      await memex.slicerPanel.expectListItemToHaveCount(0, 3)
      await memex.slicerPanel.expectListItemToHaveCount(1, 1)
      await memex.slicerPanel.expectListItemToHaveCount(3, 1)
    })

    test('Does not filter slicer items when a single select slicer item is selected', async ({memex}) => {
      await memex.navigateToStory('integrationTestsWithItems', {
        viewType,
        serverFeatures: {memex_table_without_limits},
      })

      await memex.viewOptionsMenu.open()
      await memex.viewOptionsMenu.VIEW_OPTIONS_MENU_SLICE_BY.click()
      await expect(memex.viewOptionsMenu.SLICE_BY_MENU).toBeVisible()
      await memex.viewOptionsMenu.SLICE_BY_MENU.getByTestId('slice-Stage').click()

      await memex.slicerPanel.expectListItemCount(3)
      await memex.slicerPanel.expectListItemToHaveCount(0, 1)
      await memex.slicerPanel.expectListItemToHaveCount(1, 1)
      await memex.slicerPanel.expectListItemToHaveCount(2, 5)

      await memex.slicerPanel.LIST_ITEMS.getByText('Up Next').click()

      await memex.slicerPanel.expectListItemCount(3)
      await memex.slicerPanel.expectListItemToHaveCount(0, 1)
      await memex.slicerPanel.expectListItemToHaveCount(1, 1)
    })

    test('slicer panel is resizable', async ({memex, page}) => {
      await memex.navigateToStory('reactTableWithItems', {
        viewType,
        sliceBy: {columnId: assigneesColumn.name},
        serverFeatures: {memex_table_without_limits},
      })

      const sash = memex.slicerPanel.RESIZER_SASH

      const coords = await sash.boundingBox()
      await dragTo(page, sash, {x: coords.x + 100}, {}, true)

      const newWidth = SLICER_PANEL_DEFAULT_WIDTH + 100
      await expect(memex.slicerPanel.SLICER_PANEL).toHaveCSS('width', `${newWidth}px`)
    })

    test('slicer panel is not resizable past max width', async ({memex, page}) => {
      await memex.navigateToStory('reactTableWithItems', {
        viewType,
        sliceBy: {columnId: assigneesColumn.name},
        serverFeatures: {memex_table_without_limits},
      })

      const sash = memex.slicerPanel.RESIZER_SASH

      const coords = await sash.boundingBox()
      await dragTo(page, sash, {x: coords.x + 1000}, {}, true)

      const box = await memex.slicerPanel.SLICER_PANEL.boundingBox()
      expect(box.width).toBe(SLICER_PANEL_MAX_WIDTH)
    })

    test('slicer panel is not resizable past min width', async ({memex, page}) => {
      await memex.navigateToStory('reactTableWithItems', {
        viewType,
        sliceBy: {columnId: assigneesColumn.name},
        serverFeatures: {memex_table_without_limits},
      })

      const sash = memex.slicerPanel.RESIZER_SASH
      await dragTo(page, sash, {x: 10}, {}, true)

      const box = await memex.slicerPanel.SLICER_PANEL.boundingBox()
      expect(box.width).toBe(SLICER_PANEL_MIN_WIDTH)
    })

    test('slicer panel width can be reset', async ({memex, page}) => {
      test.skip(
        true,
        'PWL: slow test takes over 30,000ms to run and is tracked under https://github.com/github/projects-platform/issues/3103',
      )
      await memex.navigateToStory('reactTableWithItems', {
        viewType,
        sliceBy: {columnId: stageColumn.name},
        serverFeatures: {memex_table_without_limits},
      })

      const sash = memex.slicerPanel.RESIZER_SASH
      const coords = await sash.boundingBox()
      const newWidth = SLICER_PANEL_DEFAULT_WIDTH + 100

      await dragTo(page, sash, {x: coords.x + 100}, {}, true)
      await expect(memex.slicerPanel.SLICER_PANEL).toHaveCSS('width', `${newWidth}px`)

      await sash.dblclick()
      await expect(memex.slicerPanel.SLICER_PANEL).toHaveCSS('width', `${SLICER_PANEL_DEFAULT_WIDTH}px`)
    })

    test('slicer panel width can be changed with keyboard', async ({memex, page}) => {
      test.skip(
        true,
        'PWL: slow test takes over 30,000ms to run and is tracked under https://github.com/github/projects-platform/issues/3103',
      )
      await memex.navigateToStory('reactTableWithItems', {
        viewType,
        sliceBy: {columnId: stageColumn.name},
        serverFeatures: {memex_table_without_limits},
      })

      const sash = page.getByTestId('slicer-panel-resizer-sash-drag-activator')
      const newWidth = SLICER_PANEL_DEFAULT_WIDTH + 50

      await sash.focus()
      await page.keyboard.press('Space')
      await page.keyboard.press('ArrowRight')
      await page.keyboard.press('ArrowRight')
      await page.keyboard.press('Space')

      // test with up/down arrowkeys as well
      await sash.focus()
      await page.keyboard.press('Space')
      await page.keyboard.press('ArrowUp')
      await page.keyboard.press('ArrowUp')
      await page.keyboard.press('ArrowDown')
      await page.keyboard.press('Space')

      await expect(memex.slicerPanel.SLICER_PANEL).toHaveCSS('width', `${newWidth + 25}px`)
    })

    test('slicer panel resizing does not affect other views', async ({memex, page}) => {
      test.skip(
        true,
        'PWL: slow test takes over 30,000ms to run and is tracked under https://github.com/github/projects-platform/issues/3103',
      )
      await memex.navigateToStory('integrationTestsWithItems', {
        viewType,
        sliceBy: {columnId: stageColumn.name},
        serverFeatures: {memex_table_without_limits},
      })

      // Create a new view
      await memex.views.createNewView()
      await memex.viewOptionsMenu.open()
      await memex.viewOptionsMenu.VIEW_OPTIONS_MENU_SLICE_BY.click()
      await memex.viewOptionsMenu.SLICE_BY_MENU.getByTestId('slice-Stage').click()
      await memex.viewOptionsMenu.close()

      const sash = memex.slicerPanel.RESIZER_SASH
      const coords = await sash.boundingBox()
      const newWidth = SLICER_PANEL_DEFAULT_WIDTH + 100

      await dragTo(page, sash, {x: coords.x + 100}, {}, true)
      await expect(memex.slicerPanel.SLICER_PANEL).toHaveCSS('width', `${newWidth}px`)

      // Go back to original view
      await memex.views.VIEW_TABS.first().click()

      await expect(memex.slicerPanel.SLICER_PANEL).toHaveCSS('width', `${SLICER_PANEL_DEFAULT_WIDTH}px`)
    })

    // Board Tests
    if (viewType === 'board') {
      test('Filters board view when a single select slicer item is toggled', async ({memex}) => {
        test.skip(
          true, // Is this something we can do with react-testing-library? verying counts seems unecessary for playwright
          'PWL: Flaky spec tracked under https://github.com/github/projects-platform/issues/3103',
        )
        await memex.navigateToStory('integrationTestsWithItems', {
          viewType,
          serverFeatures: {memex_table_without_limits},
        })

        await memex.viewOptionsMenu.open()
        await memex.viewOptionsMenu.VIEW_OPTIONS_MENU_SLICE_BY.click()
        await memex.viewOptionsMenu.SLICE_BY_MENU.getByTestId('slice-Stage').click()
        await memex.slicerPanel.expectTitle('Stage')

        await Promise.all([
          memex.boardView.getColumn('No Status').expectCardCount(3),
          memex.boardView.getColumn('Backlog').expectCardCount(2),
          memex.boardView.getColumn('In Progress').expectCardCount(0),
          memex.boardView.getColumn('Ready').expectCardCount(0),
          memex.boardView.getColumn('Done').expectCardCount(2),
        ])

        // First click selects to toggle the filter on
        await memex.slicerPanel.LIST_ITEMS.getByText('Up Next').click()

        await Promise.all([
          memex.boardView.getColumn('No Status').expectCardCount(0),
          memex.boardView.getColumn('Backlog').expectCardCount(1),
          memex.boardView.getColumn('In Progress').expectCardCount(0),
          memex.boardView.getColumn('Ready').expectCardCount(0),
          memex.boardView.getColumn('Done').expectCardCount(0),
        ])

        // Second click deselects to toggle the filter off
        await memex.slicerPanel.LIST_ITEMS.getByText('Up Next').click()

        await Promise.all([
          memex.boardView.getColumn('No Status').expectCardCount(3),
          memex.boardView.getColumn('Backlog').expectCardCount(2),
          memex.boardView.getColumn('In Progress').expectCardCount(0),
          memex.boardView.getColumn('Ready').expectCardCount(0),
          memex.boardView.getColumn('Done').expectCardCount(3),

          // Expect some relevant stats to have been sent
          await memex.stats.expectStatsToContain({
            name: SliceItemSelected,
            memexProjectColumnId: StageColumnId,
            memexProjectViewNumber: 1,
            context: JSON.stringify({layout: viewType}),
            ui: SlicerPanelUI,
          }),
          await memex.stats.expectStatsToContain({
            name: SliceItemDeselected,
            memexProjectColumnId: StageColumnId,
            memexProjectViewNumber: 1,
            context: JSON.stringify({layout: viewType}),
            ui: SlicerPanelUI,
          }),
        ])
      })

      test('Filters board view when an iteration slicer item is toggled', async ({memex}) => {
        test.skip(
          true, // Is this something we can do with react-testing-library? verying counts seems unecessary for playwright
          'PWL: Flaky spec tracked under https://github.com/github/projects-platform/issues/3103',
        )
        await memex.navigateToStory('appWithIterationsField', {
          viewType,
          serverFeatures: {memex_table_without_limits},
        })

        await memex.viewOptionsMenu.open()
        await memex.viewOptionsMenu.VIEW_OPTIONS_MENU_SLICE_BY.click()
        await memex.viewOptionsMenu.SLICE_BY_MENU.getByTestId('slice-Iteration').click()
        await memex.slicerPanel.expectTitle('Iteration')

        await Promise.all([
          memex.boardView.getColumn('No Status').expectCardCount(3),
          memex.boardView.getColumn('Backlog').expectCardCount(2),
          memex.boardView.getColumn('In Progress').expectCardCount(0),
          memex.boardView.getColumn('Ready').expectCardCount(0),
          memex.boardView.getColumn('Done').expectCardCount(3),
        ])

        // First click selects to toggle the filter on
        await memex.slicerPanel.LIST_ITEMS.getByText('Iteration 4').click()

        await Promise.all([
          memex.boardView.getColumn('No Status').expectCardCount(3),
          memex.boardView.getColumn('Backlog').expectCardCount(0),
          memex.boardView.getColumn('In Progress').expectCardCount(0),
          memex.boardView.getColumn('Ready').expectCardCount(0),
          memex.boardView.getColumn('Done').expectCardCount(1),
        ])

        // Second click deselects to toggle the filter off
        await memex.slicerPanel.LIST_ITEMS.getByText('Iteration 4').click()

        await Promise.all([
          memex.boardView.getColumn('No Status').expectCardCount(3),
          memex.boardView.getColumn('Backlog').expectCardCount(2),
          memex.boardView.getColumn('In Progress').expectCardCount(0),
          memex.boardView.getColumn('Ready').expectCardCount(0),
          memex.boardView.getColumn('Done').expectCardCount(3),
        ])
      })

      test('Filters board view when an assignee slicer item is toggled', async ({memex}) => {
        test.skip(
          true, // Is this something we can do with react-testing-library? verying counts seems unecessary for playwright
          'PWL: Flaky spec tracked under https://github.com/github/projects-platform/issues/3103',
        )
        await memex.navigateToStory('integrationTestsWithItems', {
          viewType,
          serverFeatures: {memex_table_without_limits},
        })

        await memex.viewOptionsMenu.open()
        await memex.viewOptionsMenu.VIEW_OPTIONS_MENU_SLICE_BY.click()
        await memex.viewOptionsMenu.SLICE_BY_MENU.getByTestId('slice-Assignees').click()
        await memex.slicerPanel.expectTitle('Assignees')

        await Promise.all([
          memex.boardView.getColumn('No Status').expectCardCount(3),
          memex.boardView.getColumn('Backlog').expectCardCount(2),
          memex.boardView.getColumn('In Progress').expectCardCount(0),
          memex.boardView.getColumn('Ready').expectCardCount(0),
          memex.boardView.getColumn('Done').expectCardCount(3),
        ])

        // First click selects to toggle the filter on
        await memex.slicerPanel.LIST_ITEMS.getByText('No Assignees').click()

        await Promise.all([
          memex.boardView.getColumn('No Status').expectCardCount(3),
          memex.boardView.getColumn('Backlog').expectCardCount(1),
          memex.boardView.getColumn('In Progress').expectCardCount(0),
          memex.boardView.getColumn('Ready').expectCardCount(0),
          memex.boardView.getColumn('Done').expectCardCount(0),
        ])

        // Second click deselects to toggle the filter off
        await memex.slicerPanel.LIST_ITEMS.getByText('No Assignees').click()

        await Promise.all([
          memex.boardView.getColumn('No Status').expectCardCount(3),
          memex.boardView.getColumn('Backlog').expectCardCount(2),
          memex.boardView.getColumn('In Progress').expectCardCount(0),
          memex.boardView.getColumn('Ready').expectCardCount(0),
          memex.boardView.getColumn('Done').expectCardCount(3),
        ])
      })

      test('Filters board view when an label slicer item is toggled', async ({memex}) => {
        test.skip(
          true, // Is this something we can do with react-testing-library? verying counts seems unecessary for playwright
          'PWL: Flaky spec tracked under https://github.com/github/projects-platform/issues/3103',
        )
        await memex.navigateToStory('integrationTestsWithItems', {
          viewType,
          serverFeatures: {memex_table_without_limits},
        })

        await memex.viewOptionsMenu.open()
        await memex.viewOptionsMenu.VIEW_OPTIONS_MENU_SLICE_BY.click()
        await memex.viewOptionsMenu.SLICE_BY_MENU.getByTestId('slice-Labels').click()
        await memex.slicerPanel.expectTitle('Labels')

        await Promise.all([
          memex.boardView.getColumn('No Status').expectCardCount(3),
          memex.boardView.getColumn('Backlog').expectCardCount(2),
          memex.boardView.getColumn('In Progress').expectCardCount(0),
          memex.boardView.getColumn('Ready').expectCardCount(0),
          memex.boardView.getColumn('Done').expectCardCount(3),
        ])

        // First click selects to toggle the filter on
        await memex.slicerPanel.LIST_ITEMS.getByText('tech debt').click()

        await Promise.all([
          memex.boardView.getColumn('Backlog').expectCardCount(0),
          memex.boardView.getColumn('In Progress').expectCardCount(0),
          memex.boardView.getColumn('Ready').expectCardCount(0),
          memex.boardView.getColumn('Done').expectCardCount(1),
        ])

        // Second click deselects to toggle the filter off
        await memex.slicerPanel.LIST_ITEMS.getByText('tech debt').click()

        await Promise.all([
          memex.boardView.getColumn('No Status').expectCardCount(3),
          memex.boardView.getColumn('Backlog').expectCardCount(2),
          memex.boardView.getColumn('In Progress').expectCardCount(0),
          memex.boardView.getColumn('Ready').expectCardCount(0),
          memex.boardView.getColumn('Done').expectCardCount(3),
        ])
      })

      test('Filters board view when a milestone slicer item is toggled', async ({memex}) => {
        await memex.navigateToStory('integrationTestsWithItems', {
          viewType,
          serverFeatures: {memex_table_without_limits},
        })

        await memex.viewOptionsMenu.open()
        await memex.viewOptionsMenu.VIEW_OPTIONS_MENU_SLICE_BY.click()
        await memex.viewOptionsMenu.SLICE_BY_MENU.getByTestId('slice-Milestone').click()
        await memex.slicerPanel.expectTitle('Milestone')

        await Promise.all([
          memex.boardView.getColumn('No Status').expectCardCount(2),
          memex.boardView.getColumn('Backlog').expectCardCount(2),
          memex.boardView.getColumn('In Progress').expectCardCount(0),
          memex.boardView.getColumn('Ready').expectCardCount(0),
          memex.boardView.getColumn('Done').expectCardCount(3),
        ])

        // First click selects to toggle the filter on
        await memex.slicerPanel.LIST_ITEMS.getByText('v0.1 - Prioritized Lists?').click()

        await Promise.all([
          memex.boardView.getColumn('Backlog').expectCardCount(1),
          memex.boardView.getColumn('In Progress').expectCardCount(0),
          memex.boardView.getColumn('Ready').expectCardCount(0),
          memex.boardView.getColumn('Done').expectCardCount(2),
        ])

        // Second click deselects to toggle the filter off
        await memex.slicerPanel.LIST_ITEMS.getByText('v0.1 - Prioritized Lists?').click()

        await Promise.all([
          memex.boardView.getColumn('No Status').expectCardCount(2),
          memex.boardView.getColumn('Backlog').expectCardCount(2),
          memex.boardView.getColumn('In Progress').expectCardCount(0),
          memex.boardView.getColumn('Ready').expectCardCount(0),
          memex.boardView.getColumn('Done').expectCardCount(3),
        ])
      })

      test('Filters board view when an issue type slicer item is toggled', async ({memex}) => {
        await memex.navigateToStory('integrationTestsWithItems', {
          viewType,
          serverFeatures: {memex_table_without_limits},
        })

        await memex.viewOptionsMenu.open()
        await memex.viewOptionsMenu.VIEW_OPTIONS_MENU_SLICE_BY.click()
        await memex.viewOptionsMenu.SLICE_BY_MENU.getByTestId('slice-Type').click()
        await memex.slicerPanel.expectTitle('Type')

        await Promise.all([
          memex.boardView.getColumn('No Status').expectCardCount(2),
          memex.boardView.getColumn('Backlog').expectCardCount(2),
          memex.boardView.getColumn('In Progress').expectCardCount(0),
          memex.boardView.getColumn('Ready').expectCardCount(0),
          memex.boardView.getColumn('Done').expectCardCount(3),
        ])

        // First click selects to toggle the filter on
        await memex.slicerPanel.LIST_ITEMS.getByText('Batch').click()

        await Promise.all([
          memex.boardView.getColumn('Backlog').expectCardCount(0),
          memex.boardView.getColumn('In Progress').expectCardCount(0),
          memex.boardView.getColumn('Ready').expectCardCount(0),
          memex.boardView.getColumn('Done').expectCardCount(1),
        ])

        // Second click deselects to toggle the filter off
        await memex.slicerPanel.LIST_ITEMS.getByText('Batch').click()

        await Promise.all([
          memex.boardView.getColumn('No Status').expectCardCount(2),
          memex.boardView.getColumn('Backlog').expectCardCount(2),
          memex.boardView.getColumn('In Progress').expectCardCount(0),
          memex.boardView.getColumn('Ready').expectCardCount(0),
          memex.boardView.getColumn('Done').expectCardCount(3),
        ])
      })

      test('Filters board view when a repository slicer item is toggled', async ({memex}) => {
        await memex.navigateToStory('reactTableWithItems', {
          viewType,
          serverFeatures: {memex_table_without_limits},
        })

        await memex.viewOptionsMenu.open()
        await memex.viewOptionsMenu.VIEW_OPTIONS_MENU_SLICE_BY.click()
        await memex.viewOptionsMenu.SLICE_BY_MENU.getByTestId('slice-Repository').click()
        await memex.slicerPanel.expectTitle('Repository')

        await Promise.all([
          memex.boardView.getColumn('No Status').expectCardCount(2),
          memex.boardView.getColumn('Backlog').expectCardCount(11),
          memex.boardView.getColumn('In Progress').expectCardCount(4),
          memex.boardView.getColumn('Ready').expectCardCount(11),
          memex.boardView.getColumn('Done').expectCardCount(2),
        ])

        // First click selects to toggle the filter on
        await memex.slicerPanel.LIST_ITEMS.getByText('github/github').click()

        await Promise.all([
          memex.boardView.getColumn('Backlog').expectCardCount(1),
          memex.boardView.getColumn('In Progress').expectCardCount(1),
          memex.boardView.getColumn('Ready').expectCardCount(2),
          memex.boardView.getColumn('Done').expectCardCount(0),
        ])

        // Second click deselects to toggle the filter off
        await memex.slicerPanel.LIST_ITEMS.getByText('github/github').click()

        await Promise.all([
          memex.boardView.getColumn('No Status').expectCardCount(2),
          memex.boardView.getColumn('Backlog').expectCardCount(11),
          memex.boardView.getColumn('In Progress').expectCardCount(4),
          memex.boardView.getColumn('Ready').expectCardCount(11),
          memex.boardView.getColumn('Done').expectCardCount(2),
        ])
      })

      test('Filters board view when a text slicer item is toggled', async ({memex}) => {
        await memex.navigateToStory('integrationTestsWithItems', {
          viewType,
          serverFeatures: {memex_table_without_limits},
        })

        await memex.viewOptionsMenu.open()
        await memex.viewOptionsMenu.VIEW_OPTIONS_MENU_SLICE_BY.click()
        await memex.viewOptionsMenu.SLICE_BY_MENU.getByTestId('slice-Team').click()
        await memex.slicerPanel.expectTitle('Team')

        await Promise.all([
          memex.boardView.getColumn('No Status').expectCardCount(2),
          memex.boardView.getColumn('Backlog').expectCardCount(2),
          memex.boardView.getColumn('In Progress').expectCardCount(0),
          memex.boardView.getColumn('Ready').expectCardCount(0),
          memex.boardView.getColumn('Done').expectCardCount(3),
        ])

        // First click selects to toggle the filter on
        await memex.slicerPanel.LIST_ITEMS.getByText('Novelty Aardvarks').click()

        await Promise.all([
          memex.boardView.getColumn('Backlog').expectCardCount(1),
          memex.boardView.getColumn('In Progress').expectCardCount(0),
          memex.boardView.getColumn('Ready').expectCardCount(0),
          memex.boardView.getColumn('Done').expectCardCount(1),
        ])

        // Second click deselects to toggle the filter off
        await memex.slicerPanel.LIST_ITEMS.getByText('Novelty Aardvarks').click()

        await Promise.all([
          memex.boardView.getColumn('No Status').expectCardCount(2),
          memex.boardView.getColumn('Backlog').expectCardCount(2),
          memex.boardView.getColumn('In Progress').expectCardCount(0),
          memex.boardView.getColumn('Ready').expectCardCount(0),
          memex.boardView.getColumn('Done').expectCardCount(3),
        ])
      })

      test('Filters board view when a number slicer item is toggled', async ({memex}) => {
        await memex.navigateToStory('integrationTestsWithItems', {
          viewType,
          serverFeatures: {memex_table_without_limits},
        })

        await memex.viewOptionsMenu.open()
        await memex.viewOptionsMenu.VIEW_OPTIONS_MENU_SLICE_BY.click()
        await memex.viewOptionsMenu.SLICE_BY_MENU.getByTestId('slice-Estimate').click()
        await memex.slicerPanel.expectTitle('Estimate')

        await Promise.all([
          memex.boardView.getColumn('No Status').expectCardCount(2),
          memex.boardView.getColumn('Backlog').expectCardCount(2),
          memex.boardView.getColumn('In Progress').expectCardCount(0),
          memex.boardView.getColumn('Ready').expectCardCount(0),
          memex.boardView.getColumn('Done').expectCardCount(3),
        ])

        // First click selects to toggle the filter on
        await memex.slicerPanel.LIST_ITEMS.getByText('10').click()

        await Promise.all([
          memex.boardView.getColumn('Backlog').expectCardCount(0),
          memex.boardView.getColumn('In Progress').expectCardCount(0),
          memex.boardView.getColumn('Ready').expectCardCount(0),
          memex.boardView.getColumn('Done').expectCardCount(2),
        ])

        // Second click deselects to toggle the filter off
        await memex.slicerPanel.LIST_ITEMS.getByText('10').click()

        await Promise.all([
          memex.boardView.getColumn('No Status').expectCardCount(2),
          memex.boardView.getColumn('Backlog').expectCardCount(2),
          memex.boardView.getColumn('In Progress').expectCardCount(0),
          memex.boardView.getColumn('Ready').expectCardCount(0),
          memex.boardView.getColumn('Done').expectCardCount(3),
        ])
      })

      test('Filters board view when a date slicer item is toggled', async ({memex}) => {
        test.skip(
          true, // Is this something we can do with react-testing-library? verying counts seems unecessary for playwright
          'PWL: Flaky spec tracked under https://github.com/github/projects-platform/issues/3103',
        )
        await memex.navigateToStory('integrationTestsWithItems', {
          viewType,
          serverFeatures: {memex_table_without_limits},
        })

        await memex.viewOptionsMenu.open()
        await memex.viewOptionsMenu.VIEW_OPTIONS_MENU_SLICE_BY.click()
        await memex.viewOptionsMenu.SLICE_BY_MENU.getByTestId('slice-Due Date').click()
        await memex.slicerPanel.expectTitle('Due Date')

        await Promise.all([
          memex.boardView.getColumn('No Status').expectCardCount(2),
          memex.boardView.getColumn('Backlog').expectCardCount(2),
          memex.boardView.getColumn('In Progress').expectCardCount(0),
          memex.boardView.getColumn('Ready').expectCardCount(0),
          memex.boardView.getColumn('Done').expectCardCount(3),
        ])

        // First click selects to toggle the filter on
        await memex.slicerPanel.LIST_ITEMS.getByText(todayString).click()

        await Promise.all([
          memex.boardView.getColumn('Backlog').expectCardCount(0),
          memex.boardView.getColumn('In Progress').expectCardCount(0),
          memex.boardView.getColumn('Ready').expectCardCount(0),
          memex.boardView.getColumn('Done').expectCardCount(2),
        ])

        // Second click deselects to toggle the filter off
        await memex.slicerPanel.LIST_ITEMS.getByText(todayString).click()

        await Promise.all([
          memex.boardView.getColumn('No Status').expectCardCount(2),
          memex.boardView.getColumn('Backlog').expectCardCount(2),
          memex.boardView.getColumn('In Progress').expectCardCount(0),
          memex.boardView.getColumn('Ready').expectCardCount(0),
          memex.boardView.getColumn('Done').expectCardCount(3),
        ])
      })

      test('Filters board view from URL slice params with sliceValue = Closed', async ({memex}) => {
        await memex.navigateToStory('integrationTestsWithItems', {
          viewType,
          sliceBy: {columnId: StageColumnId},
          sliceValue: 'Closed',
          serverFeatures: {memex_table_without_limits},
        })

        await memex.boardView.getColumn('Done').expectCardCount(1)
      })

      test('Filters board view from URL with slice params and sliceValue=_noValue', async ({memex}) => {
        await memex.navigateToStory('integrationTestsWithItems', {
          viewType,
          sliceBy: {columnId: StageColumnId},
          sliceValue: '_noValue',
        })

        await Promise.all([
          memex.boardView.getColumn('No Status').expectCardCount(2),
          memex.boardView.getColumn('Backlog').expectCardCount(1),
          memex.boardView.getColumn('In Progress').expectCardCount(0),
          memex.boardView.getColumn('Ready').expectCardCount(0),
          memex.boardView.getColumn('Done').expectCardCount(2),
        ])
      })

      test('Deselect button clears current slice value', async ({memex}) => {
        await memex.navigateToStory('integrationTestsWithItems', {
          viewType,
          serverFeatures: {memex_table_without_limits},
        })

        await memex.viewOptionsMenu.open()
        await memex.viewOptionsMenu.VIEW_OPTIONS_MENU_SLICE_BY.click()
        await memex.viewOptionsMenu.SLICE_BY_MENU.getByTestId('slice-Stage').click()

        await Promise.all([
          memex.boardView.getColumn('No Status').expectCardCount(2),
          memex.boardView.getColumn('Backlog').expectCardCount(2),
          memex.boardView.getColumn('In Progress').expectCardCount(0),
          memex.boardView.getColumn('Ready').expectCardCount(0),
          memex.boardView.getColumn('Done').expectCardCount(3),
        ])

        await memex.slicerPanel.LIST_ITEMS.getByText('Up Next').click()

        await Promise.all([
          memex.boardView.getColumn('No Status').expectCardCount(0),
          memex.boardView.getColumn('Backlog').expectCardCount(1),
          memex.boardView.getColumn('In Progress').expectCardCount(0),
          memex.boardView.getColumn('Ready').expectCardCount(0),
          memex.boardView.getColumn('Done').expectCardCount(0),
        ])

        await memex.slicerPanel.DESELECT.click()

        await Promise.all([
          memex.boardView.getColumn('No Status').expectCardCount(2),
          memex.boardView.getColumn('Backlog').expectCardCount(2),
          memex.boardView.getColumn('In Progress').expectCardCount(0),
          memex.boardView.getColumn('Ready').expectCardCount(0),
          memex.boardView.getColumn('Done').expectCardCount(3),
        ])

        // Expect some relevant stats to have been sent
        await memex.stats.expectStatsToContain({
          name: SlicerDeselect,
          memexProjectColumnId: StageColumnId,
          memexProjectViewNumber: 1,
          context: JSON.stringify({layout: viewType}),
          ui: SlicerPanelUI,
        })
      })

      test('Applies slice value to newly added items', async ({memex, page}) => {
        await memex.navigateToStory('reactTableWithItems', {
          viewType,
          serverFeatures: {memex_table_without_limits},
        })

        await memex.viewOptionsMenu.open()
        await memex.viewOptionsMenu.VIEW_OPTIONS_MENU_SLICE_BY.click()
        await memex.viewOptionsMenu.SLICE_BY_MENU.getByTestId('slice-Stage').click()

        await memex.slicerPanel.LIST_ITEMS.getByText('Up Next').click()
        await memex.slicerPanel.expectListItemToHaveCount(1, 12)

        const column = memex.boardView.getColumn('Backlog')
        const cardsBeforeInsertionCount = await column.getCardCount()

        await column.clickAddItem()
        await addDraftItem(page, 'To Do')

        await page.keyboard.press('Enter')

        await memex.slicerPanel.expectListItemToHaveCount(1, 12)
        const cardsAfterInsertionCount = await column.getCardCount()
        expect(cardsAfterInsertionCount).toBe(cardsBeforeInsertionCount + 1)
      })
    } else {
      // Table / Roadmap Tests
      test('Filters table view when a single select slicer item is toggled', async ({memex, page}) => {
        await memex.navigateToStory('integrationTestsWithItems', {
          viewType,
          serverFeatures: {memex_table_without_limits},
        })

        await memex.viewOptionsMenu.open()
        await memex.viewOptionsMenu.VIEW_OPTIONS_MENU_SLICE_BY.click()
        await memex.viewOptionsMenu.SLICE_BY_MENU.getByTestId('slice-Stage').click()

        const beforeCount = await getRowCountInTable(page)

        // First click selects to toggle the filter on
        await memex.slicerPanel.LIST_ITEMS.getByText('Up Next').click()

        const afterCount = await getRowCountInTable(page)

        expect(beforeCount).toBe(7)
        expect(afterCount).toBe(1)

        // Second click deselects to toggle the filter off
        await memex.slicerPanel.LIST_ITEMS.getByText('Up Next').click()

        expect(await getRowCountInTable(page)).toEqual(beforeCount)

        // Expect some relevant stats to have been sent
        await memex.stats.expectStatsToContain({
          name: SliceItemSelected,
          memexProjectColumnId: StageColumnId,
          memexProjectViewNumber: 1,
          context: JSON.stringify({layout: viewType}),
          ui: SlicerPanelUI,
        })
        await memex.stats.expectStatsToContain({
          name: SliceItemDeselected,
          memexProjectColumnId: StageColumnId,
          memexProjectViewNumber: 1,
          context: JSON.stringify({layout: viewType}),
          ui: SlicerPanelUI,
        })
      })

      test('Filters table view when an assignee item is toggled', async ({memex, page}) => {
        await memex.navigateToStory('integrationTestsWithItems', {
          viewType,
          serverFeatures: {memex_table_without_limits},
        })

        await memex.viewOptionsMenu.open()
        await memex.viewOptionsMenu.VIEW_OPTIONS_MENU_SLICE_BY.click()
        await memex.viewOptionsMenu.SLICE_BY_MENU.getByTestId('slice-Assignees').click()

        const beforeCount = await getRowCountInTable(page)

        // First click selects to toggle the filter on
        await memex.slicerPanel.LIST_ITEMS.getByText('No Assignees').click()

        const afterCount = await getRowCountInTable(page)

        expect(beforeCount).toBe(7)
        expect(afterCount).toBe(3)

        // Second click deselects to toggle the filter off
        await memex.slicerPanel.LIST_ITEMS.getByText('No Assignees').click()

        expect(await getRowCountInTable(page)).toEqual(beforeCount)
      })

      test('Filters table view when an labels item is toggled', async ({memex, page}) => {
        await memex.navigateToStory('integrationTestsWithItems', {
          viewType,
          serverFeatures: {memex_table_without_limits},
        })

        await memex.viewOptionsMenu.open()
        await memex.viewOptionsMenu.VIEW_OPTIONS_MENU_SLICE_BY.click()
        await memex.viewOptionsMenu.SLICE_BY_MENU.getByTestId('slice-Labels').click()

        const beforeCount = await getRowCountInTable(page)

        // First click selects to toggle the filter on
        await memex.slicerPanel.LIST_ITEMS.getByText('tech debt').click()

        const afterCount = await getRowCountInTable(page)

        expect(beforeCount).toBe(7)
        expect(afterCount).toBe(1)

        // Second click deselects to toggle the filter off
        await memex.slicerPanel.LIST_ITEMS.getByText('tech debt').click()

        expect(await getRowCountInTable(page)).toEqual(beforeCount)
      })

      test('Filters table view when a milestone item is toggled', async ({memex, page}) => {
        await memex.navigateToStory('integrationTestsWithItems', {
          viewType,
          serverFeatures: {memex_table_without_limits},
        })

        await memex.viewOptionsMenu.open()
        await memex.viewOptionsMenu.VIEW_OPTIONS_MENU_SLICE_BY.click()
        await memex.viewOptionsMenu.SLICE_BY_MENU.getByTestId('slice-Milestone').click()

        const beforeCount = await getRowCountInTable(page)

        // First click selects to toggle the filter on
        await memex.slicerPanel.LIST_ITEMS.getByText('v0.1 - Prioritized Lists?').click()

        const afterCount = await getRowCountInTable(page)

        expect(beforeCount).toBe(7)
        expect(afterCount).toBe(3)

        // Second click deselects to toggle the filter off
        await memex.slicerPanel.LIST_ITEMS.getByText('v0.1 - Prioritized Lists?').click()

        expect(await getRowCountInTable(page)).toEqual(beforeCount)
      })

      test('Filters table view when an issue type item is toggled', async ({memex, page}) => {
        await memex.navigateToStory('integrationTestsWithItems', {
          viewType,
          serverFeatures: {memex_table_without_limits},
        })

        await memex.viewOptionsMenu.open()
        await memex.viewOptionsMenu.VIEW_OPTIONS_MENU_SLICE_BY.click()
        await memex.viewOptionsMenu.SLICE_BY_MENU.getByTestId('slice-Type').click()

        const beforeCount = await getRowCountInTable(page)

        // First click selects to toggle the filter on
        await memex.slicerPanel.LIST_ITEMS.getByText('Batch').click()

        const afterCount = await getRowCountInTable(page)

        expect(beforeCount).toBe(7)
        expect(afterCount).toBe(1)

        // Second click deselects to toggle the filter off
        await memex.slicerPanel.LIST_ITEMS.getByText('Batch').click()

        expect(await getRowCountInTable(page)).toEqual(beforeCount)
      })

      test('Filters table view when a repository item is toggled', async ({memex, page}) => {
        await memex.navigateToStory('integrationTestsWithItems', {
          viewType,
          serverFeatures: {memex_table_without_limits},
        })

        await memex.viewOptionsMenu.open()
        await memex.viewOptionsMenu.VIEW_OPTIONS_MENU_SLICE_BY.click()
        await memex.viewOptionsMenu.SLICE_BY_MENU.getByTestId('slice-Repository').click()

        const beforeCount = await getRowCountInTable(page)

        // First click selects to toggle the filter on
        await memex.slicerPanel.LIST_ITEMS.getByText('github/memex').click()

        const afterCount = await getRowCountInTable(page)

        expect(beforeCount).toBe(7)
        expect(afterCount).toBe(5)

        // Second click deselects to toggle the filter off
        await memex.slicerPanel.LIST_ITEMS.getByText('github/memex').click()

        expect(await getRowCountInTable(page)).toEqual(beforeCount)
      })

      test('Filters table view when a text item is toggled', async ({memex, page}) => {
        await memex.navigateToStory('integrationTestsWithItems', {
          viewType,
          serverFeatures: {memex_table_without_limits},
        })

        await memex.viewOptionsMenu.open()
        await memex.viewOptionsMenu.VIEW_OPTIONS_MENU_SLICE_BY.click()
        await memex.viewOptionsMenu.SLICE_BY_MENU.getByTestId('slice-Team').click()

        const beforeCount = await getRowCountInTable(page)

        // First click selects to toggle the filter on
        await memex.slicerPanel.LIST_ITEMS.getByText('Novelty Aardvarks').click()

        const afterCount = await getRowCountInTable(page)

        expect(beforeCount).toBe(7)
        expect(afterCount).toBe(2)

        // Second click deselects to toggle the filter off
        await memex.slicerPanel.LIST_ITEMS.getByText('Novelty Aardvarks').click()

        expect(await getRowCountInTable(page)).toEqual(beforeCount)
      })

      test('Filters table view when a date item is toggled', async ({memex, page}) => {
        test.skip(
          true,
          'PWL: slicer-items throws an exception when the date value is null ' +
            'in getSlicerItem this test has been skipped under https://github.com/github/projects-platform/issues/3103',
        )

        await memex.navigateToStory('integrationTestsWithItems', {
          viewType,
          serverFeatures: {memex_table_without_limits},
        })

        await memex.viewOptionsMenu.open()
        await memex.viewOptionsMenu.VIEW_OPTIONS_MENU_SLICE_BY.click()
        await memex.viewOptionsMenu.SLICE_BY_MENU.getByTestId('slice-Due Date').click()

        const beforeCount = await getRowCountInTable(page)

        // First click selects to toggle the filter on
        await memex.slicerPanel.LIST_ITEMS.getByText(todayString).click()

        const afterCount = await getRowCountInTable(page)

        expect(beforeCount).toBe(8)
        expect(afterCount).toBe(2)

        // Second click deselects to toggle the filter off
        await memex.slicerPanel.LIST_ITEMS.getByText(todayString).click()

        expect(await getRowCountInTable(page)).toEqual(beforeCount)
      })

      test('Filters table view when a number item is toggled', async ({memex, page}) => {
        await memex.navigateToStory('integrationTestsWithItems', {
          viewType,
          serverFeatures: {memex_table_without_limits},
        })

        await memex.viewOptionsMenu.open()
        await memex.viewOptionsMenu.VIEW_OPTIONS_MENU_SLICE_BY.click()
        await memex.viewOptionsMenu.SLICE_BY_MENU.getByTestId('slice-Estimate').click()

        const beforeCount = await getRowCountInTable(page)

        // First click selects to toggle the filter on
        await memex.slicerPanel.LIST_ITEMS.getByText('10').click()

        const afterCount = await getRowCountInTable(page)

        expect(beforeCount).toBe(7)
        expect(afterCount).toBe(2)

        // Second click deselects to toggle the filter off
        await memex.slicerPanel.LIST_ITEMS.getByText('10').click()

        expect(await getRowCountInTable(page)).toEqual(beforeCount)
      })

      test('Filters table view when an iteration slicer item is toggled', async ({memex, page}) => {
        await memex.navigateToStory('appWithIterationsField', {
          viewType,
          serverFeatures: {memex_table_without_limits},
        })

        await memex.viewOptionsMenu.open()
        await memex.viewOptionsMenu.VIEW_OPTIONS_MENU_SLICE_BY.click()
        await memex.viewOptionsMenu.SLICE_BY_MENU.getByTestId('slice-Iteration').click()

        const beforeCount = await getRowCountInTable(page)

        // First click selects to toggle the filter on
        await memex.slicerPanel.LIST_ITEMS.getByText('Iteration 4').click()

        const afterCount = await getRowCountInTable(page)

        expect(beforeCount).toBe(8)
        expect(afterCount).toBe(3)

        // Second click deselects to toggle the filter off
        await memex.slicerPanel.LIST_ITEMS.getByText('Iteration 4').click()

        expect(await getRowCountInTable(page)).toEqual(beforeCount)
      })

      test('Filters table view from URL with slice params and sliceValue=Closed', async ({memex, page}) => {
        await memex.navigateToStory('integrationTestsWithItems', {
          viewType,
          sliceBy: {columnId: StageColumnId},
          sliceValue: 'Closed',
          serverFeatures: {memex_table_without_limits},
        })

        expect(await getRowCountInTable(page)).toBe(1)
      })

      test('Filters table view from URL with slice params and sliceValue=_noValue', async ({memex, page}) => {
        await memex.navigateToStory('integrationTestsWithItems', {
          viewType,
          sliceBy: {columnId: StageColumnId},
          sliceValue: '_noValue',
          serverFeatures: {memex_table_without_limits},
        })

        expect(await getRowCountInTable(page)).toBe(5)
      })

      test('Deselect button clears current slice value', async ({memex, page}) => {
        await memex.navigateToStory('integrationTestsWithItems', {
          viewType,
          serverFeatures: {memex_table_without_limits},
        })

        await memex.viewOptionsMenu.open()
        await memex.viewOptionsMenu.VIEW_OPTIONS_MENU_SLICE_BY.click()
        await memex.viewOptionsMenu.SLICE_BY_MENU.getByTestId('slice-Stage').click()

        const beforeCount = await getRowCountInTable(page)

        await memex.slicerPanel.LIST_ITEMS.getByText('Up Next').click()

        const filteredCount = await getRowCountInTable(page)
        expect(filteredCount).toBe(1)

        await memex.slicerPanel.DESELECT.click()

        const afterCount = await getRowCountInTable(page)

        expect(beforeCount).toBe(7)
        expect(afterCount).toBe(7)

        // Expect some relevant stats to have been sent
        await memex.stats.expectStatsToContain({
          name: SlicerDeselect,
          memexProjectColumnId: StageColumnId,
          memexProjectViewNumber: 1,
          context: JSON.stringify({layout: viewType}),
          ui: SlicerPanelUI,
        })
      })

      test('Applies slice value to newly added items', async ({memex, page}) => {
        test.skip(
          viewType === 'table',
          'PWL: slow test takes over 30,000ms to run and is tracked under https://github.com/github/projects-platform/issues/3103',
        )
        await memex.navigateToStory('reactTableWithItems', {
          viewType,
          serverFeatures: {memex_table_without_limits},
        })

        await memex.viewOptionsMenu.open()
        await memex.viewOptionsMenu.VIEW_OPTIONS_MENU_SLICE_BY.click()
        await memex.viewOptionsMenu.SLICE_BY_MENU.getByTestId('slice-Stage').click()

        await memex.slicerPanel.LIST_ITEMS.getByText('Up Next').click()
        await memex.slicerPanel.expectListItemToHaveCount(1, 12)

        await memex.omnibar.focusAndEnterText('Draft issue')
        await page.keyboard.press('Enter')

        await memex.slicerPanel.expectListItemToHaveCount(1, 12)
      })
    }
  })
}

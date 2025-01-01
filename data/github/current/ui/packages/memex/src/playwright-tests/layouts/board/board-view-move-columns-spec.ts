import {expect} from '@playwright/test'

import {test} from '../../fixtures/test-extended'
import {dragTo, mustGetCenter} from '../../helpers/dom/interactions'
import {PWL_SKIP_COLUMN_FILTERING, PWL_SKIP_MOCK_SERVER} from '../../helpers/pwl-spec-migration'
import {waitForFunction} from '../../helpers/utils'

const memex_table_without_limits = true

test.describe('Move columns', () => {
  test.describe('Unfiltered columns', () => {
    test.beforeEach(async ({memex}) => {
      await memex.navigateToStory('integrationTestsWithItems', {
        viewType: 'board',
        serverFeatures: {memex_table_without_limits},
      })
    })

    test('Columns can be moved by dragging-and-dropping to the left', async ({page, memex}) => {
      const titleTexts = memex.boardView.COLUMN_TITLE_TEXTS
      const thirdColTitle = await titleTexts.nth(2).textContent()
      const secondColTitle = await titleTexts.nth(1).textContent()

      if (!thirdColTitle || !secondColTitle) {
        throw new Error('Missing column titles')
      }

      const columnTitle = memex.boardView.getColumn(thirdColTitle).COLUMN_TITLE
      const targetColumn = memex.boardView.getColumn(secondColTitle).columnLocator
      const targetColumnCenter = await mustGetCenter(targetColumn)

      await dragTo(page, columnTitle, {x: targetColumnCenter.x - 10})

      // Wait for our state update to be reflected.
      const didMove = await waitForFunction(async () => {
        const titleText = await titleTexts.nth(1).textContent()
        return titleText === thirdColTitle ? true : null
      })

      expect(didMove).toBeTruthy()
    })

    test('Columns can be moved by dragging-and-dropping to the right', async ({page, memex}) => {
      test.skip(true, PWL_SKIP_MOCK_SERVER)
      const titleTexts = memex.boardView.COLUMN_TITLE_TEXTS
      const secondColTitle = await titleTexts.nth(1).textContent()
      const fourthColTitle = await titleTexts.nth(3).textContent()

      if (!fourthColTitle || !secondColTitle) {
        throw new Error('Missing column titles')
      }

      const columnTitle = memex.boardView.getColumn(secondColTitle).COLUMN_TITLE
      const targetColumn = memex.boardView.getColumn(fourthColTitle).columnLocator
      const targetColumnCenter = await mustGetCenter(targetColumn)

      await dragTo(page, columnTitle, {x: targetColumnCenter.x + 10})

      // Wait for our state update to be reflected.
      const didMove = await waitForFunction(async () => {
        const titleText = await titleTexts.nth(3).textContent()
        return titleText === secondColTitle ? true : null
      })

      expect(didMove).toBeTruthy()
    })

    test('Columns can be moved by dragging-and-dropping on the left side of the first column', async ({
      page,
      memex,
    }) => {
      const titleTexts = memex.boardView.COLUMN_TITLE_TEXTS
      const thirdColTitle = await titleTexts.nth(2).textContent()
      const firstColTitle = await titleTexts.nth(0).textContent()

      if (!thirdColTitle) {
        throw new Error('Missing third column title')
      }

      if (!firstColTitle) {
        throw new Error('Missing first column title')
      }

      const columnTitle = memex.boardView.getColumn(thirdColTitle).COLUMN_TITLE
      const targetColumn = memex.boardView.getColumn(firstColTitle).columnLocator
      const targetColumnCenter = await mustGetCenter(targetColumn)

      await dragTo(page, columnTitle, {x: targetColumnCenter.x - 10})

      // Wait for our state update to be reflected.
      const didMove = await waitForFunction(async () => {
        const titleText = await titleTexts.nth(1).textContent()
        return titleText === thirdColTitle ? true : null
      })

      expect(didMove).toBeTruthy()
    })

    test("Dragging a column right after its current position doesn't trigger reordering", async ({page, memex}) => {
      const titleTexts = memex.boardView.COLUMN_TITLE_TEXTS
      const columnIndex = 1 // second column, first column doesn't move
      const currentColTitle = await titleTexts.nth(columnIndex).textContent()

      if (!currentColTitle) {
        throw new Error('Missing first column title')
      }

      const columnTitle = memex.boardView.getColumn(currentColTitle).COLUMN_TITLE
      const targetColumn = memex.boardView.getColumn(currentColTitle).columnLocator
      const targetColumnCenter = await mustGetCenter(targetColumn)

      await dragTo(page, columnTitle, {x: targetColumnCenter.x + 20}) // move slightly to the right

      // Wait for our state update to be reflected.
      const didNotMove = await waitForFunction(async () => {
        const titleText = await titleTexts.nth(columnIndex).textContent()
        return titleText === currentColTitle ? true : null
      })

      expect(didNotMove).toBeTruthy()
    })

    test('Columns can be moved to the left via menu', async ({memex}) => {
      await memex.boardView.getColumn('In Progress').expectIndexToBe(2)

      await memex.boardView.getColumn('In Progress').openContextMenu()
      await expect(memex.boardView.COLUMN_CONTEXT_MENU_MOVE_TO_LEFT).toBeVisible()
      await memex.boardView.COLUMN_MENU('In Progress').getByRole('menuitem', {name: 'Move left'}).click()
      await memex.boardView.getColumn('In Progress').expectIndexToBe(1)
    })

    test('Columns can be moved to the right via menu', async ({memex}) => {
      test.skip(true, PWL_SKIP_MOCK_SERVER)
      await memex.boardView.getColumn('In Progress').expectIndexToBe(2)

      await memex.boardView.getColumn('In Progress').openContextMenu()
      await expect(memex.boardView.COLUMN_CONTEXT_MENU_MOVE_TO_RIGHT).toBeVisible()
      await memex.boardView.COLUMN_MENU('In Progress').getByRole('menuitem', {name: 'Move right'}).click()
      await memex.boardView.getColumn('In Progress').expectIndexToBe(3)
    })

    test('First column cannot be moved left via menu', async ({memex}) => {
      await memex.boardView.getColumn('Backlog').expectIndexToBe(1)

      await memex.boardView.getColumn('Backlog').openContextMenu()
      await expect(memex.boardView.COLUMN_CONTEXT_MENU_MOVE_TO_LEFT).toBeVisible()
      await expect(memex.boardView.COLUMN_MENU('Backlog').getByRole('menuitem', {name: 'Move left'})).toBeDisabled()
    })

    test('Last column cannot be moved right via menu', async ({memex}) => {
      await memex.boardView.getColumn('Done').expectIndexToBe(4)

      await memex.boardView.getColumn('Done').openContextMenu()
      await expect(memex.boardView.COLUMN_CONTEXT_MENU_MOVE_TO_RIGHT).toBeVisible()
      await expect(memex.boardView.COLUMN_MENU('Done').getByRole('menuitem', {name: 'Move right'})).toBeDisabled()
    })
  })

  test.describe('Filtered columns', () => {
    test.beforeEach(() => {
      test.skip(true, PWL_SKIP_COLUMN_FILTERING)
    })
    test('Columns can be moved by dragging-and-dropping to the left', async ({page, memex}) => {
      await memex.navigateToStory('integrationTestsWithItems', {
        viewType: 'board',
        filterQuery: "-status:'In Progress'",
        serverFeatures: {memex_table_without_limits},
      })
      const titleTexts = memex.boardView.COLUMN_TITLE_TEXTS
      const thirdColTitle = await titleTexts.nth(2).textContent()
      const secondColTitle = await titleTexts.nth(1).textContent()

      if (!thirdColTitle || !secondColTitle) {
        throw new Error('Missing column titles')
      }

      const columnTitle = memex.boardView.getColumn(thirdColTitle).COLUMN_TITLE
      const targetColumn = memex.boardView.getColumn(secondColTitle).columnLocator
      const targetColumnCenter = await mustGetCenter(targetColumn)

      await dragTo(page, columnTitle, {x: targetColumnCenter.x - 10})

      // Wait for our state update to be reflected.
      const didMove = await waitForFunction(async () => {
        const titleText = await titleTexts.nth(1).textContent()
        return titleText === thirdColTitle ? true : null
      })

      expect(didMove).toBeTruthy()
    })

    test('Columns can be moved by dragging-and-dropping to the right', async ({page, memex}) => {
      await memex.navigateToStory('integrationTestsWithItems', {
        viewType: 'board',
        filterQuery: "-status:'In Progress'",
        serverFeatures: {memex_table_without_limits},
      })
      const titleTexts = memex.boardView.COLUMN_TITLE_TEXTS
      const secondColTitle = await titleTexts.nth(1).textContent()
      const fourthColTitle = await titleTexts.nth(3).textContent()

      if (!fourthColTitle || !secondColTitle) {
        throw new Error('Missing column titles')
      }

      const columnTitle = memex.boardView.getColumn(secondColTitle).COLUMN_TITLE
      const targetColumn = memex.boardView.getColumn(fourthColTitle).columnLocator
      const targetColumnCenter = await mustGetCenter(targetColumn)

      await dragTo(page, columnTitle, {x: targetColumnCenter.x + 10})

      // Wait for our state update to be reflected.
      const didMove = await waitForFunction(async () => {
        const titleText = await titleTexts.nth(3).textContent()
        return titleText === secondColTitle ? true : null
      })

      expect(didMove).toBeTruthy()
    })

    test('Columns can be moved to the left via menu', async ({memex}) => {
      await memex.navigateToStory('integrationTestsWithItems', {
        viewType: 'board',
        filterQuery: "-status:'In Progress'",
        serverFeatures: {memex_table_without_limits},
      })

      await memex.boardView.getColumn('Ready').expectIndexToBe(2)

      await memex.boardView.getColumn('Ready').openContextMenu()
      await expect(memex.boardView.COLUMN_CONTEXT_MENU_MOVE_TO_LEFT).toBeVisible()
      await memex.boardView.COLUMN_MENU('Ready').getByRole('menuitem', {name: 'Move left'}).click()
      await memex.boardView.getColumn('Ready').expectIndexToBe(1)

      await memex.filter.CLEAR_FILTER_BUTTON.click()
      await memex.boardView.getColumn('Ready').expectIndexToBe(1)
    })

    test('Columns can be moved to the right via menu', async ({memex}) => {
      await memex.navigateToStory('integrationTestsWithItems', {
        viewType: 'board',
        filterQuery: "-status:'In Progress'",
        serverFeatures: {memex_table_without_limits},
      })

      await memex.boardView.getColumn('Ready').expectIndexToBe(2)

      await memex.boardView.getColumn('Ready').openContextMenu()
      await expect(memex.boardView.COLUMN_CONTEXT_MENU_MOVE_TO_RIGHT).toBeVisible()
      await memex.boardView.COLUMN_MENU('Ready').getByRole('menuitem', {name: 'Move right'}).click()
      await memex.boardView.getColumn('Ready').expectIndexToBe(3)

      await memex.filter.CLEAR_FILTER_BUTTON.click()
      await memex.boardView.getColumn('Ready').expectIndexToBe(4)
    })

    test('First column cannot be moved left via menu', async ({memex}) => {
      await memex.navigateToStory('integrationTestsWithItems', {
        viewType: 'board',
        filterQuery: "-status:'In Progress'",
        serverFeatures: {memex_table_without_limits},
      })

      await memex.boardView.getColumn('Backlog').expectIndexToBe(1)

      await memex.boardView.getColumn('Backlog').openContextMenu()
      await expect(memex.boardView.COLUMN_CONTEXT_MENU_MOVE_TO_LEFT).toBeVisible()
      await expect(memex.boardView.COLUMN_MENU('Backlog').getByRole('menuitem', {name: 'Move left'})).toBeDisabled()
    })

    test('Last column cannot be moved right via menu', async ({memex}) => {
      await memex.navigateToStory('integrationTestsWithItems', {
        viewType: 'board',
        filterQuery: "-status:'In Progress'",
        serverFeatures: {memex_table_without_limits},
      })

      await memex.boardView.getColumn('Done').expectIndexToBe(3)

      await memex.boardView.getColumn('Done').openContextMenu()
      await expect(memex.boardView.COLUMN_CONTEXT_MENU_MOVE_TO_RIGHT).toBeVisible()
      await expect(memex.boardView.COLUMN_MENU('Done').getByRole('menuitem', {name: 'Move right'})).toBeDisabled()
    })
  })

  test('Column menu move actions are disabled w/ column by iteration', async ({memex}) => {
    // In production, only the 3 most recently completed iterations are returned by default.
    // The mock server is returning all iterations.
    // The test is not skipped because it has been adjusted to account for this inaccuracy.
    test.skip(false, PWL_SKIP_COLUMN_FILTERING)
    await memex.navigateToStory('appWithIterationsField', {
      viewType: 'board',
      verticalGroupedBy: {columnId: 20},
      serverFeatures: {memex_table_without_limits},
    })

    await memex.boardView.getColumn('Iteration 1').expectIndexToBe(2)

    await memex.boardView.getColumn('Iteration 1').openContextMenu()
    await expect(memex.boardView.COLUMN_CONTEXT_MENU_MOVE_TO_RIGHT).toBeVisible()
    await expect(memex.boardView.COLUMN_MENU('Iteration 1').getByRole('menuitem', {name: 'Move left'})).toBeDisabled()
    await expect(memex.boardView.COLUMN_MENU('Iteration 1').getByRole('menuitem', {name: 'Move right'})).toBeDisabled()
  })

  test.describe('Hides column move actions when memex_column_menu_position is enabled', () => {
    test('For column by single select', async ({memex}) => {
      await memex.navigateToStory('integrationTestsWithItems', {
        viewType: 'board',
        serverFeatures: {memex_column_menu_position: false, memex_table_without_limits},
      })

      await memex.boardView.getColumn('In Progress').expectIndexToBe(2)

      await memex.boardView.getColumn('In Progress').openContextMenu()
      await expect(memex.boardView.COLUMN_CONTEXT_MENU_MOVE_TO_LEFT).toBeHidden()
      await expect(memex.boardView.COLUMN_CONTEXT_MENU_MOVE_TO_RIGHT).toBeHidden()
    })

    test('For column by iteration', async ({memex}) => {
      // In production, only the 3 most recently completed iterations are returned by default.
      // The mock server is returning all iterations.
      // The test is not skipped because it has been adjusted to account for this inaccuracy.
      test.skip(false, PWL_SKIP_COLUMN_FILTERING)
      await memex.navigateToStory('appWithIterationsField', {
        viewType: 'board',
        verticalGroupedBy: {columnId: 20},
        serverFeatures: {memex_column_menu_position: false, memex_table_without_limits},
      })

      await memex.boardView.getColumn('Iteration 1').expectIndexToBe(2)

      await memex.boardView.getColumn('Iteration 1').openContextMenu()
      await expect(memex.boardView.COLUMN_CONTEXT_MENU_MOVE_TO_LEFT).toBeHidden()
      await expect(memex.boardView.COLUMN_CONTEXT_MENU_MOVE_TO_RIGHT).toBeHidden()
    })
  })
})

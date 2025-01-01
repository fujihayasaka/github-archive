import {expect} from '@playwright/test'

import {test} from '../../fixtures/test-extended'
import {PWL_SKIP_REASON} from '../../helpers/pwl-spec-migration'
import {addDraftItem} from '../../helpers/table/interactions'
import {BacklogColumn} from '../../types/board'

const memex_table_without_limits = true

test.describe('Filter-reactive board columns', () => {
  test("When the filter doesn't contain the group field show all columns - (except no status which is hidden when it's empty)", async ({
    memex,
  }) => {
    await memex.navigateToStory('integrationTestsWithItems', {
      viewType: 'board',
      filterQuery: "backlog assignee:mattcosta7 label:bug due-date:<'2020-01-01'",
      serverFeatures: {memex_table_without_limits},
    })
    await Promise.all([
      memex.boardView.getColumn('No Status').expectHidden(),
      memex.boardView.getColumn('Backlog').expectVisible(),
      memex.boardView.getColumn('In Progress').expectVisible(),
      memex.boardView.getColumn('Ready').expectVisible(),
      memex.boardView.getColumn('Done').expectVisible(),
    ])
  })
  test('Hides a field on the board view when the filter excludes it', async ({memex}) => {
    test.skip(true, PWL_SKIP_REASON)
    await memex.navigateToStory('integrationTestsWithItems', {
      viewType: 'board',
      filterQuery: '-status:backlog',
      serverFeatures: {memex_table_without_limits},
    })
    await Promise.all([
      memex.boardView.getColumn('No Status').expectVisible(),
      memex.boardView.getColumn('Backlog').expectHidden(),
      memex.boardView.getColumn('In Progress').expectVisible(),
      memex.boardView.getColumn('Ready').expectVisible(),
      memex.boardView.getColumn('Done').expectVisible(),
    ])
  })
  test('Hides all columns on the board when filter value is invalid', async ({memex}) => {
    test.skip(true, PWL_SKIP_REASON)
    await memex.navigateToStory('integrationTestsWithItems', {
      viewType: 'board',
      filterQuery: 'status:not-a-status',
      serverFeatures: {memex_table_without_limits},
    })
    await Promise.all([
      memex.boardView.getColumn('No Status').expectHidden(),
      memex.boardView.getColumn('Backlog').expectHidden(),
      memex.boardView.getColumn('In Progress').expectHidden(),
      memex.boardView.getColumn('Ready').expectHidden(),
      memex.boardView.getColumn('Done').expectHidden(),
    ])

    // focusing the filter box should not cause a crash
    await memex.filter.INPUT.click()

    await expect(memex.filter.INPUT).toBeVisible()
  })
  test('Shows only fields on the board view that the filter includes', async ({memex}) => {
    test.skip(true, PWL_SKIP_REASON)
    await memex.navigateToStory('integrationTestsWithItems', {
      viewType: 'board',
      filterQuery: 'status:backlog,"In Progress"',
      serverFeatures: {memex_table_without_limits},
    })
    await Promise.all([
      memex.boardView.getColumn('No Status').expectHidden(),
      memex.boardView.getColumn('Backlog').expectVisible(),
      memex.boardView.getColumn('In Progress').expectVisible(),
      memex.boardView.getColumn('Ready').expectHidden(),
      memex.boardView.getColumn('Done').expectHidden(),
    ])
  })
  test('Hides a field on the board view when the filter excludes it after an item has been added to the column', async ({
    memex,
    page,
  }) => {
    test.skip(true, PWL_SKIP_REASON)
    await memex.navigateToStory('integrationTestsWithItems', {
      viewType: 'board',
      serverFeatures: {memex_table_without_limits},
    })
    await Promise.all([
      memex.boardView.getColumn('No Status').expectVisible(),
      memex.boardView.getColumn('Backlog').expectVisible(),
      memex.boardView.getColumn('In Progress').expectVisible(),
      memex.boardView.getColumn('Ready').expectVisible(),
      memex.boardView.getColumn('Done').expectVisible(),
    ])

    await memex.boardView.getColumn(BacklogColumn.Label).expectCardCount(2)

    await memex.boardView.getColumn(BacklogColumn.Label).ADD_ITEM.click()
    await addDraftItem(page, 'Draft issue')

    await memex.boardView.getColumn(BacklogColumn.Label).expectCardCount(3)

    await memex.filter.filterBy('-status:backlog')

    await Promise.all([
      memex.boardView.getColumn('No Status').expectVisible(),
      memex.boardView.getColumn('Backlog').expectHidden(),
      memex.boardView.getColumn('In Progress').expectVisible(),
      memex.boardView.getColumn('Ready').expectVisible(),
      memex.boardView.getColumn('Done').expectVisible(),
    ])
  })
  test('It filters iteration columns to a single @current iteration', async ({memex}) => {
    test.skip(true, PWL_SKIP_REASON)
    await memex.navigateToStory('appWithIterationsField', {
      viewType: 'board',
      filterQuery: 'iteration:@current',
      verticalGroupedBy: {columnId: '20'},
      serverFeatures: {memex_table_without_limits},
    })
    await Promise.all([
      memex.boardView.getColumn(`Iteration 4`).expectVisible(),
      ...[0, 1, 2, 3, 5, 6].map(index => memex.boardView.getColumn(`Iteration ${index}`).expectHidden()),
    ])
  })
  test('It filters iteration columns to all except @current', async ({memex}) => {
    test.skip(true, PWL_SKIP_REASON)
    await memex.navigateToStory('appWithIterationsField', {
      viewType: 'board',
      filterQuery: '-iteration:@current',
      verticalGroupedBy: {columnId: '20'},
      serverFeatures: {memex_table_without_limits},
    })
    await Promise.all([
      memex.boardView.getColumn(`Iteration 4`).expectHidden(),
      ...[0, 1, 2, 3, 5, 6].map(index => memex.boardView.getColumn(`Iteration ${index}`).expectVisible()),
    ])
  })
  test('It filters iteration columns displayed when using >= token', async ({memex}) => {
    test.skip(true, PWL_SKIP_REASON)
    await memex.navigateToStory('appWithIterationsField', {
      viewType: 'board',
      filterQuery: 'iteration:>=@current',
      verticalGroupedBy: {columnId: '20'},
      serverFeatures: {memex_table_without_limits},
    })
    await Promise.all([
      ...[4, 5, 6].map(index => memex.boardView.getColumn(`Iteration ${index}`).expectVisible()),
      ...[0, 1, 2, 3].map(index => memex.boardView.getColumn(`Iteration ${index}`).expectHidden()),
    ])
  })
  test('It filters iteration columns displayed when using not >= token', async ({memex}) => {
    test.skip(true, PWL_SKIP_REASON)
    await memex.navigateToStory('appWithIterationsField', {
      viewType: 'board',
      filterQuery: '-iteration:>=@current',
      verticalGroupedBy: {columnId: '20'},
      serverFeatures: {memex_table_without_limits},
    })
    await Promise.all([
      ...[4, 5, 6].map(index => memex.boardView.getColumn(`Iteration ${index}`).expectHidden()),
      ...[0, 1, 2, 3].map(index => memex.boardView.getColumn(`Iteration ${index}`).expectVisible()),
    ])
  })
  test('It filters iteration columns displayed when using token+x', async ({memex}) => {
    test.skip(true, PWL_SKIP_REASON)
    await memex.navigateToStory('appWithIterationsField', {
      viewType: 'board',
      filterQuery: 'iteration:@current+2',
      verticalGroupedBy: {columnId: '20'},
      serverFeatures: {memex_table_without_limits},
    })
    await Promise.all([
      ...[6].map(index => memex.boardView.getColumn(`Iteration ${index}`).expectVisible()),
      ...[0, 1, 2, 3, 4, 5].map(index => memex.boardView.getColumn(`Iteration ${index}`).expectHidden()),
    ])
  })
  test('It filters iteration columns displayed when using not token+x', async ({memex}) => {
    test.skip(true, PWL_SKIP_REASON)
    await memex.navigateToStory('appWithIterationsField', {
      viewType: 'board',
      filterQuery: '-iteration:@current+2',
      verticalGroupedBy: {columnId: '20'},
      serverFeatures: {memex_table_without_limits},
    })
    await Promise.all([
      ...[6].map(index => memex.boardView.getColumn(`Iteration ${index}`).expectHidden()),
      ...[0, 1, 2, 3, 4, 5].map(index => memex.boardView.getColumn(`Iteration ${index}`).expectVisible()),
    ])
  })
})

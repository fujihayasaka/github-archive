import {expect} from '@playwright/test'
import type {Readable} from 'stream'

import {FileExport} from '../../client/api/stats/contracts'
import {test} from '../fixtures/test-extended'
import {submitConfirmDialog} from '../helpers/dom/interactions'
import {integrationTestsWithItemsTsv} from '../snapshots/integration-tests-with-items-tsv'

async function readStreamAsString(stream: Readable) {
  let result = ''
  for await (const chunk of stream) result += `${chunk}`
  stream.destroy()
  return result
}

test.describe('download view', () => {
  test.beforeEach(async ({memex}) => {
    await memex.navigateToStory('integrationTestsWithItems', {
      serverFeatures: {
        memex_table_without_limits: true,
      },
    })
  })

  test('as TSV with confirmation when memex_table_without_limits is enabled', async ({memex, page}) => {
    await memex.viewOptionsMenu.open()
    const downloadPromise = page.waitForEvent('download')
    await page.keyboard.press('ArrowUp')
    await expect(memex.viewOptionsMenu.EXPORT_VIEW_DATA).toBeFocused()
    await page.keyboard.press('Enter')
    await submitConfirmDialog(page, 'Export')

    const download = await downloadPromise

    expect(download.suggestedFilename()).toBe("My Team's Memex - View 1.tsv")

    const stream = await download.createReadStream()
    const content = await readStreamAsString(stream)

    expect(content).toBe(integrationTestsWithItemsTsv)

    // Expect a correct count of items in the export (-1 to account for header)
    const expectedItemCount = integrationTestsWithItemsTsv.split('\n').length - 1
    // Expect hydro events to be posted
    await memex.stats.expectStatsToContain({
      name: FileExport,
      number_of_rows: expectedItemCount,
    })
  })

  test('as TSV', async ({memex, page}) => {
    await memex.viewOptionsMenu.open()
    const downloadPromise = page.waitForEvent('download')
    await page.keyboard.press('ArrowUp')
    await expect(memex.viewOptionsMenu.EXPORT_VIEW_DATA).toBeFocused()
    await page.keyboard.press('Enter')
    await page.waitForSelector('[role=alertdialog][aria-modal=true]')
    await submitConfirmDialog(page, 'Export')

    const download = await downloadPromise

    expect(download.suggestedFilename()).toBe("My Team's Memex - View 1.tsv")

    const stream = await download.createReadStream()
    const content = await readStreamAsString(stream)

    expect(content).toBe(integrationTestsWithItemsTsv)

    // Expect a correct count of items in the export (-1 to account for header)
    const expectedItemCount = integrationTestsWithItemsTsv.split('\n').length - 1
    // Expect hydro events to be posted
    await memex.stats.expectStatsToContain({
      name: FileExport,
      number_of_rows: expectedItemCount,
    })
  })
})

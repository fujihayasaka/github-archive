import {expect} from '@playwright/test'

import {test} from '../../fixtures/test-extended'
import {PWL_SKIP_REASON} from '../../helpers/pwl-spec-migration'
import {
  buildHtmlRowForIndex,
  buildTableHTML,
  integrationTestsWithItemsHtml,
} from '../../snapshots/integration-tests-with-items-html'
import {buildTsvRowForIndex, integrationTestsWithItemsTsv} from '../../snapshots/integration-tests-with-items-tsv'

// For behavior when pasting values, see `table-paste-spec`
test.describe('copying cells in table view', () => {
  test.beforeEach(async ({memex}) => {
    await memex.navigateToStory('integrationTestsWithItems')
  })

  test('copying a single cell copies its value without applying surrounding HTML, and highlights as copy source', async ({
    memex,
    clipboard,
  }) => {
    const sourceCell = memex.tableView.cells.getCellLocator(0, 'Status')
    const sourceText = await sourceCell.textContent()

    await sourceCell.focus()
    await clipboard.copySelection()

    const contents = await clipboard.getContents()

    expect(contents.length).toEqual(1)

    expect(contents[0]['text/plain']).toEqual(sourceText)

    expect(contents[0]['text/html']).toEqual(sourceText)

    await expect(sourceCell).toHaveClass(/is-copy-source/)
  })

  test('HTML from title cell has link & keeps code tags', async ({memex, clipboard}) => {
    test.skip(true, PWL_SKIP_REASON)
    const sourceCell = memex.tableView.cells.getCellLocator(5, 'Title')

    await sourceCell.focus()
    await clipboard.copySelection()

    const contents = await clipboard.getContents()

    expect(contents.length).toEqual(1)

    expect(contents[0]['text/plain']).toEqual('Fix this `issue` please!\thttps://github.com/github/memex/issues/336')

    expect(contents[0]['text/html']).toEqual(
      '<a href="https://github.com/github/memex/issues/336">Fix this <code>issue</code> please!</a>',
    )
  })

  test('does not linkify draft title', async ({memex, clipboard}) => {
    const sourceCell = memex.tableView.cells.getCellLocator(2, 'Title')

    await sourceCell.focus()
    await clipboard.copySelection()

    const contents = await clipboard.getContents()

    expect(contents.length).toEqual(1)

    expect(contents[0]['text/plain']).toEqual('Here is a Draft Issue!')

    expect(contents[0]['text/html']).toEqual('Here is a Draft Issue!')
  })

  test('copying multiple cells wraps in table markup, preserving empty cells but skipping redacted rows', async ({
    memex,
    clipboard,
    page,
  }) => {
    test.skip(true, PWL_SKIP_REASON)
    const sourceCell = memex.tableView.cells.getCellLocator(1, 'Status')

    await sourceCell.focus()
    for (const _ of Array(5)) await page.keyboard.press('Shift+ArrowDown')
    await clipboard.copySelection()

    const contents = await clipboard.getContents()

    // only one entry, even though it's several cells
    expect(contents.length).toEqual(1)

    expect(contents[0]['text/plain']).toEqual('Done\n\nDone\nBacklog\nBacklog')

    expect(contents[0]['text/html']).toEqual(
      `<table>
<tbody>
<tr><td>Done</td></tr>
<tr><td></td></tr>
<tr><td>Done</td></tr>
<tr><td>Backlog</td></tr>
<tr><td>Backlog</td></tr>
</tbody>
</table>`,
    )
  })

  test('can copy an entire row as HTML and TSV', async ({memex, clipboard, page}) => {
    const sourceCell = memex.tableView.cells.getCellLocator(3, 'Title')
    await sourceCell.focus()
    await page.keyboard.press('Control+a')

    await clipboard.copySelection()

    const contents = await clipboard.getContents()

    expect(contents[0]['text/plain']).toEqual(buildTsvRowForIndex(3))

    const rows = [buildHtmlRowForIndex(3)]
    expect(contents[0]['text/html']).toEqual(buildTableHTML(rows))
  })

  test('can copy a range of rows as HTML and TSV', async ({memex, clipboard, page}) => {
    const sourceCell = memex.tableView.cells.getCellLocator(3, 'Title')
    await sourceCell.focus()
    await page.keyboard.press('Control+a')
    await page.keyboard.press('Shift+ArrowUp')

    await clipboard.copySelection()

    const contents = await clipboard.getContents()

    expect(contents.length).toEqual(1)

    const tsvRows = [buildTsvRowForIndex(2), buildTsvRowForIndex(3)].join('\n')
    expect(contents[0]['text/plain']).toEqual(tsvRows)

    const htmlRows = [buildHtmlRowForIndex(2), buildHtmlRowForIndex(3)]
    expect(contents[0]['text/html']).toEqual(buildTableHTML(htmlRows))
  })

  test('can copy entire table as HTML and TSV, with headers and without redacted rows', async ({
    memex,
    clipboard,
    page,
  }) => {
    const sourceCell = memex.tableView.cells.getCellLocator(3, 'Title')
    await sourceCell.focus()
    await page.keyboard.press('Control+a')
    await page.keyboard.press('Control+a')

    await clipboard.copySelection()

    const contents = await clipboard.getContents()

    expect(contents.length).toEqual(1)

    expect(contents[0]['text/plain']).toEqual(integrationTestsWithItemsTsv)
    expect(contents[0]['text/html']).toEqual(integrationTestsWithItemsHtml)
  })
})

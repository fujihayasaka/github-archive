import {clipboardData} from './clipboard-data'

export function buildTableHTMLWithHeader(rows: Array<string>) {
  const headers = Object.keys(clipboardData).filter(h => h !== 'URL')
  const tableHeader = `<thead><tr>${headers.map(h => `<th>${h}</th>`).join('')}</tr></thead>`

  return `<table>
${tableHeader}
<tbody>
${rows.join('\n')}
</tbody>
</table>`
}

export function buildTableHTML(rows: Array<string>) {
  return `<table>
<tbody>
${rows.join('\n')}
</tbody>
</table>`
}

export function buildHtmlRowForIndex(index: number) {
  const itemData = Object.values(clipboardData).map(row => row[index])
  const row = itemData
    .filter(cell => cell.html !== undefined)
    .map(cell => `<td>${cell.html}</td>`)
    .join('')
  return `<tr>${row}</tr>`
}

function buildFullTableHTML() {
  const rows = Object.values(clipboardData)

  const tableRows: Array<string> = []
  const numRows = rows[0].length
  for (let i = 0; i < numRows; i++) {
    tableRows.push(buildHtmlRowForIndex(i))
  }

  return buildTableHTMLWithHeader(tableRows)
}

export const integrationTestsWithItemsHtml = buildFullTableHTML()

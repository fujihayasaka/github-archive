import {clipboardData} from './clipboard-data'

export function buildTsvRowForIndex(index: number) {
  return Object.values(clipboardData)
    .map(row => row[index].plain)
    .join('\t')
}

function buildFullTsv() {
  const header = Object.keys(clipboardData).join('\t')
  const rows = Object.values(clipboardData)

  const tableRows: Array<string> = []
  const numRows = rows[0].length
  for (let i = 0; i < numRows; i++) {
    tableRows.push(buildTsvRowForIndex(i))
  }

  return `${header}
${tableRows.join('\n')}`
}

export const integrationTestsWithItemsTsv = buildFullTsv()

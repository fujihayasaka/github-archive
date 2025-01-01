import type {Dataset} from './config'

export type DataRow = {
  [key: string]: string
}

export async function expandDatasets(dataset: Dataset[]): Promise<DataRow[]> {
  const rows: DataRow[] = []

  for (const d of dataset) {
    switch (true) {
      case 'rows' in d: {
        rows.push(...d.rows)
        break
      }

      default:
        throw new Error(`Unsupported dataset configuration: ${JSON.stringify(d)}`)
    }
  }

  return rows
}

export async function parseJsonL(content: string): Promise<DataRow[]> {
  return content.split('\n').map(line => JSON.parse(line))
}

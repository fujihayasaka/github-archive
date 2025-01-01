import type {EvalsRow} from '../types'

export type AddRowManager = {
  evalsAddRow: (row: EvalsRow) => void
}

export const parseJSONL = async (lines: string[], errors: string[], manager: AddRowManager) => {
  for (const line of lines) {
    try {
      const row = JSON.parse(line)

      // Check if row is an object and has at least one string property
      if (!row || typeof row !== 'object' || Array.isArray(row)) {
        errors.push('Some rows were skipped. Invalid row format.')
        continue
      }

      // Get all string keys from the row
      const stringKeys = Object.keys(row).filter(key => typeof row[key] === 'string' || typeof row[key] === 'number')

      if (stringKeys.length === 0) {
        errors.push('Some rows were skipped. No valid string fields found.')
        continue
      }

      // Add all valid string fields from row
      const evalsRow = {} as EvalsRow

      for (const stringKey of stringKeys) {
        evalsRow[stringKey] = `${row[stringKey]}`
      }

      manager.evalsAddRow(evalsRow)
    } catch {
      errors.push('Error importing file.')
    }
  }

  return errors
}

export const parseCSV = async (lines: string[], errors: string[], manager: AddRowManager) => {
  if (lines.length < 2) {
    errors.push('CSV file must have at least a header row and one data row.')
    return errors
  }

  // Parse header row to get column names
  const headerLine = lines[0]
  if (!headerLine) {
    errors.push('CSV file header row is missing.')
    return errors
  }

  const headers = headerLine
    .split(',')
    .map(header => header.trim().replace(/^["']|["']$/g, '')) // Remove quotes and trim
    .filter(header => header.length > 0)

  if (headers.length === 0) {
    errors.push('CSV file must have at least one valid column header.')
    return errors
  }

  const linesWithoutHeader = lines.slice(1)
  for (const line of linesWithoutHeader) {
    try {
      const values = line.split(',').map(value => value.trim().replace(/^["']|["']$/g, '')) // Remove quotes and trim

      if (values.length === 0 || values.every(val => val === '')) {
        errors.push('Some rows were skipped. Empty rows are not allowed.')
        continue
      }

      // Create evalsRow with column headers as keys
      const evalsRow = {} as EvalsRow

      for (let i = 0; i < Math.min(headers.length, values.length); i++) {
        const header = headers[i]
        const value = values[i]
        if (header && value !== '' && value !== undefined) {
          evalsRow[header] = value
        }
      }

      // Only add row if it has at least one non-empty field
      if (Object.keys(evalsRow).length > 0) {
        manager.evalsAddRow(evalsRow)
      } else {
        errors.push('Some rows were skipped. No valid data found.')
      }
    } catch {
      errors.push('Error importing file.')
    }
  }

  return errors
}

import type {EvalsRow} from '../types'
import {VariableExpected, VariableInput} from '../variables'

// For now we are restricting this to a very small set of variables
const supportedInputs = [VariableInput, VariableExpected]

export type AddRowManager = {
  evalsAddRow: (row: EvalsRow) => void
}

export const parseJSONL = async (lines: string[], errors: string[], manager: AddRowManager) => {
  for (const line of lines) {
    try {
      const row = JSON.parse(line)

      // Need at least one supported input
      if (!supportedInputs.some(input => input in row)) {
        // Report and skip this row
        errors.push('Some rows were skipped. "input" or "expected" fields are required.')
        continue
      }

      // Only add supported inputs from row
      const evalsRow = {} as EvalsRow

      for (const input of supportedInputs) {
        if (row[input]) {
          evalsRow[input] = `${row[input]}`
        }
      }

      manager.evalsAddRow(evalsRow)
    } catch {
      errors.push('Error importing file.')
    }
  }

  return errors
}

export const parseCSV = async (lines: string[], errors: string[], manager: AddRowManager) => {
  const linesWithoutHeader = lines.slice(1)
  for (const line of linesWithoutHeader) {
    try {
      // Only take first two values
      const values = line
        .split(',')
        .map(value => value.trim())
        .slice(0, 2)

      if (values.length < 2) {
        errors.push('Some rows were skipped. "input" or "expected" fields are required.')
        continue
      }

      const evalsRow = {input: values[0], expected: values[1]} as unknown as EvalsRow

      manager.evalsAddRow(evalsRow)
    } catch {
      errors.push('Error importing file.')
    }
  }
}

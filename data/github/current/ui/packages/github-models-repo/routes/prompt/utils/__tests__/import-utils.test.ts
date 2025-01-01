import {parseCSV, parseJSONL, type AddRowManager} from '../import-utils'

const manager: AddRowManager = {
  evalsAddRow: jest.fn(),
}

beforeEach(() => {
  jest.clearAllMocks()
})

describe('import-utils', () => {
  describe('parseJSONL', () => {
    it('can parse jsonl lines with input/expected', () => {
      const lines: string[] = [
        '{"input": "foo", "expected": "FOO"}',
        '{"input": "bar", "expected": "BAR"}',
        '{"input": "123", "expected": "123"}',
      ]

      const errors: string[] = []

      parseJSONL(lines, errors, manager)

      expect(errors).toHaveLength(0)
      expect(manager.evalsAddRow).toHaveBeenCalledTimes(3)
    })

    it('can parse jsonl lines with custom variable names', () => {
      const lines: string[] = [
        '{"question": "What is 2+2?", "answer": "4"}',
        '{"question": "What is 3+3?", "answer": "6"}',
      ]

      const errors: string[] = []

      parseJSONL(lines, errors, manager)

      expect(errors).toHaveLength(0)
      expect(manager.evalsAddRow).toHaveBeenCalledTimes(2)
    })

    it('can parse mixed variable names across rows', () => {
      const lines: string[] = [
        '{"inputData": "foo", "expectedData": "FOO"}',
        '{"input": "bar", "expected": "BAR"}',
        '{"question": "123", "answer": "123"}',
      ]
      const errors: string[] = []

      parseJSONL(lines, errors, manager)

      expect(errors).toHaveLength(0)
      expect(manager.evalsAddRow).toHaveBeenCalledTimes(3)
    })

    it('errors on rows with no valid string/number fields', () => {
      const lines: string[] = ['{"data": {"nested": "object"}}', '{"input": "bar", "expected": "BAR"}']
      const errors: string[] = []

      parseJSONL(lines, errors, manager)

      expect(errors).toHaveLength(1)
      expect(errors[0]).toBe('Some rows were skipped. No valid string fields found.')
      expect(manager.evalsAddRow).toHaveBeenCalledTimes(1)
    })

    it('errors on empty input', () => {
      const lines: string[] = ['']
      const errors: string[] = []

      parseJSONL(lines, errors, manager)

      expect(errors).toHaveLength(1)
      expect(errors[0]).toBe('Error importing file.')
      expect(manager.evalsAddRow).not.toHaveBeenCalled()
    })
  })

  describe('parseCSV', () => {
    it('can parse CSV lines with any column names', () => {
      const lines: string[] = ['input,expected', 'bar, BAR', '123, 321']

      const errors: string[] = []

      parseCSV(lines, errors, manager)

      expect(errors).toHaveLength(0)
      // 2 times, because the first line is the header
      expect(manager.evalsAddRow).toHaveBeenCalledTimes(2)
    })

    it('can parse CSV with custom column names', () => {
      const lines: string[] = ['question,answer', 'What is 2+2?, 4', 'What is 3+3?, 6']

      const errors: string[] = []

      parseCSV(lines, errors, manager)

      expect(errors).toHaveLength(0)
      expect(manager.evalsAddRow).toHaveBeenCalledTimes(2)
    })

    it('can parse CSV with multiple columns', () => {
      const lines: string[] = ['prompt,context,response,score', 'Hello,greeting,Hi,5', 'Goodbye,farewell,Bye,4']

      const errors: string[] = []

      parseCSV(lines, errors, manager)

      expect(errors).toHaveLength(0)
      expect(manager.evalsAddRow).toHaveBeenCalledTimes(2)
    })

    it('errors on empty header row', () => {
      const lines: string[] = ['', 'foo', 'bar']
      const errors: string[] = []

      parseCSV(lines, errors, manager)

      expect(errors).toHaveLength(1)
      expect(errors[0]).toBe('CSV file header row is missing.')
      expect(manager.evalsAddRow).not.toHaveBeenCalled()
    })

    it('handles rows with missing values', () => {
      const lines: string[] = ['input,expected', 'foo,', ',bar', 'baz,qux']
      const errors: string[] = []

      parseCSV(lines, errors, manager)

      expect(errors).toHaveLength(0)
      expect(manager.evalsAddRow).toHaveBeenCalledTimes(3)
    })
  })
})

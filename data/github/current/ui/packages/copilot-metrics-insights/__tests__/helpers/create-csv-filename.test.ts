import {createCsvFilename, getUTCDateTimeString} from '../../helpers/create-csv-filename'

describe('getUTCDateTimeString', () => {
  beforeEach(() => {
    jest.useFakeTimers()
  })

  afterEach(() => {
    jest.useRealTimers()
  })

  it('should return the current UTC date and time in YYYY-MM-DDTHHMMSSZ format', () => {
    const mockDate = new Date(Date.UTC(2024, 9, 26, 10, 30, 15))
    jest.setSystemTime(mockDate)

    const expectedString = '2024-10-26T103015Z'
    expect(getUTCDateTimeString()).toBe(expectedString)
  })

  it('should correctly pad single-digit month, day, hour, minute, and second with a leading zero', () => {
    const mockDate = new Date(Date.UTC(2024, 0, 5, 3, 4, 5))
    jest.setSystemTime(mockDate)

    const expectedString = '2024-01-05T030405Z'
    expect(getUTCDateTimeString()).toBe(expectedString)
  })
})

describe('createCsvFilename', () => {
  beforeEach(() => {
    jest.useFakeTimers()

    const mockDate = new Date(Date.UTC(2024, 10, 15, 14, 25, 50))
    jest.setSystemTime(mockDate)
  })

  afterEach(() => {
    jest.useRealTimers()
  })

  it('should append the formatted UTC datetime string and .csv extension to the filename', () => {
    const baseFileName = 'my_report'
    const expectedTimestamp = '2024-11-15T142550Z'
    const expectedFilename = `${baseFileName}_${expectedTimestamp}.csv`

    expect(createCsvFilename(baseFileName)).toBe(expectedFilename)
  })
})

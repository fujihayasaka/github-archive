import {formatUsageDateForPeriod, formatDate, getDateString, getPeriodText} from '../../utils/date'
import {UsagePeriod} from '../../enums'
import timezoneMock from 'timezone-mock'
import {PERIOD_SELECTIONS} from '../../test-utils/mock-data'

const MOCK_DATE = '2023-03-14T16:21:25.316Z'

const MOCK_DATE_DAILY_FORMAT = '4 PM'
const MOCK_DATE_MONTHLY_FORMAT = 'Mar 14, 2023'
const MOCK_DATE_YEARLY_FORMAT = 'Mar 2023'

describe('formatUsageDateForPeriod', () => {
  it('renders monthly date format when no period is supplied', () => {
    expect(formatUsageDateForPeriod(MOCK_DATE, undefined)).toBe(MOCK_DATE_MONTHLY_FORMAT)
  })

  it('renders daily date format when UsagePeriod.TODAY is supplied', () => {
    expect(formatUsageDateForPeriod(MOCK_DATE, UsagePeriod.TODAY)).toBe(MOCK_DATE_DAILY_FORMAT)
  })

  it('renders monthly date format when UsagePeriod.THIS_MONTH is supplied', () => {
    expect(formatUsageDateForPeriod(MOCK_DATE, UsagePeriod.THIS_MONTH)).toBe(MOCK_DATE_MONTHLY_FORMAT)
  })

  it('renders yearly date format when UsagePeriod.THIS_YEAR is supplied', () => {
    expect(formatUsageDateForPeriod(MOCK_DATE, UsagePeriod.THIS_YEAR)).toBe(MOCK_DATE_YEARLY_FORMAT)
  })

  it('renders daily date format when UsagePeriod.LAST_MONTH is supplied', () => {
    expect(formatUsageDateForPeriod(MOCK_DATE, UsagePeriod.LAST_MONTH)).toBe(MOCK_DATE_MONTHLY_FORMAT)
  })

  it('renders daily date format when UsagePeriod.LAST_YEAR is supplied', () => {
    expect(formatUsageDateForPeriod(MOCK_DATE, UsagePeriod.LAST_YEAR)).toBe(MOCK_DATE_YEARLY_FORMAT)
  })
})

describe('formatDate', () => {
  it('renders the full date when year, month and date are present', () => {
    expect(formatDate(2023, 3, 14)).toBe('Mar 14, 2023')
  })

  it('renders the month and year when only year and month are present', () => {
    expect(formatDate(2023, 3)).toBe('Mar 2023')
  })
})

describe('getDateString', () => {
  it("returns the correct start and end date in 'yyyy-mm-dd' format", () => {
    const startDate = new Date('2024-10-01T00:00:00')
    const endDate = new Date('2024-10-31T00:00:00')

    const range = {
      from: startDate,
      to: endDate,
    }

    expect(getDateString(range)).toEqual({startDate: '2024-10-01', endDate: '2024-10-31'})
  })
})

describe('getDateString for user in a timezone ahead of UTC', () => {
  beforeAll(() => {
    timezoneMock.register('Australia/Adelaide')
  })

  afterAll(() => {
    timezoneMock.unregister()
  })

  it('returns the correct start and end date in "yyyy-mm-dd" format when user is in a timezone ahead of UTC', () => {
    const startDate = new Date('2024-10-01T00:00:00')
    const endDate = new Date('2024-10-31T00:00:00')

    const range = {
      from: startDate,
      to: endDate,
    }

    expect(getDateString(range)).toEqual({startDate: '2024-10-01', endDate: '2024-10-31'})
  })
})

describe('getPeriodText', () => {
  it('should return empty string for undefined period', () => {
    const result = getPeriodText(undefined)
    expect(result).toBe('')
  })

  it('should return year for UsagePeriod.THIS_YEAR', () => {
    const result = getPeriodText(PERIOD_SELECTIONS[2])
    const year = new Date().getUTCFullYear().toString()
    expect(result).toBe(year)
  })

  it('should return month range for UsagePeriod.THIS_MONTH', () => {
    const result = getPeriodText(PERIOD_SELECTIONS[1])
    const date = new Date()
    const month = date.toLocaleDateString('en-US', {timeZone: 'UTC', month: 'short'})
    const firstDay = new Date(date.getFullYear(), date.getMonth(), 1).getDate()
    const lastDay = new Date(date.getFullYear(), date.getMonth() + 1, 0).getDate()
    const expected = `${month} ${firstDay} - ${month} ${lastDay}, ${date.getFullYear()}`
    expect(result).toBe(expected)
  })

  it('should return date string for UsagePeriod.TODAY', () => {
    const result = getPeriodText(PERIOD_SELECTIONS[0])
    const date = new Date()
    const dateString = date.toLocaleDateString('en-US', {
      timeZone: 'UTC',
      month: 'long',
      day: 'numeric',
      year: 'numeric',
    })
    const expected = `${dateString} (All times in UTC)`
    expect(result).toBe(expected)
  })

  it('should return last month range for UsagePeriod.LAST_MONTH', () => {
    const result = getPeriodText(PERIOD_SELECTIONS[3])
    const date = new Date()
    date.setMonth(date.getMonth() - 1)
    const month = date.toLocaleDateString('en-US', {timeZone: 'UTC', month: 'short'})
    const firstDay = new Date(date.getFullYear(), date.getMonth(), 1).getDate()
    const lastDay = new Date(date.getFullYear(), date.getMonth() + 1, 0).getDate()
    const expected = `${month} ${firstDay} - ${month} ${lastDay}, ${date.getFullYear()}`
    expect(result).toBe(expected)
  })

  it('should return last year for UsagePeriod.LAST_YEAR', () => {
    const result = getPeriodText(PERIOD_SELECTIONS[4])
    const year = new Date().getUTCFullYear() - 1
    const expected = `${year} (All times in UTC)`
    expect(result).toBe(expected)
  })
})

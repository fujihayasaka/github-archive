// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {generateAriaLabelForAlertTrends} from '../aria'

describe('generateAriaLabelForAlertTrends', () => {
  it('should generate an ARIA label for a line chart describing alert trends over time', () => {
    const expectedLabel =
      'Line chart describing open alert trends over time. It consists of 2 time series. The x-axis shows dates from Oct 17, 2023 to Oct 23, 2023. The y-axis shows counts of alerts with low, high severities. This chart data can only be accessed as a table.'
    const label = generateAriaLabelForAlertTrends(['low', 'high'], 'severity', '10/17/2023', '10/23/2023', true)
    expect(label).toEqual(expectedLabel)
  })

  it('should return description for no data if array is empty', () => {
    const expectedLabel = 'Empty chart. There are no open alerts in this period.'
    const label = generateAriaLabelForAlertTrends([], 'severity', '10/17/2023', '10/23/2023', true)
    expect(label).toEqual(expectedLabel)
  })

  it('should return description for error if isError is true', () => {
    const expectedLabel = 'Empty chart. Alert trends could not be loaded right now.'
    const label = generateAriaLabelForAlertTrends(['low', 'high'], 'severity', '10/17/2023', '10/23/2023', true, true)
    expect(label).toEqual(expectedLabel)
  })
})

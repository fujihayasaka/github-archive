import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import CopilotMetricsTable from '../../components/tables/CopilotMetricsTable'

const mockData = [
  {
    id: '1',
    label: 'Week 1',
    shortLabel: 'W1',
    startDate: '2025-03-31',
    endDate: '2025-04-06',
  },
  {
    id: '2',
    label: 'Week 2',
    shortLabel: 'W2',
    startDate: '2025-04-07',
    endDate: '2025-04-13',
  },
]

const renderComponent = () => {
  return render(
    <CopilotMetricsTable
      data={mockData}
      columns={[
        {
          header: 'Start Date',
          field: 'startDate',
          sortBy: 'datetime',
        },
        {
          header: 'Label',
          field: 'label',
        },
      ]}
    />,
  )
}

test('should render the CopilotMetricsTable', () => {
  renderComponent()

  expect(screen.getByTestId('copilot-metrics-table')).toBeInTheDocument()

  const headers = ['Start Date', 'Label']
  for (const headerText of headers) {
    const header = screen.getByText(headerText)
    expect(header).toBeInTheDocument()
  }
})

test('should reverse the data so that the most recent week is first', () => {
  renderComponent()

  const rows = screen.getAllByRole('row')
  // Assume the first row is the header, so the data rows start at index 1
  expect(rows[1]).toHaveTextContent('Week 2')
  expect(rows[2]).toHaveTextContent('Week 1')
})

test('should display the correct data in table cells', () => {
  renderComponent()

  const week1Row = screen.getByRole('row', {name: /Week 1/})

  expect(week1Row).toHaveTextContent('2025-03-31')
  expect(week1Row).toHaveTextContent('Week 1')
})

test('should have correct accessibility attributes', () => {
  renderComponent()

  const table = screen.getByRole('table')
  expect(table).toHaveAttribute('role', 'table')
  expect(table).toHaveAttribute('aria-describedby', 'copilot-metrics-subtitle')
  expect(table).toHaveAttribute('aria-labelledby', 'copilot-metrics')

  const headers = screen.getAllByRole('columnheader')
  expect(headers.length).toBe(2)
  for (const header of headers) {
    expect(header).toHaveAttribute('scope', 'col')
  }
})

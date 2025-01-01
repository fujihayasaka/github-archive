import type {UseQueryResult} from '@github-ui/react-query'
import {screen} from '@testing-library/react'

import {render} from '../../../../test-utils/Render'
import RepositoriesTable from '../RepositoriesTable'
import useRepositoriesQuery from '../use-repositories-query'

jest.mock('../use-repositories-query')
function mockUseRepositoriesQuery<TResult>(result: Partial<UseQueryResult<TResult>>): void {
  ;(useRepositoriesQuery as jest.Mock).mockReturnValue({
    isPending: false,
    isError: false,
    isSuccess: false,
    data: [],
    ...result,
  })
}

describe('RepositoriesTable', () => {
  it('should render', async () => {
    mockUseRepositoriesQuery({
      isSuccess: true,
      data: {
        items: [
          {
            displayName: 'fluffy-bunny',
            countOpen: 1001,
            countEPSS: 2002,
            countCritical: 3003,
            countHigh: 4004,
            countMedium: 5005,
            countLow: 6006,
          },
        ],
      },
    })

    const props = {
      query: '',
      startDate: '2024-01-01',
      endDate: '2024-12-31',
    }
    render(<RepositoriesTable {...props} />)

    expect(screen.getAllByRole('columnheader').map(x => x.textContent)).toStrictEqual([
      'Repository',
      'Open alerts',
      'EPSS > 1%',
      'Critical',
      'High',
      'Medium',
      'Low',
    ])
    expect(screen.getAllByRole('row')).toHaveLength(2) // includes thead row
    expect(screen.getAllByRole('cell')).toHaveLength(7)

    expect(screen.getByText('fluffy-bunny')).toBeInTheDocument()
    expect(screen.getByText('1,001')).toBeInTheDocument()
    expect(screen.getByText('2,002')).toBeInTheDocument()
    expect(screen.getByText('3,003')).toBeInTheDocument()
    expect(screen.getByText('4,004')).toBeInTheDocument()
    expect(screen.getByText('5,005')).toBeInTheDocument()
    expect(screen.getByText('6,006')).toBeInTheDocument()
  })

  it('should render loading state', () => {
    mockUseRepositoriesQuery({
      isPending: true,
    })

    const props = {
      query: '',
      startDate: '2024-01-01',
      endDate: '2024-12-31',
    }
    render(<RepositoriesTable {...props} />)

    expect(screen.getByTestId('loading-indicator')).toBeInTheDocument()
    expect(screen.getAllByRole('columnheader').map(x => x.textContent)).toStrictEqual([
      'Repository',
      'Open alerts',
      'EPSS > 1%',
      'Critical',
      'High',
      'Medium',
      'Low',
    ])
    expect(screen.getAllByRole('row')).toHaveLength(2) // includes thead row
    expect(screen.getAllByRole('cell')).toHaveLength(7)
  })

  it('should render error state', () => {
    mockUseRepositoriesQuery({
      isError: true,
    })

    const props = {
      query: '',
      startDate: '2024-01-01',
      endDate: '2024-12-31',
      allowAutofixFeatures: true,
    }
    render(<RepositoriesTable {...props} />)

    expect(screen.getByTestId('error-indicator')).toBeInTheDocument()
    expect(screen.queryByRole('row')).not.toBeInTheDocument()
    expect(screen.queryByRole('cell')).not.toBeInTheDocument()
  })

  it('should render no-data state', () => {
    mockUseRepositoriesQuery({
      isSuccess: true,
      data: {
        items: [],
      },
    })

    const props = {
      query: '',
      startDate: '2024-01-01',
      endDate: '2024-12-31',
      allowAutofixFeatures: true,
    }
    render(<RepositoriesTable {...props} />)

    expect(screen.getByTestId('empty-indicator')).toBeInTheDocument()
    expect(screen.queryByRole('row')).not.toBeInTheDocument()
    expect(screen.queryByRole('cell')).not.toBeInTheDocument()
  })
})

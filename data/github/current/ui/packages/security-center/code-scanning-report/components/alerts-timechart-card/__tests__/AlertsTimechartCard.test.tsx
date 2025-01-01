import type {UseQueryResult} from '@tanstack/react-query'
import {screen} from '@testing-library/react'

import {render} from '../../../../test-utils/Render'
import AlertsTimechartCard from '../AlertsTimechartCard'
import {useAlertTrendsQuery} from '../use-alert-trends-query'

jest.mock('../use-alert-trends-query')
function mockUseAlertTrendsQuery<TResult>(result: Partial<UseQueryResult<TResult>>): void {
  ;(useAlertTrendsQuery as jest.Mock).mockReturnValue({
    isPending: false,
    isError: false,
    isSuccess: false,
    data: [],
    ...result,
  })
}

jest.mock('react-chartjs-2', () => ({
  Line: jest.fn(),
}))

describe('AlertsTimechartCard', () => {
  it('should render', async () => {
    mockUseAlertTrendsQuery({
      isSuccess: true,
      data: [
        {label: 'Foo', data: [{x: '2024-01-01', y: 1}]},
        {label: 'Bar', data: [{x: '2024-01-01', y: 2}]},
        {label: 'Qux', data: [{x: '2024-01-01', y: 3}]},
      ],
    })

    const props = {
      query: '',
      startDate: '2024-01-01',
      endDate: '2024-12-31',
      allowAutofixFeatures: true,
    }
    render(<AlertsTimechartCard {...props} />)

    expect(screen.getByText('Alerts in pull requests')).toBeInTheDocument()
    expect(screen.getByTestId('chart-card')).toBeInTheDocument()
  })

  it('should render loading state', () => {
    mockUseAlertTrendsQuery({
      isPending: true,
    })

    const props = {
      query: '',
      startDate: '2024-01-01',
      endDate: '2024-12-31',
      allowAutofixFeatures: true,
    }
    render(<AlertsTimechartCard {...props} />)

    expect(screen.getByText('Alerts in pull requests')).toBeInTheDocument()
    expect(screen.getByTestId('loading-indicator')).toBeInTheDocument()
  })

  it('should render error state', () => {
    mockUseAlertTrendsQuery({
      isError: true,
    })

    const props = {
      query: '',
      startDate: '2024-01-01',
      endDate: '2024-12-31',
      allowAutofixFeatures: true,
    }
    render(<AlertsTimechartCard {...props} />)

    expect(screen.getByText('Alerts in pull requests')).toBeInTheDocument()
    expect(screen.getByTestId('error')).toBeInTheDocument()
  })

  it('should render no-data state if no series returned', () => {
    mockUseAlertTrendsQuery({
      isSuccess: true,
      data: [],
    })

    const props = {
      query: '',
      startDate: '2024-01-01',
      endDate: '2024-12-31',
      allowAutofixFeatures: true,
    }
    render(<AlertsTimechartCard {...props} />)

    expect(screen.getByText('Alerts in pull requests')).toBeInTheDocument()
    expect(screen.getByTestId('no-data')).toBeInTheDocument()
  })

  it('should render no-data state if no data points returned', () => {
    mockUseAlertTrendsQuery({
      isSuccess: true,
      data: [
        {label: 'Critical', data: []},
        {label: 'High', data: []},
        {label: 'Medium', data: []},
        {label: 'Low', data: []},
      ],
    })

    const props = {
      query: '',
      startDate: '2024-01-01',
      endDate: '2024-12-31',
      allowAutofixFeatures: true,
    }
    render(<AlertsTimechartCard {...props} />)

    expect(screen.getByText('Alerts in pull requests')).toBeInTheDocument()
    expect(screen.getByTestId('no-data')).toBeInTheDocument()
  })

  it('should render no-data state if all data points are zero', () => {
    mockUseAlertTrendsQuery({
      isSuccess: true,
      data: [
        {
          label: 'Critical',
          data: [
            {x: '2024-01-01', y: 0},
            {x: '2024-02-01', y: 0},
            {x: '2024-03-01', y: 0},
          ],
        },
        {
          label: 'High',
          data: [
            {x: '2024-01-01', y: 0},
            {x: '2024-02-01', y: 0},
            {x: '2024-03-01', y: 0},
          ],
        },
      ],
    })

    const props = {
      query: '',
      startDate: '2024-01-01',
      endDate: '2024-12-31',
      allowAutofixFeatures: true,
    }
    render(<AlertsTimechartCard {...props} />)

    expect(screen.getByText('Alerts in pull requests')).toBeInTheDocument()
    expect(screen.getByTestId('no-data')).toBeInTheDocument()
  })

  it('should include all datasets', () => {
    mockUseAlertTrendsQuery({
      isSuccess: true,
      data: [
        {label: 'Unresolved and merged', data: [{x: '2024-01-01', y: 1}]},
        {label: 'Fixed with autofix', data: [{x: '2024-01-01', y: 2}]},
        {label: 'Fixed without autofix', data: [{x: '2024-01-01', y: 3}]},
        {label: 'Dismissed as false positive', data: [{x: '2024-01-01', y: 4}]},
        {label: 'Dismissed as risk accepted', data: [{x: '2024-01-01', y: 5}]},
      ],
    })

    const props = {
      query: '',
      startDate: '2024-01-01',
      endDate: '2024-12-31',
      allowAutofixFeatures: true,
    }
    render(<AlertsTimechartCard {...props} />)

    expect(
      screen.getByRole('region', {name: 'Unresolved and merged, bar series 1 of 5 with 1 bar.'}),
    ).toBeInTheDocument()
    expect(screen.getByRole('region', {name: 'Fixed with autofix, bar series 2 of 5 with 1 bar.'})).toBeInTheDocument()
    expect(
      screen.getByRole('region', {name: 'Fixed without autofix, bar series 3 of 5 with 1 bar.'}),
    ).toBeInTheDocument()
    expect(
      screen.getByRole('region', {name: 'Dismissed as false positive, bar series 4 of 5 with 1 bar.'}),
    ).toBeInTheDocument()
    expect(
      screen.getByRole('region', {name: 'Dismissed as risk accepted, bar series 5 of 5 with 1 bar.'}),
    ).toBeInTheDocument()
  })

  describe('when autofix feature is not available', () => {
    it('should not render autofix trend data', () => {
      mockUseAlertTrendsQuery({
        isSuccess: true,
        data: [
          {label: 'Unresolved and merged', data: [{x: '2024-01-01', y: 1}]},
          {label: 'Fixed with autofix', data: [{x: '2024-01-01', y: 2}]},
          {label: 'Fixed without autofix', data: [{x: '2024-01-01', y: 3}]},
          {label: 'Dismissed as false positive', data: [{x: '2024-01-01', y: 3}]},
          {label: 'Dismissed as risk accepted', data: [{x: '2024-01-01', y: 3}]},
        ],
      })

      const props = {
        query: '',
        startDate: '2024-01-01',
        endDate: '2024-12-31',
        allowAutofixFeatures: false,
      }
      render(<AlertsTimechartCard {...props} />)

      expect(
        screen.getByRole('region', {name: 'Unresolved and merged, bar series 1 of 4 with 1 bar.'}),
      ).toBeInTheDocument()
      expect(screen.getByRole('region', {name: 'Fixed, bar series 2 of 4 with 1 bar.'})).toBeInTheDocument()
      expect(
        screen.getByRole('region', {name: 'Dismissed as false positive, bar series 3 of 4 with 1 bar.'}),
      ).toBeInTheDocument()
      expect(
        screen.getByRole('region', {name: 'Dismissed as risk accepted, bar series 4 of 4 with 1 bar.'}),
      ).toBeInTheDocument()
    })
  })
})

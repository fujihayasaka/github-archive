import {screen} from '@testing-library/react'

import {render} from '../../test-utils/Render'
import {RemediationView} from '../components/RemediationView'
import {getRemediationViewProps} from '../test-utils/mock-data'

describe('RemediationView', () => {
  test('renders all except HistoricalAlertsFixedWithAutofixCard', () => {
    const props = getRemediationViewProps()
    props.allowAutofixFeatures = false
    render(<RemediationView {...props} />)
    expect(screen.getByText('Closed alerts over time')).toBeInTheDocument()
    expect(screen.getByText('Mean time to remediate')).toBeInTheDocument()
    expect(screen.getByText('Net resolve rate')).toBeInTheDocument()
    expect(screen.getByText('Alert activity')).toBeInTheDocument()
    expect(screen.getByTestId('area-chart-card:closed-alerts-over-time')).toBeInTheDocument()
    expect(screen.getByTestId('column-chart-card:alert-activity')).toBeInTheDocument()
    expect(screen.queryByText('Alerts fixed with autofix suggestions')).not.toBeInTheDocument()
  })

  test('renders all with HistoricalAlertsFixedWithAutofixCard', () => {
    const props = getRemediationViewProps()
    props.allowAutofixFeatures = true
    render(<RemediationView {...props} />)
    expect(screen.getByText('Closed alerts over time')).toBeInTheDocument()
    expect(screen.getByText('Mean time to remediate')).toBeInTheDocument()
    expect(screen.getByText('Net resolve rate')).toBeInTheDocument()
    expect(screen.getByText('Alert activity')).toBeInTheDocument()
    expect(screen.getByTestId('area-chart-card:closed-alerts-over-time')).toBeInTheDocument()
    expect(screen.getByTestId('column-chart-card:alert-activity')).toBeInTheDocument()
    expect(screen.getByText('Alerts fixed with autofix suggestions')).toBeInTheDocument()
  })
})

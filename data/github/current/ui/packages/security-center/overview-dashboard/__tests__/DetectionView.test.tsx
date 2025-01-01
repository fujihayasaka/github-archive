import {screen} from '@testing-library/react'

import {render} from '../../test-utils/Render'
import {DetectionView} from '../components/DetectionView'
import {getDetectionViewProps} from '../test-utils/mock-data'

describe('DetectionView', () => {
  test('renders', () => {
    const props = getDetectionViewProps()
    render(<DetectionView {...props} />)
    expect(screen.getByText('Open alerts over time')).toBeInTheDocument()
    expect(screen.getByText('Age of alerts')).toBeInTheDocument()
    expect(screen.getByText('Reopened alerts')).toBeInTheDocument()
    expect(screen.getByText('Secrets bypassed')).toBeInTheDocument()
    expect(screen.getByText('Impact analysis')).toBeInTheDocument()
    expect(screen.getByTestId('area-chart-card:open-alerts-over-time')).toBeInTheDocument()
  })
})

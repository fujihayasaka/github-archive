import {screen} from '@testing-library/react'

import {render} from '../../test-utils/Render'
import {PreventionView} from '../components/PreventionView'
import {getDetectionViewProps} from '../test-utils/mock-data'

window.performance.mark = jest.fn()
window.performance.measure = jest.fn()
window.performance.getEntriesByName = jest.fn().mockReturnValue([{duration: 100}])
window.performance.clearMarks = jest.fn()
window.performance.clearMeasures = jest.fn()

describe('PreventionView', () => {
  test('renders', () => {
    const props = getDetectionViewProps()
    render(<PreventionView {...props} />)
    expect(screen.getByText('Prevented vs. Introduced')).toBeInTheDocument()
    expect(screen.getByText('CodeQL pull request alerts fixed with autofix suggestions')).toBeInTheDocument()
    expect(screen.getByText('CodeQL alerts fixed in pull requests')).toBeInTheDocument()
    expect(screen.getByTestId('area-chart-card:prevented-vs.-introduced')).toBeInTheDocument()
  })
})

import {screen} from '@testing-library/react'

import {render} from '../../test-utils/Render'
import {PreventionView} from '../components/PreventionView'
import {getPreventionViewProps} from '../test-utils/mock-data'

describe('PreventionView', () => {
  test('renders without autofix features', () => {
    const props = getPreventionViewProps()
    props.allowAutofixFeatures = false
    render(<PreventionView {...props} />)
    expect(screen.getByText('Prevented vs. Introduced')).toBeInTheDocument()
    expect(screen.queryByText('CodeQL pull request alerts fixed with autofix suggestions')).not.toBeInTheDocument()
    expect(screen.getByText('CodeQL alerts fixed in pull requests')).toBeInTheDocument()
    expect(screen.getByTestId('area-chart-card:prevented-vs.-introduced')).toBeInTheDocument()
  })

  test('renders with autofix features', () => {
    const props = getPreventionViewProps()
    props.allowAutofixFeatures = true
    render(<PreventionView {...props} />)
    expect(screen.getByText('Prevented vs. Introduced')).toBeInTheDocument()
    expect(screen.getByText('CodeQL pull request alerts fixed with autofix suggestions')).toBeInTheDocument()
    expect(screen.getByText('CodeQL alerts fixed in pull requests')).toBeInTheDocument()
    expect(screen.getByTestId('area-chart-card:prevented-vs.-introduced')).toBeInTheDocument()
  })
})

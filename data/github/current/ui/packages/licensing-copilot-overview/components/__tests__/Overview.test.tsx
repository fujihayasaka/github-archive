import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {Overview} from '../../components/Overview'
import {getOverviewProps} from '../../test-utils/mock-data'

describe('Overview Component', () => {
  test('Renders the Overview', () => {
    const props = getOverviewProps()
    render(<Overview {...props} />)
    expect(screen.getByTestId('licensing-copilot-overview')).toBeInTheDocument()
  })
})

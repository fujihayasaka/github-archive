import {getNewRoutePayload} from '../test-utils/mock-data'
import {New} from '../routes/New/Page'
import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'

describe('<New />', () => {
  it('renders', () => {
    const routePayload = getNewRoutePayload()

    render(<New />, {routePayload})

    expect(screen.getByText('All repositories', {exact: false})).toBeInTheDocument()
  })
})

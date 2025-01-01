import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {ShowApp} from '../routes/ShowApp'
import {getShowAppRoutePayload} from '../test-utils/mock-data'

describe('ShowApp', () => {
  test('Renders the ShowApp page with the ListingLayout component', () => {
    const routePayload = getShowAppRoutePayload()
    render(<ShowApp />, {
      routePayload,
    })
    expect(screen.getByTestId('marketplace-listing')).toBeInTheDocument()
    expect(screen.queryByTestId('legacy-app-listing')).not.toBeInTheDocument()
  })
})

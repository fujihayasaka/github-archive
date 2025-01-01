import {ShowAction} from '../routes/ShowAction'
import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {getShowActionRoutePayload} from '../test-utils/mock-data'

describe('ShowAction', () => {
  test('Renders the ListingLayout component', () => {
    const routePayload = getShowActionRoutePayload()
    render(<ShowAction />, {
      routePayload,
    })

    expect(screen.getByTestId('marketplace-listing')).toBeInTheDocument()
  })
})

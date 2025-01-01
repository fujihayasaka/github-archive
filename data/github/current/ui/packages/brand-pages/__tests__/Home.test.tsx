import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {Home} from '../routes/Home'
import {getHomeRoutePayload} from '../test-utils/mock-data'

test('Renders the Home', () => {
  const routePayload = getHomeRoutePayload()
  render(<Home />, {
    routePayload,
  })
  expect(screen.getByRole('article')).toHaveTextContent(routePayload.someField)
})

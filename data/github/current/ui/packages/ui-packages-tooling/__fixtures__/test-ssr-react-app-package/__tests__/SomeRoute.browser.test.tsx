import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {expect, it} from '@github-ui/tests'
import {SomeRoute} from '../routes/SomeRoute'
import {getSomeRouteRoutePayload} from '../test-utils/mock-data'

it('Renders the SomeRoute', () => {
  const routePayload = getSomeRouteRoutePayload()
  render(<SomeRoute />, {
    routePayload,
  })
  expect(screen.getByRole('article')).toHaveTextContent(routePayload.someField)
})

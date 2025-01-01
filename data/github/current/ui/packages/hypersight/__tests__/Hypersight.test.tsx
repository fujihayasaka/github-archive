import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {Hypersight} from '../routes/Hypersight'
import {getHypersightRoutePayload} from '../test-utils/mock-data'

test('Renders the Hypersight app', async () => {
  const routePayload = getHypersightRoutePayload()
  render(<Hypersight />, {
    routePayload,
  })
  expect(await screen.findByRole('heading', {level: 1})).toHaveTextContent(routePayload.pullRequest.title)
})

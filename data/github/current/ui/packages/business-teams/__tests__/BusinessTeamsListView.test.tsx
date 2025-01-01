import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {BusinessTeamsListView} from '../routes/BusinessTeamsListView'
import {getBusinessTeamsTableViewRoutePayload} from '../test-utils/mock-data'

test('Renders the BusinessTeamsTableView', () => {
  const routePayload = getBusinessTeamsTableViewRoutePayload()
  render(<BusinessTeamsListView />, {
    routePayload,
  })
  expect(screen.getByRole('article')).toHaveTextContent(routePayload.someField)
})

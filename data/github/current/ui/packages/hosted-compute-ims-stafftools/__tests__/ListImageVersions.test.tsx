import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {ListImageVersions} from '../routes/ListImageVersions'
import {getListImageVersionsRoutePayload} from '../test-utils/mock-data'

test('Renders ListImageVersions', () => {
  const routePayload = getListImageVersionsRoutePayload()
  render(<ListImageVersions />, {
    routePayload,
  })
  expect(screen.getByText('test-name-1 (ID 1)')).toBeInTheDocument()
  expect(screen.getByText('Curated images')).toBeInTheDocument()
  expect(screen.getByText('1.0.0')).toBeInTheDocument()
})

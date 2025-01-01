import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {useParams} from 'react-router-dom'

import {Overview} from '../routes/Overview'
import {getOverviewRoutePayload} from '../test-utils/mock-data'

window.performance.mark = jest.fn()
window.performance.measure = jest.fn()
window.performance.getEntriesByName = jest.fn().mockReturnValue([{duration: 100}])
window.performance.clearMarks = jest.fn()
window.performance.clearMeasures = jest.fn()

jest.mock('react-router-dom', () => ({
  ...jest.requireActual('react-router-dom'),
  useParams: jest.fn(),
}))

beforeEach(() => {
  jest.mocked(useParams).mockImplementation(() => ({}))
})

test('Renders the org Overview', () => {
  jest.mocked(useParams).mockImplementation(() => ({org: 'my-org'}))
  const routePayload = {...getOverviewRoutePayload(), scope: 'organization'}

  render(<Overview />, {routePayload})

  expect(screen.getAllByRole('heading')?.[0]).toHaveTextContent('Overview')
  expect(screen.getByText('Alert trends and insights across your organization.')).toBeInTheDocument()
})

test('Renders the enterprise Overview', () => {
  jest.mocked(useParams).mockImplementation(() => ({business: 'my-biz'}))
  const routePayload = {...getOverviewRoutePayload(), scope: 'enterprise'}
  routePayload.showCsvExport = false

  render(<Overview />, {routePayload})

  expect(screen.getAllByRole('heading')?.[0]).toHaveTextContent('Overview')
  expect(screen.getByText('Alert trends and insights across your enterprise.')).toBeInTheDocument()
})

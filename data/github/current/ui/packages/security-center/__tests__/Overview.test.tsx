import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {useParams} from 'react-router-dom'

import {Overview} from '../routes/Overview'
import {getOverviewRoutePayload} from '../test-utils/mock-data'

jest.mock('react-router-dom', () => ({
  ...jest.requireActual('react-router-dom'),
  useParams: jest.fn(),
}))

beforeEach(() => {
  jest.mocked(useParams).mockImplementation(() => ({}))
  jest.spyOn(console, 'error').mockImplementation((message: string) => {
    // * Because Filter is asynchronous, there are console errors that are thrown, but expected. This will rethrow
    // * any errors that are not related to the async nature of the component.
    if (!message.includes?.('wrapped in act(')) {
      // eslint-disable-next-line no-console
      console.error(message)
    }
  })
})

afterEach(() => {
  jest.restoreAllMocks()
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
